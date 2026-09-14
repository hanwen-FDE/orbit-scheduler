// =====================================================================
// 管理接口（需管理员令牌）：查订单、查用户、手工调点
// 用 .env 里 ADMIN_USERNAME/ADMIN_PASSWORD 登录拿到管理员 JWT 即可调用。
// =====================================================================
const express = require('express');
const db = require('../db');
const users = require('../services/users');
const iap = require('../services/iap');
const { requireAdmin } = require('../middleware/auth');
const { asyncHandler, ApiError } = require('../middleware/errorHandler');

const router = express.Router();
router.use(requireAdmin);

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

module.exports = router;
