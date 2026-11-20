#!/usr/bin/env node
// Source: /Users/liyongqiang/.agents/skills/ig-design-system/scripts/baseline/compare-page.mjs; copied 2026-11-17.
// One self-contained HTML page with a "design | implementation | difference"
// row for each screen whose render no longer matches its approved hash
// (the changed.json that baseline-check.mjs writes). The owner reviews the
// page once and approves or rejects the batch; the page approves nothing.
//
//   node compare-page.mjs --changed <changed.json> --out <compare.html> [--diff-dir <dir>] [--title <text>]
//
// Images are embedded as data URIs, so the page opens from disk and the
// in-page canvas difference works without a server. A comparer's own
// difference map, <diff-dir>/<id>.diff.png, is used instead when present.
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])
const dataUri = (file) => (file && existsSync(file) ? `data:image/png;base64,${readFileSync(file).toString('base64')}` : null)

export function comparePage(changed, { diffDir = null, title = 'Baseline changes for owner review', today = new Date().toISOString().slice(0, 10) } = {}) {
  const rows = changed.map((c) => {
    const design = dataUri(c.design)
    const impl = dataUri(c.actual)
    const diffFile = diffDir ? join(resolve(diffDir), `${c.id}.diff.png`) : null
    const diff = dataUri(diffFile)
    const cell = (label, src, extra = '') =>
      `<figure><figcaption>${label}</figcaption>${src ? `<img alt="${esc(label)} ${esc(c.id)}" src="${src}"${extra}>` : '<p class="missing">not available</p>'}</figure>`
    const diffCell = diff
      ? cell('difference (comparer)', diff)
      : design && impl
        ? `<figure><figcaption>difference (pixels that differ)</figcaption><canvas data-design="d-${esc(c.id)}" data-impl="i-${esc(c.id)}"></canvas></figure>`
        : cell('difference', null)
    return `<section>
<h2>${esc(c.id)} <small>${esc(c.kind)}</small></h2>
<p class="hash">approved <code>${esc(c.lockedSha256.slice(0, 12))}</code> (${esc(c.decision)}, ${esc(c.approvedAt)}) → now <code>${esc(c.actualSha256.slice(0, 12))}</code></p>
<div class="row">${cell('design', design, ` id="d-${esc(c.id)}"`)}${cell('implementation', impl, ` id="i-${esc(c.id)}"`)}${diffCell}</div>
</section>`
  })
  const proposal = changed.map((c) => ({ id: c.id, sha256: c.actualSha256, approvedAt: today, decision: '<owner decision id>' }))
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Baseline review</title>
<style>
:root{--bg:#fff;--fg:#1b1b1b;--muted:#666;--line:#ddd}
@media (prefers-color-scheme: dark){:root{--bg:#141414;--fg:#eee;--muted:#aaa;--line:#333}}
body{background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,sans-serif;margin:0;padding:16px}
h1{font-size:20px}h2{font-size:16px;margin:24px 0 4px}small{color:var(--muted);font-weight:400}
.row{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}
@media (max-width:720px){.row{grid-template-columns:1fr}}
figure{margin:0;border:1px solid var(--line);padding:8px}figcaption{color:var(--muted);margin-bottom:4px}
img,canvas{max-width:100%;height:auto;display:block}.hash{color:var(--muted)}.missing{color:#c33}
pre{border:1px solid var(--line);padding:8px;overflow:auto}
</style></head><body>
<h1>${esc(title)}</h1>
<p>${changed.length} screen(s) no longer match their approved hash. This page approves nothing: the owner approves or rejects the batch, then records the new hashes in the manifest with one decision id.</p>
${rows.join('\n')}
<h2>Manifest update the owner records after approving</h2>
<pre>${esc(JSON.stringify(proposal, null, 2))}</pre>
<script>
for (const c of document.querySelectorAll('canvas[data-design]')) {
  const a = document.getElementById(c.dataset.design), b = document.getElementById(c.dataset.impl)
  const draw = () => {
    if (!a.complete || !b.complete) return
    const w = Math.max(a.naturalWidth, b.naturalWidth), h = Math.max(a.naturalHeight, b.naturalHeight)
    c.width = w; c.height = h
    const read = (img) => { const t = document.createElement('canvas'); t.width = w; t.height = h; const g = t.getContext('2d'); g.drawImage(img, 0, 0, w, h); return g.getImageData(0, 0, w, h).data }
    const p = read(a), q = read(b), g = c.getContext('2d'), out = g.createImageData(w, h)
    let n = 0
    for (let i = 0; i < p.length; i += 4) {
      const d = Math.abs(p[i] - q[i]) + Math.abs(p[i + 1] - q[i + 1]) + Math.abs(p[i + 2] - q[i + 2])
      if (d > 24) { out.data[i] = 230; out.data[i + 1] = 40; out.data[i + 2] = 40; out.data[i + 3] = 255; n++ }
      else { const y = (q[i] + q[i + 1] + q[i + 2]) / 3; out.data[i] = out.data[i + 1] = out.data[i + 2] = 200 + y / 5; out.data[i + 3] = 255 }
    }
    g.putImageData(out, 0, 0)
    c.insertAdjacentHTML('afterend', '<p class="hash">' + (100 * n / (w * h)).toFixed(2) + '% of pixels differ</p>')
  }
  a.addEventListener('load', draw); b.addEventListener('load', draw); draw()
}
</script>
</body></html>
`
}

function arg(args, name) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : null
}

function main(argv) {
  const changedPath = arg(argv, '--changed')
  const out = arg(argv, '--out')
  if (!changedPath || !out) {
    process.stderr.write('usage: compare-page.mjs --changed <changed.json> --out <file.html> [--diff-dir <dir>] [--title <text>]\n')
    return 2
  }
  const changed = JSON.parse(readFileSync(changedPath, 'utf8'))
  if (!changed.length) {
    process.stdout.write('compare-page: nothing changed, no page written\n')
    return 0
  }
  writeFileSync(out, comparePage(changed, { diffDir: arg(argv, '--diff-dir'), title: arg(argv, '--title') ?? undefined }))
  process.stdout.write(`compare-page: ${changed.length} screen(s) → ${out}\n`)
  return 0
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = main(process.argv.slice(2))
