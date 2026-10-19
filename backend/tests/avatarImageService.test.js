const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/db');
const avatars = require('../src/services/avatarImageService');

const png = Buffer.concat([
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  Buffer.from([0, 0, 0, 13]), Buffer.from('IHDR'),
  Buffer.from([0, 0, 0, 1, 0, 0, 0, 1]),
]);

test('avatar replacement stores image and profile URL in one transaction', async (t) => {
  const original = db.getClient;
  t.after(() => { db.getClient = original; });
  const calls = [];
  db.getClient = async () => ({
    query: async (sql, args) => {
      calls.push({ sql, args });
      if (sql.startsWith('UPDATE users')) {
        return { rows: [{ id: 'user-1', avatar_url: args[1] }] };
      }
      return { rows: [] };
    },
    release: () => calls.push({ sql: 'RELEASE' }),
  });
  const user = await avatars.saveAvatar('user-1', { mimetype: 'image/png', buffer: png }, 'https://api.example.test');
  assert.match(user.avatarUrl, /^https:\/\/api\.example\.test\/api\/user-avatars\/[0-9a-f-]{36}$/);
  assert.deepEqual(calls.map((call) => call.sql.split(' ')[0]),
    ['BEGIN', 'UPDATE', 'INSERT', 'COMMIT', 'RELEASE']);
  assert.equal(calls[2].args[0], user.avatarUrl.split('/').at(-1));
  assert.deepEqual(calls[2].args[3], png);
});

test('avatar upload rejects a MIME mismatch before database access', async () => {
  assert.throws(() => avatars.validateImage({ mimetype: 'image/jpeg', buffer: png }),
    { statusCode: 400 });
});
