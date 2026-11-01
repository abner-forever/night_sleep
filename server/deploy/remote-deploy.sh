#!/usr/bin/env bash
# 夜深应用服务：远端部署脚本。
#
# 由 CI 在部署目录内调用，也可以在服务器上手动执行：
#   APP_ENV=prod PORT=8080 bash deploy/remote-deploy.sh
#
# 前提：部署目录里已有 .env，服务器已安装 Node.js 22+ 与 pm2。
set -euo pipefail

APP_ENV="${APP_ENV:?需要 APP_ENV（beta 或 prod）}"
PORT="${PORT:?需要 PORT}"
NPM_REGISTRY="${NPM_REGISTRY:-}"

case "$APP_ENV" in
  beta|prod) ;;
  *)
    echo "APP_ENV 只能是 beta 或 prod，收到：$APP_ENV" >&2
    exit 2
    ;;
esac

cd "$(dirname "$0")/.."
APP_NAME="night-sleep-$APP_ENV"

if [ ! -f .env ]; then
  echo "部署目录缺少 .env：$(pwd)/.env" >&2
  if [ -f .env.example ]; then
    echo "模板已放在 $(pwd)/.env.example，执行 cp .env.example .env 并填好和风天气配置后重新部署。" >&2
  fi
  exit 1
fi
if [ ! -f dist/main.js ]; then
  echo "缺少 dist/main.js，构建产物没有上传完整。" >&2
  exit 1
fi
command -v node >/dev/null 2>&1 || {
  echo "未找到 node，请先安装 Node.js 22+。" >&2
  exit 1
}
command -v pm2 >/dev/null 2>&1 || {
  echo "未找到 pm2，请执行 npm i -g pm2。" >&2
  exit 1
}

mkdir -p logs

echo "==> 安装生产依赖"
if [ -n "$NPM_REGISTRY" ]; then
  npm ci --omit=dev --no-audit --no-fund \
    --registry="$NPM_REGISTRY" --replace-registry-host=always
else
  npm ci --omit=dev --no-audit --no-fund
fi

echo "==> 启动 / 重载 PM2 应用：$APP_NAME（端口 $PORT）"
APP_ENV="$APP_ENV" PORT="$PORT" pm2 startOrReload ecosystem.config.cjs --update-env
pm2 save

echo "==> 健康检查 http://127.0.0.1:$PORT/api/health"
for _ in $(seq 1 30); do
  if PORT="$PORT" node -e "fetch('http://127.0.0.1:' + process.env.PORT + '/api/health').then((r) => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"; then
    echo "部署完成：$APP_NAME 在端口 $PORT 正常运行。"
    exit 0
  fi
  sleep 2
done

echo "健康检查失败，最近日志：" >&2
pm2 logs "$APP_NAME" --nostream --lines 80 >&2 || true
exit 1
