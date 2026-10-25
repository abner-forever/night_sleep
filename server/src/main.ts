import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';
import { configureApplication } from './application.setup';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bufferLogs: true,
  });
  const config = app.get(ConfigService);
  const logger = new Logger('Bootstrap');

  app.enableShutdownHooks();
  configureApplication(app, config);

  const port = parsePort(config.get<string>('PORT'));
  await app.listen(port);
  logger.log(`夜深应用服务已启动：http://localhost:${port}/api`);
}

function parsePort(value?: string): number {
  const port = Number.parseInt(value ?? '8080', 10);
  return Number.isInteger(port) && port > 0 && port <= 65_535 ? port : 8080;
}

void bootstrap();
