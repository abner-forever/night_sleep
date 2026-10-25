import { Injectable } from '@nestjs/common';

export const WEATHER_HTTP_CLIENT = Symbol('WEATHER_HTTP_CLIENT');

export interface WeatherHttpRequestOptions {
  signal: AbortSignal;
  headers?: Record<string, string>;
}

export interface WeatherHttpClient {
  get<T>(url: string, options: WeatherHttpRequestOptions): Promise<T>;
}

@Injectable()
export class FetchWeatherHttpClient implements WeatherHttpClient {
  async get<T>(url: string, options: WeatherHttpRequestOptions): Promise<T> {
    const response = await fetch(url, {
      headers: {
        Accept: 'application/json',
        ...options.headers,
      },
      signal: options.signal,
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    return (await response.json()) as T;
  }
}
