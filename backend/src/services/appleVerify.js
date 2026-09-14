// =====================================================================
// 苹果收据校验（经典 verifyReceipt 接口，对应需求 2）。
//
// 流程：
//   1. 先请求生产环境 verifyReceipt；
//   2. 返回 21007（收据来自沙盒）则自动改走沙盒环境——这就是“区分
//      沙盒/生产”的实现；
//   3. status 必须为 0、bundle_id 必须与本 App 一致；
//   4. 汇总收据里的所有购买记录（in_app + latest_receipt_info 去重）。
//
// 将来若迁移到苹果主推的 App Store Server API，只需替换本文件。
// =====================================================================
const config = require('../config');
const logger = require('../logger');
const { ApiError } = require('../middleware/errorHandler');

const TIMEOUT_MS = 15_000;

// 苹果状态码 -> 人话（只需要覆盖常见的）
const STATUS_MESSAGES = {
  21000: '请求 JSON 无效',
  21002: '收据数据格式错误或损坏',
  21003: '收据无法通过认证',
  21004: '共享密钥（Shared Secret）不匹配，请检查 .env 里的 APPLE_SHARED_SECRET',
  21005: '收据服务器暂时不可用，请稍后重试',
  21006: '收据有效但订阅已过期',
  21007: '这是沙盒环境的收据',
  21008: '这是生产环境的收据',
  21009: '内部数据访问错误，请稍后重试',
  21010: '找不到收据或收据已过期',
};

async function callApple(url, receiptData) {
  const resp = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      'receipt-data': receiptData,
      password: config.apple.sharedSecret,
      'exclude-old-transactions': true,
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!resp.ok) {
    throw new ApiError('APPLE_UNAVAILABLE', `苹果校验服务返回 HTTP ${resp.status}，请稍后重试`, 502);
  }
  return resp.json();
}

// 校验一条收据，返回 { environment, purchases: [...] }
async function verifyReceipt(receiptData) {
  if (typeof receiptData !== 'string' || receiptData.length < 10) {
    throw new ApiError('BAD_RECEIPT', '收据内容为空', 400);
  }

  // 第一步：先打生产环境
  let json = await callApple(config.apple.verifyUrl, receiptData);

  // 第二步：21007 说明是沙盒收据，改走沙盒接口
  let environment = 'production';
  if (json.status === 21007) {
    logger.info('apple_receipt_sandbox_fallback', {});
    json = await callApple(config.apple.sandboxVerifyUrl, receiptData);
    environment = 'sandbox';
  }

  // 第三步：校验结果
  if (json.status !== 0) {
    const hint = STATUS_MESSAGES[json.status] || `未知状态码 ${json.status}`;
    logger.warn('apple_receipt_rejected', { status: json.status });
    throw new ApiError('RECEIPT_INVALID', `收据校验未通过：${hint}`, 400);
  }

  const receipt = json.receipt || {};
  if (receipt.bundle_id !== config.apple.bundleId) {
    logger.warn('apple_receipt_bundle_mismatch', {
      expect: config.apple.bundleId, got: receipt.bundle_id,
    });
    throw new ApiError('RECEIPT_BUNDLE_MISMATCH', '收据不属于本 App，已拒绝', 400);
  }

  // 苹果响应里若带 environment 字段（"Sandbox"/"Production"），以它为准
  if (json.environment === 'Sandbox') environment = 'sandbox';
  if (json.environment === 'Production') environment = 'production';

  // 第四步：汇总购买记录并按 transaction_id 去重
  // （消耗型购买出现在 in_app；latest_receipt_info 兜底，避免个别返回结构差异漏单）
  const byTxn = new Map();
  const rawList = [...(receipt.in_app || []), ...(json.latest_receipt_info || [])];
  for (const item of rawList) {
    if (!item.transaction_id) continue;
    if (!byTxn.has(item.transaction_id)) byTxn.set(item.transaction_id, item);
  }

  const purchases = [...byTxn.values()].map((item) => ({
    transaction_id: item.transaction_id,
    original_transaction_id: item.original_transaction_id || item.transaction_id,
    product_id: item.product_id,
    quantity: Number.parseInt(item.quantity || '1', 10) || 1,
    purchase_date: item.purchase_date_ms
      ? new Date(Number(item.purchase_date_ms)).toISOString()
      : (item.purchase_date || null),
  }));

  logger.info('apple_receipt_verified', {
    environment,
    purchase_count: purchases.length,
    products: purchases.map((p) => p.product_id),
  });
  return { environment, purchases };
}

module.exports = { verifyReceipt };
