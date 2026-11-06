#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir, mkdtemp, readdir, rm } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const packagePath = 'com/ignacioli/finecoach/designsystem';
const fail = (message) => { throw new Error(message); };
const quoted = (text) => JSON.stringify(text);
const camel = (id) => id.replace(/^color\./, '').replace(/\.([a-z0-9])/g, (_, c) => c.toUpperCase());
const number = (text, label) => {
  if (!/^(?:0|[1-9]\d*)(?:\.\d+)?$/.test(text)) fail(`${label}: invalid number ${text}`);
  const value = Number(text);
  if (!Number.isFinite(value) || value <= 0) fail(`${label}: expected positive finite number`);
  return value;
};
const literal = (value) => Number.isInteger(value) ? `${value}.0` : String(value);

// Locate by section number and exact header, never by source line number.
function table(lines, section, headers) {
  const heading = new RegExp(`^#{2,3} ${section.replaceAll('.', '\\.')}\\.?(?: |$)`);
  const starts = lines.flatMap((line, i) => heading.test(line) ? [i] : []);
  if (starts.length !== 1) fail(`§${section}: expected exactly one section, found ${starts.length}`);
  const start = starts[0];
  let end = start + 1;
  while (end < lines.length && !/^#{1,3} /.test(lines[end])) end++;
  const source = lines.slice(start + 1, end);
  const tableStarts = source.flatMap((line, i) => /^\s*\|/.test(line) && (i === 0 || !/^\s*\|/.test(source[i - 1])) ? [i] : []);
  if (tableStarts.length !== 1) fail(`§${section}: malformed table structure: expected exactly one table, found ${tableStarts.length}`);
  const offset = tableStarts[0];
  const cells = (line) => {
    if (!/^\s*\|.*\|\s*$/.test(line)) fail(`§${section}: malformed table row`);
    return line.trim().slice(1, -1).split('|').map((cell) => cell.trim());
  };
  const actual = cells(source[offset]);
  if (JSON.stringify(actual) !== JSON.stringify(headers)) fail(`§${section}: unknown/missing/reordered columns: ${actual.join(', ')}`);
  const separator = cells(source[offset + 1] ?? '');
  if (separator.length !== headers.length || !separator.every((cell) => /^:?-{3,}:?$/.test(cell))) fail(`§${section}: malformed table separator`);
  const rows = [];
  let i = offset + 2;
  for (; i < source.length && /^\s*\|/.test(source[i]); i++) {
    const row = cells(source[i]);
    if (row.length !== headers.length) fail(`§${section}: malformed row column count`);
    rows.push(row);
  }
  // A dropped pipe must not silently truncate a table.
  if (i < source.length && source[i].trim() !== '') fail(`§${section}: malformed or unterminated table`);
  if (!rows.length) fail(`§${section}: empty table`);
  return { rows, location: `§${section} lines ${start + offset + 2}-${start + i + 1}` };
}

function identifier(text, pattern, label) {
  const match = /^`([^`]+)`$/.exec(text);
  if (!match || !pattern.test(match[1])) fail(`${label}: malformed identifier ${text}`);
  return match[1];
}
function unique(entries, label) {
  const seen = new Set();
  for (const entry of entries) {
    if (seen.has(entry.id)) fail(`${label}: duplicate definition ${entry.id}`);
    seen.add(entry.id);
  }
  return entries;
}
function color(text, label) {
  const match = /^`(#[A-Fa-f0-9]{6})`(?: @ (\d+(?:\.\d+)?)%)?$/.exec(text);
  if (!match) fail(`${label}: malformed color ${text}`);
  const opacity = match[2] === undefined ? 1 : Number(match[2]) / 100;
  if (opacity < 0 || opacity > 1) fail(`${label}: opacity out of range`);
  return { hex: match[1].toUpperCase(), opacity };
}
const colorValue = ({ hex, opacity }) => `Color(0xFF${hex.slice(1)})${opacity === 1 ? '' : `.copy(alpha = ${literal(opacity)}f)`}`;

