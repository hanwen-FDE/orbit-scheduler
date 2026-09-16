// =====================================================================
// 冒烟测试：不依赖真实苹果/OneAPI 服务，在本机模拟全套环境，跑通：
//
//   健康检查 → 注册登录 → 查积分 → IAP 购买（含沙盒回退、数量倍数、
//   未知商品跳过、bundle 校验）→ 重复收据幂等 → 领对话令牌 →
//   退款通知（JWS 验签、重复退款幂等、伪造签名拒绝）→ 管理员查单/补点
//
// 运行：npm run smoke   （全部通过输出 "全部通过"，任何失败退出码 1）
//
// 原理说明：
//   - 用 node-forge 生成一套测试用 CA+叶子证书（仅测试用），
//     并把后端的 APPLE_ROOT_CA_PATH 指向这套测试 CA；
//   - 用它签出和苹果格式一致的 JWS 通知，验证验签逻辑真实生效；
//   - Apple 模拟桩：生产接口恒返回 21007，触发后端沙盒回退逻辑。
// =====================================================================
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const express = require('express');

const ROOT = path.join(__dirname, '..');
// 使用系统临时目录，避免 Windows 在 OneDrive/非 ASCII 工作区清理 .tmp 时失败。
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'orbit-backend-smoke-'));
const PORTS = { backend: 9100, apple: 9101, oneapi: 9102 };
const BASE = `http://127.0.0.1:${PORTS.backend}`;
const BUNDLE_ID = 'com.test.app';
const SHARED_SECRET = 'smoke-shared-secret';
const QUOTA_PER_POINT = 100; // 1 积分 = 100 quota，心算方便

