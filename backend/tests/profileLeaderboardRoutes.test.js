const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const db = require('../src/config/db');
const env = require('../src/config/env');
const profile = require('../src/services/ownProfileService');
const leaderboard = require('../src/services/leaderboardService');

// Exercise the production app's complete route registration without real users,
// database writes, or credentials from a running deployment.
test('production app mounts profile and leaderboard endpoints', async (t) => {
  const originalSecret = env.jwt.accessSecret;
  env.jwt.accessSecret = 'route-smoke-test-only';
  t.after(() => { env.jwt.accessSecret = originalSecret; });
  t.mock.method(db, 'query', async (sql) => {
    assert.match(sql, /INSERT INTO usage_log/);
    return { rows: [] };
  });
  const user = { uid: 'ABCDE23456', displayName: 'Runner', avatarUrl: null };
  t.mock.method(profile, 'get', async (id) => {
    assert.equal(id, 'route-test-user');
    return { user, club: null, stats: { totalRuns: 0 } };
  });
  t.mock.method(profile, 'update', async (id, changes) => {
    assert.equal(id, 'route-test-user');
    assert.deepEqual(changes, { displayName: 'Updated Runner' });
    return { user: { ...user, ...changes } };
  });
  t.mock.method(leaderboard, 'weeklyDistance', async (id, scope) => {
    assert.equal(id, 'route-test-user');
    return { scope, entries: [], myEntry: null };
  });
  const app = require('../src/app');
  const server = app.listen(0, '127.0.0.1');
  t.after(() => new Promise((resolve) => server.close(resolve)));
  await new Promise((resolve) => server.once('listening', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const headers = {
    Authorization: `Bearer ${jwt.sign({}, env.jwt.accessSecret, { subject: 'route-test-user' })}`,
    'Content-Type': 'application/json',
  };
  await t.test('GET profile reaches authenticated profile service', async () => {
    const response = await fetch(`${origin}/api/users/me/profile`, { headers });
    assert.equal(response.status, 200);
    assert.deepEqual((await response.json()).data.user, user);
  });
  await t.test('PATCH profile reaches authenticated update service', async () => {
    const response = await fetch(`${origin}/api/users/me/profile`, {
      method: 'PATCH', headers, body: JSON.stringify({ displayName: 'Updated Runner' }),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).data.user.displayName, 'Updated Runner');
  });
  for (const scope of ['individual', 'guild']) {
    await t.test(`GET leaderboard supports ${scope}`, async () => {
      const response = await fetch(`${origin}/api/leaderboard?scope=${scope}`, { headers });
      assert.equal(response.status, 200);
      assert.equal((await response.json()).data.scope, scope);
    });
  }
  await t.test('both endpoints require authentication', async () => {
    for (const route of ['/api/users/me/profile', '/api/leaderboard?scope=individual']) {
      assert.equal((await fetch(`${origin}${route}`)).status, 401);
    }
  });
});
