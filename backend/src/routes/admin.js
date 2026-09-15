// =====================================================================
// 管理接口（需管理员令牌）：查订单、查用户、手工调点
// 用 .env 里 ADMIN_USERNAME/ADMIN_PASSWORD 登录拿到管理员 JWT 即可调用。
// =====================================================================
const express = require('express');
const db = require('../db');
const users = require('../services/users');
const iap = require('../services/iap');
const oneapi = require('../services/oneapi');
const config = require('../config');
const { requireAdmin } = require('../middleware/auth');
const { asyncHandler, ApiError } = require('../middleware/errorHandler');

const router = express.Router();
router.use(requireAdmin);

function timestamp(value, fallback) {
  if (!value) return fallback;
  const parsed = Date.parse(String(value));
  return Number.isNaN(parsed) ? fallback : Math.floor(parsed / 1000);
}

function usageRecord(row) {
  const quota = Number(row.quota || 0);
  return {
    id: row.id ?? row.request_id ?? null,
    request_id: row.request_id || '',
    username: row.username || '',
    model: row.model_name || row.model || '',
    token_name: row.token_name || '',
    prompt_tokens: Number(row.prompt_tokens || 0),
    completion_tokens: Number(row.completion_tokens || 0),
    cached_tokens: Number(row.cached_tokens || 0),
    quota,
    points: quota / config.oneapi.quotaPerPoint,
    elapsed_ms: Number(row.elapsed_time || 0),
    is_stream: Boolean(row.is_stream),
    created_at: row.created_at || row.timestamp || null,
  };
}

// GET /api/admin/overview —— 管理台总览卡片
router.get('/overview', asyncHandler(async (_req, res) => {
  const usersCount = db.prepare("SELECT COUNT(*) AS count FROM users WHERE role = 'user'").get().count;
  const orders = db.prepare(
    `SELECT COUNT(*) AS count,
            COALESCE(SUM(CASE WHEN status = 'delivered' THEN points ELSE 0 END), 0) AS delivered_points,
            COALESCE(SUM(CASE WHEN status = 'refunded' THEN points ELSE 0 END), 0) AS refunded_points
     FROM iap_orders`
  ).get();
  const ops = db.prepare(
    `SELECT COALESCE(SUM(CASE WHEN delta_points > 0 THEN delta_points ELSE 0 END), 0) AS credited,
            COALESCE(SUM(CASE WHEN delta_points < 0 THEN -delta_points ELSE 0 END), 0) AS debited
     FROM quota_ops`
  ).get();
  const end = Math.floor(Date.now() / 1000);
  const start = end - 30 * 24 * 60 * 60;
  let usage = { quota: 0 };
  let usageAvailable = true;
  try { usage = await oneapi.getLogsStat({ startTimestamp: start, endTimestamp: end }); }
  catch { usageAvailable = false; }
  res.json({
    users: Number(usersCount),
    orders: Number(orders.count),
    credited_points: Number(ops.credited),
    debited_points: Number(ops.debited),
    usage_30d: {
      quota: Number(usage.quota || 0),
      points: Number(usage.quota || 0) / config.oneapi.quotaPerPoint,
      available: usageAvailable,
    },
    generated_at: new Date().toISOString(),
  });
}));

// GET /api/admin/orders?status=&user_id=&limit=
router.get('/orders', asyncHandler(async (req, res) => {
  const { status, user_id, limit } = req.query;
  const conditions = [];
  const params = [];
  if (status) { conditions.push('o.status = ?'); params.push(status); }
  if (user_id) { conditions.push('o.user_id = ?'); params.push(user_id); }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const rows = db.prepare(
    `SELECT o.*, u.username FROM iap_orders o
     JOIN users u ON u.id = o.user_id
     ${where} ORDER BY o.id DESC LIMIT ?`
  ).all(...params, Math.min(Number(limit) || 100, 500));
  res.json({ orders: rows });
}));

// GET /api/admin/orders/:transaction_id —— 按苹果交易号查单
router.get('/orders/txn/:transaction_id', asyncHandler(async (req, res) => {
  const order = db.prepare(
    'SELECT o.*, u.username FROM iap_orders o JOIN users u ON u.id = o.user_id WHERE o.transaction_id = ?'
  ).get(req.params.transaction_id);
  if (!order) throw new ApiError('ORDER_NOT_FOUND', '订单不存在', 404);
  res.json({ order });
}));

