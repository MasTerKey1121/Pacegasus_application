const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const db = require('../src/config/db');
const env = require('../src/config/env');
const app = require('../src/app');

const png = Buffer.concat([
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  Buffer.from([0, 0, 0, 13]), Buffer.from('IHDR'),
  Buffer.from([0, 0, 0, 1, 0, 0, 0, 1]),
]);

test('club and profile image uploads return URLs that serve the stored bytes', async (t) => {
  const originalQuery = db.query;
  const originalGetClient = db.getClient;
  const originalNodeEnv = env.nodeEnv;
  const originalSecret = env.jwt.accessSecret;
  env.nodeEnv = 'production';
  env.jwt.accessSecret = 'image-route-test-secret';
  t.after(() => {
    db.query = originalQuery;
    db.getClient = originalGetClient;
    env.nodeEnv = originalNodeEnv;
    env.jwt.accessSecret = originalSecret;
  });

  const clubImages = new Map();
  const avatars = new Map();
  let userAvatarUrl = null;
  db.query = async (sql, args) => {
    if (sql.includes('INSERT INTO usage_log')) return { rows: [] };
    if (sql.startsWith('INSERT INTO club_images')) {
      clubImages.set(args[0], { content_type: args[1], image_data: args[2] });
      return { rows: [] };
    }
    if (sql.includes('FROM club_images')) return { rows: [clubImages.get(args[0])].filter(Boolean) };
    if (sql.includes('FROM avatar_images')) return { rows: [avatars.get(args[0])].filter(Boolean) };
    if (sql.includes('FROM users')) return { rows: [{ id: 'user-1', status: 'active', avatar_url: userAvatarUrl }] };
    throw new Error(`Unexpected query: ${sql}`);
  };
  db.getClient = async () => ({
    query: async (sql, args) => {
      if (sql.startsWith('UPDATE users SET avatar_url')) {
        userAvatarUrl = args[1];
        return { rows: [{ id: 'user-1', avatar_url: userAvatarUrl }] };
      }
      if (sql.includes('INSERT INTO avatar_images')) {
        avatars.clear();
        avatars.set(args[0], { content_type: args[2], image_data: args[3] });
      }
      return { rows: [] };
    },
    release() {},
  });

  const server = app.listen(0, '127.0.0.1');
  t.after(() => server.close());
  await new Promise((resolve) => server.once('listening', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const token = jwt.sign({ sub: 'user-1' }, env.jwt.accessSecret);
  const auth = { Authorization: `Bearer ${token}` };

  const clubUpload = await fetch(`${origin}/api/clubs/images`, {
    method: 'POST',
    headers: { ...auth, 'Content-Type': 'application/json' },
    body: JSON.stringify({ imageBase64: png.toString('base64') }),
  });
  assert.equal(clubUpload.status, 201);
  const clubUrl = (await clubUpload.json()).data.imageUrl;
  assert.match(clubUrl, /^https:\/\/127\.0\.0\.1:\d+\/api\/club-images\//);
  const clubImage = await fetch(`${origin}${new URL(clubUrl).pathname}`);
  assert.equal(clubImage.status, 200);
  assert.match(clubImage.headers.get('content-type'), /^image\/png/);
  assert.equal(clubImage.headers.get('cross-origin-resource-policy'), 'cross-origin');
  assert.deepEqual(Buffer.from(await clubImage.arrayBuffer()), png);

  const form = new FormData();
  form.append('avatar', new Blob([png], { type: 'image/png' }), 'profile.png');
  const avatarUpload = await fetch(`${origin}/api/users/me/avatar`, {
    method: 'PUT', headers: auth, body: form,
  });
  assert.equal(avatarUpload.status, 200);
  const avatarUrl = (await avatarUpload.json()).data.user.avatarUrl;
  assert.match(avatarUrl, /^https:\/\/127\.0\.0\.1:\d+\/api\/user-avatars\//);
  const avatarImage = await fetch(`${origin}${new URL(avatarUrl).pathname}`);
  assert.equal(avatarImage.status, 200);
  assert.match(avatarImage.headers.get('content-type'), /^image\/png/);
  assert.equal(avatarImage.headers.get('cross-origin-resource-policy'), 'cross-origin');
  assert.deepEqual(Buffer.from(await avatarImage.arrayBuffer()), png);

  const profile = await fetch(`${origin}/api/users/me`, { headers: auth });
  assert.equal(profile.status, 200);
  assert.equal((await profile.json()).data.user.avatarUrl, avatarUrl);
});
