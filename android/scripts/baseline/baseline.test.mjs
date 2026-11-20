// Source: /Users/liyongqiang/.agents/skills/ig-design-system/scripts/baseline/baseline.test.mjs; copied 2026-11-17.
import { test, describe } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
import { checkBaselines, sha256 } from './baseline-check.mjs'
import { comparePage } from './compare-page.mjs'
import { validate } from './contract/validate.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const skill = here

// A fake PNG is enough: the lock hashes bytes, it does not decode images.
function fixture({ approve = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'baseline-'))
  for (const d of ['baselines', 'design', 'out', 'out2']) mkdirSync(join(dir, d))
  const png = (p, s) => writeFileSync(join(dir, p), `PNG-${s}`)
  png('baselines/home.png', 'home-v1')
  png('baselines/canary.png', 'canary-v1')
  png('design/home.png', 'design')
  const entry = (id, file) => ({ id, png: file, sha256: approve ? sha256(join(dir, file)) : '0'.repeat(64), approvedAt: '2026-01-03', decision: 'D-7', design: id === 'home' ? 'design/home.png' : undefined })
  const manifest = { version: 1, algorithm: 'sha256', screens: [entry('home', 'baselines/home.png')], environment: [entry('canary', 'baselines/canary.png')] }
  const mpath = join(dir, 'baselines.json')
  writeFileSync(mpath, JSON.stringify(manifest))
  writeFileSync(join(dir, 'decisions.md'), '| D-7 | baselines approved |\n')
  return { dir, mpath, png, manifest }
}

describe('baseline-check', () => {
  test('passes when every locked file and every render matches its hash', () => {
    const f = fixture()
    f.png('out/home.png', 'home-v1')
    f.png('out/canary.png', 'canary-v1')
    const r = checkBaselines({ manifest: f.mpath, decisions: join(f.dir, 'decisions.md'), actual: join(f.dir, 'out') })
    assert.deepEqual(r.errors, [])
    assert.equal(r.code, 0)
  })

  test('a baseline file overwritten without approval fails', () => {
    const f = fixture()
    f.png('baselines/home.png', 'home-v2')
    const r = checkBaselines({ manifest: f.mpath })
    assert.equal(r.code, 1)
    assert.match(r.errors[0], /without owner approval/)
  })

  test('a changed render fails and is listed for the compare page; a changed canary adds a note', () => {
    const f = fixture()
    f.png('out/home.png', 'home-v2')
    f.png('out/canary.png', 'canary-v2')
    const r = checkBaselines({ manifest: f.mpath, actual: join(f.dir, 'out') })
    assert.equal(r.code, 1)
    assert.deepEqual(r.changed.map((c) => c.id), ['home', 'canary'])
    assert.ok(r.changed[0].design.endsWith('design/home.png'))
    assert.match(r.notes[0], /environment canary/)
  })

  test('a missing render fails; two different renders of one fixture are a usage error', () => {
    const f = fixture()
    f.png('out/home.png', 'home-v1')
    assert.equal(checkBaselines({ manifest: f.mpath, actual: join(f.dir, 'out') }).code, 1)
    f.png('out/canary.png', 'canary-v1')
    f.png('out2/home.png', 'home-v1-jitter')
    f.png('out2/canary.png', 'canary-v1')
    const r = checkBaselines({ manifest: f.mpath, actual: join(f.dir, 'out'), actual2: join(f.dir, 'out2') })
    assert.equal(r.code, 2)
    assert.match(r.errors.join('\n'), /not deterministic/)
  })

  test('decision ids must exist in the log as whole tokens', () => {
    const f = fixture()
    writeFileSync(join(f.dir, 'decisions.md'), 'D-71 something else\n')
    const r = checkBaselines({ manifest: f.mpath, decisions: join(f.dir, 'decisions.md') })
    assert.equal(r.code, 1)
    assert.match(r.errors.join('\n'), /decision D-7 not found/)
  })

  test('an entry without hash, date or decision is an invalid manifest', () => {
    const f = fixture()
    delete f.manifest.screens[0].decision
    writeFileSync(f.mpath, JSON.stringify(f.manifest))
    const r = checkBaselines({ manifest: f.mpath })
    assert.equal(r.code, 2)
    assert.match(r.errors[0], /missing required "decision"/)
  })

  test('CLI exit codes and changed-out file', () => {
    const f = fixture()
    f.png('out/home.png', 'home-v2')
    f.png('out/canary.png', 'canary-v1')
    const out = join(f.dir, 'changed.json')
    const run = spawnSync(process.execPath, [join(here, 'baseline-check.mjs'), '--manifest', f.mpath, '--actual', join(f.dir, 'out'), '--changed-out', out], { encoding: 'utf8' })
    assert.equal(run.status, 1)
    assert.match(run.stdout, /baseline-check: FAIL/)
    assert.equal(JSON.parse(readFileSync(out, 'utf8'))[0].id, 'home')
    assert.equal(spawnSync(process.execPath, [join(here, 'baseline-check.mjs')]).status, 2)
  })
})

