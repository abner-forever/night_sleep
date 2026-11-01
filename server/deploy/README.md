# 服务端部署（GitHub Actions → PM2）

`beta` 分支推送自动部署测试服，`main` 分支推送自动部署正式服。两个环境通过 GitHub
Environment 分开存服务器信息，所以**一台服务器跑两套**或**两台服务器各跑一套**都可以。

默认落点：

```
GitHub Actions                               云服务器
npm ci / typecheck / test / build
        │
        ├─ rsync dist、package*.json、ecosystem.config.cjs、deploy/*.sh、.env.example
        ▼
/var/www/night-sleep/beta   ← PM2: night-sleep-beta，端口 8081
/var/www/night-sleep/prod   ← PM2: night-sleep-prod，端口 8080

域名（Nginx 反向代理）：
  https://beta.xxx.com/api  → 127.0.0.1:8081
  https://xxx.com/api       → 127.0.0.1:8080
```

每次部署前会把上一份 `dist` 存成 `dist.prev`，出问题用 `deploy/rollback.sh` 回滚。
部署目录里的 `.env` **不由 CI 覆盖**，只在服务器上维护。

## 一、服务器一次性准备

以腾讯云 Hermes Agent 镜像默认的 `ubuntu` 用户为例（Ubuntu 24.04）。下面三种做法选一种：

### 1.1 目录与权限

`/var/www` 通常是 root 所有，**只把 `night-sleep` 子目录交给部署用户**，不要动 `/var/www` 本身：

```bash
sudo mkdir -p /var/www/night-sleep/beta /var/www/night-sleep/prod
sudo chown -R ubuntu:ubuntu /var/www/night-sleep
```

> 如果你用 `root` 登录部署，可以跳过 `chown`，并把 GitHub 里的 `SERVER_USER` 设为 `root`。
> 不建议长期用 root，能免密 SSH 的 root 账号风险更高。

### 1.2 安装 Node.js 22 与 pm2

任选其一：

```bash
# 做法 A：仓库里的初始化脚本（装 Node 22、rsync、pm2，并建好上面两个目录）
sudo DEPLOY_USER=ubuntu bash server/deploy/bootstrap-server.sh

# 做法 B：手动
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs rsync
sudo npm i -g pm2
```

宝塔面板用户：如果用「Node 版本管理器」装了 Node 22，也可以先跳过 NodeSource；但要通过它自带的
npm 安装 pm2，并确保**非交互式 SSH 登录**也能找到 node（部署时不会加载 `~/.bashrc`）。
拿不准就直接用上面的 `/usr/bin/node`（NodeSource），最省事。

### 1.3 准备 `.env`

首次部署前先把配置文件建好（或者先跑一次部署，让 CI 把 `.env.example` 传上来）：

```bash
cp /var/www/night-sleep/prod/.env.example /var/www/night-sleep/prod/.env   # 首次部署后会有模板
nano /var/www/night-sleep/prod/.env
```

必填和风天气五项：`QWEATHER_API_HOST`、`QWEATHER_PRIVATE_KEY`、`QWEATHER_PROJECT_ID`、
`QWEATHER_KEY_ID`、`QWEATHER_DEVELOPER_ID`。建议再设：

```ini
NODE_ENV=production
TRUST_PROXY=1                                   # 在 Nginx 后面
CORS_ORIGINS=https://xxx.com,https://beta.xxx.com   # 只有网页端需要；App 不需要
```

`PORT` 不用写，PM2 会按 `APP_PORT` 注入（默认正式 8080、测试 8081）。

### 1.4 开机自启

```bash
pm2 startup systemd -u ubuntu --hp /home/ubuntu   # 按提示执行输出的那条 sudo 命令
```

之后每次部署脚本都会 `pm2 save`。重启服务器后 PM2 会自动拉起两个应用。

## 二、让 GitHub 连上服务器（IP / 用户名 / 密钥）