// GET /api/admin/users/:id —— 用户详情 + 两个钱包余额
router.get('/users/:id', asyncHandler(async (req, res) => {
  const user = users.findById(Number(req.params.id));
  if (!user) throw new ApiError('USER_NOT_FOUND', '用户不存在', 404);
  const iosPoints = await users.getIosPoints(user);
  res.json({
    ...users.publicUser(user),
    status: user.status,
    ios_wallet: { oneapi_user_id: user.oneapi_ios_user_id, points: iosPoints },
    general_wallet_provisioned: Boolean(user.oneapi_general_user_id),
  });
}));

// POST /api/admin/users/:id/grant  { wallet: 'ios'|'general', points: ±N, reason: '...' }
router.post('/users/:id/grant', asyncHandler(async (req, res) => {
  const { wallet, points, reason } = req.body || {};
  const result = await iap.adminGrant(Number(req.params.id), wallet, Number(points), reason);
  res.json(result);
}));

// GET /api/admin/find?username=xxx —— 管理台用：按用户名/昵称查人 + iOS 钱包余额
router.get('/find', asyncHandler(async (req, res) => {
  const username = String(req.query.username || '').trim();
  if (!username) throw new ApiError('BAD_PARAM', '缺少 username 参数', 400);
  const user = db.prepare(
    'SELECT * FROM users WHERE username = ? OR display_name = ?'
  ).get(username, username);
  if (!user) throw new ApiError('USER_NOT_FOUND', '用户不存在', 404);
  const iosPoints = await users.getIosPoints(user);
  res.json({
    user: { ...users.publicUser(user), status: user.status, created_at: user.created_at },
    ios_wallet: { oneapi_user_id: user.oneapi_ios_user_id, points: iosPoints },
  });
}));

// GET /api/admin/ops?user_id=&limit= —— 管理台用：某用户的积分流水
router.get('/ops', asyncHandler(async (req, res) => {
  const userId = req.query.user_id ? Number(req.query.user_id) : null;
  if (req.query.user_id && (!Number.isInteger(userId) || userId <= 0)) throw new ApiError('BAD_PARAM', 'user_id 无效', 400);
  const limit = Math.min(Number(req.query.limit) || 50, 200);
  const rows = db.prepare(
    `SELECT q.id, q.user_id, u.username, q.wallet, q.delta_points, q.reason,
            q.oneapi_quota_before, q.oneapi_quota_after, q.created_at
     FROM quota_ops q JOIN users u ON u.id = q.user_id
     ${userId ? 'WHERE q.user_id = ?' : ''}
     ORDER BY q.id DESC LIMIT ?`
  ).all(...(userId ? [userId, limit] : [limit]));
  res.json({ ops: rows });
}));

// GET /api/admin/usage —— 从 OneAPI 读取真实模型调用流水
router.get('/usage', asyncHandler(async (req, res) => {
  const userId = req.query.user_id ? Number(req.query.user_id) : null;
  if (req.query.user_id && (!Number.isInteger(userId) || userId <= 0)) throw new ApiError('BAD_PARAM', 'user_id 无效', 400);
  const user = userId ? users.findById(userId) : null;
  if (userId && !user) throw new ApiError('USER_NOT_FOUND', '用户不存在', 404);
  const end = timestamp(req.query.to, Math.floor(Date.now() / 1000));
  const start = timestamp(req.query.from, end - 30 * 24 * 60 * 60);
  const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 200);
  const pages = Math.ceil(limit / 10);
  const rows = [];
  for (let page = 0; page < pages && rows.length < limit; page += 1) {
    const batch = await oneapi.getLogsPage({
      username: user?.oneapi_ios_username || '', startTimestamp: start, endTimestamp: end, page,
    });
    rows.push(...batch);
    if (batch.length < 10) break;
  }
  res.json({
    available: true,
    from: new Date(start * 1000).toISOString(),
    to: new Date(end * 1000).toISOString(),
    usage: rows.slice(0, limit).map(usageRecord),
  });
}));

// GET /api/admin/recent-users?limit= —— 管理台用：最近注册的用户，方便挑人
router.get('/recent-users', asyncHandler(async (req, res) => {
  const rows = db.prepare(
    'SELECT id, username, display_name, created_at FROM users ORDER BY id DESC LIMIT ?'
  ).all(Math.min(Number(req.query.limit) || 20, 100));
  res.json({ users: rows });
}));

module.exports = router;
