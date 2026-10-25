import { INestApplication, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { ApiExceptionFilter } from './common/api-exception.filter';
import { ApiResponseInterceptor } from './common/api-response.interceptor';

interface ApplicationSetupOptions {
  serveSwagger?: boolean;
}

export function configureApplication(
  application: INestApplication,
  config: ConfigService,
  options: ApplicationSetupOptions = {},
): void {
  const app = application as NestExpressApplication;

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

  if (options.serveSwagger !== false) {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('夜深应用服务')
      .setDescription('夜深客户端的联网能力，首个模块为天气。')
      .setVersion('0.1.0')
      .build();
    SwaggerModule.setup('api/docs', app, SwaggerModule.createDocument(app, swaggerConfig));
  }
}

function parseCorsOrigins(value?: string): string[] {
  return (value ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
}

export function parseTrustProxy(value?: string): boolean | number {
  if (!value || value === 'false' || value === '0') return false;
  if (value === 'true') return true;
  const hops = Number.parseInt(value, 10);
  return Number.isInteger(hops) && hops > 0 ? hops : false;
}
