// =====================================================================
// Express 应用装配：中间件 + 路由 + 统一错误处理。
// =====================================================================
const crypto = require('crypto');
const express = require('express');
const logger = require('./logger');

const authRoutes = require('./routes/auth');
const meRoutes = require('./routes/me');
const iapRoutes = require('./routes/iap');
const notificationsRoutes = require('./routes/notifications');
const adminRoutes = require('./routes/admin');
const healthRoutes = require('./routes/health');

const { notFoundHandler, errorHandler } = require('./middleware/errorHandler');

const app = express();

// 经过 nginx 反代时按 X-Forwarded-For 取真实 IP（限流依赖它）
app.set('trust proxy', 1);

// 每个请求分配一个 ID，贯穿日志和错误响应，方便排查
app.use((req, res, next) => {
  req.id = crypto.randomUUID();
  res.setHeader('X-Request-Id', req.id);
  next();
});

// 基础安全响应头
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  next();
});

// 请求日志：方法、路径、状态码、耗时
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    if (req.path === '/api/health') return; // 健康检查不刷屏
    logger.info('http_request', {
      request_id: req.id,
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration_ms: Date.now() - start,
      ip: req.ip,
    });
  });
  next();
});

// 收据是 base64 大字符串，放宽 JSON 体积限制到 4MB
app.use(express.json({ limit: '4mb' }));

// ---- 业务路由 ----
app.use('/api/auth', authRoutes);
app.use('/api/me', meRoutes);
app.use('/api/iap', iapRoutes);
app.use('/api/notifications', notificationsRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/health', healthRoutes);

// ---- 兜底 ----
app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;
