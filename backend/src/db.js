// =====================================================================
// 数据库：SQLite（better-sqlite3 同步接口，简单可靠）。
// 启动时自动建表，不需要手工执行 SQL。
//
// 三张表的职责：
//   users      —— 本系统的账号，以及它在 OneAPI 里的“钱包”映射
//   iap_orders —— 苹果内购订单（transaction_id 唯一，防重复加点）
//   quota_ops  —— 每一次加减积分的流水，用于对账和排查问题
// =====================================================================
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const config = require('./config');
const logger = require('./logger');

// 确保数据库所在目录存在
fs.mkdirSync(path.dirname(config.databasePath), { recursive: true });

const db = new Database(config.databasePath);
db.pragma('journal_mode = WAL'); // 写入更安全，宕机不易损坏
db.pragma('foreign_keys = ON');

db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  username               TEXT    NOT NULL UNIQUE,
  password_hash          TEXT    NOT NULL,
  role                   TEXT    NOT NULL DEFAULT 'user',    -- 'user' | 'admin'
  status                 TEXT    NOT NULL DEFAULT 'active',  -- 'active' | 'disabled'
  oneapi_ios_user_id     INTEGER,                            -- iOS 钱包对应的 OneAPI 用户 ID（懒创建）
  oneapi_ios_token_id    INTEGER,                            -- 已下发给 App 的对话令牌 ID
  oneapi_ios_token_key   TEXT,                               -- 已下发的对话令牌（sk-...）
  oneapi_general_user_id INTEGER,                            -- 其他渠道钱包（预留，iOS 内不可用）
  created_at             TEXT    NOT NULL DEFAULT (datetime('now')),
  updated_at             TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS iap_orders (
  id                      INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id                 INTEGER NOT NULL REFERENCES users(id),
  transaction_id          TEXT    NOT NULL UNIQUE,            -- 苹果交易号，唯一索引保证幂等
  original_transaction_id TEXT,
  product_id              TEXT    NOT NULL,
  points                  INTEGER NOT NULL,
  quantity                INTEGER NOT NULL DEFAULT 1,
  environment             TEXT    NOT NULL,                   -- 'sandbox' | 'production'
  status                  TEXT    NOT NULL DEFAULT 'delivered', -- 'delivered' | 'refunded'
  purchase_date           TEXT,
  created_at              TEXT    NOT NULL DEFAULT (datetime('now')),
  refunded_at             TEXT
);
CREATE INDEX IF NOT EXISTS idx_iap_orders_user   ON iap_orders(user_id);
CREATE INDEX IF NOT EXISTS idx_iap_orders_status ON iap_orders(status);

CREATE TABLE IF NOT EXISTS quota_ops (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id             INTEGER NOT NULL REFERENCES users(id),
  wallet              TEXT    NOT NULL,                       -- 'ios' | 'general'
  delta_points        INTEGER NOT NULL,                       -- 正数加点，负数扣点
  reason              TEXT    NOT NULL,                       -- 例如 'iap:order#12' / 'refund:order#12' / 'admin:grant'
  order_id            INTEGER,
  oneapi_quota_before INTEGER,
  oneapi_quota_after  INTEGER,
  created_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_quota_ops_user ON quota_ops(user_id);
`);

// 兼容已经部署过的 SQLite：Apple 登录上线时为旧表补列，不影响已有账号。
function ensureUserColumn(name, definition) {
  const columns = db.prepare('PRAGMA table_info(users)').all().map((column) => column.name);
  if (!columns.includes(name)) db.exec(`ALTER TABLE users ADD COLUMN ${name} ${definition}`);
}
ensureUserColumn('apple_subject', 'TEXT');
ensureUserColumn('apple_email', 'TEXT');
ensureUserColumn('display_name', 'TEXT');
db.exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_users_apple_subject ON users(apple_subject) WHERE apple_subject IS NOT NULL');

logger.info('db_ready', { path: config.databasePath });

module.exports = db;
