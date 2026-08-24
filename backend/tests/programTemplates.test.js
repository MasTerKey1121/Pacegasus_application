const test = require('node:test');
const assert = require('node:assert/strict');

const db = require('../src/config/db');
const programController = require('../src/controllers/programController');
const programService = require('../src/services/programService');

test('program template API handlers are exposed', () => {
  assert.equal(typeof programController.getProgramTemplates, 'function');
  assert.equal(typeof programService.getProgramTemplates, 'function');
  assert.equal(typeof programController.cancelCurrentProgram, 'function');
  assert.equal(typeof programService.cancelCurrentProgram, 'function');
  assert.equal(typeof programController.addManualQuestsBatch, 'function');
  assert.equal(typeof programService.addManualQuestsBatch, 'function');
});

test('cancelling a current program soft-deletes it', async (t) => {
  const originalQuery = db.query;
  t.after(() => { db.query = originalQuery; });

  db.query = async (sql, params) => {
    assert.match(sql, /UPDATE user_programs/);
    assert.match(sql, /status = 'cancelled'/);
    assert.match(sql, /deleted_at = now\(\)/);
    assert.deepEqual(params, ['user-1']);
    return {
      rows: [{
        id: 'program-1',
        program_template_id: 'template-1',
        start_date: '2026-08-01',
        schedule_mode: 'manual',
        status: 'cancelled',
        deleted_at: '2026-08-23T00:00:00.000Z',
      }],
    };
  };

  const result = await programService.cancelCurrentProgram('user-1');

  assert.equal(result.userProgramId, 'program-1');
  assert.equal(result.status, 'cancelled');
  assert.equal(result.deletedAt, '2026-08-23T00:00:00.000Z');
});

test('program templates include related phase, session spec, and sequencing data', async (t) => {
  const originalQuery = db.query;
  t.after(() => { db.query = originalQuery; });

  db.query = async (sql) => {
    if (sql.includes('FROM program_templates')) {
      return { rows: [{ id: 'template-1', level: 'beginner', description: 'เริ่มต้น' }] };
    }
    if (sql.includes('FROM program_phases')) {
      return { rows: [{ id: 'phase-1', program_template_id: 'template-1', phase_code: null }] };
    }
    if (sql.includes('FROM session_type_specs')) {
      return { rows: [{ id: 'spec-1', program_template_id: 'template-1', session_type: 'easy' }] };
    }
    return { rows: [{ id: 'rule-1', program_template_id: 'template-1', rule_type: 'must_precede' }] };
  };

  const [template] = await programService.getProgramTemplates();

  assert.equal(template.level, 'beginner');
  assert.equal(template.programPhases[0].id, 'phase-1');
  assert.equal(template.sessionTypeSpecs[0].id, 'spec-1');
  assert.equal(template.programSequencingRules[0].id, 'rule-1');
});

test('manual quest batch is sorted and committed as one transaction', async (t) => {
  const originalQuery = db.query;
  const originalGetClient = db.getClient;
  const calls = [];
  const client = {
    query: async (sql, params = []) => {
      calls.push({ sql, params });
      if (sql.includes('INSERT INTO main_quest_instances')) {
        return { rows: [{ id: `quest-${params[1]}`, scheduled_date: params[1], session_type: params[2] }] };
      }
      return { rows: [] };
    },
    release: () => { calls.push({ sql: 'RELEASE' }); },
  };

  t.after(() => {
    db.query = originalQuery;
    db.getClient = originalGetClient;
  });
  db.query = async () => ({ rows: [{ id: 'program-1', schedule_mode: 'manual', status: 'active' }] });
  db.getClient = async () => client;

  const quests = await programService.addManualQuestsBatch('user-1', [
    { scheduledDate: '2026-08-12', sessionType: 'easy' },
    { scheduledDate: '2026-08-10', sessionType: 'easy' },
  ]);

  assert.deepEqual(quests.map((quest) => quest.scheduled_date), ['2026-08-10', '2026-08-12']);
  assert.equal(calls[0].sql, 'BEGIN');
  assert.match(calls[1].sql, /INSERT INTO main_quest_instances/);
  assert.equal(calls[1].params[1], '2026-08-10');
  assert.equal(calls.at(-2).sql, 'COMMIT');
  assert.equal(calls.at(-1).sql, 'RELEASE');
});
