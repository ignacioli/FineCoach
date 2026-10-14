#!/usr/bin/env python3
"""Copy a Penpot board-export zip over design/*/screens/*.png.

Penpot names each PNG after its board ("D8 训练中 · 就地入口（新建分区）.png").
The first token of the board name is its code; this script maps the code to
the existing screen file and overwrites it. A board without a known screen
file (rejected options, boards awaiting review) is listed and skipped, never
written under a new name.

Usage:
  scripts/penpot/import-penpot-exports.py <export.zip> [CODE ...]
  scripts/penpot/import-penpot-exports.py <export.zip> 10 11 D3a M2-13 --dry-run

With CODEs, only those boards are imported (codes as in the board name: 10,
D8, M2-13, W-02). Without CODEs every mapped board is imported, except the
boards listed in SHADOW_BOARDS: their exports must be taken with the display
shadow removed (design-system README §1.1), so pass them explicitly, or with
--include-shadow-boards, once the shadow is off.

Every PNG is checked to be a 2x export (width 780, or 1120 for 17) before
anything is written, so a 1x zip is rejected as a whole.
"""

import argparse
import re
import struct
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
M1_SCREENS = REPO / "design/m1-b-hifi/screens"
M2_SCREENS = REPO / "design/m2-hifi/screens"

# Board code -> screen number for the D-series boards (design-system README
# §1.2 table). 01-17 map to their own number.
D_CODES = {
    "D1": "18", "D2a": "19", "D2b": "20", "D3a": "21", "D3b": "22",
    "D4": "23", "D4b": "24", "D5": "25", "D6": "26", "D6b": "27",
    "D7a": "28", "D7b": "29", "D8": "30", "D8c": "31", "D9": "32",
    "D2c": "33", "D2d": "34", "D12": "35", "D13a": "36", "D13b": "37",
    "D14": "38", "D14b": "39", "D15a": "40", "D15b": "41", "D15c": "42",
    "D15d": "43",
}
SHADOW_BOARDS = {"04", "06", "07", "08", "12"}
EXPECTED_WIDTH = {"17": 1120}
DEFAULT_WIDTH = 780


def png_size(data: bytes) -> tuple[int, int]:
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    return struct.unpack(">II", data[16:24])


def target_for(code: str) -> Path | None:
    if re.fullmatch(r"(M2|W)-\d+[a-z]?", code):
        matches = sorted(M2_SCREENS.glob(f"{code}-*.png"))
    else:
        number = D_CODES.get(code, code if re.fullmatch(r"\d{2}", code) else None)
        matches = sorted(M1_SCREENS.glob(f"{number}-*.png")) if number else []
    return matches[0] if len(matches) == 1 else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("zip", type=Path)
    parser.add_argument("codes", nargs="*")
    parser.add_argument("--include-shadow-boards", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    wanted = set(args.codes)
    planned: list[tuple[str, Path, bytes]] = []
    skipped: list[str] = []
    errors: list[str] = []

    with zipfile.ZipFile(args.zip) as archive:
        for entry in archive.namelist():
            name = Path(entry).name
            if not name.lower().endswith(".png") or name.startswith("._"):
                continue
            code = name.split(" ", 1)[0].removesuffix(".png")
            if wanted and code not in wanted:
                continue
            if not wanted and code in SHADOW_BOARDS and not args.include_shadow_boards:
                skipped.append(f"{name} (shadow board; pass {code} explicitly once its shadow is off)")
                continue
            target = target_for(code)
            if target is None:
                skipped.append(f"{name} (no single existing screen file for code {code})")
                continue
            data = archive.read(entry)
            width, height = png_size(data)
            expected = EXPECTED_WIDTH.get(code, DEFAULT_WIDTH)
            if width != expected:
                errors.append(f"{name}: width {width}, expected {expected} (not a 2x export?)")
                continue
            planned.append((code, target, data))

    missing = wanted - {code for code, _, _ in planned}
    if missing:
        errors.append(f"requested codes not imported: {', '.join(sorted(missing))}")
    for line in skipped:
        print(f"skip  {line}")
    if errors:
        for line in errors:
            print(f"error {line}", file=sys.stderr)
        print("nothing written", file=sys.stderr)
        return 1

    for code, target, data in sorted(planned, key=lambda item: str(item[1])):
        old = png_size(target.read_bytes())
        new = png_size(data)
        note = "" if old == new else f"  size {old[0]}x{old[1]} -> {new[0]}x{new[1]}"
        print(f"{'would write' if args.dry_run else 'write'} {target.relative_to(REPO)}{note}")
        if not args.dry_run:
            target.write_bytes(data)
    print(f"{len(planned)} file(s) {'planned' if args.dry_run else 'written'}, {len(skipped)} skipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
