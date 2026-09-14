// =====================================================================
// OneAPI 管理接口客户端。
//
// 后端通过它完成三件事：
//   1. 给 App 用户开一个专属 OneAPI 子账户（= 用户的 iOS 积分钱包）
//   2. 加减该账户的 quota（购买积分 / 退款扣回）
//   3. 给该账户签发对话令牌（sk-...），App 拿令牌直连 OneAPI 聊天
//
// 对接的管理接口（基于 one-api / new-api 的通用约定，字段差异见 README 排查一节）：
//   POST /api/user/            管理员创建用户
//   GET  /api/user/search      按关键字搜用户（创建后拿用户 ID）
//   GET  /api/user/:id         查用户（含 quota）
//   PUT  /api/user/            更新用户（设置 quota）
//   POST /api/token/           创建令牌
//   GET  /api/token/search     按名字搜令牌（拿 sk-key）
//   GET  /api/status           探活
// =====================================================================
const crypto = require('crypto');
const config = require('../config');
const logger = require('../logger');
const { ApiError } = require('../middleware/errorHandler');

const TIMEOUT_MS = 10_000;

// 统一请求封装：带鉴权头、超时、错误归一化
async function apiCall(method, path, body) {
  const headers = {
    Authorization: `Bearer ${config.oneapi.adminToken}`,
    'Content-Type': 'application/json',
  };
  // new-api 分支要求管理请求带 New-Api-User 头（管理员用户 ID）
  if (config.oneapi.adminUserId) headers['New-Api-User'] = config.oneapi.adminUserId;

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

function randomPassword() {
  // OneAPI 子账户的密码用户永远不会用到，随机生成即可
  return crypto.randomBytes(18).toString('base64url');
}

// ---------------------------------------------------------------------
// 1. 创建子账户，返回 OneAPI 用户 ID
// ---------------------------------------------------------------------
async function createUser(displayName) {
  const username = `orbit_${crypto.randomBytes(6).toString('hex')}`;
  await apiCall('POST', '/api/user/', {
    username,
    password: randomPassword(),
    display_name: displayName,
  });

  // 创建接口在部分分支不返回 ID，统一用“按用户名精确搜索”补拿
  const search = await apiCall('GET', `/api/user/search?keyword=${encodeURIComponent(username)}`);
  const items = search.data?.items || [];
  const found = items.find((u) => u.username === username);
  if (!found) {
    throw new ApiError('ONEAPI_ERROR', 'OneAPI 用户创建后未能查到，请检查 OneAPI 版本兼容性', 502);
  }
  logger.info('oneapi_user_created', { oneapi_user_id: found.id, display_name: displayName });
  return found.id;
}

// ---------------------------------------------------------------------
// 2. 查询 / 修改 quota
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

// ---------------------------------------------------------------------
// 3. 签发对话令牌（sk-...），返回 { id, key }
// ---------------------------------------------------------------------
async function createToken(oneapiUserId, name) {
  await apiCall('POST', '/api/token/', {
    name,
    user_id: oneapiUserId,
    remain_quota: 0,
    expired_time: -1,            // 永不过期（有效期由账户余额控制）
    unlimited_quota: true,       // 令牌不限额，直接共享账户余额
    model_limits_enabled: false,
    model_limits: '',
    allow_ips: '',
    group: '',
  });

  // 用令牌名精确搜出 key（one-api 存的 key 不带 sk- 前缀）
  const search = await apiCall('GET', `/api/token/search?keyword=${encodeURIComponent(name)}`);
  const items = search.data?.items || [];
  const found = items.find((t) => t.name === name && Number(t.user_id) === Number(oneapiUserId));
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

module.exports = { createUser, getUser, getUserQuota, addUserQuota, createToken, ping };