GitHub Actions 通过 SSH 登录你的服务器，需要三样东西：**服务器地址、SSH 用户名、私钥**。
私钥存 GitHub Secret，公钥存服务器。`beta` 和 `main` 分别对应两个 GitHub 环境，
各自可以指向同一台或不同服务器。

### 2.1 在本机生成一对 CI 专用密钥

```bash
ssh-keygen -t ed25519 -C "night-sleep-ci" -f night-sleep-ci -N ""
# 生成 night-sleep-ci（私钥）与 night-sleep-ci.pub（公钥）
```

不要把私钥提交进仓库，也不要复用你个人的 SSH 私钥。

### 2.2 把公钥装到服务器

```bash
# 本机执行（把 IP 换成你的服务器）
ssh-copy-id -i night-sleep-ci.pub ubuntu@<服务器IP>
```

没有 `ssh-copy-id`（Windows 常见）时，二选一：

- 用腾讯云 OrcaTerm / 宝塔终端登录，把 `night-sleep-ci.pub` **一整行**追加到
  `/home/ubuntu/.ssh/authorized_keys`，然后：

  ```bash
  chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
  ```

- 登录用的用户如果是 `root`，就写到 `/root/.ssh/authorized_keys`。

验证连接（本机）：

```bash
ssh -i night-sleep-ci ubuntu@<服务器IP> "echo connected"
```

云安全组/防火墙要放行 SSH 端口（默认 22）。GitHub 托管 Runner 的出口 IP 不固定，
密钥登录下建议对 `0.0.0.0/0` 放行 22，或改用自托管 Runner。

### 2.3 在 GitHub 建两个环境

仓库 **Settings → Environments → New environment**，建两个：

- `server-beta` —— 对应 `beta` 分支
- `server-prod` —— 对应 `main` 分支（建议加 Required reviewers，上线前人工确认）

两个环境里填**同名**的 Variables，值按环境不同。同一台服务器示例：

| 类型 | 名称 | `server-beta` | `server-prod` |
| --- | --- | --- | --- |
| Variable | `SERVER_HOST` | `1.2.3.4` | `1.2.3.4` |
| Variable | `SERVER_USER` | `ubuntu` | `ubuntu` |
| Variable | `SERVER_PORT` | `22`（可留空） | `22`（可留空） |
| Variable | `DEPLOY_PATH` | `/var/www/night-sleep/beta` | `/var/www/night-sleep/prod` |
| Variable | `APP_PORT` | `8081` | `8080` |
| Variable | `NPM_REGISTRY` | `https://registry.npmmirror.com`（可选） | 同左 |
| Secret | `SERVER_SSH_KEY` | 私钥 `night-sleep-ci` 全文 | 私钥 `night-sleep-ci` 全文 |

两点说明：

- `DEPLOY_PATH`、`APP_PORT` 不填也能用，工作流默认取 `/var/www/night-sleep/<环境>`
  和 `8081`/`8080`；填了以你填的为准。
- 两台服务器分别部署时，只需要把两个环境的 `SERVER_HOST` 改成各自的 IP。

`SERVER_SSH_KEY` 填**私钥全文**，包含 `-----BEGIN OPENSSH PRIVATE KEY-----` 与结尾行。
Secret 按环境隔离，所以两个环境都要各填一次。

### 2.4 触发规则

| 事件 | 目标环境 |
| --- | --- |
| push `beta`（改动 `server/**` 或工作流文件） | `server-beta` |
| push `main`（同上） | `server-prod` |
| Actions 页手动运行「服务端 · PM2 部署」，选目标 | 所选环境 |

手动部署记得在 Actions 页面**选对分支**：发测试选 `beta`，发正式选 `main`。

流水线先跑 `npm run typecheck`、`npm test`、`npm run build`，任一步失败都不会碰服务器。

## 三、域名与子域名

### 3.1 DNS

到域名服务商加 A 记录，都指向服务器公网 IP：

