import 'reflect-metadata';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { ExpressAdapter } from '@nestjs/platform-express';
import { httpServerHandler } from 'cloudflare:node';
import express from 'express';
import { createServer } from 'node:http';
import { AppModule } from './app.module';
import { configureApplication } from './application.setup';

const INTERNAL_PORT = 8080;

interface WorkerEnv {
  [key: string]: unknown;
}

let handlerPromise: Promise<ReturnType<typeof httpServerHandler>> | undefined;

async function createWorkerHandler(): Promise<ReturnType<typeof httpServerHandler>> {
  const expressApp = express();
  const adapter = new ExpressAdapter(expressApp);
  const app = await NestFactory.create(AppModule, adapter, {
    bufferLogs: true,
  });

  configureApplication(app, app.get(ConfigService), {
    serveSwagger: false,
  });
  await app.init();

  const server = createServer(expressApp);
  server.listen(INTERNAL_PORT);
  return httpServerHandler({ port: INTERNAL_PORT });
}

function getWorkerHandler(): Promise<ReturnType<typeof httpServerHandler>> {
  handlerPromise ??= createWorkerHandler();
  return handlerPromise;
}

const worker: ExportedHandler<WorkerEnv> = {
  async fetch(request, env, context): Promise<Response> {
    const handler = await getWorkerHandler();
    if (!handler.fetch) {
      throw new Error('Cloudflare Node HTTP handler 未提供 fetch 入口');
    }
    return handler.fetch(request, env, context);
  },
};

export default worker;
