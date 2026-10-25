import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class WeatherResponseDto {
  @ApiProperty({ description: '城市名称', example: '上海' })
  city!: string;

  @ApiProperty({ description: '纬度', example: 31.23 })
  latitude!: number;

  @ApiProperty({ description: '经度', example: 121.47 })
  longitude!: number;

  @ApiProperty({ description: '预报日期', example: '2026-10-25' })
  forecastDate!: string;

  @ApiProperty({ description: '当前或目标日期的气温（℃）', example: 24 })
  temperature!: number;

  @ApiProperty({ description: '最高气温（℃）', example: 27 })
  temperatureMax!: number;

  @ApiProperty({ description: '最低气温（℃）', example: 19 })
  temperatureMin!: number;

  @ApiProperty({ description: '跨平台天气代码', example: 1 })
  weatherCode!: number;

  @ApiProperty({ description: '天气文案', example: '大体晴朗' })
  weatherText!: string;

  @ApiProperty({ description: '天气图标', example: '🌤️' })
  weatherEmoji!: string;

  @ApiProperty({ description: '是否白天', example: true })
  isDay!: boolean;

  @ApiProperty({ description: '风速（km/h）', example: 12 })
  windspeed!: number;

  @ApiPropertyOptional({ description: '相对湿度（%）', example: 68 })
  humidity?: number;

  @ApiPropertyOptional({ description: '降雨量（mm）', example: 0 })
  precip?: number;
}

export class WeatherApiResponseDto {
  @ApiProperty({ example: true })
  success!: boolean;

  @ApiProperty({ example: 0 })
  code!: number;

  @ApiProperty({ example: 'success' })
  message!: string;

  @ApiProperty({ type: WeatherResponseDto })
  data!: WeatherResponseDto;
}
