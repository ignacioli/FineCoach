// fictional-data: temporary git repositories and byte-only PNG fixtures.
// S2 screens are covered by the existing whole-directory guard without changing its policy.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { inspect } from '../../scripts/baseline-guard.mjs';
test('screens manifest and PNG changes are guarded', () => {
    const dir = mkdtempSync(join(tmpdir(), 's2-baseline-guard-'));
    const git = (...args) => execFileSync('git', ['-C', dir, ...args], { encoding: 'utf8' }).trim();
    git('init', '-q'); git('config', 'user.name', 'Fixture'); git('config', 'user.email', 'fixture@example.invalid');
    const root = join(dir, 'android/screenshot-baselines/screens'); mkdirSync(root, { recursive: true });
    writeFileSync(join(root, 'baselines.json'), '{}'); writeFileSync(join(root, 'screen.png'), 'fictional-v1');
    git('add', '.'); git('commit', '-qm', 'Fixture baseline'); const base = git('rev-parse', 'HEAD');
    assert.equal(inspect(dir, base).status, 'PASS');
    writeFileSync(join(root, 'screen.png'), 'fictional-v2');
    const changed = inspect(dir, base); assert.equal(changed.status, 'BASELINE_CHANGED');
    assert.ok(changed.unapproved.includes('android/screenshot-baselines/screens/screen.png'));
    writeFileSync(join(root, 'new.png'), 'fictional');
    assert.ok(inspect(dir, base).unapproved.includes('android/screenshot-baselines/screens/new.png'));
});
