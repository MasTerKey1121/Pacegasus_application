// Minimal duration parser, e.g. "15m", "30d", "1h" -> milliseconds
module.exports = function ms(value) {
  const match = /^(\d+)\s*(ms|s|m|h|d)$/.exec(String(value).trim());
  if (!match) return Number(value) || 0;
  const num = parseInt(match[1], 10);
  const unit = match[2];
  const table = { ms: 1, s: 1000, m: 60000, h: 3600000, d: 86400000 };
  return num * table[unit];
};
