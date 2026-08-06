const test = require('node:test');
const assert = require('node:assert/strict');

const runningController = require('../src/controllers/runningController');
const runningService = require('../src/services/runningService');
const db = require('../src/config/db');

test('running controller exposes session lifecycle handlers', () => {
  assert.equal(typeof runningController.startSession, 'function');
  assert.equal(typeof runningController.completeSession, 'function');
  assert.equal(typeof runningController.abandonSession, 'function');
  assert.equal(typeof runningController.getSessionDetail, 'function');
  assert.equal(typeof runningController.getSessionHistory, 'function');
});

test('running service exposes session lifecycle handlers', () => {
  assert.equal(typeof runningService.startSession, 'function');
  assert.equal(typeof runningService.completeSession, 'function');
  assert.equal(typeof runningService.abandonSession, 'function');
  assert.equal(typeof runningService.getSessionDetail, 'function');
  assert.equal(typeof runningService.getSessionHistory, 'function');
});

test('running history sorts completed sessions by the requested time period', async () => {
  const originalQuery = db.query;
  let capturedQuery;
  let capturedParams;
  db.query = async (sql, params) => {
    capturedQuery = sql;
    capturedParams = params;
    return { rows: [{ id: 'session-1', status: 'completed' }] };
  };

  try {
    const history = await runningService.getSessionHistory('user-1', 'month', 'asc');
    assert.equal(history.sortBy, 'month');
    assert.equal(history.order, 'asc');
    assert.equal(history.sessions[0].id, 'session-1');
  } finally {
    db.query = originalQuery;
  }

  assert.match(capturedQuery, /DATE_TRUNC\('month'/);
  assert.match(capturedQuery, /ORDER BY[\s\S]*ASC/);
  assert.deepEqual(capturedParams, ['user-1']);
});

test('running service serializes route points into JSONB-safe payload', async () => {
  const originalQuery = db.query;
  let capturedParams;

  db.query = async (_sql, params) => {
    capturedParams = params;
    return { rows: [{ id: 'session-1' }] };
  };

  try {
    await runningService.startSession('user-1', {
      routePoints: '[{"lat":13.7563,"lng":100.5018}]',
    });
  } finally {
    db.query = originalQuery;
  }

  assert.equal(capturedParams[5], '[{"lat":13.7563,"lng":100.5018}]');
});

test('running service links selected side quest instances when a session starts', async () => {
  const originalQuery = db.query;
  const calls = [];

  db.query = async (sql, params) => {
    calls.push({ sql, params });
    if (sql.includes('INSERT INTO running_sessions')) {
      return { rows: [{ id: 'session-1' }] };
    }

    if (sql.includes('UPDATE user_side_quest_instances')) {
      return { rowCount: 2 };
    }

    return { rows: [] };
  };

  try {
    await runningService.startSession('user-1', {
      environment: 'park',
      sessionType: 'easy',
      sideQuestInstanceIds: ['quest-1', 'quest-2'],
    });
  } finally {
    db.query = originalQuery;
  }

  assert.equal(calls.length, 2);
  assert.match(calls[1].sql, /UPDATE user_side_quest_instances/);
  assert.equal(calls[1].params[0], 'session-1');
  assert.deepEqual(calls[1].params[1], ['quest-1', 'quest-2']);
  assert.equal(calls[1].params[2], 'user-1');
});
