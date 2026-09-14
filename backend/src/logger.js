// =====================================================================
// 极简日志：输出一行一个 JSON，方便日后用命令行或日志系统筛选。
// 规则：
//   - 每条日志带时间戳、级别、事件名；
//   - 绝不打印完整收据、密码、密钥；需要出现时用 mask() 打码。
// =====================================================================
const config = require('./config');

const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const currentLevel = LEVELS[config.logLevel] ?? LEVELS.info;

function write(level, event, extra) {
  if (LEVELS[level] < currentLevel) return;
  const line = JSON.stringify({
    ts: new Date().toISOString(),
    level,
    event,
    ...(extra || {}),
  });
  if (level === 'error') console.error(line);
  else console.log(line);
}

module.exports = {
  debug: (event, extra) => write('debug', event, extra),
  info: (event, extra) => write('info', event, extra),
  warn: (event, extra) => write('warn', event, extra),
  error: (event, extra) => write('error', event, extra),

  // 把敏感字符串打码：只保留前几位用于比对
  mask(value) {
    if (value === undefined || value === null) return '';
    const s = String(value);
    if (s.length <= 8) return '***';
    return `${s.slice(0, 6)}...(len=${s.length})`;
  },
};
