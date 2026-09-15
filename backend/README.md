# Orbit 积分后端

配套 iOS AI 对话 App 的轻量业务后端：**只负责账号、积分、苹果内购订单和退款**，
不处理 AI 对话请求——对话由 iOS 客户端拿本后端签发的令牌直连 OneAPI（支持 SSE 流式）。

```
iOS App ──注册/登录/查积分/上传收据──────> 本后端(Docker, :8080)
iOS App ──AI流式对话(sk令牌, SSE)────────> OneAPI(Docker) ──> 智谱 GLM
本后端 ──管理API(开户/加积分/扣积分)──────> OneAPI
本后端 ──verifyReceipt(生产↔沙盒)───────> Apple
本后端 <──退款通知(JWS验签)────────────── App Store Server Notifications
```

## 它做了什么

| 需求 | 实现 |
|---|---|
| 用户注册登录、JWT 鉴权 | 用户名+密码（bcrypt 哈希），JWT 有效期默认 7 天 |
| Sign in with Apple | `POST /api/auth/apple`：identityToken 用苹果公钥验签，按 `sub` 复用/建账号，原始令牌不落库 |
| 苹果 IAP 消耗型收据校验 | 经典 verifyReceipt 接口；先打生产，返回 21007 自动改沙盒；校验 bundle_id |
| 校验成功加积分 | 调 OneAPI 管理接口给用户专属子账户加 quota；`transaction_id` 唯一索引保证重复收据不重复加点 |
| 退款处理 | App Store Server Notifications V2 回调，用苹果根证书验证 JWS 签名链，按交易号扣回积分并标记订单 |
| 资产隔离 | 每个用户一个专属 OneAPI 子账户 = iOS 钱包；App 领到的对话令牌只绑定这个钱包，其他渠道积分（预留字段）在 iOS 内不可见不可用 |
| 不处理对话 | 本服务没有任何对话转发接口 |

## 目录结构

```
backend/
├── src/
│   ├── server.js / app.js        # 入口与路由装配
│   ├── config.js                 # 环境变量加载与校验
│   ├── db.js                     # SQLite 建表（users / iap_orders / quota_ops）
│   ├── middleware/               # JWT 鉴权、限流、统一错误处理
│   ├── routes/                   # auth / me / iap / notifications / admin / health
│   └── services/                 # OneAPI 客户端、苹果校验、苹果通知、内购逻辑
├── scripts/smoke.js              # 冒烟测试（自带 Apple/OneAPI 模拟桩，无需外部服务）
├── certs/AppleRootCA-G3.cer      # 苹果根证书（验证退款通知签名）
├── docs/API.md                   # 接口文档（可直接发给 iOS 端对接）
├── Dockerfile / docker-compose.yml
└── .env.example                  # 环境变量模板
```

---

## 一、部署（阿里云 ECS，Ubuntu 22.04）

### 准备清单

- [ ] ECS 已装 Docker 和 Docker Compose（`docker -v`、`docker compose version` 能出版本号）
- [ ] OneAPI 已用 Docker 跑起来，且能正常调通智谱渠道
- [ ] 一个域名解析到 ECS，并用 nginx + Let's Encrypt 配好 HTTPS（苹果收据接口虽不强制 HTTPS，但 App 直连 OneAPI 的地址**必须** HTTPS）
- [ ] App Store Connect 里：App 已建好、消耗型积分包商品已配置、拿到了 App 专用共享密钥

### 第 1 步：上传项目

把整个 `backend/` 目录上传到 ECS（示例用 scp，也可以用 git）：

```bash
scp -r ./backend root@你的ECS_IP:/opt/orbit-points
```

### 第 2 步：填写配置

```bash
cd /opt/orbit-points
cp .env.example .env
nano .env        # 或 vim，逐项填写，说明见下表
```

### 第 3 步：接入 OneAPI 所在的 Docker 网络

让本后端能用容器名直连 OneAPI：

```bash
# 1. 找到 OneAPI 容器名
docker ps
# 2. 查它在哪个网络（看 " Networks " 一行）
docker inspect OneAPI容器名 | grep -A3 Networks
# 3. 把 docker-compose.yml 最后的 oneapi-net 改成那个网络名
nano docker-compose.yml
```

如果 OneAPI 不是 Docker 部署、或不想共享网络：保持默认网络名也行，把 `.env` 里
`ONEAPI_BASE_URL` 改成 `http://ECS内网IP:3000` 这类地址即可（不建议走公网明文）。

### 第 4 步：启动

