import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const reports = [
  ['app-buildEnvironment.txt', 'app:classpath'],
  ...['debugAndroidTestRuntimeClasspath', 'debugCompileClasspath', 'debugRuntimeClasspath',
    'debugUnitTestRuntimeClasspath', 'releaseCompileClasspath', 'releaseRuntimeClasspath',
    'kspDebugKotlinProcessorClasspath', 'kspReleaseKotlinProcessorClasspath',
    'kspDebugUnitTestKotlinProcessorClasspath', 'kspDebugAndroidTestKotlinProcessorClasspath']
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
  assert.ok(process.argv.length === 3 || (process.argv.length === 5 && process.argv[3] === '--resolved-report'),
    'Usage: node generate-resolved.mjs <host-report-directory> [--resolved-report <resolved.txt>] | --self-test');
  const rows = [];
  const counts = {};
  // A ResolutionResult inventory can supply the existing scopes alongside new
  // dependency-tree reports. Preserve every row; never reconstruct old graphs.
  const inventory = new Map();
  if (process.argv[3] === '--resolved-report') {
    let scope;
    for (const line of readFileSync(process.argv[4], 'utf8').split(/\r?\n/).filter(Boolean)) {
      if (line.startsWith('# scope ')) {
        scope = line.slice('# scope '.length);
        assert.ok(reports.some(([, expected]) => expected === scope) && !inventory.has(scope), `Unexpected/duplicate scope: ${scope}`);
        inventory.set(scope, new Set());
      } else {
        const parts = line.split(' ');
        assert.ok(scope && parts.length === 2 && parts[1] === scope, `Malformed inventory row: ${line}`);
        assert.equal(selectedCoordinate(`+--- ${parts[0]}`), parts[0]);
        assert.ok(!inventory.get(scope).has(parts[0]), `Duplicate inventory row: ${line}`);
        inventory.get(scope).add(parts[0]);
      }
    }
  }
  for (const [filename, scope] of reports) {
    let coordinates = inventory.get(scope);
    if (!coordinates) {
      const text = readFileSync(join(process.argv[2], filename), 'utf8');
      assert.ok(!/\bFAILED\b|\(n\)/.test(text), `Unresolved report: ${filename}`);
      coordinates = new Set(text.split(/\r?\n/).map(selectedCoordinate).filter(Boolean));
      assert.ok(coordinates.size > 0 || /^No dependencies\s*$/m.test(text), `Missing dependency graph: ${filename}`);
    }
    assert.ok(coordinates.size > 0 || ['app:classpath', 'app:kspDebugUnitTestKotlinProcessorClasspath'].includes(scope), `Empty graph: ${scope}`);
    counts[scope] = coordinates.size;
    [...coordinates].sort().forEach(coordinate => rows.push(`${coordinate} ${scope}`));
  }
  const acceptedPrereleases = new Set([
    'com.android.tools.build.jetifier:jetifier-core:1.0.0-beta10',
    'com.android.tools.build.jetifier:jetifier-processor:1.0.0-beta10',
  ]);
  const unapproved = rows.map(row => row.split(' ')[0]).filter(coordinate =>
    /alpha|beta|rc|SNAPSHOT/i.test(coordinate.split(':')[2]) && !acceptedPrereleases.has(coordinate));
  assert.deepEqual([...new Set(unapproved)].sort(), [], 'Unapproved prerelease coordinates; allowlist was not written');
  const output = fileURLToPath(new URL('./resolved.txt', import.meta.url));
  const header = readFileSync(output, 'utf8').split('\n').filter(line => line.startsWith('#')).join('\n');
  writeFileSync(output, `${header}\n${rows.join('\n')}\n`);
  console.log(JSON.stringify({ counts, rows: rows.length, unique: new Set(rows.map(row => row.split(' ')[0])).size }));
}
