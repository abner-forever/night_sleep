import { Controller, Get } from '@nestjs/common';
import { ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';

@ApiTags('health')
@Controller('health')
export class AppController {
  @Get()
  @ApiOperation({ summary: '检查服务是否存活' })
  @ApiOkResponse({
    description: '服务存活时返回固定状态。',
    schema: {
      example: {
        success: true,
        code: 0,
        message: 'success',
        data: {
          status: 'ok',
          service: 'night-sleep-server',
          timestamp: '2026-10-25T08:00:00.000Z',
        },
      },
    },
  })
  getHealth(): {
    status: string;
    service: string;
    timestamp: string;
  } {
    return {
      status: 'ok',
      service: 'night-sleep-server',
      timestamp: new Date().toISOString(),
    };
  }
}