```bash
docker compose up -d --build
```

### 第 5 步：验证

```bash
# 本机验证
curl http://127.0.0.1:8080/api/health
# 期望：{"ok":true,"db":"ok","oneapi":"ok",...}

# 有域名的话，从外网走 nginx 再验一次
curl https://你的域名/api/health
```

看到 `"oneapi":"ok"` 说明后端 ↔ OneAPI 已打通。之后按 `docs/API.md` 里的
curl 示例注册个账号、测一遍购买流程即可。

---

## 二、.env 变量说明

| 变量 | 必填 | 说明 |
|---|---|---|
| `PORT` |  | 监听端口，默认 8080，一般不改 |
| `JWT_SECRET` | ✅ | JWT 签名密钥，随机长字符串（生成方法见下） |
| `JWT_EXPIRES_IN` |  | 令牌有效期，默认 7d |
| `DATABASE_PATH` |  | SQLite 文件路径，默认 ./data/orbit-points.db |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | ✅ | 管理员账号，首次启动自动创建 |
| `ONEAPI_BASE_URL` | ✅ | 后端访问 OneAPI 的内网地址，如 `http://one-api:3000` |
| `ONEAPI_PUBLIC_BASE_URL` | ✅ | 下发给 App 直连对话的公网 HTTPS 地址 |
| `ONEAPI_ADMIN_TOKEN` | ✅ | OneAPI 管理员的系统访问令牌（见下节） |
| `ONEAPI_ADMIN_USER_ID` |  | **仅 new-api 分支需要**：管理员数字 ID（通常 1）；one-api 原版留空 |
| `ONEAPI_QUOTA_PER_POINT` |  | 1 积分 = 多少 quota，默认 500000（OneAPI 里 50 万 quota = 1 美元） |
| `POINT_PACKS` | ✅ | JSON：商品 ID → 积分数，必须与 App Store Connect 一致 |
| `APPLE_BUNDLE_ID` | ✅ | App 的 Bundle ID |
| `APPLE_SHARED_SECRET` | ✅ | App 专用共享密钥 |
| `REGISTRATION_BONUS_POINTS` |  | 注册赠送积分，默认 0 |

**生成随机密钥**（JWT_SECRET 强烈建议用满 64 位随机串）：

```bash
openssl rand -hex 32
```

## 三、对接 OneAPI

1. **拿管理令牌**：浏览器登录 OneAPI 管理账号 → 个人设置 → 生成的令牌（系统访问令牌）→ 复制填入 `ONEAPI_ADMIN_TOKEN`。
2. **判断分支**：你用的是 one-api 原版还是 new-api？界面右上角/关于页一般能看出来。new-api 的管理接口要求额外带 `New-Api-User: 管理员ID` 请求头，所以要在 `.env` 里填 `ONEAPI_ADMIN_USER_ID=1`（管理员在 OneAPI 里的数字 ID）。
3. **本后端会用到的 OneAPI 接口**（全部封装在 `src/services/oneapi.js`，若你的 OneAPI 分支接口略有差异，只需改这一个文件）：

| 用途 | 接口 |
|---|---|
| 给 App 用户开积分钱包 | `POST /api/user/` + `GET /api/user/search` |
| 查/加减积分 | `GET /api/user/:id` + `PUT /api/user/` |
| 签发对话令牌 | `POST /api/token/` + `GET /api/token/search` |
| 探活 | `GET /api/status` |

4. **验证连通**：`curl http://127.0.0.1:8080/api/health` 里 `oneapi` 为 `ok` 即通。
   若为 `unreachable`：`docker logs orbit-points` 看具体报错，常见原因是网络名不对、令牌无效、或 new-api 没填 `ONEAPI_ADMIN_USER_ID`。

## 四、苹果内购配置

1. **共享密钥**：App Store Connect → 我的 App → App 信息 → App 专用共享密钥 → 生成 → 填入 `APPLE_SHARED_SECRET`。
2. **积分包商品**：App Store Connect → 功能 → App 内购买项目 → 创建消耗型项目。产品 ID 例如 `com.yourcompany.app.points50`，然后把它和积分数写进 `.env` 的 `POINT_PACKS`。
3. **退款通知**：App Store Connect → 我的 App → App Store 服务器通知：
   - 生产服务器 URL：`https://你的域名/api/notifications/app-store`
   - 沙盒服务器 URL：同样地址
   - 保存后苹果会发一条 TEST 通知，`docker logs orbit-points` 里看到 `apple_notify_received` + `type: TEST` 即配置成功。
