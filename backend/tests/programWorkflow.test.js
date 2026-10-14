const test = require('node:test');
const assert = require('node:assert/strict');

const db = require('../src/config/db');
const adaptive = require('../src/services/adaptiveEngineService');
const progress = require('../src/services/gameProgressService');
const programs = require('../src/services/programService');

function setup(t, query, clientQuery = async () => ({ rows: [] })) {
  const originalQuery = db.query;
  const originalClient = db.getClient;
  const calls = [];
  t.after(() => { db.query = originalQuery; db.getClient = originalClient; });
  db.query = query;
  db.getClient = async () => ({
    query: async (sql, params) => {
      calls.push({ sql, params });
      return clientQuery(sql, params);
    },
    release: () => calls.push({ sql: 'RELEASE' }),
  });
  return calls;
}

function startQuery(sql) {
  if (sql.includes('FROM user_basic_info')) {
    return { rows: [{ running_experience_level: 'beginner' }] };
  }
  if (sql.includes('FROM user_programs')) return { rows: [] };
  if (sql.includes('FROM program_templates')) {
    return { rows: [{ id: 'template1', level: 'beginner', duration_weeks_min: 1 }] };
  }
  return { rows: [] };
}

function startClient(sql) {
  if (sql.includes('INSERT INTO user_programs')) {
    return { rows: [{ id: 'program1', start_date: '2026-10-14', current_week: 1,
      status: 'active', schedule_mode: 'manual' }] };
  }
  if (sql.includes('SELECT DISTINCT ON') && sql.includes('value_low')) {
    return { rows: [{ session_type: 'easy', value_low: 2, unit: 'km' }] };
  }
  if (sql.includes('SELECT DISTINCT ON') && sql.includes('program_total_target')) {
    return { rows: [{ session_type: 'easy', program_total_target: 10 }] };
  }
  return { rows: [] };
}

test('program start rejects missing onboarding, an active program, and unknown template', async (t) => {
  let mode = 'missing';
  setup(t, async (sql) => {
    if (sql.includes('FROM user_basic_info')) return { rows: mode === 'missing'
      ? [] : [{ running_experience_level: 'beginner' }] };
    if (sql.includes('FROM user_programs')) return { rows: mode === 'active' ? [{ id: 'p1' }] : [] };
    return { rows: [] };
  });
  await assert.rejects(programs.startProgram('u1', 'beginner', 'manual'), { statusCode: 400 });
  mode = 'active';
  await assert.rejects(programs.startProgram('u1', 'beginner', 'manual'), { statusCode: 400 });
  mode = 'no-template';
  await assert.rejects(programs.startProgram('u1', 'beginner', 'manual'), { statusCode: 404 });
});

test('program start enforces level prerequisites', async (t) => {
  let userLevel = 'advanced';
  setup(t, async (sql) => {
    if (sql.includes('FROM user_basic_info')) return { rows: [{ running_experience_level: userLevel }] };
    if (sql.includes('FROM user_programs')) return { rows: [] };
    if (sql.includes('FROM program_templates')) {
      return { rows: [{ id: 'template1', require_exp_level: 'lower_intermediate' }] };
    }
    return { rows: [{ user_rank: 1, required_rank: 2 }] };
  });
  await assert.rejects(programs.startProgram('u1', 'lower_intermediate', 'manual'), { statusCode: 400 });
  userLevel = 'beginner';
  await assert.rejects(programs.startProgram('u1', 'lower_intermediate', 'manual'), { statusCode: 400 });
});

test('manual program creates baselines and completion targets atomically', async (t) => {
  const calls = setup(t, async (sql) => startQuery(sql), async (sql) => startClient(sql));
  const result = await programs.startProgram('u1', 'beginner', 'manual');
  assert.equal(result.userProgramId, 'program1');
  assert.equal(calls[0].sql, 'BEGIN');
  assert.ok(calls.some((call) => call.sql.includes('INSERT INTO user_program_baselines')));
  assert.ok(calls.some((call) => call.sql.includes('INSERT INTO user_program_completion')));
  assert.equal(calls.some((call) => call.sql.includes('INSERT INTO main_quest_instances')), false);
  assert.equal(calls.at(-2).sql, 'COMMIT');
  assert.equal(calls.at(-1).sql, 'RELEASE');
});

test('auto program generates its weekly schedule', async (t) => {
  const calls = setup(t, async (sql) => startQuery(sql), async (sql) => {
    if (sql.includes('INSERT INTO user_programs')) {
      return { rows: [{ id: 'program1', start_date: '2026-10-14', current_week: 1,
        status: 'active', schedule_mode: 'auto' }] };
    }
    return startClient(sql);
  });
  await programs.startProgram('u1', 'beginner', 'auto');
  const inserted = calls.filter((call) => call.sql.includes('INSERT INTO main_quest_instances'));
  assert.equal(inserted.length, 4);
  assert.deepEqual(inserted.map((call) => call.params[2]), ['easy', 'easy', 'easy', 'long_run']);
});

test('program start rolls back when a baseline insert fails', async (t) => {
  const calls = setup(t, async (sql) => startQuery(sql), async (sql) => {
    if (sql.includes('INSERT INTO user_program_baselines')) throw new Error('baseline failed');
    return startClient(sql);
  });
  await assert.rejects(programs.startProgram('u1', 'beginner', 'manual'), /baseline failed/);
  assert.ok(calls.some((call) => call.sql === 'ROLLBACK'));
  assert.equal(calls.at(-1).sql, 'RELEASE');
});

