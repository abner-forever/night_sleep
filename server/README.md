# 夜深应用服务

基于 NestJS 11 的应用服务，首个模块是和风天气。服务只接收城市、日期和网络位置，
不接收睡眠记录、备注或音频。

## 环境要求

- Node.js 22+
- 一个启用 JWT 凭据的和风天气项目

## 本地运行

```powershell
cd server
npm install
Copy-Item .env.example .env
# 填写 .env 中的 QWEATHER_* 配置
npm run dev
```

模拟器访问宿主机时，可在 `server/.env` 中临时设置 `WEATHER_DEFAULT_LOCATION=上海`，
避免私有 IP 无法定位城市。服务默认监听 `http://localhost:8080`。

```bash
curl "http://localhost:8080/api/weather?location=上海"
curl "http://localhost:8080/api/weather?location=上海&date=2026-10-26"
curl "http://localhost:8080/api/health"
```

Swagger 文档位于 `http://localhost:8080/api/docs`。

## Cloudflare Workers

本项目同时提供 Cloudflare Worker 入口。Cloudflare 项目必须是 **Worker**，不能使用只识别静态文件的
Pages 静态站点配置。Workers Builds 使用：

- Worker 名称：`night-sleep`
- 构建命令：`npm run build`
- 部署命令：`npx wrangler deploy`

`npx wrangler deploy` 发布正式 Worker。`npx wrangler preview` 是 Cloudflare 的预览部署命令，
需要 `wrangler.jsonc` 中独立的 `previews` 配置，预览环境的密钥通过
`npx wrangler preview secret put <名称>` 单独管理。不要用 Preview 代替正式部署。

部署前在 Cloudflare 的 Variables and Secrets 中配置 `QWEATHER_API_HOST`、
`QWEATHER_PRIVATE_KEY`、`QWEATHER_PROJECT_ID`、`QWEATHER_KEY_ID` 和
`QWEATHER_DEVELOPER_ID`。私钥必须使用 Secret，不能作为普通变量提交到仓库。

Worker 通过 Cloudflare 的 Node HTTP 兼容层运行 NestJS，生产环境不暴露 Swagger UI；本地 Node
模式仍可通过 `http://localhost:8080/api/docs` 查看。可先运行 `npm run dev:worker` 在 Workerd
中检查 Worker 入口。

## 天气接口

`GET /api/weather`

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `location` | 否 | 城市名、Location ID、Adcode 或 `经度,纬度`；为空时使用配置默认城市或公网 IP |
| `adm` | 否 | 上级行政区划，用于排除重名城市 |
| `date` | 否 | `YYYY-MM-DD`，仅支持今天和未来两天 |

成功响应：

```json
{
  "success": true,
  "code": 0,
  "message": "success",
  "data": {
    "city": "上海",
    "latitude": 31.23,
    "longitude": 121.47,
    "forecastDate": "2026-10-25",
    "temperature": 24,
    "temperatureMax": 27,
    "temperatureMin": 19,
    "weatherCode": 1,
    "weatherText": "大体晴朗",
    "weatherEmoji": "🌤️",
    "isDay": true,
    "windspeed": 12,
    "humidity": 68,
    "precip": 0
  }
}
```

城市无法解析时返回 404，上游不可用或配置缺失时返回 503，不会返回可供展示的占位天气。

## 验证

```powershell
npm run typecheck
npm test
npm run build
npm run dev:worker
```