describe('compare-page', () => {
  test('one design | implementation | difference row per changed screen, images embedded, names escaped', () => {
    const f = fixture()
    f.png('out/home.png', 'home-v2')
    f.png('out/canary.png', 'canary-v1')
    const { changed } = checkBaselines({ manifest: f.mpath, actual: join(f.dir, 'out') })
    changed[0].decision = '<script>x</script>'
    const html = comparePage(changed, { today: '2026-01-09' })
    assert.equal((html.match(/<section>/g) || []).length, 1)
    assert.ok(html.includes('data:image/png;base64,'))
    assert.ok(html.includes('<canvas data-design="d-home"'))
    assert.ok(!html.includes('<script>x</script>'))
    assert.ok(html.includes('&quot;decision&quot;: &quot;&lt;owner decision id&gt;&quot;'))
    assert.ok(html.includes('approves nothing'))
  })

  test('uses a comparer difference map when one exists, and says when an image is missing', () => {
    const f = fixture()
    mkdirSync(join(f.dir, 'diff'))
    f.png('diff/home.diff.png', 'diff')
    const c = { id: 'home', kind: 'screen', lockedSha256: 'a'.repeat(64), actualSha256: 'b'.repeat(64), actual: join(f.dir, 'nope.png'), design: join(f.dir, 'design/home.png'), decision: 'D-7', approvedAt: '2026-01-03' }
    const html = comparePage([c], { diffDir: join(f.dir, 'diff') })
    assert.ok(html.includes('difference (comparer)'))
    assert.ok(html.includes('not available'))
  })
})

describe('contract schemas', () => {
  const schema = (n) => JSON.parse(readFileSync(join(skill, 'schemas', `${n}.schema.json`), 'utf8'))
  const example = (n) => JSON.parse(readFileSync(join(skill, 'examples', n), 'utf8'))

  test('every example validates against its schema', () => {
    for (const [s, e] of [
      ['layers', 'conformance/home.layers.json'],
      ['map', 'conformance/home.map.json'],
      ['capture', 'conformance/home.capture.json'],
      ['report', 'conformance/home.report.json'],
      ['baseline-manifest', 'conformance/baselines.json'],
      ['scan-config', 'board-scan/scan.config.json'],
    ]) assert.deepEqual(validate(schema(s), example(e)), [], `${e} vs ${s}`)
  })

  test('the validator reports wrong types, enums, patterns and refs', () => {
    const bad = example('conformance/home.layers.json')
    bad.layers[0].type = 'blob'
    bad.layers[1].path = 'x'
    bad.viewport.w = '360'
    const errs = validate(schema('layers'), bad)
    assert.ok(errs.some((e) => e.startsWith('/layers/0/type')))
    assert.ok(errs.some((e) => e.startsWith('/layers/1/path')))
    assert.ok(errs.some((e) => e.startsWith('/viewport/w')))
    const m = example('conformance/baselines.json')
    m.environment.push(m.environment[0], m.environment[0])
    assert.ok(validate(schema('baseline-manifest'), m).some((e) => /more than 2/.test(e)))
  })
})