| 主机记录 | 记录类型 | 记录值 |
| --- | --- | --- |
| `@` 或 `www` | A | 服务器 IP（正式服） |
| `beta` | A | 服务器 IP（测试服；两台服务器时填测试服 IP） |

### 3.2 Nginx 反向代理

完整示例见 `server/deploy/nginx.conf.example`，核心是 `server_name` 区分环境：

```nginx
server {
    listen 80;
    server_name xxx.com www.xxx.com;
    location /api/ { proxy_pass http://127.0.0.1:8080; }
}

server {
    listen 80;
    server_name beta.xxx.com;
    location /api/ { proxy_pass http://127.0.0.1:8081; }
}
```

- 原生 Nginx：放到 `/etc/nginx/conf.d/night-sleep.conf`，`nginx -t && nginx -s reload`。
- 宝塔面板：网站 → 添加站点 `xxx.com` / `beta.xxx.com` → 设置 → 反向代理，
  目标 URL 分别填 `http://127.0.0.1:8080`、`http://127.0.0.1:8081`。
- `proxy_pass` **不要加尾斜杠**，否则 `/api` 前缀会被去掉，后端收到的是 `/weather`。

### 3.3 HTTPS

宝塔在「网站 → SSL」申请 Let's Encrypt 即可；原生 Nginx：

```bash
sudo certbot --nginx -d xxx.com -d www.xxx.com -d beta.xxx.com
```

### 3.4 客户端要填的地址

App 的 `WEATHER_API_BASE_URL` **包含 `/api` 前缀**：

- 正式：`https://xxx.com/api`
- 测试：`https://beta.xxx.com/api`

当前 `.github/workflows/android.yml` 两个分支共用仓库变量 `WEATHER_API_BASE_URL`，
所以 beta 包默认也会连正式服。要让 beta 包连测试服，需要把该工作流里的变量改成按分支取值
（例如用两个 Environment 变量），这不在本次服务端部署范围内，需要时再改。

## 四、手动操作（在服务器上）

```bash
cd /var/www/night-sleep/prod

# 重新部署当前目录里的构建产物（例如只改了 .env 后重启）
APP_ENV=prod PORT=8080 bash deploy/remote-deploy.sh

# 回滚到上一次部署的 dist（首次部署后才有 dist.prev）
APP_ENV=prod PORT=8080 bash deploy/rollback.sh

# 状态与日志
pm2 status
pm2 logs night-sleep-prod --nostream --lines 100
pm2 restart night-sleep-prod --update-env
```

## 五、常见问题

**`Permission denied` 写不进 `/var/www/night-sleep`**
目录属主不是部署用户。执行 `sudo chown -R ubuntu:ubuntu /var/www/night-sleep`，
或者把 `SERVER_USER` 改成实际拥有该目录的用户。

**非交互 SSH 找不到 node / pm2**
GitHub Actions 的 SSH 命令不加载 `~/.bashrc`。把 Node 装在 `/usr/bin`（NodeSource），
或给 `/usr/local/bin` 建软链；pm2 用 `sudo npm i -g pm2` 装到 `/usr/local/bin` 最稳。

**Actions 连不上服务器（Connection timed out）**
GitHub 托管 Runner 到国内云服务器偶有链路问题。可改用自托管 Runner，或去掉工作流里的
`rsync`/`ssh` 步骤，改为在服务器上 `git pull` 后执行 `deploy/remote-deploy.sh`。

**`npm ci` 很慢或超时**
在对应 Environment 里把 `NPM_REGISTRY` 设为 `https://registry.npmmirror.com`。

**健康检查失败**
脚本会打印最近 80 行 `pm2` 日志。先确认 `.env` 存在且和风天气五项齐全，
再确认端口没被占用：`ss -ltnp | grep 8081`。

**部署成功但外网访问不到**
应用默认监听 `0.0.0.0`。检查安全组、Nginx `server_name` 与 DNS 是否生效；
有反向代理时 `.env` 里要设 `TRUST_PROXY=1`，否则按 IP 定位天气会拿到代理地址。