let failed = 0;
function check(name, cond, detail) {
  if (cond) console.log(`  ✅ ${name}`);
  else { failed++; console.error(`  ❌ ${name}${detail ? ` —— ${detail}` : ''}`); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------------
// 测试证书链：不依赖第三方库，手写最小 DER 编码生成 X.509 证书。
//   CA：RSA 密钥自签名（后端把根证书锚定到它）
//   叶子：EC P-256 密钥（JWS 的 ES256 签名必须用 EC 密钥），由 CA 签发
// ---------------------------------------------------------------------

// ---- 迷你 DER 编码工具 ----
function derLenBytes(n) {
  if (n < 128) return [n];
  const bytes = [];
  let v = n;
  while (v > 0) { bytes.unshift(v & 0xff); v >>= 8; }
  return [0x80 | bytes.length, ...bytes];
}
function tlv(tag, content) {
  return Buffer.concat([Buffer.from([tag, ...derLenBytes(content.length)]), content]);
}
function derSeq(...parts) { return tlv(0x30, Buffer.concat(parts)); }
function derSet(...parts) { return tlv(0x31, Buffer.concat(parts)); }
function derOid(dots) {
  const arcs = dots.split('.').map(Number);
  const out = [arcs[0] * 40 + arcs[1]];
  for (const arc of arcs.slice(2)) {
    if (arc < 128) { out.push(arc); continue; }
    const tmp = [];
    let v = arc;
    while (v > 0) { tmp.unshift(v & 0x7f); v >>= 7; }
    tmp.forEach((_, i) => { if (i < tmp.length - 1) tmp[i] |= 0x80; });
    out.push(...tmp);
  }
  return tlv(0x06, Buffer.from(out));
}
function derUtf8(s) { return tlv(0x0c, Buffer.from(s, 'utf8')); }
function derUtctime(d) {
  const p = (n) => String(n).padStart(2, '0');
  return tlv(0x17, Buffer.from(
    `${p(d.getUTCFullYear() % 100)}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}` +
    `${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}Z`
  ));
}
function derBitString(buf) { return tlv(0x03, Buffer.concat([Buffer.from([0x00]), buf])); }

const OID_CN = '2.5.4.3';
const OID_SHA256_RSA = '1.2.840.113549.1.1.11';
const sigAlg = derSeq(derOid(OID_SHA256_RSA), tlv(0x05, Buffer.alloc(0))); // sha256WithRSAEncryption + NULL

function name(cn) {
  return derSeq(derSet(derSeq(derOid(OID_CN), derUtf8(cn))));
}

// 用给定的公钥（SPKI DER）和签发方私钥生成一张最小化 X.509 v1 证书
function buildCert({ cn, issuerCn, spkiDer, signerKey }) {
  const serial = tlv(0x02, Buffer.from([Date.now() % 254 + 1]));
  const tbs = derSeq(
    serial,
    sigAlg,
    name(issuerCn),
    derSeq(derUtctime(new Date(Date.now() - 3600_000)), derUtctime(new Date(Date.now() + 3600_000))),
    name(cn),
    spkiDer
  );
  const signature = crypto.createSign('SHA256').update(tbs).sign(signerKey);
  const der = derSeq(tbs, sigAlg, derBitString(signature));
  return { der, pem: `-----BEGIN CERTIFICATE-----\n${der.toString('base64')}\n-----END CERTIFICATE-----\n` };
}

function genTestChain(cn) {
  // CA：RSA 自签
  const caKeys = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const caSpki = caKeys.publicKey.export({ type: 'spki', format: 'der' });
  const ca = buildCert({ cn: `${cn} Root`, issuerCn: `${cn} Root`, spkiDer: caSpki, signerKey: caKeys.privateKey });
  // 叶子：EC P-256，由 CA 签发
  const leafKeys = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const leafSpki = leafKeys.publicKey.export({ type: 'spki', format: 'der' });
  const leaf = buildCert({ cn: `${cn} Leaf`, issuerCn: `${cn} Root`, spkiDer: leafSpki, signerKey: caKeys.privateKey });
  return { ca, leaf, leafKeys };
}

// Node 签出来的是 DER 格式 ECDSA 签名，JWS 需要裸 R||S 格式，做一次转换
function derSigToRaw(sig) {
  const rLen = sig[3];
  const r = sig.subarray(4, 4 + rLen);
  const sStart = 4 + rLen + 2;
  const sLen = sig[sStart - 1];
  const s = sig.subarray(sStart, sStart + sLen);
  const strip = (b) => { let i = 0; while (i < b.length - 1 && b[i] === 0) i++; return b.subarray(i); };
  const pad = (b) => Buffer.concat([Buffer.alloc(32 - b.length), b]);
  return Buffer.concat([pad(strip(r)), pad(strip(s))]);
}

function signJws(payload, chain) {
  const { ca, leaf, leafKeys } = chain;
  const header = { alg: 'ES256', x5c: [leaf.der.toString('base64'), ca.der.toString('base64')] };
  const signingInput = `${Buffer.from(JSON.stringify(header)).toString('base64url')}.${Buffer.from(JSON.stringify(payload)).toString('base64url')}`;
  const derSig = crypto.createSign('SHA256').update(signingInput).sign(leafKeys.privateKey);
  return `${signingInput}.${derSigToRaw(derSig).toString('base64url')}`;
}

// ---------------------------------------------------------------------
// Apple 模拟桩：生产接口恒返 21007，逼后端走沙盒回退
// ---------------------------------------------------------------------
const appleStub = { purchases: [], bundleId: BUNDLE_ID };

function startAppleStub() {
  const app = express();
  app.use(express.json());

  app.post('/verifyReceipt', (_req, res) => res.json({ status: 21007 }));

  app.post('/sandbox/verifyReceipt', (req, res) => {
    if (req.body?.password !== SHARED_SECRET) {
      res.json({ status: 21004 });
      return;
    }
    res.json({
      status: 0,
      environment: 'Sandbox',
      receipt: {
        bundle_id: appleStub.bundleId,
        in_app: appleStub.purchases.map((p) => ({
          transaction_id: p.transaction_id,
          original_transaction_id: p.transaction_id,
          product_id: p.product_id,
          quantity: String(p.quantity),
          purchase_date_ms: String(Date.now()),
        })),
      },
      latest_receipt_info: [],
    });
  });

  return app.listen(PORTS.apple);
}

// ---------------------------------------------------------------------
// OneAPI 模拟桩：实现后端用到的管理接口
// ---------------------------------------------------------------------
function startOneApiStub() {
  const app = express();
  app.use(express.json());

  const users = new Map(); // id -> {id, username, password, quota}
  const tokens = [];       // {id, name, user_id, key}
  const logs = [{ id: 501, user_id: 101, username: 'orbit_smoke', model_name: 'glm-4v-plus', token_name: 'orbit_uid_2', prompt_tokens: 120, completion_tokens: 80, quota: 200, elapsed_time: 420, is_stream: true, created_at: Math.floor(Date.now() / 1000) }];
  const sessions = new Map(); // session id -> userId（模拟登录会话）
  let nextUserId = 100;
  let nextTokenId = 200;
  const authOk = (req) => req.get('Authorization') === 'Bearer smoke-oneapi-token';
  const sessionUser = (req) => {
    const m = String(req.get('cookie') || '').match(/session=([^\s;]+)/);
    return m ? sessions.get(m[1]) : undefined;
  };

  // 模拟真实 one-api 的权限模型：
  //   用户/额度管理接口要管理员令牌；令牌接口要“本人登录会话”（自签语义，
  //   管理员令牌替签的令牌会挂错人）；登录和 status 对外开放。
  app.use('/api', (req, res, next) => {
    if (req.path === '/status' || req.path === '/user/login') { next(); return; }
    if (req.path.startsWith('/token')) {
      const uid = sessionUser(req);
      if (!uid) { res.status(401).json({ success: false, message: '未登录' }); return; }
      req.stubUserId = uid;
      next();
      return;
    }
    if (!authOk(req)) { res.status(401).json({ success: false, message: '无权限' }); return; }
    next();
  });

  // 子账户登录：校验通过后发 session cookie（后端签令牌前先走这里）
  app.post('/api/user/login', (req, res) => {
    const { username, password } = req.body || {};
    const u = [...users.values()].find((x) => x.username === username);
    if (!u || u.password !== password) {
      res.json({ success: false, message: '用户名或密码错误' });
      return;
    }
    const sid = `sess-${crypto.randomBytes(8).toString('hex')}`;
    sessions.set(sid, u.id);
    res.setHeader('Set-Cookie', `session=${sid}; Path=/; HttpOnly`);
    res.json({ success: true, message: '', data: { id: u.id, username: u.username } });
  });

  app.post('/api/user/', (req, res) => {
    const id = ++nextUserId;
    users.set(id, { id, username: req.body.username, password: req.body.password, quota: 0 });
    res.json({ success: true, message: '' });
  });

  app.get('/api/user/search', (req, res) => {
    const items = [...users.values()].filter((u) => u.username.includes(req.query.keyword || ''));
    res.json({ success: true, data: { items } });
  });

  app.get('/api/user/:id', (req, res) => {
    const u = users.get(Number(req.params.id));
    if (!u) { res.json({ success: false, message: '用户不存在' }); return; }
    res.json({ success: true, data: u });
  });

  app.put('/api/user/', (req, res) => {
    const u = users.get(Number(req.body.id));
    if (!u) { res.json({ success: false, message: '用户不存在' }); return; }
    if (typeof req.body.quota === 'number') u.quota = req.body.quota;
    if (typeof req.body.password === 'string' && req.body.password) u.password = req.body.password;
    res.json({ success: true, message: '' });
  });

  // 自签语义：令牌一律挂到“当前登录会话”的用户名下，body 里的 user_id 被无视
  app.post('/api/token/', (req, res) => {
    const token = {
      id: ++nextTokenId,
      name: req.body.name,
      user_id: req.stubUserId,
      key: crypto.randomBytes(24).toString('hex'),
    };
    tokens.push(token);
    res.json({ success: true, message: '' });
  });

  app.get('/api/token/search', (req, res) => {
    const items = tokens.filter((t) => t.user_id === req.stubUserId && t.name.includes(req.query.keyword || ''));
    res.json({ success: true, data: { items } });
  });

  app.get('/api/status', (_req, res) => res.json({ success: true, data: {} }));
  app.get('/api/log/', (req, res) => {
    const username = String(req.query.username || '');
    const filtered = logs.filter((log) => !username || log.username === username);
    res.json({ success: true, data: filtered });
  });
  app.get('/api/log/stat', (req, res) => {
    const username = String(req.query.username || '');
    const quota = logs.filter((log) => !username || log.username === username)
      .reduce((sum, log) => sum + log.quota, 0);
    res.json({ success: true, data: { quota } });
  });

  return app.listen(PORTS.oneapi);
}

// ---------------------------------------------------------------------
// HTTP 小工具
// ---------------------------------------------------------------------
async function api(method, p, body, token) {
  const res = await fetch(BASE + p, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch { /* 非 JSON */ }
  return { status: res.status, json };
}

async function waitBackend() {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(`${BASE}/api/health`);
      if (r.ok) return true;
    } catch { /* 尚未启动 */ }
    await sleep(300);
  }
  return false;
}

// ---------------------------------------------------------------------
// 主流程
// ---------------------------------------------------------------------
async function main() {
  console.log('== Orbit 积分后端冒烟测试 ==\n');

  // 临时目录已在模块加载时创建。

  // 测试证书：正规 CA 链（给后端锚定）+ 一套“伪造”CA（用于攻击测试）
  const chain = genTestChain('Smoke');
  const fakeChain = genTestChain('Fake');
  fs.writeFileSync(path.join(TMP, 'smoke-root-ca.pem'), chain.ca.pem);
  // 自检：Node 必须能解析生成的证书并验证链
  const caCert = new crypto.X509Certificate(chain.ca.pem);
  const leafCert = new crypto.X509Certificate(chain.leaf.pem);
  if (!leafCert.verify(caCert.publicKey)) throw new Error('测试证书链自检失败');

  const appleSrv = startAppleStub();
  const oneapiSrv = startOneApiStub();

  const child = spawn(process.execPath, ['src/server.js'], {
    cwd: ROOT,
    stdio: 'inherit',
    env: {
      ...process.env,
      PORT: String(PORTS.backend),
      JWT_SECRET: 'smoke-jwt-secret',
      JWT_EXPIRES_IN: '1h',
      DATABASE_PATH: path.join(TMP, 'smoke.db'),
      ADMIN_USERNAME: 'smokeadmin',
      ADMIN_PASSWORD: 'smoke-admin-pass-123',
      ONEAPI_BASE_URL: `http://127.0.0.1:${PORTS.oneapi}`,
      ONEAPI_PUBLIC_BASE_URL: `http://127.0.0.1:${PORTS.oneapi}`,
      ONEAPI_ADMIN_TOKEN: 'smoke-oneapi-token',
      ONEAPI_ADMIN_USER_ID: '1',
      ONEAPI_QUOTA_PER_POINT: String(QUOTA_PER_POINT),
      POINT_PACKS: JSON.stringify({ 'com.test.points50': 50, 'com.test.points250': 250 }),
      APPLE_BUNDLE_ID: BUNDLE_ID,
      APPLE_SHARED_SECRET: SHARED_SECRET,
      APPLE_VERIFY_URL: `http://127.0.0.1:${PORTS.apple}/verifyReceipt`,
      APPLE_SANDBOX_VERIFY_URL: `http://127.0.0.1:${PORTS.apple}/sandbox/verifyReceipt`,
      APPLE_ROOT_CA_PATH: path.join(TMP, 'smoke-root-ca.pem'),
      LOG_LEVEL: 'warn', // 减少日志噪音，聚焦测试结果
    },
  });

  try {
    console.log('[1] 健康检查');
    check('后端启动并可访问', await waitBackend());
    const health = await api('GET', '/api/health');
    check('health 返回 ok 且 OneAPI 连通', health.json?.ok === true && health.json?.oneapi === 'ok');

    console.log('\n[2] 注册 / 登录');
    const badReg = await api('POST', '/api/auth/register', { username: 'u', password: '123' });
    check('弱参数被拒绝(400)', badReg.status === 400);
    const reg = await api('POST', '/api/auth/register', { username: 'tester1', password: 'passw0rd123' });
    check('注册成功(201)并返回 token', reg.status === 201 && !!reg.json?.token);
    const userToken = reg.json?.token;
    const dupReg = await api('POST', '/api/auth/register', { username: 'tester1', password: 'passw0rd123' });
    check('重复用户名被拒绝(409)', dupReg.status === 409);
    const noAuth = await api('GET', '/api/me');
    check('未登录访问被拒(401)', noAuth.status === 401);

    console.log('\n[3] 钱包初始状态');
    const me0 = await api('GET', '/api/me', null, userToken);
    check('新用户积分为 0 且未开户', me0.json?.ios_wallet?.points === 0 && me0.json?.ios_wallet?.provisioned === false);

    console.log('\n[4] IAP 购买（沙盒回退 + 入账）');
    appleStub.purchases = [{ transaction_id: 'smoke_txn_1', product_id: 'com.test.points50', quantity: 1 }];
    const v1 = await api('POST', '/api/iap/verify', { receipt: 'ZmFrZS1yZWNlaXB0' }, userToken);
    check('生产 21007 自动回退沙盒', v1.json?.environment === 'sandbox');
    check('50 积分包入账', v1.json?.processed?.[0]?.status === 'credited' && v1.json?.points_added === 50);
    check('余额变为 50', v1.json?.points === 50);

    console.log('\n[5] 重复收据幂等');
    const v2 = await api('POST', '/api/iap/verify', { receipt: 'ZmFrZS1yZWNlaXB0' }, userToken);
    check('同一收据标记 duplicate 不重复加点', v2.json?.processed?.[0]?.status === 'duplicate' && v2.json?.points_added === 0);
    check('余额仍为 50', v2.json?.points === 50);

    console.log('\n[6] 数量倍数 + 未知商品跳过');
    appleStub.purchases = [
      { transaction_id: 'smoke_txn_2', product_id: 'com.test.points250', quantity: 2 },
      { transaction_id: 'smoke_txn_3', product_id: 'com.otherapp.thing', quantity: 1 },
    ];
    const v3 = await api('POST', '/api/iap/verify', { receipt: 'ZmFrZS1yZWNlaXB0LTI=' }, userToken);
    check('数量 2 的 250 积分包入账 500', v3.json?.points_added === 500);
    check('未知商品被跳过', v3.json?.processed?.some((p) => p.status === 'ignored_unknown_product'));
    check('余额 50 + 500 = 550', v3.json?.points === 550);

    console.log('\n[7] bundle_id 校验');
    appleStub.bundleId = 'com.wrong.app';
    appleStub.purchases = [{ transaction_id: 'smoke_txn_4', product_id: 'com.test.points50', quantity: 1 }];
    const v4 = await api('POST', '/api/iap/verify', { receipt: 'ZmFrZS1yZWNlaXB0LTM=' }, userToken);
    check('他人 App 的收据被拒绝(400)', v4.status === 400 && v4.json?.error?.code === 'RECEIPT_BUNDLE_MISMATCH');
    appleStub.bundleId = BUNDLE_ID;

    console.log('\n[8] 领取对话令牌');
    const keyResp = await api('POST', '/api/me/api-key', {}, userToken);
    check('返回 sk- 令牌与对话地址', String(keyResp.json?.api_key || '').startsWith('sk-') && !!keyResp.json?.base_url);
    const keyResp2 = await api('POST', '/api/me/api-key', {}, userToken);
    check('重复领取复用同一令牌', keyResp2.json?.api_key === keyResp.json?.api_key);

    console.log('\n[9] 退款通知（JWS 验签）');
    const refundPayload = {
      notificationType: 'REFUND',
      data: {
        signedTransactionInfo: signJws(
          { transactionId: 'smoke_txn_1', bundleId: BUNDLE_ID, productId: 'com.test.points50' },
          chain
        ),
      },
    };
    const r1 = await api('POST', '/api/notifications/app-store', { signedPayload: signJws(refundPayload, chain) });
    check('退款通知处理成功', r1.status === 200 && r1.json?.handled === true);
    const pts1 = await api('GET', '/api/me/points', null, userToken);
    check('积分扣回 50，余额 500', pts1.json?.points === 500);
    const r2 = await api('POST', '/api/notifications/app-store', { signedPayload: signJws(refundPayload, chain) });
    check('重复退款幂等（不重复扣）', r2.json?.already === true);
    const pts2 = await api('GET', '/api/me/points', null, userToken);
    check('余额仍为 500', pts2.json?.points === 500);

    console.log('\n[10] 伪造签名拒绝');
    const forged = await api('POST', '/api/notifications/app-store', { signedPayload: signJws(refundPayload, fakeChain) });
    check('非苹果链签名被拒(401)', forged.status === 401 && forged.json?.error?.code === 'NOTIFY_INVALID');

    console.log('\n[11] TEST 通知应答');
    const testNotify = await api('POST', '/api/notifications/app-store', { signedPayload: signJws({ notificationType: 'TEST' }, chain) });
    check('TEST 通知返回 200', testNotify.status === 200 && testNotify.json?.type === 'TEST');

    console.log('\n[12] 管理员接口');
    const adminLogin = await api('POST', '/api/auth/login', { username: 'smokeadmin', password: 'smoke-admin-pass-123' });
    check('管理员登录', adminLogin.status === 200 && adminLogin.json?.user?.role === 'admin');
    const adminToken = adminLogin.json?.token;
    const forbidden = await api('GET', '/api/admin/orders', null, userToken);
    check('普通用户访问管理接口被拒(403)', forbidden.status === 403);
    const orders = await api('GET', '/api/admin/orders', null, adminToken);
    check('订单列表 2 笔（未知商品不入库）', orders.json?.orders?.length === 2);
    check('其中 1 笔已退款', orders.json?.orders?.filter((o) => o.status === 'refunded').length === 1);
    const grant = await api('POST', `/api/admin/users/${reg.json.user.id}/grant`, { wallet: 'ios', points: 10, reason: 'smoke' }, adminToken);
    check('管理员补点成功', grant.status === 200);
    const pts3 = await api('GET', '/api/me/points', null, userToken);
    check('补点后余额 510', pts3.json?.points === 510);
    const ledger = await api('GET', '/api/me/points/ledger', null, userToken);
    check('用户可读取自己的积分账本与余额快照', ledger.status === 200 && ledger.json?.entries?.[0]?.balance_after === 510);
    const overview = await api('GET', '/api/admin/overview', null, adminToken);
    check('管理台总览接口返回积分与使用量', overview.status === 200 && overview.json?.users === 1 && overview.json?.usage_30d?.available === true);
    const usage = await api('GET', '/api/admin/usage?limit=20', null, adminToken);
    check('管理台可读取 OneAPI 模型使用流水', usage.status === 200 && usage.json?.usage?.[0]?.model === 'glm-4v-plus');
    const allOps = await api('GET', '/api/admin/ops?limit=100', null, adminToken);
    check('管理台可读取全部用户积分流水', allOps.status === 200 && allOps.json?.ops?.length >= 1);
  } finally {
    child.kill();
    appleSrv.close();
    oneapiSrv.close();
    // Windows 上子进程退出与端口释放是异步的；让系统临时目录自行回收，
    // 避免清理仍被测试进程占用的目录而把成功测试误报为失败。
  }

  console.log('\n========================');
  if (failed === 0) {
    console.log('✅ 全部通过');
    process.exit(0);
  } else {
    console.error(`❌ ${failed} 项失败`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('冒烟测试自身出错：', err);
  process.exit(1);
});
