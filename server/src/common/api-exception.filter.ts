import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';

@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(ApiExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const response = context.getResponse<Response>();
    const request = context.getRequest<Request>();
    const status =
      exception instanceof HttpException ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;

    if (status >= HttpStatus.INTERNAL_SERVER_ERROR && !(exception instanceof HttpException)) {
      this.logger.error(
        `请求处理失败：${request.method} ${request.originalUrl}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    } else if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      this.logger.warn(
        `${status} ${request.method} ${request.originalUrl}：${this.getMessage(exception)}`,
      );
    }

    response.status(status).json({
      success: false,
      code: status,
      message: this.getMessage(exception),
      data: null,
    });
  }

  private getMessage(exception: unknown): string {
    if (!(exception instanceof HttpException)) {
      return '服务内部错误';
    }

    const response = exception.getResponse();
    if (typeof response === 'string') return response;
    if (typeof response !== 'object' || response === null) {
      return exception.message;
    }

    const message = (response as { message?: unknown }).message;
    if (Array.isArray(message)) return message.map(String).join('；');
    if (typeof message === 'string') return message;
    return exception.message;
  }
}
