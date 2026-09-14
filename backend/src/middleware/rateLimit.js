// =====================================================================
// 简易内存限流（滑动窗口）：保护注册/登录/收据接口不被刷。
// 说明：状态存在进程内存里，重启清零；单实例部署完全够用。
// =====================================================================
const { ApiError } = require('./errorHandler');

const buckets = new Map(); // key -> 时间戳数组

// 定期清理过期桶，避免内存缓慢增长
setInterval(() => {
  const now = Date.now();
  for (const [key, hits] of buckets) {
    const alive = hits.filter((t) => now - t < 10 * 60 * 1000);
    if (alive.length === 0) buckets.delete(key);
    else buckets.set(key, alive);
  }
}, 10 * 60 * 1000).unref();

function clientIp(req) {
  // 经过 nginx 反代时取真实 IP（app.js 已设置 trust proxy）
  return req.ip || 'unknown';
}

// 用法：rateLimit({ windowMs: 60_000, max: 10 })
function rateLimit({ windowMs, max }) {
  return (req, res, next) => {
    const key = `${req.baseUrl || req.path}|${clientIp(req)}`;
    const now = Date.now();
    const hits = (buckets.get(key) || []).filter((t) => now - t < windowMs);
    if (hits.length >= max) {
      res.setHeader('Retry-After', Math.ceil(windowMs / 1000));
      next(new ApiError('RATE_LIMITED', '请求太频繁，请稍后再试', 429));
      return;
    }
    hits.push(now);
    buckets.set(key, hits);
    next();
  };
}

module.exports = { rateLimit };
