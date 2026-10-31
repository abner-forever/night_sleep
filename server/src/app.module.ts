import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller';
import { WeatherModule } from './weather/weather.module';

/**
 * 是否跑在 Cloudflare Worker 里。
 *
 * 用「运行时是不是 Worker」而不是 `NODE_ENV=development` 判断要不要读 `.env`，
 * 是因为后者有先有后的问题：`NODE_ENV` 本身也可能写在 `.env` 里，可 `NODE_ENV`
 * 为空时恰恰又不读这个文件，于是 `npm run start` 里 `.env` 明明有值，配置全是空。
 */
const isCloudflareWorker =
  typeof navigator !== 'undefined' && navigator.userAgent === 'Cloudflare-Workers';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      // Worker 没有文件系统，也不该读本地文件；Node 侧（开发、start:prod）一律读。
      // 真实环境变量优先级高于文件，production 用平台注入的变量时不受影响。
      ignoreEnvFile: isCloudflareWorker,
      envFilePath: isCloudflareWorker ? undefined : ['.env.local', '.env'],
    }),
    WeatherModule,
  ],
  controllers: [AppController],
})
export class AppModule {}
