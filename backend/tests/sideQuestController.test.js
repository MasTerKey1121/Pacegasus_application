const test = require('node:test');
const assert = require('node:assert/strict');

const sideQuestController = require('../src/controllers/sideQuestController');
const sideQuestService = require('../src/services/sideQuestService');

test('side quest controller exposes lifecycle handlers', () => {
  assert.equal(typeof sideQuestController.startSideQuest, 'function');
  assert.equal(typeof sideQuestController.updateProgress, 'function');
  assert.equal(typeof sideQuestController.finishSideQuest, 'function');
  assert.equal(typeof sideQuestController.getQuestAlbum, 'function');
});

test('side quest service exposes lifecycle handlers', () => {
  assert.equal(typeof sideQuestService.startSideQuest, 'function');
  assert.equal(typeof sideQuestService.updateProgress, 'function');
  assert.equal(typeof sideQuestService.finishSideQuest, 'function');
  assert.equal(typeof sideQuestService.getQuestAlbum, 'function');
});
