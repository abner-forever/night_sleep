import { Transform } from 'class-transformer';
import { IsOptional, IsString, Matches, MaxLength } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';

const trim = ({ value }: { value: unknown }): unknown =>
  typeof value === 'string' ? value.trim() : value;

export class WeatherQueryDto {
  @ApiPropertyOptional({
    description: '城市名、Location ID、Adcode 或经度,纬度',
    example: '上海',
  })
  @Transform(trim)
  @IsOptional()
  @IsString({ message: 'location 必须是字符串' })
  @MaxLength(100, { message: 'location 不能超过 100 个字符' })
  location?: string;

  @ApiPropertyOptional({
    description: '上级行政区划，用于排除重名城市',
    example: '上海',
  })
  @Transform(trim)
  @IsOptional()
  @IsString({ message: 'adm 必须是字符串' })
  @MaxLength(100, { message: 'adm 不能超过 100 个字符' })
  adm?: string;

  @ApiPropertyOptional({
    description: '目标日期，仅支持今天和未来两天',
    example: '2026-10-25',
  })
  @Transform(trim)
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/, {
    message: 'date 必须使用 YYYY-MM-DD 格式',
  })
  date?: string;
}
