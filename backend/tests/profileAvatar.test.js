const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const express = require('express');
const jwt = require('jsonwebtoken');
const db = require('../src/config/db');
const env = require('../src/config/env');
const userRoutes = require('../src/routes/userRoutes');
const { errorHandler } = require('../src/middleware/errorHandler');
const { AVATAR_DIR } = require('../src/middleware/uploadAvatar');

test('profile avatar upload authenticates, persists, reloads and replaces the image', async (t) => {
  const originalQuery = db.query;
  const originalSecret = env.jwt.accessSecret;
  const originalBaseUrl = env.publicBaseUrl;
  env.jwt.accessSecret = 'profile-avatar-test-only';
  env.publicBaseUrl = undefined;
  let user = { id: 'avatar-integration-test', uid: 'ABCDE23456',
    display_name: 'Runner', avatar_url: null, status: 'active' };
  const createdFiles = [];
  db.query = async (sql, args) => {
    assert.equal(args[0], user.id);
    if (sql.includes('UPDATE users SET avatar_url = $2')) {
      user = { ...user, avatar_url: args[1] };
      createdFiles.push(path.join(AVATAR_DIR, path.basename(new URL(args[1]).pathname)));
    }
    return { rows: [{ ...user }] };
  };
  const app = express();
  app.use('/uploads/avatars', express.static(AVATAR_DIR));
  app.use('/api/users', userRoutes);
  app.use(errorHandler);
  const server = app.listen(0, '127.0.0.1');
  t.after(async () => {
    db.query = originalQuery;
    env.jwt.accessSecret = originalSecret;
    env.publicBaseUrl = originalBaseUrl;
    await new Promise((resolve) => server.close(resolve));
    for (const file of createdFiles) await fs.unlink(file).catch(() => {});
  });
  await new Promise((resolve) => server.once('listening', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const headers = { Authorization: `Bearer ${jwt.sign({}, env.jwt.accessSecret, { subject: user.id })}` };
  const bytes = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK1sAAAAASUVORK5CYII=', 'base64');
  const form = (type = 'image/png', field = 'avatar') => {
    const body = new FormData();
    body.append(field, new Blob([bytes], { type }), 'avatar.png');
    return body;
  };
  const endpoint = `${origin}/api/users/me/avatar`;
  assert.equal((await fetch(endpoint, { method: 'PUT', body: form() })).status, 401);
  assert.equal((await fetch(endpoint, { method: 'PUT', headers, body: form('text/plain') })).status, 400);
  assert.equal((await fetch(endpoint, { method: 'PUT', headers, body: form('image/png', 'wrong') })).status, 400);
  assert.equal((await fetch(endpoint, { method: 'PUT', headers })).status, 400);
  let previousUrl;
  for (let i = 0; i < 2; i++) {
    const response = await fetch(endpoint, { method: 'PUT', headers, body: form() });
    assert.equal(response.status, 200);
    const { data } = await response.json();
    assert.equal(data.user.uid, user.uid);
    assert.equal(data.user.avatarUrl, user.avatar_url);
    const image = await fetch(data.user.avatarUrl);
    assert.equal(image.status, 200);
    assert.deepEqual(Buffer.from(await image.arrayBuffer()), bytes);
    const profile = await fetch(`${origin}/api/users/me/profile`, { headers });
    assert.equal(profile.status, 200);
    assert.equal((await profile.json()).data.user.avatarUrl, data.user.avatarUrl);
    if (previousUrl) assert.equal((await fetch(previousUrl)).status, 404);
    previousUrl = data.user.avatarUrl;
  }
});
