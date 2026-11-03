#!/usr/bin/env bash
# 用未入库的 .env.local 起本地调试。
#
#   tool/run_local.sh                      # 起当前设备
#   tool/run_local.sh -d emulator-5554     # 参数原样传给 flutter run
#
# 仓库里不保存线上接口地址（见 lib/core/config/app_config.dart），所以本地
# 想看到天气就得先配一份 .env.local：
#
#   cp .env.local.example .env.local   # 填上 WEATHER_API_BASE_URL
#
# 不配也能跑，只是首页没有天气卡；指向本机 NestJS 服务时同理可以用
# WEATHER_API_BASE_URL=http://127.0.0.1:8080/api（debug 包放行明文）。
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env.local ]; then
  echo "缺少 .env.local：先 cp .env.local.example .env.local，再填 WEATHER_API_BASE_URL。" >&2
  echo "（也可以跳过，直接 flutter run —— 只是首页不会显示天气。）" >&2
  exit 1
fi

if ! grep -Eq '^[[:space:]]*WEATHER_API_BASE_URL=.+' .env.local; then
  echo "提示：.env.local 里的 WEATHER_API_BASE_URL 还是空的，这次不会请求天气。" >&2
fi

exec flutter run --dart-define-from-file=.env.local "$@"
