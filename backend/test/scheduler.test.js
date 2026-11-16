const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const getHubTime = require('../src/get-hub-time');
const findDueSchedules = require('../src/find-due-schedules');
const createHistory = require('../src/schedule-history');
const { getScheduleActions } = require('../src/scheduler');
const fixture = require('../../docs/db.json');

test('hub clock uses Asia/Kolkata across a UTC date boundary', () => {
  assert.deepEqual(getHubTime(new Date('2026-11-15T20:45:00Z')),
    { date: '2026-11-16', day: 'mon', time: '02:15' });
});

test('only enabled schedules matching both weekday and minute are due', () => {
  assert.deepEqual(findDueSchedules(fixture.schedules, { day: 'mon', time: '06:30' }).map(s => s.id), ['sc1']);
  assert.deepEqual(findDueSchedules(fixture.schedules, { day: 'sat', time: '18:00' }), []);
  assert.deepEqual(findDueSchedules(fixture.schedules, { day: 'mon', time: '06:31' }), []);
});

test('occurrence claims survive reopening and leave the assignment database unchanged', () => {
  const file = path.resolve(__dirname, '../../build', `schedule-history-unit-${process.pid}.json`);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  try {
    assert.equal(createHistory(file).claimOccurrence('test/2026-11-16/06:30'), true);
    assert.equal(createHistory(file).claimOccurrence('test/2026-11-16/06:30'), false);
    assert.equal(createHistory(file).claimOccurrence('test/2026-11-17/06:30'), true);
  } finally {
    if (fs.existsSync(file)) fs.unlinkSync(file);
  }
});

test('targets resolve exact device state and fetch the current scene actions', async () => {
  const deviceSchedule = fixture.schedules.find(s => s.id === 'sc3');
  assert.deepEqual(await getScheduleActions(deviceSchedule), [{ deviceId: 'd16', state: { on: true } }]);
  const originalFetch = global.fetch;
  let current = [{ deviceId: 'd1', state: { on: false } }];
  global.fetch = async () => ({ ok: true, json: async () => ({ actions: current }) });
  try {
    assert.deepEqual(await getScheduleActions(fixture.schedules[0]), current);
    current = [{ deviceId: 'd2', state: { level: 80 } }];
    assert.deepEqual(await getScheduleActions(fixture.schedules[0]), current);
  } finally {
    global.fetch = originalFetch;
  }
});
