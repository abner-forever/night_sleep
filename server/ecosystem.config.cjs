// PM2 进程配置。部署脚本通过 APP_ENV / PORT 选择环境：
//   APP_ENV=beta PORT=8081  → 测试服
//   APP_ENV=prod PORT=8080  → 正式服
// 两个环境可以落在同一台服务器的不同目录，也可以各用一台服务器。
const appEnv = process.env.APP_ENV === 'beta' ? 'beta' : 'prod';
const port = process.env.PORT || (appEnv === 'beta' ? '8081' : '8080');

module.exports = {
  apps: [
    {
      name: `night-sleep-${appEnv}`,
      cwd: __dirname,
      script: 'dist/main.js',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_memory_restart: '512M',
      time: true,
      out_file: './logs/out.log',
      error_file: './logs/error.log',
      merge_logs: true,
      env: {
        NODE_ENV: 'production',
        APP_ENV: appEnv,
        PORT: String(port),
      },
    },
  ],
};
