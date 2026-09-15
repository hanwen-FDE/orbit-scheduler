// =====================================================================
// OneAPI 管理接口客户端。
//
// 后端通过它完成四件事：
//   1. 给 App 用户开一个专属 OneAPI 子账户（= 用户的 iOS 积分钱包）
//   2. 加减该账户的 quota（购买积分 / 退款扣回）
//   3. 以子账户自己的身份签发对话令牌（sk-...），App 拿令牌直连聊天
//   4. 管理员视角查询 / 重置子账户（客服与存量钱包补录凭证）
//
// 实测版本兼容性（one-api v0.6.11-preview.7，2026-09）：
//   - 管理创建用户：密码 ≤20 位、用户名长度上限约 12~15 位，
//     超限一律报 "Invalid input, please check your input"；
//   - 用户/令牌搜索：data 可能直接是数组（新版）或 {items:[...]}（旧版），
//     searchItems() 两种都认；
//   - 令牌接口是“自签”语义：POST /api/token/ 只会给当前登录者自己签令牌，
//     管理员令牌无法替别的账户签发。因此 createToken 必须先用子账户
//     登录拿 session cookie，再以它自己的名义创建和查询令牌。
// =====================================================================
const crypto = require('crypto');
const config = require('../config');
const logger = require('../logger');
const { ApiError } = require('../middleware/errorHandler');

const TIMEOUT_MS = 10_000;
// 密码字符集：大小写字母+数字（避开易混字符），16 位——实测通过管理接口校验
const PASSWORD_ALPHABET = 'ABCDEFGHJKLMnpQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';

