import {
  BadRequestException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createPrivateKey, sign } from 'node:crypto';
import { isIP } from 'node:net';
import {
  QWeatherDailyResponse,
  QWeatherGeoResponse,
  QWeatherNowResponse,
  ResolvedLocation,
  WeatherData,
  WeatherQuery,
} from './weather.types';
import { WEATHER_HTTP_CLIENT, WeatherHttpClient } from './weather-http.client';

const WEATHER_CODE_MAP: Record<number, { text: string; emoji: string }> = {
  0: { text: '晴', emoji: '☀️' },
  1: { text: '大体晴朗', emoji: '🌤️' },
  2: { text: '局部多云', emoji: '⛅' },
  3: { text: '阴天', emoji: '☁️' },
  45: { text: '有雾', emoji: '🌫️' },
  48: { text: '冰雾', emoji: '🌫️' },
  51: { text: '轻毛毛雨', emoji: '🌦️' },
  53: { text: '毛毛雨', emoji: '🌦️' },
  55: { text: '大毛毛雨', emoji: '🌦️' },
  61: { text: '小雨', emoji: '🌧️' },
  63: { text: '中雨', emoji: '🌧️' },
  65: { text: '大雨', emoji: '🌧️' },
  71: { text: '小雪', emoji: '🌨️' },
  73: { text: '中雪', emoji: '🌨️' },
  75: { text: '大雪', emoji: '🌨️' },
  77: { text: '冰晶', emoji: '❄️' },
  80: { text: '阵雨', emoji: '🌦️' },
  81: { text: '阵雨', emoji: '🌦️' },
  82: { text: '暴雨', emoji: '⛈️' },
  85: { text: '阵雪', emoji: '🌨️' },
  86: { text: '大阵雪', emoji: '🌨️' },
  95: { text: '雷暴', emoji: '⛈️' },
  96: { text: '冰雹雷暴', emoji: '⛈️' },
  99: { text: '大冰雹雷暴', emoji: '⛈️' },
};

interface WeatherConfig {
  apiHost: string;
  privateKey: string;
  projectId: string;
  keyId: string;
  developerId: string;
  defaultLocation: string;
  ipGeolocationBaseUrl: string;
  timeZone: string;
  timeoutMs: number;
  cacheTtlSeconds: number;
}

interface CacheEntry {
  data: WeatherData;
  expiresAt: number;
}

@Injectable()
export class WeatherService {
  private readonly logger = new Logger(WeatherService.name);
  private readonly cache = new Map<string, CacheEntry>();
  private readonly config: WeatherConfig;

  constructor(
    configService: ConfigService,
    @Inject(WEATHER_HTTP_CLIENT)
    private readonly httpClient: WeatherHttpClient,
  ) {
    this.config = {
      apiHost: configService.get<string>('QWEATHER_API_HOST')?.trim() ?? '',
      privateKey: configService.get<string>('QWEATHER_PRIVATE_KEY')?.trim() ?? '',
      projectId: configService.get<string>('QWEATHER_PROJECT_ID')?.trim() ?? '',
      keyId: configService.get<string>('QWEATHER_KEY_ID')?.trim() ?? '',
      developerId: configService.get<string>('QWEATHER_DEVELOPER_ID')?.trim() ?? '',
      defaultLocation: configService.get<string>('WEATHER_DEFAULT_LOCATION')?.trim() ?? '',
      ipGeolocationBaseUrl:
        configService.get<string>('IP_GEOLOCATION_BASE_URL')?.trim().replace(/\/+$/, '') ||
        'https://ipwho.is',
      timeZone: configService.get<string>('WEATHER_TIME_ZONE')?.trim() || 'Asia/Shanghai',
      timeoutMs: this.positiveInteger(configService.get<string>('WEATHER_HTTP_TIMEOUT_MS'), 8_000),
      cacheTtlSeconds: this.positiveInteger(
        configService.get<string>('WEATHER_CACHE_TTL_SECONDS'),
        600,
      ),
    };
  }

