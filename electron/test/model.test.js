import { test } from 'node:test'
import assert from 'node:assert/strict'
import { fuzzy, rank, relativeAge, shortProject, toMemory, formatArgs, kindFromName } from '../src/shared/model.js'

test('fuzzy matches subsequences and reports hit positions', () => {
  assert.deepEqual(fuzzy('ki', 'kind:issue').hits, [0, 1])
  assert.equal(fuzzy('zz', 'kind:issue'), null)
  assert.ok(fuzzy('ab', 'ab xx').score > fuzzy('ab', 'a xb').score, 'consecutive hits score higher')
  assert.ok(fuzzy('x', 'a:x').score > fuzzy('x', 'ax').score, 'word starts score higher')
})

test('rank keeps order for an empty query and sorts by score otherwise', () => {
  const items = [{ label: 'refresh' }, { label: 'remember' }, { label: 'kind:issue' }]
  assert.deepEqual(rank('', items).map((r) => r.item.label), ['refresh', 'remember', 'kind:issue'])
  assert.deepEqual(rank('rem', items).map((r) => r.item.label), ['remember'])
  assert.equal(rank('re', items)[0].item.label, 'refresh', 'ties keep input order')
})

test('relativeAge buckets', () => {
  const m = 60_000
  assert.equal(relativeAge(10_000), 'now')
  assert.equal(relativeAge(3 * m), '3m')
  assert.equal(relativeAge(5 * 60 * m), '5h')
  assert.equal(relativeAge(2 * 1440 * m), '2d')
  assert.equal(relativeAge(21 * 1440 * m), '3w')
  assert.equal(relativeAge(400 * 1440 * m), '1y')
  assert.equal(relativeAge(-5), 'now')
})

test('records normalise from tool output', () => {
  const m = toMemory({ id: '7', title: 't', kind: 'bogus', project_name: 'a/b', project_id: 3, updated_at: '2026-10-05T12:00:00Z' })
  assert.deepEqual(m, { id: 7, title: 't', body: null, kind: 'work', status: 'open', project: 'a/b', projectId: 3, updatedAt: Date.UTC(2026, 9, 5, 12) })
  assert.equal(kindFromName('issue'), 'issue')
  assert.equal(shortProject('ReqallSystem/desktop-app'), 'desktop-app')
  assert.equal(shortProject('.user'), '.user')
})

test('formatArgs prints compact, skips empties and truncates long values', () => {
  assert.equal(formatArgs({ limit: 1, status: 'open', kind: undefined }), '{limit:1, status:open}')
  assert.equal(formatArgs({}), '')
  assert.match(formatArgs({ title: 'x'.repeat(80) }), /^\{title:x{39}…\}$/)
})
