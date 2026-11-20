// FineCoach S2 adapter, 2026-11-17. Uses the vendored ig-design-system baseline checker.
// Existing conformance suites already render twice. Their stability hashes are
// witnesses for both renders, including suites that retain only the final PNG.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { checkBaselines, sha256 } from './baseline-check.mjs';

const [manifestPath, decisions, reportPath, pngPath, screenID, out] = process.argv.slice(2);
if (![manifestPath, decisions, reportPath, pngPath, screenID, out].every(Boolean)) throw Error('manifest decisions report png screen out required');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
const full = checkBaselines({ manifest: manifestPath, decisions });
if (full.code) { process.stderr.write(full.errors.join('\n') + '\n'); process.exit(full.code); }
const entry = manifest.screens.find(e => e.id === screenID);
if (!entry) throw Error('Unregistered core screen');
const report = JSON.parse(readFileSync(reportPath, 'utf8'));
const hashes = report.stability?.sha256;
if (report.stability?.renderCount !== 2 || report.stability?.stable !== true || !Array.isArray(hashes) || hashes.length !== 2 || hashes[0] !== hashes[1]) throw Error('Missing or non-deterministic dual-render evidence');
if (sha256(pngPath) !== hashes[0]) throw Error('PNG does not match both witnessed render hashes');
mkdirSync(out, { recursive: true });
const actual = join(out, 'actual'), actual2 = join(out, 'actual2');
mkdirSync(actual, { recursive: true }); mkdirSync(actual2, { recursive: true });
// Preserve raw run PNGs when the suite emits them. Otherwise recover the exact
// bytes from the final PNG, after checking its digest against BOTH render hashes.
for (const [run, destination] of [[1, actual], [2, actual2]]) {
    const raw = pngPath.replace(/\.android\.png$/, `.run${run}.png`);
    const source = existsSync(raw) ? raw : pngPath;
    if (sha256(source) !== hashes[run - 1]) throw Error('Raw render hash mismatch');
    writeFileSync(join(destination, `${screenID}.png`), readFileSync(source));
}
const subset = join(out, 'manifest.json');
writeFileSync(subset, JSON.stringify({ ...manifest, environment: [], screens: [{ ...entry, png: resolve(dirname(manifestPath), entry.png) }] }));
const result = checkBaselines({ manifest: subset, decisions, actual, actual2 });
writeFileSync(join(out, 'changed.json'), JSON.stringify(result.changed, null, 2) + '\n');
writeFileSync(join(out, 'result.json'), JSON.stringify({ ...result, screenID, report: resolve(reportPath), hashes }, null, 2) + '\n');
process.stdout.write(result.code ? result.errors.join('\n') + '\n' : `baseline-check: PASS ${screenID}\n`);
process.exitCode = result.code;
