// =====================================================================
// 认证路由：注册 / 登录
// =====================================================================
const express = require('express');
const jwt = require('jsonwebtoken');
const config = require('../config');
const users = require('../services/users');
const { asyncHandler } = require('../middleware/errorHandler');
const { rateLimit } = require('../middleware/rateLimit');

const router = express.Router();

// 同一 IP 每分钟最多 10 次（防刷注册/暴力破解）
const authLimiter = rateLimit({ windowMs: 60_000, max: 10 });

function signToken(user) {
  return jwt.sign({ sub: String(user.id), role: user.role }, config.jwtSecret, {
    expiresIn: config.jwtExpiresIn,
  });
}

// POST /api/auth/register  { username, password }
router.post('/register', authLimiter, asyncHandler(async (req, res) => {
  const { username, password } = req.body || {};
  const user = users.register(username, password);
  res.status(201).json({ token: signToken(user), user: users.publicUser(user) });
}));

// POST /api/auth/login  { username, password }
router.post('/login', authLimiter, asyncHandler(async (req, res) => {
  const { username, password } = req.body || {};
  const user = users.login(username, password);
  res.json({ token: signToken(user), user: users.publicUser(user) });
}));

module.exports = router;
