// =====================================================================
// App Store Server Notifications V2（对应需求 4：退款事件处理）。
//
// 苹果会把退款等事件推到 POST /api/notifications/app-store，
// 请求体是 {"signedPayload": "<JWS>"}。
//
// 安全验证（不依赖任何第三方库，只用 Node 内置 crypto）：
//   1. JWS 头部带 x5c 证书链 [叶子证书, 中间证书(, 根证书)]；
//   2. 逐级验证“每个证书由下一级签发”，且链尾锚定到本地保存的
//      苹果根证书（certs/AppleRootCA-G3.cer）——伪造的通知过不了；
//   3. 用叶子证书的公钥验证 JWS 签名（ES256）；
//   4. 内层 signedTransactionInfo 同样是 JWS，用相同方法再验一次。
// =====================================================================
const crypto = require('crypto');
const fs = require('fs');
const config = require('../config');
const logger = require('../logger');
const { ApiError } = require('../middleware/errorHandler');

// ---------- base64url 工具 ----------
function b64urlToBuffer(s) {
  return Buffer.from(s, 'base64url');
}
function jsonFromB64url(s) {
  return JSON.parse(b64urlToBuffer(s).toString('utf8'));
}

// ---------- ES256 签名格式转换 ----------
// JWS 的 ES256 签名是 64 字节裸格式（R||S 各 32 字节），
// Node crypto 需要 DER 编码格式，这里做一次转换。
function rawSignatureToDer(raw) {
  if (raw.length !== 64) throw new Error(`非法的 ES256 签名长度：${raw.length}`);
  function derInteger(buf) {
    let i = 0;
    while (i < buf.length - 1 && buf[i] === 0) i++; // 去掉前导零
    let v = buf.subarray(i);
    if (v[0] & 0x80) v = Buffer.concat([Buffer.from([0]), v]); // 最高位为 1 需补零
    return Buffer.concat([Buffer.from([0x02, v.length]), v]);
  }
  const r = derInteger(raw.subarray(0, 32));
  const s = derInteger(raw.subarray(32));
  return Buffer.concat([Buffer.from([0x30, r.length + s.length]), r, s]);
}

// ---------- 证书链验证 ----------
let rootCertCache = null;

function loadRootCert() {
  if (rootCertCache) return rootCertCache;
  const pemOrDer = fs.readFileSync(config.apple.rootCaPath);
  rootCertCache = new crypto.X509Certificate(pemOrDer);
  return rootCertCache;
}

function checkValidityPeriod(cert) {
  const now = Date.now();
  if (Date.parse(cert.validFrom) > now || Date.parse(cert.validTo) < now) {
    throw new Error(`证书不在有效期内：${cert.subject}`);
  }
}

// 验证证书链并返回叶子证书
function verifyChain(certs, rootCert) {
  if (certs.length === 0) throw new Error('x5c 证书链为空');
  for (const cert of certs) checkValidityPeriod(cert);
  for (let i = 0; i < certs.length - 1; i++) {
    if (!certs[i].verify(certs[i + 1].publicKey)) {
      throw new Error(`证书链第 ${i} 级验签失败`);
    }
  }
  const last = certs[certs.length - 1];
  const anchored = last.fingerprint256 === rootCert.fingerprint256 || last.verify(rootCert.publicKey);
  if (!anchored) throw new Error('证书链未锚定到苹果根证书');
  return certs[0];
}

// ---------- JWS 验证与解码 ----------
// 输入 compact JWS 字符串，验证通过后返回 payload 对象
function verifyJws(jws) {
  const parts = String(jws).split('.');
  if (parts.length !== 3) throw new Error('JWS 格式错误');
  const [h, p, s] = parts;

  const header = jsonFromB64url(h);
  if (header.alg !== 'ES256') throw new Error(`不支持的签名算法：${header.alg}`);
  if (!Array.isArray(header.x5c) || header.x5c.length === 0) throw new Error('JWS 头缺少 x5c 证书链');

  const certs = header.x5c.map((b64) => new crypto.X509Certificate(Buffer.from(b64, 'base64')));
  const leaf = verifyChain(certs, loadRootCert());

  const ok = crypto
    .createVerify('SHA256')
    .update(`${h}.${p}`)
    .verify(leaf.publicKey, rawSignatureToDer(b64urlToBuffer(s)));
  if (!ok) throw new Error('JWS 签名验证失败');

  return jsonFromB64url(p);
}

// ---------- 通知处理入口 ----------
// 返回给路由层的结果；任何验签失败都会抛 ApiError(NOTIFY_INVALID, 401)
async function handleNotification(signedPayload) {
  let payload;
  try {
    payload = verifyJws(signedPayload);
  } catch (err) {
    logger.warn('apple_notify_bad_signature', { error: err.message });
    throw new ApiError('NOTIFY_INVALID', `通知验签失败：${err.message}`, 401);
  }

  const type = payload.notificationType;
  const subtype = payload.subtype || '';
  logger.info('apple_notify_received', { type, subtype });

  // 苹果在配置 URL 后会先发一条 TEST 通知用于连通性验证
  if (type === 'TEST') {
    return { handled: true, type, note: '测试通知已确认' };
  }

  // 退款：需要解出内层交易信息拿 transactionId
  if (type === 'REFUND') {
    const signedTxn = payload.data?.signedTransactionInfo;
    if (!signedTxn) throw new ApiError('NOTIFY_INVALID', 'REFUND 通知缺少交易信息', 400);

    let txn;
    try {
      txn = verifyJws(signedTxn);
    } catch (err) {
      logger.warn('apple_notify_bad_inner_signature', { error: err.message });
      throw new ApiError('NOTIFY_INVALID', `内层交易信息验签失败：${err.message}`, 401);
    }
    if (txn.bundleId && txn.bundleId !== config.apple.bundleId) {
      logger.warn('apple_notify_bundle_mismatch', { got: txn.bundleId });
      return { handled: false, type, reason: 'bundle_mismatch' };
    }

    const iap = require('./iap'); // 延迟引入避免循环依赖
    const result = await iap.refundByTransactionId(String(txn.transactionId));
    return { handled: result.handled, type, ...result };
  }

  // 其他类型（订阅续费、账单问题等）与消耗型积分无关，确认收到即可
  return { handled: true, type, ignored: true };
}

module.exports = { handleNotification, verifyJws };
