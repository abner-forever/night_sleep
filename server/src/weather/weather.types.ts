export interface WeatherData {
  city: string;
  latitude: number;
  longitude: number;
  forecastDate: string;
  temperature: number;
  temperatureMax: number;
  temperatureMin: number;
  weatherCode: number;
  weatherText: string;
  weatherEmoji: string;
  isDay: boolean;
  windspeed: number;
  humidity?: number;
  precip?: number;
}

export interface WeatherQuery {
  clientIp: string;
  /**
   * Cloudflare 边缘给出的请求位置。有坐标时优先于按 IP 查第三方库：
   * 少一次外网请求，也不会把用户 IP 交给外部服务。
   */
  clientGeo?: ClientGeo;
  location?: string;
  adm?: string;
  date?: string;
}

export interface ClientGeo {
  latitude?: number;
  longitude?: number;
  city?: string;
}

/** 已经通过范围校验的坐标（可跨 Cloudflare 头部、默认城市等来源）。 */
export interface ResolvedCoordinates {
  latitude: number;
  longitude: number;
  city?: string;
}

export interface ResolvedLocation {
  city: string;
  latitude: number;
  longitude: number;
}

export interface QWeatherGeoResponse {
  code: string;
  location?: Array<{
    name: string;
    lat: string;
    lon: string;
  }>;
}

export interface QWeatherNowResponse {
  code: string;
  now?: {
    temp?: string;
    icon?: string;
    windSpeed?: string;
    humidity?: string;
    precip?: string;
  };
}

export interface QWeatherDailyResponse {
  code: string;
  daily?: Array<{
    fxDate: string;
    tempMax?: string;
    tempMin?: string;
    iconDay?: string;
    textDay?: string;
    windSpeedDay?: string;
    humidity?: string;
    precip?: string;
  }>;
}

export interface IpLocationResponse {
  success?: boolean;
  /** success 为 false 时上游给出的原因（限流、保留地址等）。 */
  message?: string;
  city?: string;
  latitude?: number;
  longitude?: number;
}