export function generateTokens(input) {
  const lines = input.split(/\r?\n/);
  const primitiveTable = table(lines, '2.1', ['Token', '值', '备注']);
  const semanticTable = table(lines, '2.2', ['语义 Token', '引用', '值', '画稿中的实际用途']);
  const scaleTable = table(lines, '3.2', ['样式', '字号 / 字重', '行高', '允许的字重变体（画稿实测）', '缩放基准', '画稿用途']);
  const exceptionTable = table(lines, '3.3', ['样式', '字号 / 字重', '行高', '缩放基准', '画稿用途']);
  const spacingTable = table(lines, '4', ['Token', '值']);
  const shapeTable = table(lines, '5', ['Token', '值', '画稿用途']);
  const primitives = unique(primitiveTable.rows.map(([id, value]) => ({ id: identifier(id, /^color\.[a-z][a-zA-Z0-9]*(?:\.[a-zA-Z0-9]+)+$/, 'primitive'), ...color(value, id) })), 'primitives');
  const semantic = unique(semanticTable.rows.map(([id, reference, value]) => ({ id: identifier(id, /^color\.[a-z][a-zA-Z0-9]*(?:\.[a-zA-Z0-9]+)+$/, 'semantic'), reference, ...color(value, id) })), 'semantic');
  unique([...primitives, ...semantic], 'colors');
  unique([...primitives, ...semantic].map((item) => ({ id: camel(item.id) })), 'Kotlin properties');
  for (const item of semantic) {
    if (/^—（[^）]+）$/.test(item.reference)) continue;
    const reference = /^([a-zA-Z0-9]+(?:\.[a-zA-Z0-9]+)+)(?: (\d+(?:\.\d+)?)% 不透明度)?$/.exec(item.reference);
    if (!reference) fail(`${item.id}: malformed alias ${item.reference}`);
    const target = [...primitives, ...semantic].find(({ id }) => id === `color.${reference[1]}`);
    if (!target || target === item) fail(`${item.id}: unresolved/self alias ${item.reference}`);
    const opacity = reference[2] === undefined ? target.opacity : Number(reference[2]) / 100;
    if (target.hex !== item.hex || opacity !== item.opacity) fail(`${item.id}: alias/value mismatch`);
  }
  const styleRow = (row, main) => {
    const id = identifier(row[0], /^[a-z][a-zA-Z0-9]*$/, 'style');
    const sizeWeight = /^(\d+(?:\.\d+)?) \/ (400|500|600|700)$/.exec(row[1]);
    if (!sizeWeight) fail(`${id}: malformed size / weight`);
    const size = number(sizeWeight[1], id);
    const weight = Number(sizeWeight[2]);
    const multiplier = number(row[2], id);
    const scalingBase = row[main ? 4 : 3];
    if (!['largeTitle', 'title1', 'title2', 'title3', 'headline', 'body', 'callout', 'footnote', 'subheadline'].includes(scalingBase)) fail(`${id}: unknown scaling base`);
    const variants = main ? row[3] : '—';
    if (!/^(?:—|(?:400|500|600|700)(?:、(?:400|500|600|700))*|(?:400|500|600|700) → `[a-z][a-zA-Z0-9]*`)$/.test(variants)) fail(`${id}: malformed weight variants`);
    const allowed = [weight];
    if (variants !== '—') allowed.push(...variants.match(/\d{3}/g).map(Number));
    if (!main && id === 'compact') {
      if (!row[4].includes('选中/今天用 600')) fail('compact: missing approved selected/today weight rule');
      allowed.push(600);
    }
    return { id, size, weight, multiplier, variants, allowed: [...new Set(allowed)], scalingBase };
  };
  const styles = unique([...scaleTable.rows.map((row) => styleRow(row, true)), ...exceptionTable.rows.map((row) => styleRow(row, false))], 'styles');
  if (styles.length !== 14 || scaleTable.rows.length !== 7 || exceptionTable.rows.length !== 7) fail('typography: expected 7 scale + 7 named styles');
  for (const style of styles) {
    const named = /^(\d{3}) → `([a-z][a-zA-Z0-9]*)`$/.exec(style.variants);
    if (named) {
      const target = styles.find(({ id }) => id === named[2]);
      if (!target || target.weight !== Number(named[1]) || target.size !== style.size || target.multiplier !== style.multiplier || target.scalingBase !== style.scalingBase) fail(`${style.id}: named variant mismatch`);
    }
  }
  const spacing = unique(spacingTable.rows.map(([token, value]) => ({ id: identifier(token, /^space\.[1-9]\d*$/, 'spacing'), value: number(value, token) })), 'spacing');
  if (spacing.length !== 6) fail('spacing: expected six scale tokens');
  const shapes = unique(shapeTable.rows.map(([token, value]) => {
    const id = identifier(token, /^radius\.[a-z][a-zA-Z0-9]*$/, 'radius');
    if (id === 'radius.capsule') {
      if (value !== '高度 / 2') fail('radius.capsule: expected 高度 / 2');
      return { id, value: null };
    }
    return { id, value: number(value, token) };
  }), 'radius');
  if (shapes.length !== 6 || !shapes.some(({ id }) => id === 'radius.capsule')) fail('radius: expected five fixed radii and capsule');
  // These textual policies are not another numeric token source. Fail on drift
  // rather than guessing a replacement font, tracking or scaling strategy.
  for (const policy of ['Noto Sans SC', 'NotoSansSC-VF.otf', 'SIL OFL 1.1', '字距一律为 0', '## 15. Android 映射规则', 'letterSpacing=0.sp', 'lineHeight=(s × m).sp', 'RoundedCornerShape(percent=50)']) {
    if (!input.includes(policy)) fail(`Missing approved mapping policy: ${policy}`);
  }
  const digest = createHash('sha256').update(input).digest('hex');
  const header = (tables) => `// Generated by scripts/android/generate-tokens.mjs; DO NOT EDIT.\n// Source: design/design-system/README.md; SHA-256: ${digest}\n${tables.map(({ location }) => `// ${location}`).join('\n')}\npackage com.ignacioli.finecoach.designsystem\n\n`;
  const map = (items, expression) => `mapOf(\n${items.map((item) => `        ${quoted(item.id)} to ${expression(item)},`).join('\n')}\n    )`;
  const files = {};
  files['FcColors.kt'] = header([primitiveTable, semanticTable]) + `import androidx.compose.ui.graphics.Color\n\nobject FcColors {\n${[...primitives, ...semantic].map((item) => `    val ${camel(item.id)} = ${colorValue(item)}`).join('\n')}\n\n    val primitives: Map<String, Color> = ${map(primitives, (item) => camel(item.id))}\n    val semantic: Map<String, Color> = ${map(semantic, (item) => camel(item.id))}\n    // The approved palette is invariant across appearance; no dark values are invented.\n    val light: Map<String, Color> = semantic\n    val dark: Map<String, Color> = semantic\n}\n`;
  files['FcTypography.kt'] = header([scaleTable, exceptionTable]) + `import androidx.compose.ui.text.TextStyle\nimport androidx.compose.ui.text.font.FontWeight\nimport androidx.compose.ui.text.font.FontSynthesis\nimport androidx.compose.ui.unit.sp\n\nobject FcTypography {\n${styles.map((item) => `    val ${item.id} = TextStyle(\n        fontFamily = FcFontFamily,\n        fontWeight = FontWeight(${item.weight}),\n        fontSize = ${literal(item.size)}.sp,\n        lineHeight = ${literal(Number((item.size * item.multiplier).toPrecision(12)))}.sp,\n        letterSpacing = 0.sp,\n        fontSynthesis = FontSynthesis.None,\n    )`).join('\n')}\n    val styles: Map<String, TextStyle> = ${map(styles, (item) => item.id)}\n    val allowedWeights: Map<String, Set<Int>> = ${map(styles, (item) => `setOf(${item.allowed.join(', ')})`)}\n    val lineHeightMultipliers: Map<String, Float> = ${map(styles, (item) => `${literal(item.multiplier)}f`)}\n\n    fun style(name: String, weight: Int): TextStyle {\n        require(name in styles) { "Unknown text style: $name" }\n        require(weight in allowedWeights.getValue(name)) { "Unapproved weight for $name: $weight" }\n        return styles.getValue(name).copy(fontWeight = FontWeight(weight))\n    }\n}\n`;
  files['FcSpacing.kt'] = header([spacingTable]) + `import androidx.compose.ui.unit.Dp\nimport androidx.compose.ui.unit.dp\n\nobject FcSpacing {\n${spacing.map((item) => `    val ${camel(item.id)} = ${literal(item.value)}.dp`).join('\n')}\n    val values: Map<String, Dp> = ${map(spacing, (item) => camel(item.id))}\n}\n`;
  const fixedShapes = shapes.filter(({ value }) => value !== null);
  files['FcShapes.kt'] = header([shapeTable]) + `import androidx.compose.foundation.shape.RoundedCornerShape\nimport androidx.compose.ui.unit.Dp\nimport androidx.compose.ui.unit.dp\n\nobject FcShapes {\n${fixedShapes.map((item) => `    val ${item.id.slice(7)} = ${literal(item.value)}.dp`).join('\n')}\n    val capsule = RoundedCornerShape(percent = 50)\n    val radii: Map<String, Dp> = ${map(fixedShapes, (item) => item.id.slice(7))}\n}\n`;
  return files;
}

