// =====================================================================
// 苹果服务器通知回调（App Store Server Notifications V2）。
// 在 App Store Connect -> App -> App Store 服务器通知 里把 URL 配成
// https://你的域名/api/notifications/app-store （生产+沙盒都配）。
// =====================================================================
const express = require('express');
const appleNotify = require('../services/appleNotify');
const { asyncHandler } = require('../middleware/errorHandler');
const { rateLimit } = require('../middleware/rateLimit');

const router = express.Router();

// 通知量不大，但给个宽松限流挡异常流量
const notifyLimiter = rateLimit({ windowMs: 60_000, max: 60 });

// POST /api/notifications/app-store  { signedPayload: "<JWS>" }
router.post('/app-store', notifyLimiter, asyncHandler(async (req, res) => {
  const { signedPayload } = req.body || {};
  const result = await appleNotify.handleNotification(signedPayload);
  // 苹果只认 2xx：正常处理或已知忽略都返回 200，避免它反复重发
  res.json(result);
}));

module.exports = router;
