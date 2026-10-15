// Read-only audit probes: all database operations are replaced in memory.
// These assertions document observed defects; they are not acceptance tests.
const assert = require('node:assert/strict');
const path = require('node:path');
const { once } = require('node:events');
const backend = path.resolve(__dirname, '../../backend');
const fromBackend = file => require(path.join(backend, file));
const db = fromBackend('src/config/db');
const progress = fromBackend('src/services/gameProgressService');
const original = { query: db.query, getClient: db.getClient, award: progress.award };
const findings = [];
const observed = (id, details) => { findings.push({ id, details }); console.log(`${id}: ${details}`); };

(async () => {
  // Capture logging without any server or real database.
  let logValues;
  db.query = async (sql, values) => { logValues = values; return { rows: [] }; };
  let finish;
  const res = { statusCode: 200, json: body => body, send: body => body,
    on: (event, callback) => { if (event === 'finish') finish = callback; },
    getHeaders: () => ({}) };
  fromBackend('src/middleware/usageLog')({ method: 'POST', originalUrl: '/api/auth/otp/verify',
    headers: {}, body: { otp: 'AUDIT_OTP', refreshToken: 'AUDIT_REQUEST_REFRESH' },
    get: () => 'audit' }, res, () => {});
  res.json({ data: { accessToken: 'AUDIT_ACCESS', refreshToken: 'AUDIT_RESPONSE_REFRESH' } });
  finish();
  assert.match(logValues[5], /AUDIT_OTP/);
  assert.doesNotMatch(logValues[5], /AUDIT_REQUEST_REFRESH/);
  assert.doesNotMatch(logValues[10], /AUDIT_ACCESS/);
  assert.doesNotMatch(logValues[10], /AUDIT_RESPONSE_REFRESH/);
  observed('A01', 'Usage logs retain OTP in plaintext; access and refresh tokens are correctly masked.');

  // Prove two missing API paths on the actual application router.
  db.query = async () => ({ rows: [] });
  const env = fromBackend('src/config/env');
  const jwt = require(path.join(backend, 'node_modules/jsonwebtoken'));
  const token = jwt.sign({ sub: '00000000-0000-4000-8000-000000000001' }, env.jwt.accessSecret);
  const app = fromBackend('src/app');
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const replacement = await fetch(`${base}/api/programs/quests/week`, {
      method: 'PUT', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ weekStart: '2026-10-15', quests: [] }) });
    assert.equal(replacement.status, 404);
    observed('A02', 'The frontend schedule replacement URL returns HTTP 404.');
    const image = await fetch(`${base}/api/club-images/audit.png`);
    assert.equal(image.status, 401);
    const authenticatedImage = await fetch(`${base}/api/club-images/audit.png`, {
      headers: { Authorization: `Bearer ${token}` } });
    assert.equal(authenticatedImage.status, 404);
    observed('A03', 'The club image URL prefix returns HTTP 401 without auth and HTTP 404 with auth.');
  } finally { await new Promise(resolve => server.close(resolve)); }

  // State transitions and input validation in the real running service.
  let state = { status: 'completed', distance_km: 5 };
  db.query = async (sql, args) => {
    state = { status: sql.includes("status = 'abandoned'") ? 'abandoned' : 'completed', distance_km: args[2] };
    return { rows: [state] };
  };
  const running = fromBackend('src/services/runningService');
  await running.abandonSession('user', 'session', {});
  assert.equal(state.status, 'abandoned');
  await running.completeSession('user', 'session', { distanceKm: -100, durationSeconds: -1 });
  assert.equal(state.status, 'completed');
  assert.equal(state.distance_km, -100);
  observed('A04', 'Completed/abandoned sessions can be changed again; negative run metrics reach SQL.');

  // A unique reward event per RPE row does not deduplicate the same run.
  let rpeInserts = 0;
  let awards = 0;
  db.query = async () => ({ rows: [{ id: 'session' }] });
  db.getClient = async () => ({ release() {}, query: async sql => {
    if (sql.includes('INSERT INTO rpe_logs')) return { rows: [{ id: `rpe-${++rpeInserts}` }] };
    return { rows: [] };
  } });
  progress.award = async () => { awards++; return { awarded: true, coins: 5, exp: 5 }; };
  const rpe = fromBackend('src/services/rpeService');
  const feedback = { runningSessionId: 'session', durationMinutes: 30, rpeScore: 5,
    stressLevel: 5, mood: 'good', hasPain: false };
  await rpe.logRpe('user', feedback);
  await rpe.logRpe('user', feedback);
  assert.equal(rpeInserts, 2);
  assert.equal(awards, 2);
  observed('A05', 'Submitting feedback twice creates two RPE rows and two reward attempts for one run.');

  db.getClient = async () => ({ release() {}, query: async sql => {
    if (sql.includes('SELECT q.*')) return { rows: [{ id: 'quest', user_id: 'user',
      status: 'pending', running_session_id: null, target_count: 5, found_count: 0, coin_reward_base: 10 }] };
    if (sql.includes('UPDATE user_side_quest_instances')) return { rows: [{ id: 'quest', status: 'completed' }] };
    return { rows: [] };
  } });
  const before = awards;
  await fromBackend('src/services/sideQuestService').finishSideQuest('user', 'quest');
  assert.equal(awards, before + 1);
  observed('A06', 'A pending side quest with no running session can be finished and rewarded.');

  // Concurrent refresh requests both read the unrevoked row before either update.
  let reads = 0, inserts = 0, releaseReads;
  const gate = new Promise(resolve => { releaseReads = resolve; });
  db.query = async sql => {
    if (sql.includes('SELECT id, user_id, revoked')) {
      if (++reads === 2) releaseReads();
      await gate;
      return { rows: [{ id: 'refresh', user_id: 'user', revoked: false,
        expires_at: new Date(Date.now() + 60000) }] };
    }
    if (sql.includes('INSERT INTO refresh_tokens')) inserts++;
    return { rows: [] };
  };
  const tokens = fromBackend('src/services/tokenService');
  const rotated = await Promise.all([tokens.rotateRefreshToken('same-token'), tokens.rotateRefreshToken('same-token')]);
  assert.equal(rotated.filter(Boolean).length, 2);
  assert.equal(inserts, 2);
  observed('A07', 'Two concurrent rotations of the same refresh token both issue valid successors.');
  console.log(`Verified ${findings.length} audit observations; no real database queries or user mutations.`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  db.query = original.query; db.getClient = original.getClient; progress.award = original.award;
});