async function writeOutput(directory, files) {
  const destination = join(directory, packagePath);
  await mkdir(destination, { recursive: true });
  for (const [name, content] of Object.entries(files)) await writeFile(join(destination, name), content);
}

async function kotlinFiles(directory, prefix = '') {
  const result = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(prefix, entry.name);
    if (entry.isDirectory()) result.push(...await kotlinFiles(join(directory, entry.name), path));
    else result.push(path);
  }
  return result.sort();
}

export async function run(args) {
  let input = join(root, 'design/design-system/README.md');
  let output = join(root, 'android/app/build/generated/designtokens');
  let check = false;
  const seen = new Set();
  for (let i = 0; i < args.length; i++) {
    const option = args[i];
    if (seen.has(option)) fail(`Duplicate option: ${option}`);
    seen.add(option);
    if (option === '--check') check = true;
    else if (['--input', '--output'].includes(option)) {
      const value = args[++i];
      if (!value || value.startsWith('--')) fail(`Missing value for ${option}`);
      if (option === '--input') input = resolve(value);
      else output = resolve(value);
    } else fail(`Unknown option: ${option}`);
  }
  const files = generateTokens(await readFile(input, 'utf8'));
  if (check) {
    const temporary = await mkdtemp(join(tmpdir(), 'finecoach-token-check-'));
    try {
      await writeOutput(temporary, files);
      const expected = await kotlinFiles(temporary);
      const actual = await kotlinFiles(output);
      if (JSON.stringify(actual) !== JSON.stringify(expected)) fail('Generated file inventory differs; run generateDesignTokens');
      for (const name of expected) {
        if (!(await readFile(join(temporary, name))).equals(await readFile(join(output, name)))) fail(`Generated token changed: ${name}`);
      }
    } finally { await rm(temporary, { recursive: true, force: true }); }
    console.log(`Design tokens match: ${output} (4 files)`);
  } else {
    await writeOutput(output, files);
    console.log(`Generated design tokens: ${output} (4 files)`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  run(process.argv.slice(2)).catch((error) => { console.error(`generate-tokens: ${error.message}`); process.exitCode = 1; });
}
