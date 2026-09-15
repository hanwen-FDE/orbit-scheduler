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
const crypto = require('crypto');
const db = require('../db');
const config = require('../config');
const logger = require('../logger');
const oneapi = require('./oneapi');
const { ApiError } = require('../middleware/errorHandler');

const USERNAME_RE = /^[A-Za-z0-9_]{3,32}$/;

function publicUser(user) {
  return {
    id: user.id,
    // Apple 首次授权提供的姓名仅用于界面展示，内部用户名不暴露给用户。
    username: user.display_name || user.username,
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

/// Apple 的 sub 是同一开发团队 + 同一 App 下稳定且不可逆的用户标识。
/// 用它做唯一键，用户更换邮箱或 Apple 隐藏邮箱也仍能回到同一 Orbit 账户。
function loginWithApple({ subject, email, displayName }) {
  let user = db.prepare('SELECT * FROM users WHERE apple_subject = ?').get(subject);
  if (user) {
    if (user.status !== 'active') throw new ApiError('AUTH_DISABLED', '账号已被禁用', 403);
    // Apple 仅在首次授权时通常提供姓名/邮箱；后续空字段绝不覆盖已有资料。
    if ((!user.display_name && displayName) || (!user.apple_email && email)) {
      db.prepare(
        `UPDATE users SET display_name = COALESCE(display_name, ?),
         apple_email = COALESCE(apple_email, ?), updated_at = datetime('now') WHERE id = ?`
      ).run(displayName || null, email || null, user.id);
      user = findById(user.id);
    }
    return user;
  }

  const suffix = crypto.createHash('sha256').update(subject).digest('hex').slice(0, 20);
  const username = `apple_${suffix}`;
  const passwordHash = bcrypt.hashSync(crypto.randomBytes(32).toString('hex'), 10);
  const info = db.prepare(
    'INSERT INTO users (username, password_hash, apple_subject, apple_email, display_name) VALUES (?, ?, ?, ?, ?)'
  ).run(username, passwordHash, subject, email || null, displayName || 'Apple 用户');
  user = findById(info.lastInsertRowid);
  logger.info('user_registered_apple', { user_id: user.id });
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
  // 注意在“已捕获”的副本上做清理：直接对 next 调 finally 会产生一条
  // 无人处理的 rejected promise（曾表现为 unhandled_rejection 日志噪音）。
  next
    .catch(() => {})
    .finally(() => {
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

    // username/password 必须存库：签发对话令牌时要用子账户身份登录
    const account = await oneapi.createUser(`orbit_uid_${user.id}`);
    db.prepare(
      `UPDATE users SET oneapi_ios_user_id = ?, oneapi_ios_username = ?, oneapi_ios_password = ?,
         updated_at = datetime('now')
       WHERE id = ? AND oneapi_ios_user_id IS NULL`
    ).run(account.id, account.username, account.password, user.id);
    logger.info('ios_wallet_provisioned', { user_id: user.id, oneapi_user_id: account.id });
    return findById(user.id);
  });
}

// 存量钱包补录：旧版部署建的钱包没存登录凭证（当时密码生成后即丢弃）。
// 用管理员接口读回用户名、重置一个新密码，存库后即可走正常的签令牌流程。
async function ensureWalletCredentials(user) {
  if (user.oneapi_ios_username && user.oneapi_ios_password) return user;

  const info = await oneapi.getUser(user.oneapi_ios_user_id);
  const username = info?.username;
  if (!username) {
    throw new ApiError('ONEAPI_ERROR', '无法读取 OneAPI 子账户信息以补录凭证', 502);
  }
  const password = oneapi.randomPassword();
  await oneapi.resetUserPassword(user.oneapi_ios_user_id, password);
  db.prepare(
    `UPDATE users SET oneapi_ios_username = ?, oneapi_ios_password = ?, updated_at = datetime('now')
     WHERE id = ?`
  ).run(username, password, user.id);
  logger.info('ios_wallet_credentials_restored', { user_id: user.id, oneapi_user_id: user.oneapi_ios_user_id });
  return findById(user.id);
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
  let walletUser = await ensureIosWallet(user);
  walletUser = await ensureWalletCredentials(walletUser);
  if (walletUser.oneapi_ios_token_key) {
    return { key: walletUser.oneapi_ios_token_key, id: walletUser.oneapi_ios_token_id };
  }
  // 令牌必须以子账户自己的身份签发（管理员替签会挂在管理员名下，
  // 花错人的额度）——oneapi.createToken 内部会先登录再创建。
  const token = await oneapi.createToken(
    walletUser.oneapi_ios_user_id,
    `orbit_uid_${user.id}`,
    walletUser.oneapi_ios_username,
    walletUser.oneapi_ios_password
  );
  db.prepare(
    `UPDATE users SET oneapi_ios_token_id = ?, oneapi_ios_token_key = ?, updated_at = datetime('now') WHERE id = ?`
  ).run(token.id, token.key, user.id);
  return token;
}

module.exports = {
  publicUser, register, login, loginWithApple, findById, bootstrapAdmin,
  ensureIosWallet, ensureWalletCredentials, getIosPoints, issueApiKey, validateCredentials,
};
