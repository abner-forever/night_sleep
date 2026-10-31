import {
  BadRequestException,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { KeyObject, generateKeyPairSync, verify } from 'node:crypto';
import { WeatherHttpClient } from './weather-http.client';
import { WeatherService } from './weather.service';

describe('WeatherService', () => {
  let privateKeyPem: string;
  let publicKey: KeyObject;
  let httpGet: jest.Mock;
  let configValues: Record<string, string>;

  beforeEach(() => {
    const keyPair = generateKeyPairSync('ed25519');
    privateKeyPem = keyPair.privateKey.export({ format: 'pem', type: 'pkcs8' }).toString();
    publicKey = keyPair.publicKey;
    httpGet = jest.fn();
    configValues = {
      QWEATHER_API_HOST: 'example.qweatherapi.com',
      QWEATHER_PRIVATE_KEY: privateKeyPem,
      QWEATHER_PROJECT_ID: 'project-id',
      QWEATHER_KEY_ID: 'key-id',
      QWEATHER_DEVELOPER_ID: 'Q123456789',
      WEATHER_TIME_ZONE: 'Asia/Shanghai',
    };
  });

  it('解析城市并返回 App 约定的天气字段', async () => {
    const today = todayInShanghai();
    httpGet.mockImplementation(async (url: string) => {
      if (url.includes('/geo/v2/city/lookup')) {
        return {
          code: '200',
          location: [{ name: '上海', lat: '31.2304', lon: '121.4737' }],
        };
      }
      if (url.includes('/v7/weather/now')) {
        return {
          code: '200',
          now: {
            temp: '23.6',
            icon: '104',
            windSpeed: '14',
            humidity: '72',
            precip: '0.1',
          },
        };
      }
      if (url.includes('/v7/weather/3d')) {
        return {
          code: '200',
          daily: [
            {
              fxDate: today,
              tempMax: '28',
              tempMin: '18',
              iconDay: '104',
              windSpeedDay: '15',
              humidity: '70',
              precip: '0',
            },
          ],
        };
      }
      throw new Error(`unexpected URL: ${url}`);
    });

    const service = createService(configValues, httpGet);
    const result = await service.getWeather({
      clientIp: '127.0.0.1',
      location: '上海',
    });

    expect(result).toMatchObject({
      city: '上海',
      latitude: 31.2304,
      longitude: 121.4737,
      forecastDate: today,
      temperature: 23.6,
      temperatureMax: 28,
      temperatureMin: 18,
      weatherCode: 2,
      weatherText: '局部多云',
      weatherEmoji: '⛅',
      isDay: true,
      windspeed: 14,
      humidity: 72,
      precip: 0.1,
    });

    const authenticatedCall = httpGet.mock.calls.find(([url]) =>
      String(url).includes('/v7/weather/now'),
    );
    const authorization = authenticatedCall?.[1]?.headers?.Authorization as string;
    const token = authorization.replace(/^Bearer /, '');
    const [header, payload, signature] = token.split('.');
    expect(JSON.parse(Buffer.from(header, 'base64url').toString())).toEqual({
      alg: 'EdDSA',
      kid: 'key-id',
    });
    expect(JSON.parse(Buffer.from(payload, 'base64url').toString())).toMatchObject({
      iss: 'Q123456789',
      sub: 'project-id',
    });
    expect(
      verify(
        null,
        Buffer.from(`${header}.${payload}`),
        publicKey,
        Buffer.from(signature, 'base64url'),
      ),
    ).toBe(true);

    await service.getWeather({ clientIp: '127.0.0.1', location: '上海' });
    expect(httpGet).toHaveBeenCalledTimes(3);
  });

  it('未来日期使用日预报均值', async () => {
    const dates = forecastDates();
    httpGet.mockImplementation(async (url: string) => {
      if (url.includes('/geo/v2/city/lookup')) {
        return {
          code: '200',
          location: [{ name: '上海', lat: '31.23', lon: '121.47' }],
        };
      }
      if (url.includes('/v7/weather/now')) {
        return {
          code: '200',
          now: { temp: '20', icon: '150', windSpeed: '8' },
        };
      }
      if (url.includes('/v7/weather/3d')) {
        return {
          code: '200',
          daily: dates.map((fxDate) => ({
            fxDate,
            tempMax: '24',
            tempMin: '16',
            iconDay: '305',
            windSpeedDay: '11',
            humidity: '80',
            precip: '3.2',
          })),
        };
      }
      throw new Error(`unexpected URL: ${url}`);
    });

    const result = await createService(configValues, httpGet).getWeather({
      clientIp: '127.0.0.1',
      location: '上海',
      date: dates[1],
    });

    expect(result).toMatchObject({
      forecastDate: dates[1],
      temperature: 20,
      weatherCode: 61,
      weatherText: '小雨',
      weatherEmoji: '🌧️',
      precip: 3.2,
    });
  });

  it('超出三日范围的日期不请求上游', async () => {
    const service = createService(configValues, httpGet);

    await expect(
      service.getWeather({
        clientIp: '127.0.0.1',
        location: '上海',
        date: '2099-01-01',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(httpGet).not.toHaveBeenCalled();
  });

  it('城市未找到时返回 404 错误', async () => {
    httpGet.mockResolvedValue({ code: '204', location: [] });
    const service = createService(configValues, httpGet);

    await expect(
      service.getWeather({
        clientIp: '127.0.0.1',
        location: '不存在',
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('上游异常时返回服务不可用，不生成占位天气', async () => {
    httpGet.mockImplementation(async (url: string) => {
      if (url.includes('/geo/v2/city/lookup')) {
        return {
          code: '200',
          location: [{ name: '上海', lat: '31.23', lon: '121.47' }],
        };
      }
      if (url.includes('/v7/weather/now')) {
        return { code: '500' };
      }
      if (url.includes('/v7/weather/3d')) {
        return {
          code: '200',
          daily: [
            {
              fxDate: todayInShanghai(),
              tempMax: '28',
              tempMin: '18',
              iconDay: '100',
            },
          ],
        };
      }
      throw new Error(`unexpected URL: ${url}`);
    });
    const service = createService(configValues, httpGet);

    await expect(
      service.getWeather({ clientIp: '127.0.0.1', location: '上海' }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('无城市且请求来自私有 IP 时拒绝猜测', async () => {
    const service = createService(configValues, httpGet);

    await expect(service.getWeather({ clientIp: '127.0.0.1' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(httpGet).not.toHaveBeenCalled();
  });

  it('缺少和风天气配置时返回服务不可用', async () => {
    const service = createService({}, httpGet);

    await expect(
      service.getWeather({ clientIp: '127.0.0.1', location: '上海' }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('配置报错只说缺哪个变量，不回显任何值', async () => {
    const service = createService(
      {
        QWEATHER_API_HOST: 'example.qweatherapi.com',
        QWEATHER_PRIVATE_KEY: privateKeyPem,
      },
      httpGet,
    );

    const error = await service
      .getWeather({ clientIp: '127.0.0.1', location: '上海' })
      .catch((thrown: unknown) => thrown);

    expect(error).toBeInstanceOf(ServiceUnavailableException);
    const message = (error as ServiceUnavailableException).message;
    expect(message).toContain('QWEATHER_KEY_ID');
    expect(message).toContain('QWEATHER_DEVELOPER_ID');
    expect(message).toContain('QWEATHER_PROJECT_ID');
    expect(message).not.toContain('example.qweatherapi.com');
    expect(message).not.toContain('PRIVATE KEY');
  });

  it('优先用边缘给出的坐标换城市，不再请求第三方 IP 库', async () => {
    const today = todayInShanghai();
    httpGet.mockImplementation(async (url: string) => {
      if (url.includes('/geo/v2/city/lookup')) {
        expect(String(url)).toContain('location=120.16%2C30.29');
        return {
          code: '200',
          location: [{ name: '杭州', lat: '30.29', lon: '120.16' }],
        };
      }
      if (url.includes('/v7/weather/now')) {
        return { code: '200', now: { temp: '21', icon: '101', windSpeed: '9' } };
      }
      if (url.includes('/v7/weather/3d')) {
        return {
          code: '200',
          daily: [
            {
              fxDate: today,
              tempMax: '25',
              tempMin: '17',
              iconDay: '101',
              windSpeedDay: '10',
            },
          ],
        };
      }
      throw new Error(`unexpected URL: ${url}`);
    });

    const result = await createService(configValues, httpGet).getWeather({
      clientIp: '203.0.113.8',
      clientGeo: { latitude: 30.2936, longitude: 120.1614, city: 'Hangzhou' },
    });

    expect(result.city).toBe('杭州');
    expect(httpGet.mock.calls.some(([url]) => String(url).startsWith('https://ipwho.is'))).toBe(
      false,
    );
  });

  it('边缘坐标查不到中国城市时退回按请求 IP 定位', async () => {
    const today = todayInShanghai();
    httpGet.mockImplementation(async (url: string) => {
      if (url.includes('/geo/v2/city/lookup')) {
        // 境外出口的坐标被 `range: 'cn'` 过滤掉，和风返回 404。
        return { code: '404' };
      }
      if (url.startsWith('https://ipwho.is/203.0.113.8')) {
        return { success: true, city: '深圳', latitude: 22.54, longitude: 114.06 };
      }
      if (url.includes('/v7/weather/now')) {
        return { code: '200', now: { temp: '26', icon: '104', windSpeed: '11' } };
      }
      if (url.includes('/v7/weather/3d')) {
        return {
          code: '200',
          daily: [
            {
              fxDate: today,
              tempMax: '29',
              tempMin: '22',
              iconDay: '104',
              windSpeedDay: '12',
            },
          ],
        };
      }
      throw new Error(`unexpected URL: ${url}`);
    });

    const result = await createService(configValues, httpGet).getWeather({
      clientIp: '203.0.113.8',
      clientGeo: { latitude: 51.51, longitude: -0.13 },
    });

    expect(result.city).toBe('深圳');
  });

  it('第三方 IP 库返回 success=false 时抛服务不可用', async () => {
    httpGet.mockImplementation(async (url: string) => {
      if (url.startsWith('https://ipwho.is/')) {
        return { success: false, message: 'Rate limit exceeded' };
      }
      throw new Error(`unexpected URL: ${url}`);
    });

    await expect(
      createService(configValues, httpGet).getWeather({ clientIp: '203.0.113.8' }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('第三方 IP 库查不到城市时抛服务不可用', async () => {
    httpGet.mockImplementation(async (url: string) => {
      if (url.startsWith('https://ipwho.is/')) {
        return { success: true, latitude: 22.54, longitude: 114.06 };
      }
      throw new Error(`unexpected URL: ${url}`);
    });

    await expect(
      createService(configValues, httpGet).getWeather({ clientIp: '203.0.113.8' }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });
});

function createService(values: Record<string, string>, get: jest.Mock): WeatherService {
  const configService = {
    get: jest.fn((key: string) => values[key]),
  } as unknown as ConfigService;
  const httpClient = { get } as unknown as WeatherHttpClient;
  return new WeatherService(configService, httpClient);
}

function todayInShanghai(): string {
  return dateWithOffset(0);
}

function forecastDates(): string[] {
  return [0, 1, 2].map(dateWithOffset);
}

function dateWithOffset(offset: number): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  const date = new Date(`${values.year}-${values.month}-${values.day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + offset);
  return date.toISOString().slice(0, 10);
}
