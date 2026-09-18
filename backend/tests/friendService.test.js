const test = require('node:test');
const assert = require('node:assert/strict');

const db = require('../src/config/db');
const friendService = require('../src/services/friendService');
const { serializeUser } = require('../src/controllers/authController');
const { sendFriendRequestSchema, friendRequestFiltersSchema } = require('../src/utils/friendValidators');

const ME = '11111111-1111-4111-8111-111111111111';
const OTHER = '22222222-2222-4222-8222-222222222222';
const TARGET_ROW = { user_id: OTHER, uid: 'ABCDE23456', display_name: 'Runner', avatar_url: null, level: 3 };

// Replaces db.query (user lookup) and db.getClient (transaction) for one test.
function mockDb(t, { target = TARGET_ROW, existing = null, onWrite } = {}) {
  const originalQuery = db.query;
  const originalGetClient = db.getClient;
  const statements = [];
  t.after(() => { db.query = originalQuery; db.getClient = originalGetClient; });

  db.query = async (sql) => {
    assert.match(sql, /FROM users u/);
    return { rows: target ? [target] : [] };
  };
  db.getClient = async () => ({
    query: async (sql, params) => {
      statements.push(sql.trim().split(/\s+/)[0]);
      if (sql.includes('FOR UPDATE')) return { rows: existing ? [existing] : [] };
      if (/^(INSERT|UPDATE)/.test(sql.trim())) return { rows: [onWrite(sql, params)] };
      return { rows: [] };
    },
    release: () => {},
  });
  return statements;
}

test('uid is normalised and validated', () => {
  assert.equal(sendFriendRequestSchema.validate({ uid: ' abcde23456 ' }).value.uid, 'ABCDE23456');
  assert.ok(sendFriendRequestSchema.validate({ uid: 'ABCDE2345O' }).error, 'O is not in the alphabet');
  assert.ok(sendFriendRequestSchema.validate({}).error);
  assert.equal(friendRequestFiltersSchema.validate({}).value.direction, 'incoming');
});

test('profile serialisation exposes uid', () => {
  assert.equal(serializeUser({ id: ME, uid: 'ABCDE23456' }).uid, 'ABCDE23456');
});

test('sending a request creates a pending friendship', async (t) => {
  const statements = mockDb(t, {
    onWrite: (sql, params) => {
      assert.match(sql, /INSERT INTO friendships/);
      assert.deepEqual(params, [ME, OTHER]);
      return { id: 'f-1', requester_id: ME, addressee_id: OTHER, status: 'pending', created_at: 'now', responded_at: null };
    },
  });

  const result = await friendService.sendFriendRequest(ME, 'ABCDE23456');

  assert.deepEqual(statements, ['BEGIN', 'SELECT', 'INSERT', 'COMMIT']);
  assert.equal(result.status, 'pending');
  assert.equal(result.direction, 'outgoing');
  assert.equal(result.autoAccepted, false);
  assert.equal(result.user.uid, 'ABCDE23456');
});

test('adding someone who already sent you a request accepts it', async (t) => {
  const existing = { id: 'f-1', requester_id: OTHER, addressee_id: ME, status: 'pending' };
  mockDb(t, {
    existing,
    onWrite: (sql) => {
      assert.match(sql, /UPDATE friendships SET status = 'accepted'/);
      return { ...existing, status: 'accepted', responded_at: 'now' };
    },
  });

  const result = await friendService.sendFriendRequest(ME, 'ABCDE23456');

  assert.equal(result.status, 'accepted');
  assert.equal(result.autoAccepted, true);
});

test('duplicate, already-friend, self and unknown uid requests are rejected', async (t) => {
  await t.test('pending request already sent', async (st) => {
    const statements = mockDb(st, { existing: { id: 'f-1', requester_id: ME, addressee_id: OTHER, status: 'pending' } });
    await assert.rejects(friendService.sendFriendRequest(ME, 'ABCDE23456'), { statusCode: 409 });
    assert.equal(statements.at(-1), 'ROLLBACK');
  });
  await t.test('already friends', async (st) => {
    mockDb(st, { existing: { id: 'f-1', requester_id: OTHER, addressee_id: ME, status: 'accepted' } });
    await assert.rejects(friendService.sendFriendRequest(ME, 'ABCDE23456'), { statusCode: 409 });
  });
  await t.test('concurrent reverse request hits the pair unique index', async (st) => {
    mockDb(st, { onWrite: () => { throw Object.assign(new Error('duplicate'), { code: '23505' }); } });
    await assert.rejects(friendService.sendFriendRequest(ME, 'ABCDE23456'), { statusCode: 409 });
  });
  await t.test('self', async (st) => {
    mockDb(st, { target: { ...TARGET_ROW, user_id: ME } });
    await assert.rejects(friendService.sendFriendRequest(ME, 'ABCDE23456'), { statusCode: 400 });
  });
  await t.test('unknown uid', async (st) => {
    mockDb(st, { target: null });
    await assert.rejects(friendService.sendFriendRequest(ME, 'ABCDE23456'), { statusCode: 404 });
  });
});

test('only the addressee can accept a pending request', async (t) => {
  const originalQuery = db.query;
  t.after(() => { db.query = originalQuery; });

  db.query = async (sql, params) => {
    assert.match(sql, /f\.addressee_id = \$2 AND f\.status = 'pending'/);
    assert.deepEqual(params, ['f-1', ME]);
    return { rows: [] };
  };

  await assert.rejects(friendService.acceptFriendRequest(ME, 'f-1'), { statusCode: 404 });
});

test('deleting a pending request reports declined or cancelled by role', async (t) => {
  const originalQuery = db.query;
  t.after(() => { db.query = originalQuery; });

  db.query = async (sql, params) => {
    assert.match(sql, /DELETE FROM friendships/);
    assert.equal(params[2], 'pending');
    return { rows: [{ id: 'f-1', requester_id: OTHER, addressee_id: ME }] };
  };
  assert.equal((await friendService.removeFriendRequest(ME, 'f-1')).action, 'declined');
  assert.equal((await friendService.removeFriendRequest(OTHER, 'f-1')).action, 'cancelled');
});

test('friend list returns the other user of each accepted friendship', async (t) => {
  const originalQuery = db.query;
  t.after(() => { db.query = originalQuery; });

  db.query = async (sql, params) => {
    assert.match(sql, /f\.status = 'accepted'/);
    assert.deepEqual(params, [ME, 50, 0]);
    return { rows: [{ id: 'f-1', requester_id: ME, addressee_id: OTHER, status: 'accepted', ...TARGET_ROW }] };
  };

  const [friend] = await friendService.listFriends(ME, { limit: 50, offset: 0 });
  assert.equal(friend.friendshipId, 'f-1');
  assert.deepEqual(friend.user, { id: OTHER, uid: 'ABCDE23456', displayName: 'Runner', avatarUrl: null, level: 3 });
});
