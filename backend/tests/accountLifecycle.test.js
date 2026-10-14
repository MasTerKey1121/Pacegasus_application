const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/db');
const otp = require('../src/services/otpService');
const tokens = require('../src/services/tokenService');
const jwt = require('jsonwebtoken');
const google = require('../src/services/googleAuthService');
const deletion = require('../src/services/accountDeletionService');
const auth = require('../src/controllers/authController');
const { requireAuth } = require('../src/middleware/auth');

function invoke(handler, body) {
  return new Promise((resolve, reject) => handler(
    { body, headers: {}, ip: '127.0.0.1', user: { id: 'old-user' } },
    { status(code) { this.code = code; return this; }, json(result) { resolve({ code: this.code, ...result }); } },
    reject,
  ));
}

function store(t, { empty = false } = {}) {
  let user = empty ? null : { id: 'old-user', email: 'runner@example.com', status: 'active', email_verified: true, policy_accepted: false };
  let generation = 0;
  const queries = [];
  const query = async (sql, params) => {
    queries.push({ sql, params });
    if (sql.startsWith('SELECT')) return { rows: user ? [user] : [] };
    if (sql.startsWith('DELETE FROM users')) user = null;
    if (sql.includes('INSERT INTO users')) {
      generation++;
      user = { id: generation === 1 ? 'new-user' : `new-user-${generation}`, email: params[0], status: 'active', email_verified: params[1], policy_accepted: params[4], policy_accepted_at: params[5], policy_version: params[6], onboarding_completed: false };
      return { rows: [user] };
    }
    if (sql.includes('SET policy_accepted = TRUE')) {
      user = { ...user, policy_accepted: true, policy_accepted_at: new Date(), policy_version: params[1] };
      return { rows: [user] };
    }
    return { rows: [] };
  };
  t.mock.method(db, 'query', query);
  const client = { query, release() {} };
  t.mock.method(db, 'getClient', async () => client);
  t.mock.method(otp, 'requestOtp', async () => ({ otpRef: 'ABC123', expiresInMinutes: 5 }));
  return { queries, client, get user() { return user; } };
}

test('delete removes the account, identity, sessions and OTPs; same email registers as a fresh user', async (t) => {
  const state = store(t);
  await deletion.deleteAccount('old-user');
  assert.equal(state.user, null);
  assert.ok(state.queries.some(({ sql }) => sql.startsWith('DELETE FROM otp_codes')));
  assert.ok(state.queries.some(({ sql }) => sql.startsWith('DELETE FROM refresh_tokens')));
  assert.ok(state.queries.some(({ sql }) => sql.startsWith('DELETE FROM user_auth_providers')));
  assert.equal(state.queries.at(-1).sql, 'COMMIT');
  const check = await invoke(auth.checkRegistration, { email: ' Runner@Example.com ' });
  assert.equal(check.data.available, true);
  await invoke(auth.requestOtp, { email: 'runner@example.com', purpose: 'register', policyAccepted: true, policyVersion: '2026-07' });
  assert.equal(state.user.id, 'new-user');
  assert.equal(state.user.onboarding_completed, false);
});

test('verified email is rejected before consent and again when requesting registration OTP', async (t) => {
  store(t);
  await assert.rejects(invoke(auth.checkRegistration, { email: 'runner@example.com' }), { statusCode: 409 });
  await assert.rejects(invoke(auth.requestOtp, { email: 'runner@example.com', purpose: 'register', policyAccepted: true, policyVersion: '2026-07' }), { statusCode: 409 });
  assert.equal(otp.requestOtp.mock.callCount(), 0);
});

test('login allows identity verification when consent has not been accepted', async (t) => {
  store(t);
  t.mock.method(otp, 'verifyOtp', async () => true);
  t.mock.method(tokens, 'signAccessToken', () => 'access');
  t.mock.method(tokens, 'issueRefreshToken', async () => 'refresh');
  await invoke(auth.requestOtp, { email: 'runner@example.com', purpose: 'login' });
  const result = await invoke(auth.verifyOtp, { email: 'runner@example.com', otp: '123456', otpRef: 'ABC123' });
  assert.equal(result.data.user.policyAccepted, false);
  assert.equal(result.data.accessToken, 'access');
});

