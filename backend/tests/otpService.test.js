const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/db');
const supabaseOtpService = require('../src/services/supabaseOtpService');
const otpService = require('../src/services/otpService');

function mockDependencies(t, query, sendOtp, verifyOtp) {
  const originals = {
    query: db.query,
    sendOtp: supabaseOtpService.sendOtp,
    verifyOtp: supabaseOtpService.verifyOtp,
  };
  db.query = query;
  supabaseOtpService.sendOtp = sendOtp || (async () => {});
  supabaseOtpService.verifyOtp = verifyOtp || (async () => {});
  t.after(() => {
    db.query = originals.query;
    supabaseOtpService.sendOtp = originals.sendOtp;
    supabaseOtpService.verifyOtp = originals.verifyOtp;
  });
}

test('request stores a reference and asks Supabase to send OTP', async (t) => {
  const queries = [];
  const emails = [];
  mockDependencies(t, async (sql, params) => {
    queries.push({ sql, params });
    if (sql.includes('SELECT created_at')) return { rows: [] };
    if (sql.includes('RETURNING id')) return { rows: [{ id: 'otp-1' }] };
    return { rows: [] };
  }, async (email) => emails.push(email));

  const result = await otpService.requestOtp('runner@example.com', 'register');
  assert.deepEqual(emails, ['runner@example.com']);
  assert.match(result.otpRef, /^[A-Z2-9]{6}$/);
  assert.equal(queries[1].params[2], result.otpRef);
  assert.equal(queries[1].params[3], 'register');
  assert.match(queries[2].sql, /id <> \$2/);
});

test('failed delivery removes the local request so the user can retry', async (t) => {
  const queries = [];
  mockDependencies(t, async (sql, params) => {
    queries.push({ sql, params });
    if (sql.includes('SELECT created_at')) return { rows: [] };
    if (sql.includes('RETURNING id')) return { rows: [{ id: 'otp-2' }] };
    return { rows: [] };
  }, async () => { throw new Error('delivery failed'); });

  await assert.rejects(otpService.requestOtp('runner@example.com'), /delivery failed/);
  assert.match(queries.at(-1).sql, /DELETE FROM otp_codes WHERE id = \$1/);
  assert.deepEqual(queries.at(-1).params, ['otp-2']);
});

test('verify delegates the code to Supabase and consumes the local reference', async (t) => {
  const queries = [];
  const verified = [];
  mockDependencies(t, async (sql, params) => {
    queries.push({ sql, params });
    if (sql.includes('SELECT id, attempts')) {
      return { rows: [{ id: 'otp-3', attempts: 0, max_attempts: 5, expires_at: new Date(Date.now() + 60000) }] };
    }
    return { rows: [] };
  }, undefined, async (email, code) => verified.push({ email, code }));

  await otpService.verifyOtp('runner@example.com', '123456', 'ABC234');
  assert.deepEqual(verified, [{ email: 'runner@example.com', code: '123456' }]);
  assert.match(queries.at(-1).sql, /SET is_used = TRUE WHERE id = \$1/);
});

test('wrong code counts as a failed attempt', async (t) => {
  const queries = [];
  mockDependencies(t, async (sql, params) => {
    queries.push({ sql, params });
    if (sql.includes('SELECT id, attempts')) {
      return { rows: [{ id: 'otp-4', attempts: 0, max_attempts: 5, expires_at: new Date(Date.now() + 60000) }] };
    }
    return { rows: [] };
  }, undefined, async () => { throw { statusCode: 400 }; });

  await assert.rejects(otpService.verifyOtp('runner@example.com', '000000', 'ABC234'), { statusCode: 400 });
  assert.match(queries.at(-1).sql, /SET attempts = attempts \+ 1/);
});
