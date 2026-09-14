// =====================================================================
// 服务入口：加载配置 -> 初始化数据库 -> 创建管理员 -> 监听端口。
// 启动：npm start（开发环境建议先复制 .env.example 为 .env 并填好）
// =====================================================================
const config = require('./config');
const logger = require('./logger');
require('./db');            // 引入即完成建表
const users = require('./services/users');
const app = require('./app');

function main() {
  // 首次启动按 .env 引导管理员账号
  users.bootstrapAdmin();

  app.listen(config.port, () => {
    logger.info('server_started', {
      port: config.port,
      env: config.env,
      oneapi: config.oneapi.baseUrl,
      point_packs: Object.keys(config.pointPacks),
    });
    console.log(`\n  Orbit 积分后端已启动: http://127.0.0.1:${config.port}`);
    console.log('  健康检查: GET /api/health\n');
  });
}

// 兜住所有未捕获异常，记录后退出（Docker 的 restart 策略会自动拉起）
process.on('uncaughtException', (err) => {
  logger.error('uncaught_exception', { error: err.message, stack: err.stack });
  process.exit(1);
});
process.on('unhandledRejection', (reason) => {
  logger.error('unhandled_rejection', { error: String(reason) });
});

main();
