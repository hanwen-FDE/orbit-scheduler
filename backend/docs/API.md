# Orbit 积分后端接口文档

- Base URL：`https://你的域名`（下文用 `BASE` 代替）
- 数据格式：请求与响应均为 JSON（`Content-Type: application/json`）
- 鉴权方式：需要登录的接口在请求头带 `Authorization: Bearer <token>`
- 每个响应头都带 `X-Request-Id`，报障时提供它方便查日志

## 统一错误格式

```json
{ "error": { "code": "错误码", "message": "人话描述", "request_id": "..." } }
```

| 错误码 | HTTP | 含义 |
|---|---|---|
| `BAD_USERNAME` / `BAD_PASSWORD` | 400 | 用户名需 3~32 位字母数字下划线；密码 8~64 位 |
| `USERNAME_TAKEN` | 409 | 用户名已被占用 |
| `AUTH_FAILED` | 401 | 用户名或密码错误 |
| `AUTH_MISSING` / `AUTH_INVALID` | 401 | 未带令牌 / 令牌无效或过期 |
| `AUTH_DISABLED` | 403 | 账号已被禁用 |
| `APPLE_TOKEN_INVALID` | 401 | Apple 登录凭证无效或已过期 |
| `APPLE_AUTH_UNAVAILABLE` | 503 | 苹果登录验证服务暂不可达 |
| `RECEIPT_INVALID` | 400 | 苹果收据校验未通过（信息里会带原因） |
| `RECEIPT_BUNDLE_MISMATCH` | 400 | 收据不属于本 App |
| `NOTIFY_INVALID` | 401 | 苹果通知验签失败 |
| `ONEAPI_UNREACHABLE` / `ONEAPI_ERROR` | 502 | OneAPI 不可达或调用失败 |
| `APPLE_UNAVAILABLE` | 502 | 苹果校验服务不可用 |
| `RATE_LIMITED` | 429 | 请求太频繁 |
| `FORBIDDEN` | 403 | 需要管理员权限 |

---

## 1. 注册

`POST BASE/api/auth/register`

```json
{ "username": "zhangsan", "password": "a-strong-password" }
```

成功（201）：

```json
{
  "token": "eyJhbGciOi...(JWT，后续请求带上)",
  "user": { "id": 3, "username": "zhangsan", "role": "user", "created_at": "2026-09-14 07:00:00" }
}
```

限流：同一 IP 每分钟 10 次（注册+登录共享）。

## 2. 登录

`POST BASE/api/auth/login`

```json
{ "username": "zhangsan", "password": "a-strong-password" }
```

成功（200）：响应同注册。令牌默认 7 天有效，过期重新登录。

### 2.1 通过 Apple 登录（iOS 端推荐方式）

`POST BASE/api/auth/apple`

```json
{
  "identity_token": "<ASAuthorizationAppleIDCredential.identityToken 转字符串>",
  "full_name": "张三"
}
```

- `full_name` 可选，仅在 Apple 首次授权提供姓名时传；后端只用于展示，绝不覆盖已有资料
- 成功（200）：响应同注册（`token` + `user`）
- 服务端行为：用 `https://appleid.apple.com/auth/keys` 的公钥验签 identity_token（校验签名、`iss`、`aud`=`APPLE_BUNDLE_ID`、有效期），通过后按苹果 `sub` 标识复用或创建账号；**原始 identity_token 不落库**
- 同一个 Apple ID（含换邮箱、隐藏邮箱）永远回到同一个 Orbit 账号
- 前提：Apple Developer 后台已为该 App ID 开启 Sign in with Apple 能力
- 错误码：`APPLE_TOKEN_INVALID`（401，凭证无效或过期，提示用户重试）、`APPLE_AUTH_UNAVAILABLE`（503，苹果公钥服务暂不可达）

## 3. 个人信息

`GET BASE/api/me`（需登录）

```json
{
  "id": 3,
  "username": "zhangsan",
  "role": "user",
  "created_at": "2026-09-14 07:00:00",
  "ios_wallet": { "provisioned": true, "points": 120 }
}
```

`points` 为实时读取 OneAPI 后换算的积分余额。

## 4. 查积分

`GET BASE/api/me/points`（需登录）

```json
{ "wallet": "ios", "points": 120 }
```

## 5. 领取对话令牌（对接 OneAPI 直连）

`POST BASE/api/me/api-key`（需登录，无参数）

```json
{
  "api_key": "sk-xxxxxxxxxxxxxxxx",
  "base_url": "https://api.your-domain.com",
  "default_model": "glm-4v-plus",
  "note": "积分仅支持在 iOS 端使用"
}
```

**iOS 端用法**：拿 `api_key` + `base_url` 直接请求 OneAPI 的 OpenAI 兼容接口，
支持 SSE 流式：

