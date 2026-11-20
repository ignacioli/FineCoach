#!/usr/bin/env node
// Source: /Users/liyongqiang/.agents/skills/ig-design-system/scripts/baseline/baseline-check.mjs; copied 2026-11-17.
// Baseline lock for core-screen screenshots. It never writes the manifest:
// only the owner approves a baseline (screen-conformance.md §2).
//
//   node baseline-check.mjs --manifest <baselines.json>
//       [--decisions <decision-log.md>]   every entry's decision id must appear in the log
//       [--actual <dir>]                  fresh renders, <dir>/<id>.png, compared with the locked hash
//       [--actual2 <dir>]                 a second render of the same fixtures; must be byte-identical
//       [--changed-out <changed.json>]    list of changed entries, input for compare-page.mjs
//
// Exit 0 = every lock holds; 1 = a locked file or a render differs from its
// hash, a decision id is missing, or a render is missing; 2 = usage error,
// invalid manifest or non-deterministic rendering.
import { createHash } from 'node:crypto'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { validate } from './contract/validate.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const SCHEMA = join(here, 'schemas', 'baseline-manifest.schema.json')

export const sha256 = (file) => createHash('sha256').update(readFileSync(file)).digest('hex')
const locked = (lock, actual) => actual.startsWith(lock.toLowerCase())
// whole-token match, so D-1 does not match D-12
const mentions = (text, id) => new RegExp(`(^|[^A-Za-z0-9-])${id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^A-Za-z0-9-]|$)`, 'm').test(text)

/**
 * Check a manifest. Returns { code, errors, changed, notes } without printing,
 * so tests and other scripts can call it.
 */
export function checkBaselines({ manifest, decisions = null, actual = null, actual2 = null }) {
  const errors = []
  const notes = []
  const changed = []
  let m
  try {
    m = JSON.parse(readFileSync(manifest, 'utf8'))
  } catch (e) {
    return { code: 2, errors: [`cannot read manifest: ${e.message}`], changed, notes }
  }
  const schemaErrs = validate(JSON.parse(readFileSync(SCHEMA, 'utf8')), m)
  if (schemaErrs.length) return { code: 2, errors: schemaErrs.map((e) => `manifest ${e}`), changed, notes }

  const base = dirname(resolve(manifest))
  const entries = [...m.screens.map((e) => ({ ...e, kind: 'screen' })), ...(m.environment || []).map((e) => ({ ...e, kind: 'environment' }))]
  const ids = entries.map((e) => e.id)
  for (const id of new Set(ids)) if (ids.filter((x) => x === id).length > 1) errors.push(`${id}: duplicate id`)

  const log = decisions ? readFileSync(decisions, 'utf8') : null
  let nondeterministic = false
  for (const e of entries) {
    if (log !== null && !mentions(log, e.decision)) errors.push(`${e.id}: decision ${e.decision} not found in ${decisions}`)
    const file = resolve(base, e.png)
    if (!existsSync(file)) errors.push(`${e.id}: baseline file missing (${e.png})`)
    else if (!locked(e.sha256, sha256(file))) errors.push(`${e.id}: baseline file ${e.png} no longer matches its approved hash ${e.sha256} — a baseline changed without owner approval`)

    if (!actual) continue
    const a = join(resolve(actual), `${e.id}.png`)
    if (!existsSync(a)) {
      errors.push(`${e.id}: not rendered (${a})`)
      continue
    }
    const h = sha256(a)
    if (actual2) {
      const b = join(resolve(actual2), `${e.id}.png`)
      if (!existsSync(b) || sha256(b) !== h) {
        nondeterministic = true
        errors.push(`${e.id}: two renders differ — rendering is not deterministic, so no hash can lock it`)
        continue
      }
    }
    if (!locked(e.sha256, h)) {
      changed.push({ id: e.id, kind: e.kind, lockedSha256: e.sha256, actualSha256: h, actual: a, baseline: existsSync(file) ? file : null, design: e.design ? resolve(base, e.design) : null, decision: e.decision, approvedAt: e.approvedAt })
    }
  }
  if (changed.some((c) => c.kind === 'environment')) {
    notes.push('an environment canary changed: the renderer, fonts or device profile moved; screen differences may be environment, not UI — settle that first')
  }
  for (const c of changed) errors.push(`${c.id}: render ${c.actualSha256.slice(0, 12)} differs from approved ${c.lockedSha256.slice(0, 12)}`)
  return { code: nondeterministic ? 2 : errors.length ? 1 : 0, errors, changed, notes }
}

function arg(args, name) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : null
}

function main(argv) {
  const manifest = arg(argv, '--manifest')
  if (!manifest) {
    process.stderr.write('usage: baseline-check.mjs --manifest <file> [--decisions <log>] [--actual <dir>] [--actual2 <dir>] [--changed-out <file>]\n')
    return 2
  }
  const r = checkBaselines({ manifest, decisions: arg(argv, '--decisions'), actual: arg(argv, '--actual'), actual2: arg(argv, '--actual2') })
  const out = arg(argv, '--changed-out')
  if (out) writeFileSync(out, JSON.stringify(r.changed, null, 2) + '\n')
  for (const n of r.notes) process.stdout.write(`NOTE ${n}\n`)
  for (const e of r.errors) process.stdout.write(`FAIL ${e}\n`)
  process.stdout.write(r.code === 0 ? 'baseline-check: PASS\n' : `baseline-check: FAIL (${r.errors.length})\n`)
  return r.code
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = main(process.argv.slice(2))
