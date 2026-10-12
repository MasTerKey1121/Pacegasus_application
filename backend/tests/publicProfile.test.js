const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/db');
const friends = require('../src/services/friendService');
const avatars = require('../src/services/avatarService');
const { getProfile } = require('../src/services/publicProfileService');

test('public profile exposes only public data and grants management only to same club leader', async (t) => {
  const original = [db.query, friends.lookupByUid, avatars.getAvatarByUid];
  t.after(() => { [db.query, friends.lookupByUid, avatars.getAvatarByUid] = original; });
  let viewerRole = 'leader', targetRole = 'member';
  db.query = async (sql, args) => {
    if (sql.includes('FROM users')) return { rows: [{ uid: 'ABCDE23456' }] };
    if (sql.includes('FROM club_members')) {
      assert.deepEqual(args, ['target', 'viewer']);
      return { rows: [{ id: 'club', name: 'Club', role: targetRole, viewer_role: viewerRole }] };
    }
    assert.match(sql, /status = 'completed'/);
    return { rows: [{ distance: '123.45' }] };
  };
  friends.lookupByUid = async () => ({ user: { id: 'target', uid: 'ABCDE23456' }, relationship: { status: 'none' } });
  avatars.getAvatarByUid = async () => ({ equipment: [] });
  assert.equal((await getProfile('viewer', 'ABCDE23456')).canManageMember, true);
  viewerRole = 'member';
  assert.equal((await getProfile('viewer', 'ABCDE23456')).canManageMember, false);
  viewerRole = null;
  assert.equal((await getProfile('viewer', 'ABCDE23456')).canManageMember, false);
  viewerRole = 'leader'; targetRole = 'leader';
  const profile = await getProfile('viewer', 'ABCDE23456');
  assert.equal(profile.canManageMember, false);
  assert.equal(profile.distanceKm, 123.45);
  assert.deepEqual(profile.club, { id: 'club', name: 'Club', role: 'leader' });
  assert.equal(profile.club.viewer_role, undefined);
  await assert.rejects(getProfile('viewer', 'invalid'), { statusCode: 400 });
});
