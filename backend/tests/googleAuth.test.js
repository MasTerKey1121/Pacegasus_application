const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/db');
const google = require('../src/services/googleAuthService');
const tokens = require('../src/services/tokenService');
const { googleAuth } = require('../src/controllers/authController');

const profile = { googleId: 'google-1', email: 'runner@example.com', emailVerified: true, displayName: 'Runner', avatarUrl: 'https://example.com/avatar.png' };
const existing = { id: 'user-1', email: profile.email, email_verified: true, avatar_url: profile.avatarUrl, status: 'active', policy_accepted: true, onboarding_completed: true };

function setup(t, user = null) {
  const queries = [];
  t.mock.method(google, 'verifyGoogleIdToken', async (token) => {
    assert.equal(token, 'google-id-token');
    return profile;
  });
  t.mock.method(tokens, 'signAccessToken', () => 'access-token');
  t.mock.method(tokens, 'issueRefreshToken', async () => 'refresh-token');
  t.mock.method(db, 'query', async (sql, params) => {
    queries.push({ sql, params });
    if (sql.includes('SELECT * FROM users WHERE email')) return { rows: user ? [user] : [] };
    if (sql.includes('INSERT INTO users')) return { rows: [{ ...existing, policy_accepted: params[4], policy_accepted_at: params[5], policy_version: params[6], onboarding_completed: false }] };
    return { rows: [] };
  });
  return queries;
}

function invoke(body = { idToken: 'google-id-token' }) {
  return new Promise((resolve, reject) => {
    const res = { status(code) { this.code = code; return this; }, json(data) { resolve({ code: this.code, ...data }); } };
    googleAuth({ body, headers: {}, ip: '127.0.0.1' }, res, reject);
  });
}

test('Google registration issues session without assuming policy consent', async (t) => {
  const queries = setup(t);
  const res = await invoke();
  assert.equal(res.code, 200);
  assert.equal(res.data.user.policyAccepted, false);
  assert.equal(res.data.user.policyAcceptedAt, null);
  assert.equal(res.data.user.onboardingCompleted, false);
  assert.equal(res.data.accessToken, 'access-token');
  assert.equal(res.data.refreshToken, 'refresh-token');
  assert.ok(queries.some(({ sql, params }) => sql.includes('user_auth_providers') && params[2] === profile.googleId));
});

test('Google login reuses an existing account', async (t) => {
  const queries = setup(t, existing);
  const res = await invoke();
  assert.equal(res.data.user.id, existing.id);
  assert.equal(res.data.user.policyAccepted, true);
  assert.equal(queries.filter(({ sql }) => sql.includes('INSERT INTO users')).length, 0);
});

test('disabled account cannot log in with Google', async (t) => {
  setup(t, { ...existing, status: 'disabled' });
  await assert.rejects(invoke(), { statusCode: 403 });
  assert.equal(tokens.issueRefreshToken.mock.callCount(), 0);
});

test('invalid Google token creates no user or session', async (t) => {
  const queries = setup(t);
  t.mock.method(google, 'verifyGoogleIdToken', async () => { throw Object.assign(new Error('invalid token'), { statusCode: 401 }); });
  await assert.rejects(invoke(), { statusCode: 401 });
  assert.equal(queries.length, 0);
  assert.equal(tokens.issueRefreshToken.mock.callCount(), 0);
});
