const test = require('node:test');
const assert = require('node:assert/strict');

const db = require('../src/config/db');
const clubService = require('../src/services/clubService');
const shopService = require('../src/services/shopService');
const { createClubSchema, updateClubSchema, inviteSchema } = require('../src/utils/clubValidators');
const { updateAvatarSchema, inventoryFiltersSchema } = require('../src/utils/avatarValidators');
const { shopItemFiltersSchema } = require('../src/utils/shopValidators');

const ME = '11111111-1111-4111-8111-111111111111';
const OTHER = '22222222-2222-4222-8222-222222222222';
const CLUB = '33333333-3333-4333-8333-333333333333';

// Transaction client that answers by matching SQL, and records the statements it saw.
function mockClient(t, answer) {
  const originalGetClient = db.getClient;
  const statements = [];
  t.after(() => { db.getClient = originalGetClient; });
  db.getClient = async () => ({
    query: async (sql, params) => {
      statements.push(sql.trim().split(/\s+/).slice(0, 3).join(' '));
      return { rows: answer(sql, params) || [] };
    },
    release: () => {},
  });
  return statements;
}

test('club input is normalised: Thai tags keep their marks, blank description allowed', () => {
  const { value, error } = createClubSchema.validate({ name: '  Morning Runners ', tags: ['กรุงเทพ', 'Morning'], description: '' });
  assert.equal(error, undefined);
  assert.equal(value.name, 'Morning Runners');
  assert.deepEqual(value.tags, ['กรุงเทพ', 'morning']);
  assert.ok(createClubSchema.validate({ name: 'ab' }).error, 'name too short');
  assert.ok(createClubSchema.validate({ name: 'abc', tags: ['a', 'b', 'c', 'd', 'e', 'f'] }).error, 'max 5 tags');
  assert.ok(createClubSchema.validate({ name: 'abc', tags: ['has space'] }).error);
  assert.ok(updateClubSchema.validate({}).error, 'update needs at least one field');
  assert.equal(inviteSchema.validate({ uid: 'abcde23456' }).value.uid, 'ABCDE23456');
});

test('avatar and shop filters accept comma lists and repeated params', () => {
  assert.deepEqual(inventoryFiltersSchema.validate({ slot: 'hair, beard' }).value.slot, ['hair', 'beard']);
  assert.deepEqual(shopItemFiltersSchema.validate({ slot: ['hair', 'aura'] }).value.slot, ['hair', 'aura']);
  assert.deepEqual(shopItemFiltersSchema.validate({ rarity: 'EPIC' }).value.rarity, ['epic']);
  assert.ok(shopItemFiltersSchema.validate({ rarity: 'mythic' }).error);
  assert.ok(shopItemFiltersSchema.validate({ sort: 'random' }).error, 'sort is whitelisted');
  assert.equal(shopItemFiltersSchema.validate({}).value.sort, 'featured');
});

test('avatar update: colours upper-cased, duplicate slots rejected, null unequips', () => {
  const { value } = updateAvatarSchema.validate({ skinTone: '#8d5524', equipment: [{ slot: 'hair', itemId: null }] });
  assert.equal(value.skinTone, '#8D5524');
  assert.equal(value.equipment[0].itemId, null);
  assert.ok(updateAvatarSchema.validate({ equipment: [{ slot: 'hair', itemId: null }, { slot: 'hair', itemId: null }] }).error);
  assert.ok(updateAvatarSchema.validate({ skinTone: 'red' }).error);
});

test('kicking someone of equal rank is forbidden and rolls back', async (t) => {
  const statements = mockClient(t, (sql) => {
    if (sql.includes('FROM clubs WHERE id')) return [{ id: CLUB, member_count: 3, max_members: 20 }];
    if (sql.includes('FROM club_members m')) {
      return [{ role: 'sub_leader', can_approve_requests: true, can_invite: true, can_kick: true, can_edit_info: false }];
    }
    return [];
  });

  await assert.rejects(clubService.kickMember(ME, CLUB, OTHER), { statusCode: 403 });
  assert.equal(statements.at(-1), 'ROLLBACK');
  assert.ok(!statements.some((s) => s.startsWith('DELETE')));
});

test('a full club rejects join requests before inserting', async (t) => {
  const statements = mockClient(t, (sql) => {
    if (sql.includes('FROM clubs WHERE id')) return [{ id: CLUB, member_count: 20, max_members: 20 }];
    return [];
  });

  await assert.rejects(clubService.requestToJoin(ME, CLUB, {}), { statusCode: 409, message: 'คลับเต็มแล้ว' });
  assert.ok(!statements.some((s) => s.startsWith('INSERT INTO club_join_requests')));
});

test('duplicate club name from the unique index becomes a 409', async (t) => {
  mockClient(t, (sql) => {
    if (sql.startsWith('INSERT INTO clubs')) {
      throw Object.assign(new Error('duplicate key'), { code: '23505', constraint: 'uq_clubs_name_lower' });
    }
    return [];
  });

  await assert.rejects(clubService.createClub(ME, { name: 'Taken', tags: [] }), {
    statusCode: 409,
    message: 'ชื่อคลับนี้ถูกใช้แล้ว',
  });
});

test('purchase locks the coin balance before checking ownership', async (t) => {
  const statements = mockClient(t, (sql) => {
    if (sql.includes('FROM user_game_progress') && sql.includes('FOR UPDATE')) {
      return [{ coin_balance: 500, level: 1, exp: 0, exp_to_next: 200 }];
    }
    if (sql.includes('FROM shop_listings')) return [{ listing_id: 'l-1', item_id: 'i-1', price_coins: 100, owned: true }];
    return [];
  });

  await assert.rejects(shopService.purchase(ME, 'l-1'), { statusCode: 409 });
  const lockAt = statements.findIndex((s) => s.startsWith('SELECT coin_balance'));
  const listingAt = statements.findIndex((s) => s.startsWith('SELECT l.id'));
  assert.ok(lockAt !== -1 && lockAt < listingAt, statements.join(' | '));
  assert.ok(!statements.some((s) => s.startsWith('UPDATE user_game_progress')), 'no coins spent');
});