test('deletion rolls back and releases the connection if removing related data fails', async (t) => {
  const state = store(t);
  const originalQuery = state.client.query;
  t.mock.method(state.client, 'query', async (sql, params) => {
    if (sql.startsWith('DELETE FROM refresh_tokens')) throw new Error('database failure');
    return originalQuery(sql, params);
  });
  t.mock.method(state.client, 'release');
  await assert.rejects(deletion.deleteAccount('old-user'), /database failure/);
  assert.equal(state.queries.at(-1).sql, 'ROLLBACK');
  assert.equal(state.client.release.mock.callCount(), 1);
  assert.equal(state.user.id, 'old-user');
});

test('old access tokens cannot authorize a deleted account', async (t) => {
  const state = store(t);
  await deletion.deleteAccount('old-user');
  t.mock.method(jwt, 'verify', () => ({ sub: 'old-user' }));
  const error = await new Promise((resolve) => requireAuth(
    { headers: { authorization: 'Bearer old-token' } }, {}, resolve,
  ));
  assert.equal(error.statusCode, 401);
});

test('legacy deleted account with unchanged email is removed before registration', async (t) => {
  const state = store(t);
  state.user.status = 'deleted';
  const result = await invoke(auth.checkRegistration, { email: 'runner@example.com' });
  assert.equal(result.data.available, true);
  assert.equal(state.user, null);
});

function googleIdentity(t) {
  t.mock.method(google, 'verifyGoogleIdToken', async () => ({
    googleId: 'same-google-identity', email: 'runner@example.com',
    emailVerified: true, displayName: 'Runner', avatarUrl: null,
  }));
  t.mock.method(tokens, 'signAccessToken', (user) => `access-${user.id}`);
  t.mock.method(tokens, 'issueRefreshToken', async (id) => `refresh-${id}`);
}

test('Google registration -> consent -> delete -> same Google identity registers a fresh account', async (t) => {
  const state = store(t, { empty: true });
  googleIdentity(t);
  const first = await invoke(auth.googleAuth, { idToken: 'google-token' });
  assert.equal(first.code, 200);
  assert.equal(first.data.user.policyAccepted, false);
  assert.equal(first.data.user.emailVerified, true);
  assert.equal(first.data.user.onboardingCompleted, false);

  // invoke() supplies old-user by default; use the actual identity for consent.
  await new Promise((resolve, reject) => auth.acceptPolicy(
    { body: { policyVersion: '2026-07' }, user: { id: first.data.user.id } },
    { status() { return this; }, json: resolve }, reject,
  ));
  assert.equal(state.user.policy_accepted, true);
  state.user.onboarding_completed = true;
  await deletion.deleteAccount(first.data.user.id);
  assert.equal(state.user, null);

  const second = await invoke(auth.googleAuth, { idToken: 'google-token' });
  assert.equal(second.code, 200);
  assert.notEqual(second.data.user.id, first.data.user.id);
  assert.equal(second.data.user.email, first.data.user.email);
  assert.equal(second.data.user.policyAccepted, false);
  assert.equal(second.data.user.policyAcceptedAt, null);
  assert.equal(second.data.user.policyVersion, null);
  assert.equal(second.data.user.onboardingCompleted, false);
  assert.notEqual(second.data.accessToken, first.data.accessToken);
  assert.notEqual(second.data.refreshToken, first.data.refreshToken);
  const links = state.queries.filter(({ sql }) => sql.includes('INSERT INTO user_auth_providers'));
  assert.deepEqual(links.map(({ params }) => params), [
    [first.data.user.id, 'google', 'same-google-identity'],
    [second.data.user.id, 'google', 'same-google-identity'],
  ]);
  assert.ok(state.queries.some(({ sql, params }) => sql.startsWith('DELETE FROM user_auth_providers') && params[0] === first.data.user.id));
  assert.ok(state.queries.some(({ sql, params }) => sql.startsWith('DELETE FROM refresh_tokens') && params[0] === first.data.user.id));
  assert.equal(otp.requestOtp.mock.callCount(), 0);
});

test('deleted Google account can register again with email OTP using the same email', async (t) => {
  const state = store(t, { empty: true });
  googleIdentity(t);
  const first = await invoke(auth.googleAuth, { idToken: 'google-token' });
  await deletion.deleteAccount(first.data.user.id);
  await invoke(auth.checkRegistration, { email: first.data.user.email });
  await invoke(auth.requestOtp, { email: first.data.user.email, purpose: 'register', policyAccepted: true, policyVersion: '2026-07' });
  assert.notEqual(state.user.id, first.data.user.id);
  assert.equal(state.user.email, first.data.user.email);
  assert.equal(state.user.onboarding_completed, false);
  assert.equal(otp.requestOtp.mock.callCount(), 1);
});
