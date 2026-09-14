// =====================================================================
// 用户服务：注册、登录、管理员引导，以及“iOS 钱包”的懒创建。
//
// 资产隔离设计（对应需求 5）：
//   每个用户有一个专属 OneAPI 子账户作为 iOS 钱包。IAP 积分只进这个
//   钱包，App 领取的对话令牌也只绑定这个钱包——其他渠道的积分（预留的
//   general 钱包）在 iOS App 内天然不可见、不可用。
//
// “懒创建”：注册时不碰 OneAPI（避免 OneAPI 故障导致无法注册），在用户
// 第一次需要积分（购买/领令牌）时才创建钱包。
// =====================================================================
const bcrypt = require('bcryptjs');
const db = require('../db');
const config = require('../config');
const logger = require('../logger');
const oneapi = require('./oneapi');
const { ApiError } = require('../middleware/errorHandler');

const USERNAME_RE = /^[A-Za-z0-9_]{3,32}$/;

function publicUser(user) {
  return {
    id: user.id,
    username: user.username,
    role: user.role,
    created_at: user.created_at,
  };
}

// ---------------------------------------------------------------------
// 注册 / 登录
// ---------------------------------------------------------------------
function validateCredentials(username, password) {
  if (typeof username !== 'string' || !USERNAME_RE.test(username)) {
    throw new ApiError('BAD_USERNAME', '用户名需为 3~32 位字母、数字或下划线', 400);
  }
  if (typeof password !== 'string' || password.length < 8 || password.length > 64) {
    throw new ApiError('BAD_PASSWORD', '密码长度需在 8~64 位之间', 400);
  }
}

function register(username, password) {
  validateCredentials(username, password);
  const exists = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
  if (exists) throw new ApiError('USERNAME_TAKEN', '用户名已被占用', 409);

  const hash = bcrypt.hashSync(password, 10);
  const info = db
    .prepare('INSERT INTO users (username, password_hash) VALUES (?, ?)')
    .run(username, hash);
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(info.lastInsertRowid);
  logger.info('user_registered', { user_id: user.id, username });
  return user;
}

function login(username, password) {
  const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username);
  // 统一提示，避免暴露“用户名是否存在”
  if (!user || !bcrypt.compareSync(password || '', user.password_hash)) {
    throw new ApiError('AUTH_FAILED', '用户名或密码错误', 401);
  }
  if (user.status !== 'active') throw new ApiError('AUTH_DISABLED', '账号已被禁用', 403);
  return user;
}

function findById(id) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id);
}

// ---------------------------------------------------------------------
// 管理员引导：首次启动按 .env 创建管理员；已存在则确保角色是 admin
// ---------------------------------------------------------------------
function bootstrapAdmin() {
  const existing = db.prepare('SELECT * FROM users WHERE username = ?').get(config.adminUsername);
  if (!existing) {
    const hash = bcrypt.hashSync(config.adminPassword, 10);
    db.prepare("INSERT INTO users (username, password_hash, role) VALUES (?, ?, 'admin')")
      .run(config.adminUsername, hash);
    logger.info('admin_created', { username: config.adminUsername });
    return;
  }
  if (existing.role !== 'admin') {
    db.prepare("UPDATE users SET role = 'admin', updated_at = datetime('now') WHERE id = ?").run(existing.id);
    logger.warn('admin_role_fixed', { user_id: existing.id });
  }
}

// ---------------------------------------------------------------------
// iOS 钱包（懒创建，进程内加锁防并发重复开户）
// ---------------------------------------------------------------------
const walletLocks = new Map(); // userId -> Promise 链

function withUserLock(userId, fn) {
  const prev = walletLocks.get(userId) || Promise.resolve();
  const next = prev.catch(() => {}).then(fn);
  walletLocks.set(userId, next);
  next.finally(() => {
    if (walletLocks.get(userId) === next) walletLocks.delete(userId);
  });
  return next;
}

async function ensureIosWallet(user) {
  if (user.oneapi_ios_user_id) return user;

  return withUserLock(user.id, async () => {
    // 拿到锁后重读，可能别的并发请求已经开好户
    const fresh = findById(user.id);
    if (fresh.oneapi_ios_user_id) return fresh;

    const oneapiUserId = await oneapi.createUser(`orbit_uid_${user.id}`);
    db.prepare(
      `UPDATE users SET oneapi_ios_user_id = ?, updated_at = datetime('now')
       WHERE id = ? AND oneapi_ios_user_id IS NULL`
    ).run(oneapiUserId, user.id);
    logger.info('ios_wallet_provisioned', { user_id: user.id, oneapi_user_id: oneapiUserId });
    return findById(user.id);
  });
}

// 查询 iOS 钱包实时积分（未开户返回 0）
async function getIosPoints(user) {
  if (!user.oneapi_ios_user_id) return 0;
  const quota = await oneapi.getUserQuota(user.oneapi_ios_user_id);
  return Math.floor(quota / config.oneapi.quotaPerPoint);
}

// ---------------------------------------------------------------------
// 领取对话令牌：已有就复用，没有就签发（对应需求 6，App 直连 OneAPI）
// ---------------------------------------------------------------------
async function issueApiKey(user) {
  const walletUser = await ensureIosWallet(user);
  if (walletUser.oneapi_ios_token_key) {
    return { key: walletUser.oneapi_ios_token_key, id: walletUser.oneapi_ios_token_id };
  }
  const token = await oneapi.createToken(walletUser.oneapi_ios_user_id, `orbit_uid_${user.id}`);
  db.prepare(
    `UPDATE users SET oneapi_ios_token_id = ?, oneapi_ios_token_key = ?, updated_at = datetime('now') WHERE id = ?`
  ).run(token.id, token.key, user.id);
  return token;
}

module.exports = {
  publicUser, register, login, findById, bootstrapAdmin,
  ensureIosWallet, getIosPoints, issueApiKey, validateCredentials,
};