  async getWeather(query: WeatherQuery): Promise<WeatherData> {
    this.assertConfigured();

    const targetDate = this.normalizeTargetDate(query.date);
    const normalizedLocation = this.normalizeText(query.location);
    const normalizedAdm = this.normalizeText(query.adm);
    const clientIp = this.normalizeIp(query.clientIp);
    const cacheKey = [
      normalizedLocation
        ? `location:${normalizedLocation}`
        : this.config.defaultLocation
          ? `default:${this.config.defaultLocation}`
          : `ip:${clientIp}`,
      normalizedAdm ?? 'noadm',
      targetDate,
    ].join(':');

    const cached = this.getCached(cacheKey);
    if (cached) return cached;

    const location = await this.resolveLocation(normalizedLocation, normalizedAdm, clientIp);
    const data = await this.fetchWeather(location, targetDate);
    this.setCached(cacheKey, data);
    return data;
  }

  private async fetchWeather(location: ResolvedLocation, targetDate: string): Promise<WeatherData> {
    const jwt = this.generateJwt();
    const coordinates = `${location.longitude.toFixed(2)},${location.latitude.toFixed(2)}`;
    const [nowResponse, dailyResponse] = await Promise.all([
      this.requestQWeather<QWeatherNowResponse>('/v7/weather/now', { location: coordinates }, jwt),
      this.requestQWeather<QWeatherDailyResponse>('/v7/weather/3d', { location: coordinates }, jwt),
    ]);

    if (nowResponse.code !== '200' || !nowResponse.now) {
      throw this.upstreamUnavailable(`实时天气返回异常代码 ${nowResponse.code}`);
    }
    if (dailyResponse.code !== '200' || !dailyResponse.daily?.length) {
      throw this.upstreamUnavailable(`天气预报返回异常代码 ${dailyResponse.code}`);
    }

    const daily = dailyResponse.daily.find((item) => item.fxDate === targetDate);
    if (!daily) {
      throw new BadRequestException('目标日期不在天气服务预报范围内');
    }

    const today = this.getToday();
    const isToday = targetDate === today;
    const now = nowResponse.now;
    const rawCode = this.requiredNumber(isToday ? now.icon : daily.iconDay, '天气代码');
    const weatherCode = this.normalizeToSharedWeatherCode(rawCode, isToday);
    const isDay = isToday ? this.resolveDaylight(rawCode) : true;
    const temperatureMax = this.requiredNumber(daily.tempMax, '最高气温');
    const temperatureMin = this.requiredNumber(daily.tempMin, '最低气温');
    const temperature = isToday
      ? this.requiredNumber(now.temp, '当前气温')
      : this.roundOne((temperatureMax + temperatureMin) / 2);
    const windspeed = this.requiredNumber(isToday ? now.windSpeed : daily.windSpeedDay, '风速');
    const humidity = this.optionalNumber(isToday ? now.humidity : daily.humidity);
    const precip = this.optionalNumber(isToday ? now.precip : daily.precip);
    const presentation = this.getWeatherPresentation(weatherCode, isDay);

    return {
      city: location.city,
      latitude: location.latitude,
      longitude: location.longitude,
      forecastDate: daily.fxDate,
      temperature,
      temperatureMax,
      temperatureMin,
      weatherCode,
      weatherText: presentation.text,
      weatherEmoji: presentation.emoji,
      isDay,
      windspeed,
      ...(humidity === undefined ? {} : { humidity }),
      ...(precip === undefined ? {} : { precip }),
    };
  }

  private async resolveLocation(
    location: string | undefined,
    adm: string | undefined,
    clientIp: string,
  ): Promise<ResolvedLocation> {
    if (location) return this.lookupLocation(location, adm);
    if (this.config.defaultLocation) {
      return this.lookupLocation(this.config.defaultLocation);
    }
    if (!this.isPublicIp(clientIp)) {
      throw new BadRequestException('未提供城市参数，且当前请求 IP 无法用于城市级定位');
    }

    const ipLocation = await this.resolveIpLocation(clientIp);
    if (!ipLocation) {
      throw new ServiceUnavailableException('无法根据请求 IP 定位城市，请传入 location');
    }
    return ipLocation;
  }

