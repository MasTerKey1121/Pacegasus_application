const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/db');
const service = require('../src/services/ownProfileService');
test('name update targets only authenticated user and uses existing columns', async (t) => {
  const original = db.query;
  t.after(() => { db.query = original; });
  db.query = async (sql, args) => {
    assert.deepEqual(args, ['me', 'นักวิ่ง']);
    assert.match(sql, /WHERE id = \$1 AND status = 'active'/);
    assert.doesNotMatch(sql, /description/);
    return { rows: [{ uid: 'ABCDE23456', display_name: args[1], avatar_url: null }] };
  };
  assert.equal((await service.update('me', { displayName: ' นักวิ่ง ' })).user.displayName, 'นักวิ่ง');
  for (const input of [{}, undefined, { displayName: ' ' }, { description: 'bio' }, { displayName: 'Name', uid: 'OTHER' }]) {
    await assert.rejects(service.update('me', input), { statusCode: 400 });
  }
});
test('profile summary has no description dependency and correct weekly boundary', async (t) => {
  const original = db.query;
  t.after(() => { db.query = original; });
  db.query = async (sql, args) => {
    assert.deepEqual(args, ['me']);
    assert.match(sql, /status = 'completed'/);
    assert.match(sql, /date_trunc\('week', now\(\) AT TIME ZONE 'Asia\/Bangkok'\)/);
    assert.doesNotMatch(sql, /profile_description/);
    return { rows: [{ uid: 'ABCDE23456', display_name: 'Runner', club: null,
      total_km: '128.4', total_runs: '18', week_km: '24.8', week_runs: '3' }] };
  };
  const result = await service.get('me');
  assert.equal(result.club, null);
  assert.deepEqual(result.stats, { totalDistanceKm: 128.4, totalRuns: 18, weeklyDistanceKm: 24.8, weeklyRuns: 3 });
});
