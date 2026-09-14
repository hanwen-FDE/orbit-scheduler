// =====================================================================
// 配置加载：所有密钥和可调参数都来自环境变量（.env 文件或 Docker 注入），
// 本项目任何文件都不允许出现硬编码的密钥。
// 启动时逐项校验，缺了直接报错退出，避免带着错误配置上线。
// =====================================================================
require('dotenv').config();

const path = require('path');

function required(name, value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    throw new Error(`缺少必需的环境变量 ${name}，请检查 .env 文件（参考 .env.example）`);
  }
  return String(value).trim();
}

function optional(name, value, fallback) {
  if (value === undefined || value === null || String(value).trim() === '') return fallback;
  return String(value).trim();
}

function parseIntEnv(name, value, fallback) {
  if (value === undefined || value === null || String(value).trim() === '') return fallback;
  const n = Number.parseInt(value, 10);
  if (Number.isNaN(n)) throw new Error(`环境变量 ${name} 必须是整数，当前值：${value}`);
  return n;
}

// 解析积分包配置：{"商品ID": 积分数}，例如 {"com.orbit.points50": 50}
function parsePointPacks(raw) {
  const empty = {};
  if (!raw) return empty;
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(`POINT_PACKS 不是合法 JSON：${raw}`);
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw new Error('POINT_PACKS 必须是 {"商品ID": 积分数} 形式的 JSON 对象');
  }
  for (const [productId, points] of Object.entries(parsed)) {
    if (!Number.isInteger(points) || points <= 0) {
      throw new Error(`POINT_PACKS 中商品 ${productId} 的积分数必须是正整数`);
    }
  }
  return parsed;
}

const config = {
  env: optional('NODE_ENV', process.env.NODE_ENV, 'development'),
  port: parseIntEnv('PORT', process.env.PORT, 8080),

  // ---- 登录令牌（JWT）----
  jwtSecret: required('JWT_SECRET', process.env.JWT_SECRET),
  jwtExpiresIn: optional('JWT_EXPIRES_IN', process.env.JWT_EXPIRES_IN, '7d'),

  // ---- 数据库 ----
  databasePath: optional('DATABASE_PATH', process.env.DATABASE_PATH, path.join(__dirname, '..', 'data', 'orbit-points.db')),

  // ---- 管理员引导账号（首次启动时自动创建，之后可改 .env 中的密码）----
  adminUsername: required('ADMIN_USERNAME', process.env.ADMIN_USERNAME),
  adminPassword: required('ADMIN_PASSWORD', process.env.ADMIN_PASSWORD),

  // ---- OneAPI 网关 ----
  oneapi: {
    // 后端访问 OneAPI 的内网地址（Docker 网络内互通）
    baseUrl: required('ONEAPI_BASE_URL', process.env.ONEAPI_BASE_URL).replace(/\/+$/, ''),
    // 下发给 iOS 客户端用于直连对话的地址（公网 HTTPS）
    publicBaseUrl: required('ONEAPI_PUBLIC_BASE_URL', process.env.ONEAPI_PUBLIC_BASE_URL).replace(/\/+$/, ''),
    // OneAPI 管理员的访问令牌（个人设置里生成）
    adminToken: required('ONEAPI_ADMIN_TOKEN', process.env.ONEAPI_ADMIN_TOKEN),
    // new-api 分支管理接口需要 New-Api-User 头填管理员用户 ID；one-api 原版留空即可
    adminUserId: optional('ONEAPI_ADMIN_USER_ID', process.env.ONEAPI_ADMIN_USER_ID, ''),
    // 1 积分 = 多少 OneAPI quota（OneAPI 默认 500000 quota = 1 美元）
    quotaPerPoint: parseIntEnv('ONEAPI_QUOTA_PER_POINT', process.env.ONEAPI_QUOTA_PER_POINT, 500000),
    // 可选：下发给客户端的默认模型提示
    defaultModel: optional('ONEAPI_DEFAULT_MODEL', process.env.ONEAPI_DEFAULT_MODEL, ''),
  },

  // ---- 积分包：App Store 商品 ID -> 积分数 ----
  pointPacks: parsePointPacks(process.env.POINT_PACKS),

  // ---- 苹果内购 ----
  apple: {
    bundleId: required('APPLE_BUNDLE_ID', process.env.APPLE_BUNDLE_ID),
    // App Store Connect 里配置的“App 专用共享密钥”
    sharedSecret: required('APPLE_SHARED_SECRET', process.env.APPLE_SHARED_SECRET),
    // 校验收据的官方接口（一般不用改；冒烟测试会指向本地桩）
    verifyUrl: optional('APPLE_VERIFY_URL', process.env.APPLE_VERIFY_URL, 'https://buy.itunes.apple.com/verifyReceipt'),
    sandboxVerifyUrl: optional('APPLE_SANDBOX_VERIFY_URL', process.env.APPLE_SANDBOX_VERIFY_URL, 'https://sandbox.itunes.apple.com/verifyReceipt'),
    // 验证 App Store 服务器通知签名用的苹果根证书
    rootCaPath: optional('APPLE_ROOT_CA_PATH', process.env.APPLE_ROOT_CA_PATH, path.join(__dirname, '..', 'certs', 'AppleRootCA-G3.cer')),
  },

  // ---- 其他 ----
  // 新用户注册是否赠送体验积分（默认 0 不赠送；赠送会立即创建 OneAPI 钱包）
  registrationBonusPoints: parseIntEnv('REGISTRATION_BONUS_POINTS', process.env.REGISTRATION_BONUS_POINTS, 0),
  logLevel: optional('LOG_LEVEL', process.env.LOG_LEVEL, 'info'),
};

module.exports = config;