  private async lookupLocation(location: string, adm?: string): Promise<ResolvedLocation> {
    const response = await this.requestQWeather<QWeatherGeoResponse>(
      '/geo/v2/city/lookup',
      {
        location,
        ...(adm ? { adm } : {}),
        range: 'cn',
        number: '5',
      },
      this.generateJwt(),
    );

    if (response.code === '404' || response.code === '204' || !response.location?.length) {
      throw new NotFoundException(`未找到城市“${location}”`);
    }
    if (response.code !== '200') {
      throw this.upstreamUnavailable(`城市查询返回异常代码 ${response.code}`);
    }

    const result = response.location[0];
    return {
      city: result.name,
      latitude: this.requiredNumber(result.lat, '城市纬度'),
      longitude: this.requiredNumber(result.lon, '城市经度'),
    };
  }

  private async resolveIpLocation(clientIp: string): Promise<ResolvedLocation | null> {
    const url = `${this.config.ipGeolocationBaseUrl}/${encodeURIComponent(clientIp)}`;
    try {
      const response = await this.httpClient.get<{
        success?: boolean;
        city?: string;
        latitude?: number;
        longitude?: number;
      }>(url, { signal: AbortSignal.timeout(this.config.timeoutMs) });

      if (
        response.success === false ||
        !response.city ||
        typeof response.latitude !== 'number' ||
        typeof response.longitude !== 'number'
      ) {
        return null;
      }
      return {
        city: response.city,
        latitude: response.latitude,
        longitude: response.longitude,
      };
    } catch (error: unknown) {
      this.logger.warn(`IP 城市定位失败：${this.safeErrorMessage(error)}`);
      return null;
    }
  }

  private async requestQWeather<T>(
    path: string,
    query: Record<string, string>,
    jwt: string,
  ): Promise<T> {
    const host = this.config.apiHost.replace(/^https?:\/\//, '').replace(/\/+$/, '');
    const url = new URL(`https://${host}${path}`);
    for (const [key, value] of Object.entries(query)) {
      url.searchParams.set(key, value);
    }

    try {
      return await this.httpClient.get<T>(url.toString(), {
        signal: AbortSignal.timeout(this.config.timeoutMs),
        headers: { Authorization: `Bearer ${jwt}` },
      });
    } catch (error: unknown) {
      throw this.upstreamUnavailable(`和风天气请求失败：${this.safeErrorMessage(error)}`);
    }
  }

  private generateJwt(): string {
    const now = Math.floor(Date.now() / 1000);
    const issuedAt = now - 30;
    const header = { alg: 'EdDSA', kid: this.config.keyId };
    const payload = {
      iss: this.config.developerId,
      sub: this.config.projectId,
      iat: issuedAt,
      exp: issuedAt + 900,
    };
    const headerPart = this.base64Url(JSON.stringify(header));
    const payloadPart = this.base64Url(JSON.stringify(payload));
    const data = `${headerPart}.${payloadPart}`;
    const privateKey = createPrivateKey({
      key: this.normalizePrivateKey(this.config.privateKey),
      format: 'pem',
    });
    const signature = sign(null, Buffer.from(data), privateKey);
    return `${data}.${this.base64Url(signature)}`;
  }

  private normalizePrivateKey(value: string): string {
    let pem = value.replace(/\\n/g, '\n').trim();
    if (!pem.includes('-----BEGIN')) {
      pem = `-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----`;
    }
    return pem;
  }

  private base64Url(value: string | Buffer): string {
    return Buffer.from(value)
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '');
  }

  private getWeatherPresentation(
    weatherCode: number,
    isDay: boolean,
  ): { text: string; emoji: string } {
    const mapped = WEATHER_CODE_MAP[weatherCode];
    if (!mapped) return { text: '未知', emoji: '🌈' };
    if (!isDay && weatherCode === 0) {
      return { text: mapped.text, emoji: '🌙' };
    }
    return mapped;
  }

  private normalizeToSharedWeatherCode(weatherCode: number, isToday: boolean): number {
    if (WEATHER_CODE_MAP[weatherCode]) return weatherCode;
    if (weatherCode === 100 || (weatherCode === 150 && !isToday)) return 0;
    if (weatherCode === 150) return 0;
    if ([101, 102, 151, 152].includes(weatherCode)) return 1;
    if ([103, 104, 153, 154].includes(weatherCode)) return 2;
    if (weatherCode >= 300 && weatherCode < 400) return 61;
    if (weatherCode >= 400 && weatherCode < 500) return 71;
    if (weatherCode >= 500 && weatherCode < 600) return 45;
    if (weatherCode >= 900) return 95;
    return weatherCode;
  }

