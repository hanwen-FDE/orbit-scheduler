// =====================================================================
// 健康检查：部署后先 curl 它确认服务、数据库、OneAPI 三者都正常。
// =====================================================================
const express = require('express');
const db = require('../db');
const oneapi = require('../services/oneapi');
const { asyncHandler } = require('../middleware/errorHandler');

const router = express.Router();

// GET /api/health
router.get('/', asyncHandler(async (_req, res) => {
  let dbOk = false;
  try {
    db.prepare('SELECT 1').get();
    dbOk = true;
  } catch { /* 保持 false */ }

  const oneapiOk = await oneapi.ping();

  res.status(dbOk ? 200 : 500).json({
    ok: dbOk,
    db: dbOk ? 'ok' : 'error',
    oneapi: oneapiOk ? 'ok' : 'unreachable',
    ts: new Date().toISOString(),
  });
}));

module.exports = router;
