#!/usr/bin/env node
// Source: /Users/liyongqiang/.agents/skills/ig-design-system/scripts/contract/validate.mjs; copied 2026-11-17.
// Minimal JSON Schema check for the contract files in ../../schemas, with no
// dependency. Supports the subset those schemas use: type, required,
// properties, items, enum, pattern, minimum, maximum, minLength, minItems,
// maxItems and local $ref (#/$defs/…). Anything else is ignored, so keep the
// schemas inside this subset or use a full validator instead.
//
//   node validate.mjs <schema.json> <file.json> [<file.json> …]
//   exit 0 = valid, 1 = invalid, 2 = usage error
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const typeOf = (v) => (v === null ? 'null' : Array.isArray(v) ? 'array' : Number.isInteger(v) ? 'integer' : typeof v)
const typeOk = (want, v) => {
  const t = typeOf(v)
  return (Array.isArray(want) ? want : [want]).some((w) => w === t || (w === 'number' && t === 'integer'))
}

/** Returns a list of "<json pointer>: <problem>" strings; empty means valid. */
export function validate(schema, value, root = schema, at = '') {
  const errs = []
  if (schema.$ref) {
    const m = schema.$ref.match(/^#\/\$defs\/(.+)$/)
    if (!m || !root.$defs?.[m[1]]) return [`${at || '/'}: unresolved $ref ${schema.$ref}`]
    return validate(root.$defs[m[1]], value, root, at)
  }
  const here = at || '/'
  if (schema.type && !typeOk(schema.type, value)) return [`${here}: expected ${schema.type}, got ${typeOf(value)}`]
  if (schema.enum && !schema.enum.some((e) => JSON.stringify(e) === JSON.stringify(value))) errs.push(`${here}: ${JSON.stringify(value)} not in ${JSON.stringify(schema.enum)}`)
  if (typeof value === 'string') {
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) errs.push(`${here}: "${value}" does not match ${schema.pattern}`)
    if (schema.minLength !== undefined && value.length < schema.minLength) errs.push(`${here}: shorter than ${schema.minLength}`)
  }
  if (typeof value === 'number') {
    if (schema.minimum !== undefined && value < schema.minimum) errs.push(`${here}: ${value} < ${schema.minimum}`)
    if (schema.maximum !== undefined && value > schema.maximum) errs.push(`${here}: ${value} > ${schema.maximum}`)
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) errs.push(`${here}: fewer than ${schema.minItems} items`)
    if (schema.maxItems !== undefined && value.length > schema.maxItems) errs.push(`${here}: more than ${schema.maxItems} items`)
    if (schema.items) value.forEach((v, i) => errs.push(...validate(schema.items, v, root, `${at}/${i}`)))
  }
  if (typeOf(value) === 'object') {
    for (const k of schema.required || []) if (!(k in value)) errs.push(`${here}: missing required "${k}"`)
    for (const [k, s] of Object.entries(schema.properties || {})) if (k in value) errs.push(...validate(s, value[k], root, `${at}/${k}`))
  }
  return errs
}

function main(argv) {
  const [schemaPath, ...files] = argv
  if (!schemaPath || !files.length) {
    process.stderr.write('usage: validate.mjs <schema.json> <file.json> [...]\n')
    return 2
  }
  const schema = JSON.parse(readFileSync(schemaPath, 'utf8'))
  let bad = 0
  for (const f of files) {
    const errs = validate(schema, JSON.parse(readFileSync(f, 'utf8')))
    if (errs.length) {
      bad++
      process.stdout.write(`INVALID ${f}\n${errs.map((e) => `  ${e}`).join('\n')}\n`)
    } else process.stdout.write(`valid ${f}\n`)
  }
  return bad ? 1 : 0
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = main(process.argv.slice(2))
