const test = require('node:test');
const assert = require('node:assert/strict');

const db = require('../src/config/db');
const profileService = require('../src/services/profileService');

const ME = '11111111-1111-4111-8111-111111111111';
const OTHER = '22222222-2222-4222-8222-222222222222';

function mockDb(t, { target, friends }) {
  const original = db.query;
  t.after(() => { db.query = original; });
  db.query = async (sql) => {
    if (/FROM users u/.test(sql)) return { rows: target ? [target] : [] };
    if (/FROM friendships/.test(sql)) return { rows: friends ? [{ '?column?': 1 }] : [] };
    if (/FROM user_avatars/.test(sql) || /FROM user_avatar_equipment/.test(sql)) return { rows: [] };
    if (/FROM club_members/.test(sql)) return { rows: [{ id: 'c1', name: 'Club', image_url: null, member_count: 3, max_members: 20, role: 'member' }] };
    if (/FROM running_sessions/.test(sql)) return { rows: [{ total_km: 12.345, runs: 4 }] };
    throw new Error(`unexpected query: ${sql}`);
  };
}

const TARGET = { id: OTHER, uid: 'ABCDE23456', display_name: 'Runner', avatar_url: null, level: 5 };

test('friend can view profile with club, avatar and total distance', async (t) => {
  mockDb(t, { target: TARGET, friends: true });
  const p = await profileService.getProfileByUid(ME, 'ABCDE23456');
  assert.equal(p.user.uid, 'ABCDE23456');
  assert.equal(p.user.displayName, 'Runner');
  assert.equal(p.club.name, 'Club');
  assert.equal(p.stats.totalDistanceKm, 12.35);
  assert.equal(p.relationship, 'friend');
  assert.deepEqual(p.avatar.equipment, []);
});

test('non-friend can still view profile', async (t) => {
  mockDb(t, { target: TARGET, friends: false });
  const p = await profileService.getProfileByUid(ME, 'ABCDE23456');
  assert.equal(p.relationship, 'none');
  assert.equal(p.user.displayName, 'Runner');
});

test('unknown uid gets 404', async (t) => {
  mockDb(t, { target: null, friends: false });
  await assert.rejects(profileService.getProfileByUid(ME, 'ABCDE23456'), { statusCode: 404 });
});

test('own profile does not need friendship', async (t) => {
  mockDb(t, { target: { ...TARGET, id: ME }, friends: false });
  assert.equal((await profileService.getProfileByUid(ME, 'ABCDE23456')).relationship, 'self');
});
