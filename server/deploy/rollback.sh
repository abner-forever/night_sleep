#!/usr/bin/env bash
# 夜深应用服务：回滚到上一次部署的构建产物。
#
# 在服务器部署目录内执行：
#   APP_ENV=prod PORT=8080 bash deploy/rollback.sh
#
# 每次部署前 CI 会把上一份 dist 留作 dist.prev；回滚就是把它换回来并重启 PM2。
set -euo pipefail

APP_ENV="${APP_ENV:?需要 APP_ENV（beta 或 prod）}"
PORT="${PORT:?需要 PORT}"

cd "$(dirname "$0")/.."
APP_NAME="night-sleep-$APP_ENV"

if [ ! -d dist.prev ]; then
  echo "没有可回滚的版本：$(pwd)/dist.prev 不存在。" >&2
  exit 1
fi

echo "==> 回滚 $APP_NAME：用 dist.prev 替换 dist"
rm -rf dist.failed
mv dist dist.failed
mv dist.prev dist

APP_ENV="$APP_ENV" PORT="$PORT" pm2 restart "$APP_NAME" --update-env

echo "==> 健康检查 http://127.0.0.1:$PORT/api/health"
for _ in $(seq 1 30); do
  if PORT="$PORT" node -e "fetch('http://127.0.0.1:' + process.env.PORT + '/api/health').then((r) => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"; then
    rm -rf dist.failed
    echo "回滚完成：$APP_NAME 已恢复到上一版本。"
    exit 0
  fi
  sleep 2
done

echo "回滚后健康检查仍失败，失败版本保留在 $(pwd)/dist.failed，请查看：pm2 logs $APP_NAME --nostream" >&2
exit 1
