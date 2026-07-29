/**
 * usageLogMiddleware.js
 * ---------------------------------------------------------
 * Middleware สำหรับบันทึก request/response ทุก API call
 * ลงตาราง usage_log ผ่าน pg Pool ที่มีอยู่แล้วในโปรเจค (config/db.js)
 *
 * วิธีใช้ (ใน app.js):
 *   const usageLogMiddleware = require('./middleware/usageLogMiddleware');
 *   app.use(usageLogMiddleware);   // ใส่หลัง body-parser, ก่อน routes
 * ---------------------------------------------------------
 */

const db = require('../config/db'); // ใช้ pool เดียวกับที่เหลือของโปรเจค

// ฟิลด์ที่ต้อง mask ไม่ให้หลุดลง log (เพิ่ม/ลดได้ตามระบบจริง)
const SENSITIVE_KEYS = [
  'password',
  'confirm_password',
  'access_token',
  'refresh_token',
  'authorization',
  'client_secret',
  'token',
];

/**
 * mask ค่าฟิลด์อ่อนไหวใน object แบบ recursive
 * ป้องกันไม่ให้ token/password หลุดเข้าไปใน DB log
 */
function sanitize(input) {
  if (!input || typeof input !== 'object') return input;

  const clone = Array.isArray(input) ? [...input] : { ...input };

  for (const key of Object.keys(clone)) {
    const lowerKey = key.toLowerCase();
    if (SENSITIVE_KEYS.some((k) => lowerKey.includes(k))) {
      clone[key] = '***';
    } else if (clone[key] && typeof clone[key] === 'object') {
      clone[key] = sanitize(clone[key]); // เผื่อ nested object เช่น { user: { password } }
    }
  }
  return clone;
}

/**
 * ตัด response body ที่ใหญ่เกินไปทิ้ง กัน JSONB บวมเกินจำเป็น
 */
function truncateBody(body, maxLength = 5000) {
  try {
    const str = JSON.stringify(body);
    if (str.length > maxLength) {
      return { truncated: true, preview: str.slice(0, maxLength) };
    }
    return body;
  } catch {
    return null; // เผื่อ body ไม่ใช่ JSON-serializable (เช่น stream/buffer)
  }
}

/**
 * insert 1 record ลง usage_log แบบไม่ throw ออกไปกระทบ request หลัก
 */
async function saveUsageLog(entry) {
  const sql = `
    INSERT INTO usage_log (
      user_id, method, api_url, endpoint_name,
      request_headers, request_body, request_ip, user_agent,
      response_status, response_headers, response_body,
      response_time_ms, error_message
    ) VALUES (
      $1, $2, $3, $4,
      $5, $6, $7, $8,
      $9, $10, $11,
      $12, $13
    )
  `;

  const values = [
    entry.user_id,
    entry.method,
    entry.api_url,
    entry.endpoint_name,
    JSON.stringify(entry.request_headers ?? null),
    JSON.stringify(entry.request_body ?? null),
    entry.request_ip,
    entry.user_agent,
    entry.response_status,
    JSON.stringify(entry.response_headers ?? null),
    JSON.stringify(entry.response_body ?? null),
    entry.response_time_ms,
    entry.error_message,
  ];

  try {
    await db.query(sql, values);
  } catch (err) {
    // ไม่ throw ต่อ กัน log พังแล้วกระทบ request จริงของผู้ใช้
    // eslint-disable-next-line no-console
    console.error('[usage_log] insert failed:', err.message);
  }
}

/**
 * Middleware หลัก
 */
function usageLogMiddleware(req, res, next) {
  const startTime = Date.now();

  // ห่อ res.json และ res.send เพื่อดักจับ response body ก่อนส่งออกจริง
  const originalJson = res.json.bind(res);
  const originalSend = res.send.bind(res);
  let capturedBody;

  res.json = (body) => {
    capturedBody = body;
    return originalJson(body);
  };

  res.send = (body) => {
    if (capturedBody === undefined) capturedBody = body;
    return originalSend(body);
  };

  // ทำงานหลัง response ถูกส่งออกไปแล้วเท่านั้น (ไม่หน่วง response จริง)
  res.on('finish', () => {
    const entry = {
      user_id: req.user?.id ?? null, // ต้องผ่าน requireAuth มาก่อนถึงจะมีค่า
      method: req.method,
      api_url: req.originalUrl,
      endpoint_name: req.route?.path ?? req.baseUrl ?? null,
      request_headers: sanitize(req.headers),
      request_body: sanitize(req.body),
      request_ip: req.ip,
      user_agent: req.headers['user-agent'] ?? null,
      response_status: res.statusCode,
      response_headers: sanitize(res.getHeaders()),
      response_body: truncateBody(sanitize(capturedBody)),
      response_time_ms: Date.now() - startTime,
      error_message: res.statusCode >= 400 ? capturedBody?.message ?? null : null,
    };

    // fire-and-forget: ไม่ await เพื่อไม่ให้กระทบ latency ของ endpoint จริง
    saveUsageLog(entry);
  });

  next();
}

module.exports = usageLogMiddleware;