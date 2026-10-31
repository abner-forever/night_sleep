import 'reflect-metadata';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { ExpressAdapter } from '@nestjs/platform-express';
import { httpServerHandler } from 'cloudflare:node';
import express from 'express';
import { createServer } from 'node:http';
import { AppModule } from './app.module';
import { configureApplication } from './application.setup';
import {
  GEO_CITY_HEADER,
  GEO_HEADERS,
  GEO_LATITUDE_HEADER,
  GEO_LONGITUDE_HEADER,
  encodeGeoCity,
} from './weather/geo-headers';

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
    return handler.fetch(withRequestGeo(request), env, context);
  },
};

/**
 * 把 `request.cf` 里的城市与坐标写进请求头，交给 Node 侧的城市解析用。
 *
 * 客户端自带的同名头先删掉再写：这三个头是「边缘算出来的位置」，不能被外部伪造。
 * `request.cf` 取不到坐标时（本地 `wrangler dev`、非 Cloudflare 来源）就把头留空，
 * 服务端会退回按请求 IP 定位。
 */
function withRequestGeo(request: Request): Request<unknown, IncomingRequestCfProperties> {
  const cf = request.cf as IncomingRequestCfProperties | undefined;
  const headers = new Headers(request.headers);
  for (const name of GEO_HEADERS) headers.delete(name);

  const city = typeof cf?.city === 'string' ? cf.city.trim() : '';
  if (city) headers.set(GEO_CITY_HEADER, encodeGeoCity(city));

  const latitude = parseCoordinate(cf?.latitude, 90);
  const longitude = parseCoordinate(cf?.longitude, 180);
  if (latitude !== undefined && longitude !== undefined) {
    headers.set(GEO_LATITUDE_HEADER, String(latitude));
    headers.set(GEO_LONGITUDE_HEADER, String(longitude));
  }

  return new Request(request, { headers }) as Request<unknown, IncomingRequestCfProperties>;
}

function parseCoordinate(value: unknown, limit: number): number | undefined {
  if (typeof value !== 'string' && typeof value !== 'number') return undefined;
  const parsed = Number.parseFloat(String(value));
  if (!Number.isFinite(parsed) || Math.abs(parsed) > limit) return undefined;
  return parsed;
}

export default worker;
