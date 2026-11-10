import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

// Convert only the reviewed, path-only SVG subset; reject new shapes/transforms.
const here = path.dirname(fileURLToPath(import.meta.url));
const input = process.argv[2];
assert(input, 'Pass the host asset directory containing SVG, SOURCE.txt, SHA256SUMS and LICENSE');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const source = fs.readFileSync(path.join(input, 'SOURCE.txt'), 'utf8');
const commit = source.match(/@ ([0-9a-f]{40})\b/)?.[1];
assert.equal(commit, '10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7');
const sums = new Map(fs.readFileSync(path.join(input, 'SHA256SUMS'), 'utf8').trim().split('\n').map(line => {
  const match = line.match(/^([0-9a-f]{64})  ([a-z_]+\.svg|LICENSE)$/);
  assert(match, `Unexpected checksum row: ${line}`);
  return [match[2], match[1]];
}));
assert.equal(sums.size, 20);
const rows = fs.readFileSync(path.join(here, 'material-symbols-manifest.txt'), 'utf8').split('\n')
  .filter(line => line && !line.startsWith('#')).map(line => line.split('|').map(s => s.trim()));
assert.equal(rows.length, 19);
const drawableDir = path.resolve(here, '../app/src/main/res/drawable');
const originals = path.join(here, 'material-symbols-svg');
fs.mkdirSync(drawableDir, { recursive: true });
fs.mkdirSync(originals, { recursive: true });
const records = [];
for (const [name, styleWeight, iosSymbol, components] of rows) {
  assert(/^[a-z_]+$/.test(name));
  const [style, weight] = styleWeight.split('/');
  const filled = name.endsWith('_filled');
  const upstreamName = name.replace(/_filled$/, '');
  assert.equal(style, 'outlined');
  assert(['300', '400', '600'].includes(weight));
  const filename = `${name}.svg`;
  const bytes = fs.readFileSync(path.join(input, filename));
  assert.equal(sha(bytes), sums.get(filename), `${filename} checksum mismatch`);
  const svg = bytes.toString('utf8').trim();
  assert(/^<svg\s[^>]*>\s*(?:<path d="[^"<>]+"\s*\/>\s*)+<\/svg>$/.test(svg), `Unsupported SVG: ${filename}`);
  assert(svg.includes('viewBox="0 -960 960 960"'));
  assert(svg.includes('height="24"') && svg.includes('width="24"'));
  const paths = [...svg.matchAll(/<path d="([^"<>]+)"\s*\/>/g)].map(match => match[1]);
  assert(paths.length > 0 && paths.every(d => !d.includes('&')));
  const xml = `<?xml version="1.0" encoding="utf-8"?>\n<!-- Material Symbols by Google; Apache-2.0. Source and conversion: android/design-assets/. -->\n<vector xmlns:android="http://schemas.android.com/apk/res/android"\n    android:width="24dp" android:height="24dp"\n    android:viewportWidth="960" android:viewportHeight="960">\n    <group android:translateY="960">\n${paths.map(d => `        <path android:fillColor="@android:color/white" android:pathData="${d}" />`).join('\n')}\n    </group>\n</vector>\n`;
  const drawable = `ic_ms_${name}.xml`;
  fs.writeFileSync(path.join(drawableDir, drawable), xml);
  fs.writeFileSync(path.join(originals, filename), bytes);
  records.push({ symbol: name, style, weight: Number(weight), fill: filled ? 1 : 0, iosSymbol, components: components.split(','),
    sourceSvg: `material-symbols-svg/${filename}`, sourceSha256: sums.get(filename), upstreamCommit: commit,
    upstreamPath: `symbols/web/${upstreamName}/materialsymbolsoutlined/${upstreamName}${weight === '400' ? '' : `_wght${weight}`}${filled ? (weight === '400' ? '_fill1' : 'fill1') : ''}_24px.svg`,
    drawable: `app/src/main/res/drawable/${drawable}`, drawableSha256: sha(xml) });
}
const license = fs.readFileSync(path.join(input, 'LICENSE'));
assert.equal(sha(license), sums.get('LICENSE'));
fs.writeFileSync(path.join(here, 'material-symbols-LICENSE.txt'), license);
fs.copyFileSync(path.join(input, 'SOURCE.txt'), path.join(here, 'material-symbols-SOURCE.txt'));
fs.copyFileSync(path.join(input, 'SHA256SUMS'), path.join(here, 'material-symbols-SHA256SUMS'));
fs.writeFileSync(path.join(here, 'material-symbols-provenance.json'), JSON.stringify({
  upstreamRepository: 'https://github.com/google/material-design-icons', upstreamCommit: commit,
  license: 'Apache-2.0', licenseSha256: sha(license), icons: records,
}, null, 2) + '\n');
const packaged = path.resolve(here, '../app/src/main/assets/licenses');
fs.mkdirSync(packaged, { recursive: true });
fs.writeFileSync(path.join(packaged, 'material-symbols-LICENSE.txt'), license);
const notice = `Material Symbols by Google\nSource: https://github.com/google/material-design-icons\nCommit: ${commit}\nLicensed under the Apache License, Version 2.0.\nSee material-symbols-LICENSE.txt for the full license.\nModified for Android: SVG paths retained verbatim; converted to vector drawable,\nY translated by 960; white placeholder fill colored by Compose tint.\n`;
fs.writeFileSync(path.join(packaged, 'material-symbols-NOTICE.txt'), notice);
fs.writeFileSync(path.join(here, 'material-symbols-NOTICE.txt'), notice);
console.log(`Verified ${records.length} SVG SHA-256 values and LICENSE; wrote ${records.length} vectors and provenance.`);
console.log(`Packaged license SHA-256: ${sha(license)}; notice SHA-256: ${sha(notice)}`);
