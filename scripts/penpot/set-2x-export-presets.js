// Sets one export preset (PNG, 2x, no suffix) on every top-level board of
// every page in the open Penpot file, then re-reads each board to verify.
//
// Run it in the Penpot plugin context, e.g. pasted into the Penpot MCP
// `execute_code` tool with the file "M1-B G5 Design" open. Boards whose name
// starts with an entry of SKIP_PREFIXES keep their current presets (rejected
// options that must not end up in the export zip).
//
// The plugin API can only modify shapes on the active page, so each page is
// opened before it is touched.

const SKIP_PREFIXES = ['AppIcon'];
const PRESET = { type: 'png', scale: 2, suffix: '' };

const isWanted = (exports) =>
  (exports || []).length === 1 &&
  exports[0].type === PRESET.type &&
  exports[0].scale === PRESET.scale &&
  !exports[0].suffix;

const boardsOf = () =>
  penpot.currentPage.root.children.filter(
    (shape) => shape.type === 'board' && !SKIP_PREFIXES.some((p) => shape.name.startsWith(p))
  );

const startPage = penpot.currentPage;
const changed = [];
const failed = [];

for (const page of penpot.currentFile.pages) {
  await penpot.openPage(page);
  for (const board of boardsOf()) {
    if (!isWanted(board.exports)) {
      board.exports = [{ ...PRESET }];
      changed.push(`${page.name} | ${board.name}`);
    }
  }
}

// A try/catch once hid a failed assignment, so verify by reading back.
for (const page of penpot.currentFile.pages) {
  await penpot.openPage(page);
  for (const board of boardsOf()) {
    if (!isWanted(board.exports)) failed.push(`${page.name} | ${board.name}`);
  }
}

await penpot.openPage(startPage);
return { changed: changed.length, failed };
