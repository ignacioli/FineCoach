import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { inspect } from './baseline-guard.mjs';
function fixture() {
  const root = mkdtempSync(join(tmpdir(), 'fc-baseline-guard-'));
  const git = (...args) => execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim();
  git('init', '-q'); git('config', 'user.email', 'fixture@example.invalid'); git('config', 'user.name', 'Fictional Fixture');
  const dir = join(root, 'android/screenshot-baselines/components'); mkdirSync(dir, { recursive: true });
  const file = join(dir, 'sample.txt'); writeFileSync(file, 'approved'); git('add', '.'); git('commit', '-qm', 'Fixture approved base');
  return { root, git, file, base: git('rev-parse', 'HEAD') };
}
for (const mode of ['staged', 'unstaged', 'untracked', 'committed']) test(`rejects ${mode} change relative to approved base`, () => {
  const f = fixture();
  if (mode === 'untracked') writeFileSync(join(f.root, 'android/screenshot-baselines/components/new.txt'), 'new');
  else writeFileSync(f.file, 'changed');
  if (mode === 'staged' || mode === 'committed') f.git('add', '.');
  if (mode === 'committed') f.git('commit', '-qm', 'Fixture changed after approval');
  const r = inspect(f.root, f.base);
  assert.equal(r.status, 'BASELINE_CHANGED'); assert.equal(r.changes[mode].length, 1); assert.equal(r.unapproved.length, 1);
});
test('manifest before/after rejects changed bytes', () => {
  const f = fixture(), before = inspect(f.root, f.base);
  assert.equal(before.status, 'PASS'); writeFileSync(f.file, 'different bytes');
  assert.equal(inspect(f.root, f.base, undefined, before).stable, false);
});

test('ignored untracked baseline is still rejected', () => {
  const f = fixture(); writeFileSync(join(f.root, '.gitignore'), '*.tmp*\n');
  writeFileSync(join(f.root, 'android/screenshot-baselines/components/sample.tmp.png'), 'unexpected');
  const r = inspect(f.root, f.base); assert.equal(r.status, 'BASELINE_CHANGED'); assert.equal(r.changes.untracked.length, 1);
});
test('trusted later approval commit can approve an earlier baseline commit', () => {
  const f = fixture(); writeFileSync(f.file, 'owner-approved update'); f.git('add', '.'); f.git('commit', '-qm', 'Fixture owner baseline update');
  const approvedCommit = f.git('rev-parse', 'HEAD');
  const record = { baseCommit: f.base, approvedCommit, files: { 'android/screenshot-baselines/components/sample.txt': createHash('sha256').update(readFileSync(f.file)).digest('hex') } };
  mkdirSync(join(f.root, 'android/design-assets'), { recursive: true });
  writeFileSync(join(f.root, 'android/design-assets/baseline-approvals.json'), JSON.stringify(record)); f.git('add', '.'); f.git('commit', '-qm', 'Fixture owner approval');
  const approvalCommit = f.git('rev-parse', 'HEAD');
  assert.equal(inspect(f.root, f.base, approvalCommit).status, 'PASS');
  writeFileSync(f.file, 'agent modification'); assert.equal(inspect(f.root, f.base, approvalCommit).status, 'BASELINE_CHANGED');
});
