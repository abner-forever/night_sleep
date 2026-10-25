import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller';
import { WeatherModule } from './weather/weather.module';

const readLocalEnvFile = process.env.NODE_ENV !== 'production';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      ignoreEnvFile: !readLocalEnvFile,
      envFilePath: readLocalEnvFile ? ['.env.local', '.env'] : undefined,
    }),
    WeatherModule,
  ],
  controllers: [AppController],
})
export class AppModule {}
