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
  location?: string;
  adm?: string;
  date?: string;
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
  city?: string;
  latitude?: number;
  longitude?: number;
}
