// =====================================================================
// 内购路由：上传收据 -> 校验 -> 加积分（幂等）
// iOS 端购买积分包、交易完成后把 SK1 收据（base64 字符串）传到这里。
// =====================================================================
const express = require('express');
const logger = require('../logger');
const iap = require('../services/iap');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errorHandler');
const { rateLimit } = require('../middleware/rateLimit');

const router = express.Router();

// 每 IP 每分钟最多 30 次校验（正常用户远用不到）
const verifyLimiter = rateLimit({ windowMs: 60_000, max: 30 });

// POST /api/iap/verify  { receipt: "<base64 收据>" }
router.post('/verify', verifyLimiter, requireAuth, asyncHandler(async (req, res) => {
  const { receipt } = req.body || {};
  // 日志只记长度，不打印收据内容
  logger.info('iap_verify_requested', { user_id: req.user.id, receipt_len: String(receipt || '').length });
  const result = await iap.processReceipt(req.user, receipt);
  res.json(result);
}));

module.exports = router;
