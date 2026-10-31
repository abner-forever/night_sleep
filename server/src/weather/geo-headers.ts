/**
 * Cloudflare 边缘算好的请求地理位置，由 Worker 入口写进请求头再交给 Express。
 *
 * 为什么要自己转发：`cloudflare:node` 的 `httpServerHandler` 只把 HTTP 报文
 * 交给 Node 侧，`request.cf` 不会跟着过去；而 `cf.city/latitude/longitude`
 * 是 Cloudflare 用自己的 IP 库算出来的，比再找第三方接口查一次更准、更省一次
 * 外网请求，也不把用户 IP 发给外部服务。
 *
 * 这三个头只在 Worker 入口被信任：入口会先删掉客户端自带的同名头，再用
 * `request.cf` 重写，所以外部无法伪造位置。
 */
export const GEO_CITY_HEADER = 'x-night-sleep-geo-city';
export const GEO_LATITUDE_HEADER = 'x-night-sleep-geo-latitude';
export const GEO_LONGITUDE_HEADER = 'x-night-sleep-geo-longitude';

export const GEO_HEADERS = [GEO_CITY_HEADER, GEO_LATITUDE_HEADER, GEO_LONGITUDE_HEADER] as const;

/** 头部只能放 ASCII，城市名（中文）先做 URL 编码。 */
export function encodeGeoCity(city: string): string {
  return encodeURIComponent(city);
}

export function decodeGeoCity(value: string | string[] | undefined): string | undefined {
  const raw = Array.isArray(value) ? value[0] : value;
  if (!raw) return undefined;
  try {
    const decoded = decodeURIComponent(raw).trim();
    return decoded || undefined;
  } catch {
    // 头部被手工塞进了非法 % 序列：当作没有城市名，不影响坐标定位。
    return undefined;
  }
}

export function parseGeoCoordinate(
  value: string | string[] | undefined,
  limit: number,
): number | undefined {
  const raw = Array.isArray(value) ? value[0] : value;
  if (!raw) return undefined;
  const parsed = Number.parseFloat(raw);
  if (!Number.isFinite(parsed) || Math.abs(parsed) > limit) return undefined;
  return parsed;
}
