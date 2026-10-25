import { Module } from '@nestjs/common';
import { WeatherController } from './weather.controller';
import { FetchWeatherHttpClient, WEATHER_HTTP_CLIENT } from './weather-http.client';
import { WeatherService } from './weather.service';

@Module({
  controllers: [WeatherController],
  providers: [
    WeatherService,
    {
      provide: WEATHER_HTTP_CLIENT,
      useClass: FetchWeatherHttpClient,
    },
  ],
  exports: [WeatherService],
})
export class WeatherModule {}
