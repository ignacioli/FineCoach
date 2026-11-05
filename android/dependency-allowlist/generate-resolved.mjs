import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const reports = [
  ['app-buildEnvironment.txt', 'app:classpath'],
  ...['debugAndroidTestRuntimeClasspath', 'debugCompileClasspath', 'debugRuntimeClasspath',
    'debugUnitTestRuntimeClasspath', 'releaseCompileClasspath', 'releaseRuntimeClasspath']
    .map(scope => [`app-${scope}.txt`, `app:${scope}`]),
  ['root-buildEnvironment.txt', 'root:classpath'],
];

export function selectedCoordinate(line) {
  const tree = line.match(/^[|\s]*(?:\+---|\\---) (.+)$/);
  if (!tree) return null;
  const body = tree[1].replace(/(?:\s+\((?:c|\*)\))+$/, '');
  if (/^project ':app'$/.test(body)) return null;
  // Split before parsing coordinates: BOM-supplied requests can omit a version.
  const arrow = body.lastIndexOf(' -> ');
  const request = arrow >= 0 ? body.slice(0, arrow) : body;
  const requested = request.match(/^([^:\s]+):([^:\s]+)(?::(.+))?$/);
  assert.ok(requested, `Malformed dependency: ${line}`);
  const [, group, artifact, expression = ''] = requested;
  // A selected version after the arrow wins over rich requested constraints.
  let selected = arrow >= 0 ? body.slice(arrow + 4) : expression;
  const strict = selected.match(/^\{strictly ([^\s{}]+)\}$/);
  if (strict) selected = strict[1];
  if (selected.includes(':')) {
    assert.match(selected, /^[^:\s]+:[^:\s]+:[0-9][A-Za-z0-9_.-]*(?:\+[A-Za-z0-9_.-]+)?$/, `Invalid substitution: ${line}`);
    return selected;
  }
  assert.match(selected, /^[0-9][A-Za-z0-9_.-]*(?:\+[A-Za-z0-9_.-]+)?$/, `No exact selected version: ${line}`);
  return `${group}:${artifact}:${selected}`;
}

function selfTest() {
  const cases = [
    ['+--- fictional:library:1.0', 'fictional:library:1.0'],
    ['|    +--- fictional:library:1.0 -> 2.0 (*)', 'fictional:library:2.0'],
    ['\\--- fictional:library:{strictly 1.0} -> 2.0 (c)', 'fictional:library:2.0'],
    ['+--- fictional:library:{strictly 1.0} (c)', 'fictional:library:1.0'],
    ['+--- fictional:library -> 2.0 (*)', 'fictional:library:2.0'],
    ['+--- fictional:library:1.0 (c) (*)', 'fictional:library:1.0'],
    ['+--- fictional:library:1.0 -> fictional:replacement:2.0', 'fictional:replacement:2.0'],
    ["+--- project ':app' (*)", null],
  ];
  cases.forEach(([line, expected]) => assert.equal(selectedCoordinate(line), expected));
  for (const version of ['{strictly', '1.+', '[1,2)', '1.0 FAILED']) {
    assert.throws(() => selectedCoordinate(`+--- fictional:library:${version}`));
  }
  console.log('Parser fixtures: 8 positive/project cases + 4 rejected malformed/unresolved versions');
}

selfTest();
if (process.argv[2] !== '--self-test') {
  assert.equal(process.argv.length, 3, 'Usage: node generate-resolved.mjs <host-report-directory> | --self-test');
  const rows = [];
  const counts = {};
  for (const [filename, scope] of reports) {
    const text = readFileSync(join(process.argv[2], filename), 'utf8');
    assert.ok(!/\bFAILED\b|\(n\)/.test(text), `Unresolved report: ${filename}`);
    const coordinates = new Set(text.split(/\r?\n/).map(selectedCoordinate).filter(Boolean));
    assert.ok(coordinates.size > 0 || scope === 'app:classpath', `Empty graph: ${scope}`);
    counts[scope] = coordinates.size;
    [...coordinates].sort().forEach(coordinate => rows.push(`${coordinate} ${scope}`));
  }
  const output = fileURLToPath(new URL('./resolved.txt', import.meta.url));
  const header = readFileSync(output, 'utf8').split('\n').filter(line => line.startsWith('#')).join('\n');
  writeFileSync(output, `${header}\n${rows.join('\n')}\n`);
  console.log(JSON.stringify({ counts, rows: rows.length, unique: new Set(rows.map(row => row.split(' ')[0])).size }));
}