test('current week rejects missing programs and annotates only today pending quests', async (t) => {
  const originalAdjustment = adaptive.computeAdjustment;
  t.after(() => { adaptive.computeAdjustment = originalAdjustment; });
  let exists = false;
  let adjustments = 0;
  adaptive.computeAdjustment = async () => { adjustments += 1; return { action: 'as_planned' }; };
  const today = new Date().toLocaleDateString('en-CA');
  setup(t, async (sql) => {
    if (sql.includes('FROM user_programs')) return { rows: exists
      ? [{ id: 'program1', start_date: '2026-10-14', schedule_mode: 'auto' }] : [] };
    if (sql.includes('week_number')) {
      return { rows: [{ week_number: 0, week_start: today, week_end: today }] };
    }
    return { rows: [
      { id: 'q1', scheduled_date: today, status: 'pending', planned_value: 5, session_type: 'easy' },
      { id: 'q2', scheduled_date: today, status: 'completed', planned_value: 5 },
    ] };
  });
  await assert.rejects(programs.getCurrentWeek('u1'), { statusCode: 404 });
  exists = true;
  const result = await programs.getCurrentWeek('u1');
  assert.equal(result.weekNumber, 1);
  assert.equal(result.quests[0].adjustment.action, 'as_planned');
  assert.equal(result.quests[1].adjustment, undefined);
  assert.equal(adjustments, 1);
});

test('manual quest requires an active manual-mode program', async (t) => {
  let mode = 'none';
  setup(t, async () => ({ rows: mode === 'none' ? [] : [{ id: 'program1', schedule_mode: mode }] }));
  await assert.rejects(programs.addManualQuest('u1', '2026-10-14', 'easy'), { statusCode: 404 });
  mode = 'auto';
  await assert.rejects(programs.addManualQuest('u1', '2026-10-14', 'easy'), { statusCode: 400 });
});

test('manual quest inserts for the active program and translates database errors', async (t) => {
  let failure = null;
  setup(t, async (sql, params) => {
    if (sql.includes('FROM user_programs')) return { rows: [{ id: 'program1', schedule_mode: 'manual' }] };
    if (failure) { const error = new Error('weekly cap exceeded'); error.code = failure; throw error; }
    assert.deepEqual(params, ['program1', '2026-10-14', 'easy']);
    return { rows: [{ id: 'q1' }] };
  });
  assert.equal((await programs.addManualQuest('u1', '2026-10-14', 'easy')).id, 'q1');
  failure = 'P0001';
  await assert.rejects(programs.addManualQuest('u1', '2026-10-14', 'easy'), { statusCode: 400 });
  failure = '23503';
  await assert.rejects(programs.addManualQuest('u1', '2026-10-14', 'easy'), { statusCode: 400 });
  failure = '22P02';
  await assert.rejects(programs.addManualQuest('u1', '2026-10-14', 'easy'), { statusCode: 400 });
});

test('deleting a manual quest only reports a pending owned quest', async (t) => {
  let found = false;
  setup(t, async (sql, params) => {
    if (sql.includes('FROM user_programs')) return { rows: [{ id: 'program1', schedule_mode: 'manual' }] };
    assert.deepEqual(params, ['q1', 'program1']);
    return { rows: found ? [{ id: 'q1' }] : [] };
  });
  await assert.rejects(programs.deleteManualQuest('u1', 'q1'), { statusCode: 404 });
  found = true;
  assert.equal((await programs.deleteManualQuest('u1', 'q1')).deletedId, 'q1');
});

test('quest range supports explicit dates and current-week fallback', async (t) => {
  const captured = [];
  setup(t, async (sql, params) => {
    captured.push({ sql, params });
    if (sql.includes('FROM user_programs')) {
      return { rows: [{ id: 'program1', start_date: '2026-10-14', schedule_mode: 'manual' }] };
    }
    if (sql.includes('week_start')) return { rows: [{ week_start: '2026-10-14', week_end: '2026-10-20' }] };
    return { rows: [] };
  });
  const explicit = await programs.getQuestsInRange('u1', '2026-10-01', '2026-10-31');
  assert.equal(explicit.from, '2026-10-01');
  const fallback = await programs.getQuestsInRange('u1');
  assert.equal(fallback.from, '2026-10-14');
  assert.match(captured.find(({ sql }) => sql.includes('AS week_start')).sql, /FLOOR\(\(CURRENT_DATE - \$1::date\) \/ 7\)::integer \* 7/);
  assert.deepEqual(captured.at(-1).params, ['program1', '2026-10-14', '2026-10-20']);
});

test('main quest completion awards once and rolls back missing quests', async (t) => {
  const originalAward = progress.award;
  t.after(() => { progress.award = originalAward; });
  let exists = false;
  progress.award = async (_client, userId, reward) => {
    assert.equal(userId, 'u1');
    assert.equal(reward.sourceId, 'q1');
    assert.equal(reward.coins, 8);
    return { awarded: true };
  };
  const calls = setup(t, async () => ({ rows: [] }), async (sql) => {
    if (sql.includes('SELECT mq.id')) {
      return { rows: exists ? [{ id: 'q1', status: 'pending', session_type: 'easy' }] : [] };
    }
    if (sql.includes('UPDATE main_quest_instances')) {
      return { rows: [{ id: 'q1', status: 'completed' }] };
    }
    return { rows: [] };
  });
  await assert.rejects(programs.completeMainQuest('u1', 'q1'), { statusCode: 404 });
  assert.ok(calls.some((call) => call.sql === 'ROLLBACK'));
  exists = true;
  const result = await programs.completeMainQuest('u1', 'q1');
  assert.equal(result.quest.status, 'completed');
  assert.equal(result.reward.awarded, true);
});
