import { Logger, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { ApiExceptionFilter } from './common/api-exception.filter';
import { ApiResponseInterceptor } from './common/api-response.interceptor';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bufferLogs: true,
  });
  const config = app.get(ConfigService);
  const logger = new Logger('Bootstrap');

  app.enableShutdownHooks();
  app.setGlobalPrefix('api');
  app.set('trust proxy', parseTrustProxy(config.get<string>('TRUST_PROXY')));
  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidNonWhitelisted: true,
    }),
  );
  app.useGlobalInterceptors(new ApiResponseInterceptor());
  app.useGlobalFilters(new ApiExceptionFilter());

  const corsOrigins = parseCorsOrigins(config.get<string>('CORS_ORIGINS'));
  app.enableCors({
    origin: corsOrigins.length > 0 ? corsOrigins : false,
  });

  const swaggerConfig = new DocumentBuilder()
    .setTitle('夜深应用服务')
    .setDescription('夜深客户端的联网能力，首个模块为天气。')
    .setVersion('0.1.0')
    .build();
  SwaggerModule.setup('api/docs', app, SwaggerModule.createDocument(app, swaggerConfig));

  const port = parsePort(config.get<string>('PORT'));
  await app.listen(port);
  logger.log(`夜深应用服务已启动：http://localhost:${port}/api`);
}

function parseCorsOrigins(value?: string): string[] {
  return (value ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
}

function parsePort(value?: string): number {
  const port = Number.parseInt(value ?? '8080', 10);
  return Number.isInteger(port) && port > 0 && port <= 65_535 ? port : 8080;
}

function parseTrustProxy(value?: string): boolean | number {
  if (!value || value === 'false' || value === '0') return false;
  if (value === 'true') return true;
  const hops = Number.parseInt(value, 10);
  return Number.isInteger(hops) && hops > 0 ? hops : false;
}

void bootstrap();