// 统一请求封装：带鉴权头、超时、错误归一化
async function rawCall(method, path, body, extraHeaders) {
  const headers = {
    'Content-Type': 'application/json',
    ...(extraHeaders || {}),
  };

  let resp;
  try {
    resp = await fetch(`${config.oneapi.baseUrl}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (err) {
    logger.error('oneapi_request_error', { path, method, error: err.message });
    throw new ApiError('ONEAPI_UNREACHABLE', '无法连接 OneAPI，请检查服务状态和网络', 502);
  }

  let json;
  try {
    json = await resp.json();
  } catch {
    logger.error('oneapi_bad_response', { path, method, status: resp.status });
    throw new ApiError('ONEAPI_ERROR', 'OneAPI 返回了无法解析的内容', 502);
  }

  if (!resp.ok || json.success === false) {
    logger.error('oneapi_api_error', { path, method, status: resp.status, message: json.message });
    throw new ApiError('ONEAPI_ERROR', `OneAPI 接口调用失败：${json.message || resp.status}`, 502);
  }
  return json;
}

// 管理员身份调用（创建用户 / 额度管理 / 重置密码）
async function apiCall(method, path, body) {
  const headers = { Authorization: `Bearer ${config.oneapi.adminToken}` };
  // new-api 分支要求管理请求带 New-Api-User 头（管理员用户 ID）
  if (config.oneapi.adminUserId) headers['New-Api-User'] = config.oneapi.adminUserId;
  return rawCall(method, path, body, headers);
}

// 子账户会话调用（登录后签令牌用；只带 session cookie，不带管理员令牌）
async function apiCallWithSession(cookie, method, path, body) {
  return rawCall(method, path, body, { Cookie: cookie });
}

function randomPassword() {
  // OneAPI 子账户的密码用户永远不会用到，随机生成即可。
  // 长度和字符集按实测兼容性约束生成（见文件头备注）。
  const bytes = crypto.randomBytes(16);
  return Array.from(bytes, (b) => PASSWORD_ALPHABET[b % PASSWORD_ALPHABET.length]).join('');
}

// 搜索接口兼容两种返回格式：data 直接是数组（新）或 {items:[...]}（旧）
function searchItems(json) {
  const raw = json?.data;
  return Array.isArray(raw) ? raw : (raw?.items || []);
}

// ---------------------------------------------------------------------
// 1. 创建子账户，返回 { id, username, password }
//    username/password 需要存库：签发令牌时要用它登录（见文件头备注）
// ---------------------------------------------------------------------
async function createUser(displayName) {
  const username = `orbit_${crypto.randomBytes(3).toString('hex')}`; // 共 12 字符
  const password = randomPassword();
  await apiCall('POST', '/api/user/', {
    username,
    password,
    display_name: displayName,
  });

  // 创建接口在部分分支不返回 ID，统一用“按用户名精确搜索”补拿
  const search = await apiCall('GET', `/api/user/search?keyword=${encodeURIComponent(username)}`);
  const found = searchItems(search).find((u) => u.username === username);
  if (!found) {
    throw new ApiError('ONEAPI_ERROR', 'OneAPI 用户创建后未能查到，请检查 OneAPI 版本兼容性', 502);
  }
  logger.info('oneapi_user_created', { oneapi_user_id: found.id, display_name: displayName });
  return { id: found.id, username, password };
}

// ---------------------------------------------------------------------
// 2. 查询 / 修改 quota（管理员）
// ---------------------------------------------------------------------
async function getUser(oneapiUserId) {
  const json = await apiCall('GET', `/api/user/${oneapiUserId}`);
  return json.data;
}

async function getUserQuota(oneapiUserId) {
  const user = await getUser(oneapiUserId);
  return Number(user?.quota ?? 0);
}

// 读-改-写方式更新额度（带重试应对并发写冲突）。
// deltaQuota 为正加点、为负扣点；允许扣成负数——负余额会被 OneAPI 拒绝服务，
// 正好实现“退款时积分已花完则无法继续对话”的业务规则。
async function addUserQuota(oneapiUserId, deltaQuota, reason) {
  let lastError = null;
  for (let attempt = 1; attempt <= 3; attempt++) {
    const user = await getUser(oneapiUserId);
    const before = Number(user?.quota ?? 0);
    const after = before + deltaQuota;
    try {
      await apiCall('PUT', '/api/user/', { id: oneapiUserId, quota: after });
      logger.info('oneapi_quota_changed', {
        oneapi_user_id: oneapiUserId, before, after, delta: deltaQuota, reason,
      });
      return { before, after };
    } catch (err) {
      lastError = err;
      logger.warn('oneapi_quota_retry', { oneapi_user_id: oneapiUserId, attempt, error: err.message });
    }
  }
  throw lastError || new ApiError('ONEAPI_ERROR', '更新 OneAPI 额度失败', 502);
}

// 管理员重置子账户密码：给旧版部署建的存量钱包补录登录凭证用
async function resetUserPassword(oneapiUserId, newPassword) {
  await apiCall('PUT', '/api/user/', { id: oneapiUserId, password: newPassword });
  logger.info('oneapi_password_reset', { oneapi_user_id: oneapiUserId });
}

// ---------------------------------------------------------------------
// 3. 签发对话令牌（sk-...），返回 { id, key }
//    必须以子账户自己的身份登录后创建——管理员替签的令牌挂在管理员名下，
//    花的是管理员额度，资产隔离会被打破。
// ---------------------------------------------------------------------
async function loginSession(username, password) {
  let resp;
  try {
    resp = await fetch(`${config.oneapi.baseUrl}/api/user/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (err) {
    logger.error('oneapi_request_error', { path: '/api/user/login', method: 'POST', error: err.message });
    throw new ApiError('ONEAPI_UNREACHABLE', '无法连接 OneAPI，请检查服务状态和网络', 502);
  }

  let json = null;
  try { json = await resp.json(); } catch { /* 下面统一判失败 */ }
  if (!resp.ok || !json || json.success === false) {
    logger.error('oneapi_api_error', {
      path: '/api/user/login', method: 'POST', status: resp.status, message: json?.message,
    });
    throw new ApiError('ONEAPI_ERROR', `OneAPI 子账户登录失败：${json?.message || resp.status}`, 502);
  }

  // 从 Set-Cookie 里取 session（多个 cookie 时用逗号拼接，正则只认 session=）
  const setCookie = resp.headers.get('set-cookie') || '';
  const match = setCookie.match(/session=[^;,\s]+/);
  if (!match) {
    throw new ApiError('ONEAPI_ERROR', 'OneAPI 登录成功但未返回会话 Cookie', 502);
  }
  return match[0];
}

async function createToken(oneapiUserId, name, username, password) {
  const cookie = await loginSession(username, password);

  // user_id 不用传：该接口的语义就是“给当前登录者自己签”
  await apiCallWithSession(cookie, 'POST', '/api/token/', {
    name,
    remain_quota: 0,
    expired_time: -1,            // 永不过期（有效期由账户余额控制）
    unlimited_quota: true,       // 令牌不限额，直接共享账户余额
    model_limits_enabled: false,
    model_limits: '',
    allow_ips: '',
    group: '',
  });

  // 用令牌名精确搜出 key（one-api 存的 key 不带 sk- 前缀）；
  // 会话搜索本身只返回自己的令牌，按名字匹配即可
  const search = await apiCallWithSession(
    cookie, 'GET', `/api/token/search?keyword=${encodeURIComponent(name)}`
  );
  const found = searchItems(search).find((t) => t.name === name);
  if (!found || !found.key) {
    throw new ApiError('ONEAPI_ERROR', 'OneAPI 令牌创建后未能查到，请检查 OneAPI 版本兼容性', 502);
  }
  const key = found.key.startsWith('sk-') ? found.key : `sk-${found.key}`;
  logger.info('oneapi_token_created', { oneapi_user_id: oneapiUserId, token_id: found.id });
  return { id: found.id, key };
}

// ---------------------------------------------------------------------
// 4. 探活（健康检查用）
// ---------------------------------------------------------------------
async function ping() {
  try {
    await apiCall('GET', '/api/status');
    return true;
  } catch {
    return false;
  }
}

module.exports = {
  createUser, getUser, getUserQuota, addUserQuota, resetUserPassword,
  createToken, randomPassword, ping,
};
