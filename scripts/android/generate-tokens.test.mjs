import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const script = join(dirname(fileURLToPath(import.meta.url)), 'generate-tokens.mjs');
const root = resolve(dirname(script), '../..');
const source = readFileSync(join(root, 'design/design-system/README.md'), 'utf8');
const packagePath = 'com/ignacioli/finecoach/designsystem';

function fixture(callback) {
  const directory = mkdtempSync(join(tmpdir(), 'finecoach-token-test-'));
  try { callback(directory); } finally { rmSync(directory, { recursive: true, force: true }); }
}
function invoke(directory, input = source, check = false) {
  const readme = join(directory, 'README.md');
  writeFileSync(readme, input);
  return spawnSync(process.execPath, [script, '--input', readme, '--output', join(directory, 'generated'), ...(check ? ['--check'] : [])], { encoding: 'utf8' });
}

test('approved README generates exactly four deterministic Kotlin files and checks them', () => fixture((directory) => {
  const generated = invoke(directory);
  assert.equal(generated.status, 0, generated.stderr);
  const output = join(directory, 'generated', packagePath);
  const names = readdirSync(output).sort();
  assert.deepEqual(names, ['FcColors.kt', 'FcShapes.kt', 'FcSpacing.kt', 'FcTypography.kt']);
  const before = names.map((name) => readFileSync(join(output, name), 'utf8'));
  assert.equal(invoke(directory, source, true).status, 0);
  assert.equal(invoke(directory).status, 0);
  assert.deepEqual(names.map((name) => readFileSync(join(output, name), 'utf8')), before);
  assert.match(before[0], /SHA-256: [a-f0-9]{64}/);
  assert.match(before[0], /copy\(alpha = 0\.4f\)/);
  assert.match(before[3], /lineHeight = 40\.8\.sp/);
}));

const invalid = [
  ['missing section', (text) => text.replace('### 2.1 原子色（FC Primitives）', '### 原子色'), /§2\.1/],
  ['missing table', (text) => text.replace(/\| Token \| 值 \|\n\|---\|---\|\n(?:\| `space\.[^\n]+\n)+/, ''), /§4/],
  ['duplicate token', (text) => text.replace('| `space.1` | 4 |', '| `space.1` | 4 |\n| `space.1` | 4 |'), /duplicate/],
  ['duplicate style', (text) => text.replace('| `display` | 34 / 700 | 1.2 | — | largeTitle | 一级页面大标题：今日、学员（01/10/16） |', '$&\n$&'), /duplicate/],
  ['unknown column', (text) => text.replace('| Token | 值 | 备注 |', '| Token | 值 | unknown |'), /columns/],
  ['bad value', (text) => text.replace('| `space.1` | 4 |', '| `space.1` | 4px |'), /invalid number/],
  ['bad color', (text) => text.replace('`#2A2822` | 暖炭黑', '`#GGGGGG` | 暖炭黑'), /malformed color/],
  ['bad table row', (text) => text.replace('| `space.1` | 4 |', '| `space.1` | 4 | extra |'), /column count/],
  ['dropped row pipe', (text) => text.replace('| `space.2` | 8 |', '`space.2` | 8 |'), /malformed/],
  ['alias mismatch', (text) => text.replace('| brand.primary | `#2A2822` |', '| brand.primary | `#FFFFFF` |'), /alias\/value mismatch/],
  ['named variant mismatch', (text) => text.replace('| `titleEmphasis` | 22 / 700 |', '| `titleEmphasis` | 22 / 600 |'), /variant mismatch/],
  ['capsule is not a fixed radius', (text) => text.replace('| `radius.capsule` | 高度 / 2 |', '| `radius.capsule` | 999 |'), /capsule/],
];
for (const [name, change, message] of invalid) {
  test(`rejects ${name}`, () => fixture((directory) => {
    const input = change(source);
    assert.notEqual(input, source, 'fixture must change the approved input');
    const result = invoke(directory, input);
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, message);
  }));
}

for (const mutation of ['modified', 'missing', 'extra']) {
  test(`check rejects ${mutation} output without rewriting it`, () => fixture((directory) => {
    assert.equal(invoke(directory).status, 0);
    const target = join(directory, 'generated', packagePath, 'FcSpacing.kt');
    if (mutation === 'modified') writeFileSync(target, '// hand edited\n');
    if (mutation === 'missing') rmSync(target);
    if (mutation === 'extra') {
      mkdirSync(join(directory, 'generated', 'extra'));
      writeFileSync(join(directory, 'generated', 'extra', 'unexpected.kt'), '// extra\n');
    }
    const result = invoke(directory, source, true);
    assert.notEqual(result.status, 0, result.stdout);
    if (mutation === 'modified') assert.equal(readFileSync(target, 'utf8'), '// hand edited\n');
  }));
}
