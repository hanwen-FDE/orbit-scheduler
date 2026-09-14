// =====================================================================
// 统一错误处理：
//   - 业务代码抛 ApiError(code, message, status)，这里统一转成 JSON 响应；
//   - 意外异常也兜住，返回 500 并记录日志，不让进程崩溃。
// 所有错误响应格式统一为：{ "error": { "code", "message", "request_id" } }
// =====================================================================

class ApiError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

function notFoundHandler(req, res) {
  res.status(404).json({
    error: { code: 'NOT_FOUND', message: `接口不存在：${req.method} ${req.path}`, request_id: req.id },
  });
}

// Express 会在异步路由抛错时自动进入这里（Express 4 需在路由中 next(err)，本项目统一用 asyncHandler 包装）
function errorHandler(err, req, res, _next) {
  const status = err.status || 500;
  const code = err.code || 'INTERNAL';
  const message = status < 500 ? err.message : '服务器内部错误，请稍后重试';
  if (status >= 500) {
    // 500 级别记录完整堆栈用于排查；400 级别只记一行
    require('../logger').error('request_failed', {
      request_id: req.id,
      method: req.method,
      path: req.path,
      status,
      error: err.message,
      stack: err.stack,
    });
  }
  res.status(status).json({
    error: { code, message, request_id: req.id },
  });
}

// 包装异步路由，把 reject 交给错误处理器
function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

module.exports = { ApiError, notFoundHandler, errorHandler, asyncHandler };