  private resolveDaylight(weatherCode: number): boolean {
    if (weatherCode >= 100 && weatherCode <= 104) return true;
    if (weatherCode >= 150 && weatherCode <= 154) return false;

    const hour = Number.parseInt(
      new Intl.DateTimeFormat('en-GB', {
        timeZone: this.config.timeZone,
        hour: '2-digit',
        hourCycle: 'h23',
      }).format(new Date()),
      10,
    );
    return hour >= 6 && hour < 18;
  }

  private normalizeTargetDate(value?: string): string {
    const today = this.getToday();
    const targetDate = value?.trim() || today;
    const timestamp = Date.parse(`${targetDate}T00:00:00Z`);
    if (
      !Number.isFinite(timestamp) ||
      new Date(timestamp).toISOString().slice(0, 10) !== targetDate
    ) {
      throw new BadRequestException('date 不是有效日期');
    }

    const days = Math.round((timestamp - Date.parse(`${today}T00:00:00Z`)) / 86_400_000);
    if (days < 0 || days > 2) {
      throw new BadRequestException('date 仅支持今天和未来两天');
    }
    return targetDate;
  }

  private getToday(): string {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: this.config.timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(new Date());
    const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
    return `${values.year}-${values.month}-${values.day}`;
  }

  private assertConfigured(): void {
    if (
      !this.config.apiHost ||
      !this.config.privateKey ||
      !this.config.projectId ||
      !this.config.keyId ||
      !this.config.developerId
    ) {
      throw new ServiceUnavailableException('天气服务尚未完成配置');
    }
  }

  private requiredNumber(value: string | undefined, field: string): number {
    const number = Number.parseFloat(value ?? '');
    if (!Number.isFinite(number)) {
      throw this.upstreamUnavailable(`天气数据缺少${field}`);
    }
    return number;
  }

  private optionalNumber(value: string | undefined): number | undefined {
    if (!value?.trim()) return undefined;
    const number = Number.parseFloat(value);
    return Number.isFinite(number) ? number : undefined;
  }

  private roundOne(value: number): number {
    return Math.round(value * 10) / 10;
  }

  private positiveInteger(value: string | undefined, fallback: number): number {
    const parsed = Number.parseInt(value ?? '', 10);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
  }

  private normalizeText(value?: string): string | undefined {
    const normalized = value?.trim();
    return normalized || undefined;
  }

  private normalizeIp(value: string): string {
    return value.trim().replace(/^::ffff:/i, '');
  }

  private isPublicIp(value: string): boolean {
    if (!isIP(value)) return false;
    if (value.includes(':')) {
      const normalized = value.toLowerCase();
      return (
        normalized !== '::1' &&
        !normalized.startsWith('fc') &&
        !normalized.startsWith('fd') &&
        !normalized.startsWith('fe80')
      );
    }

    const [a, b] = value.split('.').map(Number);
    return !(
      a === 0 ||
      a === 10 ||
      a === 127 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168)
    );
  }

  private getCached(key: string): WeatherData | undefined {
    const entry = this.cache.get(key);
    if (!entry) return undefined;
    if (entry.expiresAt <= Date.now()) {
      this.cache.delete(key);
      return undefined;
    }
    return entry.data;
  }

  private setCached(key: string, data: WeatherData): void {
    if (this.cache.size >= 1_000 && !this.cache.has(key)) {
      const oldestKey = this.cache.keys().next().value as string | undefined;
      if (oldestKey) this.cache.delete(oldestKey);
    }
    this.cache.set(key, {
      data,
      expiresAt: Date.now() + this.config.cacheTtlSeconds * 1_000,
    });
  }

  private upstreamUnavailable(detail: string): ServiceUnavailableException {
    this.logger.warn(detail);
    return new ServiceUnavailableException('天气服务暂时不可用');
  }

  private safeErrorMessage(error: unknown): string {
    return error instanceof Error ? error.message : '未知错误';
  }
}
