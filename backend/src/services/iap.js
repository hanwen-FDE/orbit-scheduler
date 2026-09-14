// =====================================================================
// 内购核心逻辑（对应需求 3、4）：
//   收据校验通过 -> 订单幂等落库 -> 经 OneAPI 给 iOS 钱包加积分 -> 记流水。
//
// 幂等保证：iap_orders.transaction_id 有唯一索引。苹果重复投递收据、
// 用户重复点击、网络重试，第二次起只会返回 duplicate=true，不会重复加点。
//
// 退款：按 transaction_id 找订单，经 OneAPI 扣回积分并标记 refunded。
// 积分已被花掉时允许余额变负——OneAPI 会对负余额拒绝服务，用户自然
// 无法继续对话，直到重新充值补回。
// =====================================================================
const db = require('../db');
const config = require('../config');
const logger = require('../logger');
const appleVerify = require('./appleVerify');
const users = require('./users');
const oneapi = require('./oneapi');
const { ApiError } = require('../middleware/errorHandler');

// 记录一条积分流水
function insertQuotaOp({ userId, wallet, deltaPoints, reason, orderId, before, after }) {
  db.prepare(
    `INSERT INTO quota_ops (user_id, wallet, delta_points, reason, order_id, oneapi_quota_before, oneapi_quota_after)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(userId, wallet, deltaPoints, reason, orderId, before, after);
}

// ---------------------------------------------------------------------
// 处理收据：校验 + 逐单幂等入账
// ---------------------------------------------------------------------
async function processReceipt(user, receiptData) {
  const { environment, purchases } = await appleVerify.verifyReceipt(receiptData);

  const processed = [];
  let pointsAdded = 0;

  for (const p of purchases) {
    const packPoints = config.pointPacks[p.product_id];
    if (!packPoints) {
      // 收据里有我们不认识的商品（例如别的 App 的购买）——跳过并说明
      logger.warn('iap_unknown_product', { user_id: user.id, product_id: p.product_id });
      processed.push({
        transaction_id: p.transaction_id,
        product_id: p.product_id,
        status: 'ignored_unknown_product',
      });
      continue;
    }

    const points = packPoints * p.quantity;

    // 幂等落库：唯一索引冲突说明这笔交易已经入过账
    let inserted;
    try {
      const info = db.prepare(
        `INSERT INTO iap_orders (user_id, transaction_id, original_transaction_id, product_id,
                                 points, quantity, environment, purchase_date)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      ).run(user.id, p.transaction_id, p.original_transaction_id, p.product_id,
            points, p.quantity, environment, p.purchase_date);
      inserted = { id: info.lastInsertRowid };
    } catch (err) {
      if (String(err.message).includes('UNIQUE constraint failed')) {
        const existing = db.prepare('SELECT * FROM iap_orders WHERE transaction_id = ?').get(p.transaction_id);
        if (existing.user_id !== user.id) {
          // 同一笔苹果交易出现在另一个账号：极可能是伪造重放，只记录不加点
          logger.error('iap_transaction_user_conflict', {
            transaction_id: p.transaction_id,
            order_user: existing.user_id, request_user: user.id,
          });
          processed.push({
            transaction_id: p.transaction_id, product_id: p.product_id, status: 'conflict',
          });
          continue;
        }
        processed.push({
          transaction_id: p.transaction_id, product_id: p.product_id, points,
          status: 'duplicate',
        });
        continue;
      }
      throw err;
    }

    // 首次见到这笔交易：开钱包 -> OneAPI 加点 -> 流水
    const walletUser = await users.ensureIosWallet(user);
    const { before, after } = await oneapi.addUserQuota(
      walletUser.oneapi_ios_user_id,
      points * config.oneapi.quotaPerPoint,
      `iap:order#${inserted.id}`
    );
    insertQuotaOp({
      userId: user.id, wallet: 'ios', deltaPoints: points,
      reason: `iap:order#${inserted.id}`, orderId: inserted.id, before, after,
    });
    pointsAdded += points;
    processed.push({
      transaction_id: p.transaction_id, product_id: p.product_id, points, status: 'credited',
    });
  }

  const fresh = users.findById(user.id);
  const currentPoints = await users.getIosPoints(fresh);
  logger.info('iap_receipt_processed', { user_id: user.id, environment, points_added: pointsAdded });
  return { environment, processed, points_added: pointsAdded, points: currentPoints };
}

