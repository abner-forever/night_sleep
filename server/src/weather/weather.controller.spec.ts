import { INestApplication, NotFoundException, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { ApiExceptionFilter } from '../common/api-exception.filter';
import { ApiResponseInterceptor } from '../common/api-response.interceptor';
import { WeatherController } from './weather.controller';
import { WeatherService } from './weather.service';

describe('WeatherController', () => {
  let app: INestApplication;
  const weatherService = {
    getWeather: jest.fn(),
  };

  beforeEach(async () => {
    weatherService.getWeather.mockReset();
    const module = await Test.createTestingModule({
      controllers: [WeatherController],
      providers: [
        {
          provide: WeatherService,
          useValue: weatherService,
        },
      ],
    }).compile();

    app = module.createNestApplication();
    app.setGlobalPrefix('api');
    app.useGlobalPipes(
      new ValidationPipe({
        transform: true,
        whitelist: true,
        forbidNonWhitelisted: true,
      }),
    );
    app.useGlobalInterceptors(new ApiResponseInterceptor());
    app.useGlobalFilters(new ApiExceptionFilter());
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  it('按统一结构返回天气数据', async () => {
    const data = {
      city: '上海',
      latitude: 31.23,
      longitude: 121.47,
      forecastDate: '2026-10-25',
      temperature: 24,
      temperatureMax: 27,
      temperatureMin: 19,
      weatherCode: 1,
      weatherText: '大体晴朗',
      weatherEmoji: '🌤️',
      isDay: true,
      windspeed: 12,
      humidity: 68,
    };
    weatherService.getWeather.mockResolvedValue(data);

    const response = await request(app.getHttpServer())
      .get('/api/weather')
      .query({ location: '上海' })
      .expect(200);

    expect(response.body).toEqual({
      success: true,
      code: 0,
      message: 'success',
      data,
    });
    expect(weatherService.getWeather).toHaveBeenCalledWith(
      expect.objectContaining({ location: '上海' }),
    );
  });

  it('Cloudflare Worker 使用 CF-Connecting-IP 做城市定位', async () => {
    weatherService.getWeather.mockResolvedValue({
      city: '上海',
      latitude: 31.23,
      longitude: 121.47,
      forecastDate: '2026-10-25',
      temperature: 24,
      temperatureMax: 27,
      temperatureMin: 19,
      weatherCode: 1,
      weatherText: '大体晴朗',
      weatherEmoji: '🌤️',
      isDay: true,
      windspeed: 12,
    });

    await request(app.getHttpServer())
      .get('/api/weather')
      .set('CF-Connecting-IP', '203.0.113.8')
      .expect(200);

    expect(weatherService.getWeather).toHaveBeenCalledWith(
      expect.objectContaining({ clientIp: '203.0.113.8' }),
    );
  });

  it('把 Worker 转发的位置头解析成 clientGeo', async () => {
    weatherService.getWeather.mockResolvedValue({
      city: '杭州',
      latitude: 30.29,
      longitude: 120.16,
      forecastDate: '2026-10-25',
      temperature: 24,
      temperatureMax: 27,
      temperatureMin: 19,
      weatherCode: 1,
      weatherText: '大体晴朗',
      weatherEmoji: '🌤️',
      isDay: true,
      windspeed: 12,
    });

    await request(app.getHttpServer())
      .get('/api/weather')
      .set('CF-Connecting-IP', '203.0.113.8')
      .set('X-Night-Sleep-Geo-City', encodeURIComponent('杭州'))
      .set('X-Night-Sleep-Geo-Latitude', '30.2936')
      .set('X-Night-Sleep-Geo-Longitude', '120.1614')
      .expect(200);

    expect(weatherService.getWeather).toHaveBeenCalledWith(
      expect.objectContaining({
        clientIp: '203.0.113.8',
        clientGeo: { latitude: 30.2936, longitude: 120.1614, city: '杭州' },
      }),
    );
  });

  it('位置头缺坐标或超出范围时忽略', async () => {
    weatherService.getWeather.mockResolvedValue({
      city: '上海',
      latitude: 31.23,
      longitude: 121.47,
      forecastDate: '2026-10-25',
      temperature: 24,
      temperatureMax: 27,
      temperatureMin: 19,
      weatherCode: 1,
      weatherText: '大体晴朗',
      weatherEmoji: '🌤️',
      isDay: true,
      windspeed: 12,
    });

    await request(app.getHttpServer())
      .get('/api/weather')
      .set('X-Night-Sleep-Geo-City', encodeURIComponent('杭州'))
      .set('X-Night-Sleep-Geo-Latitude', '91')
      .set('X-Night-Sleep-Geo-Longitude', '120.1614')
      .expect(200);

    expect(weatherService.getWeather).toHaveBeenCalledWith(
      expect.objectContaining({ clientGeo: undefined }),
    );
  });

  it('把参数校验错误包装为统一错误响应', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/weather')
      .query({ date: '2026/10/25' })
      .expect(400);

    expect(response.body).toMatchObject({
      success: false,
      code: 400,
      data: null,
    });
    expect(response.body.message).toContain('YYYY-MM-DD');
    expect(weatherService.getWeather).not.toHaveBeenCalled();
  });

  it('保留城市未找到的 404 状态', async () => {
    weatherService.getWeather.mockRejectedValue(new NotFoundException('未找到城市“不存在”'));

    const response = await request(app.getHttpServer())
      .get('/api/weather')
      .query({ location: '不存在' })
      .expect(404);

    expect(response.body).toEqual({
      success: false,
      code: 404,
      message: '未找到城市“不存在”',
      data: null,
    });
  });
});
