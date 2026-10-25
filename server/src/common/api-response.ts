export interface ApiResponse<T> {
  success: boolean;
  code: number;
  message: string;
  data: T | null;
}

export function successResponse<T>(data: T): ApiResponse<T> {
  return {
    success: true,
    code: 0,
    message: 'success',
    data,
  };
}
