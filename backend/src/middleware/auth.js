// =====================================================================
// JWT 鉴权中间件：
//   - requireAuth  ：解析 Authorization: Bearer <token>，校验并把用户挂到 req.user
//   - requireAdmin ：在 requireAuth 基础上要求管理员角色
// 每次请求都从数据库重新读用户，账号被禁用后令牌立即失效。
// =====================================================================
const jwt = require('jsonwebtoken');
const config = require('../config');
const db = require('../db');
const { ApiError, asyncHandler } = require('./errorHandler');

function verifyToken(req) {
  const header = req.get('Authorization') || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new ApiError('AUTH_MISSING', '缺少登录令牌，请先登录', 401);
  let payload;
  try {
    payload = jwt.verify(match[1], config.jwtSecret);
  } catch {
    throw new ApiError('AUTH_INVALID', '登录令牌无效或已过期，请重新登录', 401);
  }
  if (!payload.sub) throw new ApiError('AUTH_INVALID', '登录令牌格式错误', 401);
  return payload;
}

const requireAuth = asyncHandler(async (req, _res, next) => {
  const payload = verifyToken(req);
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(Number(payload.sub));
  if (!user) throw new ApiError('AUTH_INVALID', '账号不存在', 401);
  if (user.status !== 'active') throw new ApiError('AUTH_DISABLED', '账号已被禁用', 403);
  req.user = user;
  next();
});

const requireAdmin = [requireAuth, (req, _res, next) => {
  if (req.user.role !== 'admin') {
    next(new ApiError('FORBIDDEN', '需要管理员权限', 403));
    return;
  }
  next();
}];

module.exports = { requireAuth, requireAdmin };