4. **沙盒测试**：App Store Connect → 用户和访问 → 沙盒测试者 → 创建。真机登录该测试账号后购买，走的就是沙盒；后端会自动识别（生产接口返回 21007 → 切沙盒校验）。

## 五、日常运维

```bash
# 看日志（每行一个 JSON）
docker logs -f orbit-points --tail 100

# 重启 / 更新代码后重建
docker compose restart
docker compose up -d --build

# 备份数据库（建议加到 crontab 每日一次）
sqlite3 ./data/orbit-points.db ".backup '/opt/orbit-points/backup-$(date +%F).db'"
```

### 积分管理台（网页版，日常管理用它）

浏览器打开 **`https://你的域名:8443/api/admin/console`**（同一域名，即 nginx 入口），
用 `.env` 里的 `ADMIN_USERNAME` / `ADMIN_PASSWORD` 登录，可：

- 按用户名/昵称查用户，看实时积分与 OneAPI 钱包
- 一键加/扣积分（正数加、负数扣，自动记流水）
- 看某用户的内购订单与全部最近订单
- 看某用户的积分流水（quota 前后值）

页面本身无需鉴权，但页面调用的每个接口都要求管理员令牌，接口清单见 docs/API.md。

命令行的等价操作（备份手段，详见 docs/API.md）：

```bash
# 查所有订单
curl -H "Authorization: Bearer 管理员token" https://你的域名/api/admin/orders

# 给用户 3 补 10 积分（客服场景）
curl -X POST -H "Authorization: Bearer 管理员token" -H "Content-Type: application/json" \
  -d '{"wallet":"ios","points":10,"reason":"客服补偿"}' \
  https://你的域名/api/admin/users/3/grant
```

### 常见错误对照

| 错误码 | 含义 | 处理 |
|---|---|---|
| `RECEIPT_INVALID` + "共享密钥不匹配" | 苹果共享密钥填错 | 核对 `APPLE_SHARED_SECRET` |
| `RECEIPT_BUNDLE_MISMATCH` | 收据不属于本 App | 核对 `APPLE_BUNDLE_ID` 与 Xcode 工程 |
| `ONEAPI_UNREACHABLE` / `ONEAPI_ERROR` | OneAPI 访问失败 | 看日志定位：网络名、令牌、分支差异 |
| `NOTIFY_INVALID` | 通知验签失败 | 确认苹果发来的 URL 和证书文件存在；正常情况只有攻击/配置错误会触发 |
| `RATE_LIMITED` | 触发限流 | 正常用户不会遇到，被刷时才会 |

## 六、上线前安全清单

- [ ] `JWT_SECRET`、`ADMIN_PASSWORD` 已换成强随机值，`.env` 没有提交到 Git
- [ ] 域名 HTTPS（Let's Encrypt 免费证书 + 自动续期）
- [ ] 防火墙/安全组只放行 80/443，**不要**把 8080 直接暴露公网
- [ ] App 直连 OneAPI 的地址也是 HTTPS，且 OneAPI 管理后台已改默认密码
- [ ] 数据库每日备份已配置
- [ ] `POINT_PACKS` 商品 ID 与 App Store Connect 完全一致

## 七、已知限制与升级路径（如实说明）

1. **verifyReceipt 是苹果的经典接口**：功能稳定、MVP 够用，但苹果长期主推 App Store Server API。代码已把校验隔离在 `src/services/appleVerify.js` 单文件，将来迁移只改它。
2. **加减积分采用"读-改-写"**：极端并发下同一用户同时购买+退款可能有一次重试（代码已带 3 次重试和流水对账表）。单实例 MVP 完全够用；若将来量大可换 OneAPI 兑换码方案。
3. **单实例设计**：限流状态在内存、SQLite 单文件写入，不适合起多个副本。用户量大了再迁移 MySQL/Redis，结构不用变。
4. **退款时积分已花完**：OneAPI 余额会被扣成负数，用户无法继续对话，直到再次充值补回——这是符合预期的行为，不是 bug。

## 八、本地冒烟测试（可选）

不需要真实苹果/OneAPI，脚本自带模拟桩：

```bash
cd backend
npm install
npm run smoke     # 全部通过输出 "✅ 全部通过"
```

覆盖场景：注册登录、沙盒回退、重复收据幂等、数量倍数、未知商品、bundle 校验、
令牌签发与复用、退款扣点与重复退款幂等、伪造签名拒绝、管理员查单补点。

---

接口详情见 **[docs/API.md](docs/API.md)**。