// ---------------------------------------------------------------------
// 退款：按苹果交易号扣回积分（幂等）
// ---------------------------------------------------------------------
async function refundByTransactionId(transactionId) {
  const order = db.prepare('SELECT * FROM iap_orders WHERE transaction_id = ?').get(transactionId);
  if (!order) {
    // 通知可能涉及我们不处理的交易类型（如订阅），记录后放行
    logger.warn('refund_order_not_found', { transaction_id: transactionId });
    return { handled: false, reason: 'order_not_found' };
  }
  if (order.status === 'refunded') {
    return { handled: true, already: true, order_id: order.id };
  }

  const user = users.findById(order.user_id);
  if (!user) {
    logger.error('refund_user_missing', { order_id: order.id, user_id: order.user_id });
    return { handled: false, reason: 'user_missing' };
  }

  const walletUser = await users.ensureIosWallet(user);
  const { before, after } = await oneapi.addUserQuota(
    walletUser.oneapi_ios_user_id,
    -order.points * config.oneapi.quotaPerPoint,
    `refund:order#${order.id}`
  );
  db.prepare(
    `UPDATE iap_orders SET status = 'refunded', refunded_at = datetime('now') WHERE id = ?`
  ).run(order.id);
  insertQuotaOp({
    userId: user.id, wallet: 'ios', deltaPoints: -order.points,
    reason: `refund:order#${order.id}`, orderId: order.id, before, after,
  });
  logger.warn('iap_order_refunded', { order_id: order.id, user_id: user.id, points: -order.points });
  return { handled: true, order_id: order.id };
}

// ---------------------------------------------------------------------
// 管理员手工调点（客服补点 / 测试）
// ---------------------------------------------------------------------
async function adminGrant(userId, wallet, points, reason) {
  if (!Number.isInteger(points) || points === 0) {
    throw new ApiError('BAD_POINTS', 'points 必须是非零整数（正数补、负数扣）', 400);
  }
  if (wallet !== 'ios' && wallet !== 'general') {
    throw new ApiError('BAD_WALLET', 'wallet 只能是 ios 或 general', 400);
  }

  const user = users.findById(userId);
  if (!user) throw new ApiError('USER_NOT_FOUND', '用户不存在', 404);

  let walletUser = user;
  let oneapiUserId;
  if (wallet === 'ios') {
    walletUser = await users.ensureIosWallet(user);
    oneapiUserId = walletUser.oneapi_ios_user_id;
  } else {
    // 其他渠道钱包：按需开户（当前 MVP 没有其他充值渠道，仅预留）
    if (!walletUser.oneapi_general_user_id) {
      const oneapi = require('./oneapi');
      const id = await oneapi.createUser(`orbit_g_${user.id}`);
      db.prepare(
        `UPDATE users SET oneapi_general_user_id = ?, updated_at = datetime('now')
         WHERE id = ? AND oneapi_general_user_id IS NULL`
      ).run(id, user.id);
      walletUser = users.findById(user.id);
    }
    oneapiUserId = walletUser.oneapi_general_user_id;
  }

  const { before, after } = await oneapi.addUserQuota(
    oneapiUserId, points * config.oneapi.quotaPerPoint,
    `admin:grant:${reason || 'manual'}`
  );
  insertQuotaOp({
    userId: user.id, wallet, deltaPoints: points,
    reason: `admin:grant:${reason || 'manual'}`, orderId: null, before, after,
  });
  logger.info('admin_grant', { user_id: user.id, wallet, points, reason });
  return { user_id: user.id, wallet, points, quota_before: before, quota_after: after };
}

module.exports = { processReceipt, refundByTransactionId, adminGrant };
