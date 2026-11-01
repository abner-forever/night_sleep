#!/usr/bin/env bash
# 夜深应用服务：服务器一次性初始化（可选）。
#
# 在 Ubuntu 24.04 上执行：
#   sudo DEPLOY_USER=ubuntu bash deploy/bootstrap-server.sh
#
# 会做三件事：安装 Node.js 22 / rsync / pm2，创建 /var/www/night-sleep/{beta,prod}，
# 并把目录交给 DEPLOY_USER。重复执行是安全的。
#
# 宝塔面板用户请注意：如果已经用「Node 版本管理器」装过 Node 22，建议跳过本脚本的
# Node 安装，改用该版本自带的 npm 安装 pm2，并确保部署用户的 PATH 能找到 node
# （非交互式 SSH 不会加载 ~/.bashrc）。最省事的做法仍是让 /usr/bin/node 指向 22。
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-ubuntu}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/var/www/night-sleep}"

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 sudo 运行：sudo DEPLOY_USER=ubuntu bash $0" >&2
  exit 1
fi
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  echo "用户不存在：$DEPLOY_USER" >&2
  exit 1
fi

echo "==> 安装 rsync / curl / ca-certificates"
apt-get update -y
apt-get install -y rsync curl ca-certificates

node_major=0
if command -v node >/dev/null 2>&1; then
  node_major="$(node -p 'process.versions.node.split(".")[0]')"
fi
if [ "$node_major" -lt 22 ]; then
  echo "==> 安装 Node.js 22（当前版本：${node_major:-未安装}）"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
else
  echo "==> 已有 Node.js $(node -v)，跳过安装"
fi

if command -v pm2 >/dev/null 2>&1; then
  echo "==> 已有 pm2 $(pm2 -v)，跳过安装"
else
  echo "==> 安装 pm2"
  npm i -g pm2
fi

echo "==> 创建部署目录 $DEPLOY_ROOT/{beta,prod}"
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" \
  "$DEPLOY_ROOT" "$DEPLOY_ROOT/beta" "$DEPLOY_ROOT/prod"

cat <<EOF

初始化完成。接下来：
1. 把 CI 公钥写入 $DEPLOY_USER 的 ~/.ssh/authorized_keys（见 deploy/README.md 第二节）。
2. 首次部署前建好环境配置：
     sudo -u $DEPLOY_USER nano $DEPLOY_ROOT/prod/.env
   模板见仓库 server/.env.example。
3. 部署成功后设置开机自启：
     pm2 startup systemd -u $DEPLOY_USER --hp $(getent passwd "$DEPLOY_USER" | cut -d: -f6)
   （之后每次部署脚本都会执行 pm2 save）
4. 域名与反向代理见 server/deploy/nginx.conf.example。
EOF
