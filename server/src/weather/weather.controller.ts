import { Controller, Get, Query, Req } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiServiceUnavailableResponse,
  ApiTags,
} from '@nestjs/swagger';
import { Request } from 'express';
import { WeatherQueryDto } from './dto/weather-query.dto';
import { WeatherApiResponseDto } from './dto/weather-response.dto';
import { WeatherService } from './weather.service';
import { WeatherData } from './weather.types';

@ApiTags('weather')
@Controller('weather')
export class WeatherController {
  constructor(private readonly weatherService: WeatherService) {}

  @Get()
  @ApiOperation({
    summary: '根据城市或请求 IP 获取当前天气和三日预报',
  })
  @ApiOkResponse({
    description: '天气数据',
    type: WeatherApiResponseDto,
  })
  @ApiBadRequestResponse({ description: '参数无效，或无法确定目标城市' })
  @ApiNotFoundResponse({ description: '城市未找到' })
  @ApiServiceUnavailableResponse({
    description: '天气服务未配置或上游暂时不可用',
  })
  getWeather(@Req() request: Request, @Query() query: WeatherQueryDto): Promise<WeatherData> {
    return this.weatherService.getWeather({
      clientIp: resolveClientIp(request),
      location: query.location,
      adm: query.adm,
      date: query.date,
    });
  }
}

function resolveClientIp(request: Request): string {
  const cloudflareIp = request.headers['cf-connecting-ip'];
  if (typeof cloudflareIp === 'string' && cloudflareIp.trim()) {
    return cloudflareIp.trim();
  }
  return request.ip || request.socket.remoteAddress || '';
}