```
POST {base_url}/v1/chat/completions
Authorization: Bearer {api_key}
Content-Type: application/json

{ "model": "glm-4v-plus", "messages": [...], "stream": true }
```

对话消耗的积分由 OneAPI 按 quota 自动扣减，本后端不参与对话链路。
令牌重复领取返回同一个，不会作废旧的。

## 6. 内购收据校验（核心）

`POST BASE/api/iap/verify`（需登录）

```json
{ "receipt": "<SK1 收据的 base64 字符串>" }
```

iOS 端取收据：`Bundle.main.appStoreReceiptURL` 读文件后 base64。
**注意在收到本接口成功响应后再调用 `SKPaymentQueue.finishTransaction()`**，
否则收据丢失无法补验。

成功（200）：

```json
{
  "environment": "sandbox",
  "processed": [
    { "transaction_id": "1000000123456789", "product_id": "com.x.points50", "points": 50, "status": "credited" },
    { "transaction_id": "1000000123456790", "product_id": "com.x.points250", "points": 250, "status": "duplicate" },
    { "transaction_id": "1000000123456791", "product_id": "com.other.thing", "status": "ignored_unknown_product" }
  ],
  "points_added": 50,
  "points": 170
}
```

- `status` 含义：`credited` 首次入账；`duplicate` 该交易已入过账（幂等，不重复加点）；
  `ignored_unknown_product` 收据里有未配置的商品；`conflict` 交易属于其他账号（拒绝）
- 一份收据里可能含多笔交易，会逐笔处理
- 沙盒收据自动识别：先请求苹果生产接口，返回 21007 改走沙盒

限流：同一 IP 每分钟 30 次。

## 7. 苹果服务器通知（给苹果调，不是给 App 调）

`POST BASE/api/notifications/app-store`

```json
{ "signedPayload": "<苹果签名的 JWS，原样透传即可>" }
```

- 验证 JWS 证书链锚定苹果根证书后处理；目前处理 `REFUND`（退款扣回积分），
  `TEST`（连通性测试），其余类型确认后忽略
- 验签失败返回 401；正常处理返回 200 `{"handled": true, ...}`

## 8. 健康检查

`GET BASE/api/health`（无需登录）

```json
{ "ok": true, "db": "ok", "oneapi": "ok", "ts": "2026-09-14T07:00:00.000Z" }
```

---

## 管理接口（需管理员登录令牌）

### 0. 积分管理台（网页）

`GET BASE/api/admin/console` —— 静态网页，浏览器打开后用管理员账号登录即可查用户、加/扣积分、看订单与流水。页面调用的都是下面这些管理员接口。

### 12.1 按用户名查用户

`GET BASE/api/admin/find?username=<用户名或昵称>`

```json
{
  "user": { "id": 12, "username": "ceshiyonghu", "role": "user", "status": "active", "created_at": "..." },
  "ios_wallet": { "oneapi_user_id": 103, "points": 50 }
}
```

### 12.2 某用户积分流水

`GET BASE/api/admin/ops?user_id=<ID>&limit=50`

### 12.3 最近注册用户

`GET BASE/api/admin/recent-users?limit=20`

### 9. 订单列表

`GET BASE/api/admin/orders?status=&user_id=&limit=`

```json
{
  "orders": [
    {
      "id": 1, "user_id": 3, "username": "zhangsan",
      "transaction_id": "1000000123456789", "product_id": "com.x.points50",
      "points": 50, "quantity": 1, "environment": "production",
      "status": "refunded", "purchase_date": "2026-09-10T02:00:00.000Z",
      "created_at": "2026-09-10 02:01:00", "refunded_at": "2026-09-12 08:00:00"
    }
  ]
}
```

### 10. 按苹果交易号查单

`GET BASE/api/admin/orders/txn/<transaction_id>`

### 11. 用户详情（含钱包余额）

`GET BASE/api/admin/users/<id>`

### 12. 手工调点（客服补点/测试）

`POST BASE/api/admin/users/<id>/grant`

```json
{ "wallet": "ios", "points": 10, "reason": "客服补偿" }
```

`points` 正数补、负数扣；`wallet` 目前只有 `ios`（`general` 为其他渠道预留）。

---

## iOS 端完整对接时序

```
1. POST /api/auth/register（或 login）          → 得到 token
2. 用户在 App 内购买积分包（StoreKit 完成支付）
3. POST /api/iap/verify { receipt }             → 积分入账
4. finishTransaction()
5. POST /api/me/api-key                         → 得到 sk 令牌和 base_url
6. 直连 OneAPI: POST {base_url}/v1/chat/completions (stream: true)
7. 展示余额: GET /api/me/points
8. 余额不足时回到第 2 步
```

退款无需 App 参与：苹果 → 本后端 webhook → 自动扣回积分。
