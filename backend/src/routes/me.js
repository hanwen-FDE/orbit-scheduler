// =====================================================================
// 个人信息路由：查资料 / 查积分 / 领取对话令牌（App 用它直连 OneAPI）
// =====================================================================
const express = require('express');
const config = require('../config');
const users = require('../services/users');
const logger = require('../logger');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler, ApiError } = require('../middleware/errorHandler');

const router = express.Router();
router.use(requireAuth);

// GET /api/me —— 基础资料 + iOS 钱包概况
router.get('/', asyncHandler(async (req, res) => {
  const user = req.user;
  const points = await users.getIosPoints(user);
  res.json({
    ...users.publicUser(user),
    ios_wallet: {
      provisioned: Boolean(user.oneapi_ios_user_id),
      points,
    },
  });
}));

// GET /api/me/points —— 实时积分余额（直接读 OneAPI）
router.get('/points', asyncHandler(async (req, res) => {
  const points = await users.getIosPoints(req.user);
  res.json({ wallet: 'ios', points });
}));

// POST /api/me/api-key —— 领取对话令牌和对话地址
// iOS 端拿到后：POST {base_url}/v1/chat/completions
//   Authorization: Bearer <api_key>，body 里 model 填配置的模型，支持 stream
router.post('/api-key', asyncHandler(async (req, res) => {
  const { key } = await users.issueApiKey(req.user);
  logger.info('api_key_issued', { user_id: req.user.id });
  res.json({
    api_key: key,
    base_url: config.oneapi.publicBaseUrl,
    ...(config.oneapi.defaultModel ? { default_model: config.oneapi.defaultModel } : {}),
    note: '积分仅支持在 iOS 端使用',
  });
}));

module.exports = router;
