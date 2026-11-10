import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const sourceDir = path.join(root, 'design/m1-b-hifi/icons');
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const names = fs.readdirSync(sourceDir).filter(n => n.endsWith('.svg')).sort();
assert.equal(names.length, 21);
const records = [];
for (const file of names) {
  const bytes = fs.readFileSync(path.join(sourceDir, file));
  const svg = bytes.toString('utf8');
  assert(svg.includes('viewBox="0 0 24 24"'));
  assert(!/<(?:circle|rect|ellipse|polygon|polyline|line|use|image)\b|transform=/.test(svg));
  const group = svg.match(/<g\s+([^>]+)>/)?.[1] ?? '';
  const attrs = text => Object.fromEntries([...text.matchAll(/([\w-]+)="([^"]*)"/g)].map(m => [m[1], m[2]]));
  const paths = [...svg.matchAll(/<path\s+([^>]+)\/>/g)].map(m => ({...attrs(group), ...attrs(m[1])}));
  assert(paths.length > 0);
  const rendered = paths.map(a => {
    assert(a.d && !a.d.includes('&'));
    assert(['none', '#2A2822'].includes(a.fill));
    const fill = a.fill === 'none' ? '#00000000' : '#FFFFFFFF';
    if (a.fill !== 'none') assert.equal(file, 'kettlebell.svg');
    if (a.stroke) {
      assert.equal(a.stroke, '#2A2822'); assert.equal(a['stroke-width'], '2');
      assert.equal(a['stroke-linecap'], 'round'); assert.equal(a['stroke-linejoin'], 'round');
    }
    return `    <path android:pathData="${a.d}" android:fillColor="${fill}"${a.stroke ? ' android:strokeColor="#FFFFFFFF" android:strokeWidth="2" android:strokeLineCap="round" android:strokeLineJoin="round"' : ''} />`;
  });
  const xml = `<?xml version="1.0" encoding="utf-8"?>\n<!-- FineCoach product-owned equipment artwork; design/m1-b-hifi/icons/${file}. Paths retained verbatim. -->\n<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">\n${rendered.join('\n')}\n</vector>\n`;
  const drawable = `app/src/main/res/drawable/ic_equipment_${file.replace('.svg', '').replaceAll('-', '_')}.xml`;
  fs.writeFileSync(path.join(root, 'android', drawable), xml);
  records.push({name: file.replace('.svg',''), source: `design/m1-b-hifi/icons/${file}`, sourceSha256: digest(bytes), drawable, drawableSha256: digest(xml), paths: paths.length});
}
fs.writeFileSync(path.join(here, 'equipment-provenance.json'), JSON.stringify({ owner: 'FineCoach', provenance: 'design/design-system/README.md §7.1; product-owned artwork; no third-party Material license applies', conversion: 'Path data retained verbatim; inherited group attributes expanded; white template tint; 24dp viewport; 2px round strokes; kettlebell body is the only fill', icons: records }, null, 2)+'\n');
fs.writeFileSync(path.join(here, 'equipment-SHA256SUMS'), records.flatMap(r => [`${r.sourceSha256}  ${r.source}`, `${r.drawableSha256}  android/${r.drawable}`]).join('\n')+'\n');
fs.writeFileSync(path.join(here, 'equipment-manifest.txt'), '# Product-owned equipment SVG → Android vector; see equipment-provenance.json\n'+records.map(r=>`${r.name} | ${r.source} | ${r.drawable}`).join('\n')+'\n');
console.log(`Verified and converted ${records.length} product-owned equipment SVGs.`);
