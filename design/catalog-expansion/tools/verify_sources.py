#!/usr/bin/env python3
"""Verify the external exercise-catalog sources used by the C' expansion review.

Downloads free-exercise-db's ``dist/exercises.json`` and the wger
``exerciseinfo`` endpoint for every id referenced by ``match-audit.csv``,
caches the raw responses verbatim under ``design/catalog-expansion/source/cache/``
and writes a deterministic ``verified-sources.json`` with a per-file SHA-256
manifest.

Usage (from the worktree root, stdlib only):

    python3 -I design/catalog-expansion/tools/verify_sources.py --refresh
    python3 -I design/catalog-expansion/tools/verify_sources.py

``--refresh`` hits the network once and rewrites cache + manifest. A plain run
never touches the network: it re-derives the JSON from the cached bytes and the
recorded manifest, so two plain runs are byte-identical. Missing, corrupt or
incomplete cache without ``--refresh`` fails loudly with a non-zero exit.

Exit status is 0 on success. A missing fedb id or a failed wger fetch is review
data, not a crash: it is printed prominently and recorded under ``checks``.
A free-exercise-db SHA-256 mismatch is a real source-integrity failure and
exits non-zero (the cache is left untouched).
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

SCHEMA_VERSION = 1

# Audit retrieval date, fixed on purpose: verification runs must be
# reproducible, so the date comes from this constant / the cache manifest,
# never from datetime.now().
RETRIEVED_DATE = "2026-10-18"

# Worktree root is derived from __file__, never from the current directory.
# __file__ = <root>/design/catalog-expansion/tools/verify_sources.py
ROOT = Path(__file__).resolve().parents[3]
DESIGN = ROOT / "design" / "catalog-expansion"
INPUT = DESIGN / "source" / "2026-10-17" / "out"
AUDIT_CSV = INPUT / "reports" / "match-audit.csv"
ATTRIBUTION_CSV = INPUT / "reports" / "wger-attribution.csv"
SOURCES_MD = INPUT / "SOURCES.md"

CACHE_DIR = DESIGN / "source" / "cache"
FEDB_CACHE = CACHE_DIR / "free-exercise-db" / "exercises.json"
WGER_CACHE_DIR = CACHE_DIR / "wger"
OUTPUT = CACHE_DIR / "verified-sources.json"

FEDB_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
FEDB_REF = "main"
WGER_URL_TEMPLATE = "https://wger.de/api/v2/exerciseinfo/{id}/"
USER_AGENT = "FineCoach-catalog-verify/1.0 (offline iOS app data audit)"
POLITE_DELAY_SECONDS = 0.3
HTTP_ATTEMPTS = 3
HTTP_TIMEOUT_SECONDS = 60

# Attribute names compared between the wger API and wger-attribution.csv.
ATTRIBUTION_FIELDS = (
    ("name", "name", "name"),
    ("license", "license", "licenseShortName"),
    ("license_url", "license_url", "licenseURL"),
    ("author", "author", "licenseAuthor"),
)


class CacheError(Exception):
    """A cache/manifest/source-integrity failure that must stop the run."""


# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------


def read_csv(path: Path) -> list[dict[str, str]]:
    """Read a UTF-8 CSV. Both audit CSVs carry a BOM, hence utf-8-sig."""
    if not path.is_file():
        raise CacheError(f"required input missing: {path.relative_to(ROOT)}")
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def declared_fedb_sha(path: Path) -> str:
    """Parse the free-exercise-db declared SHA-256 from SOURCES.md."""
    if not path.is_file():
        raise CacheError(f"required input missing: {path.relative_to(ROOT)}")
    match = re.search(r"SHA-256[^0-9a-fA-F]*([0-9a-fA-F]{64})", path.read_text(encoding="utf-8"))
    if match is None:
        raise CacheError(f"cannot parse declared SHA-256 from {path.relative_to(ROOT)}")
    return match.group(1).lower()


def referenced_ids(rows: list[dict[str, str]]) -> tuple[list[str], list[int]]:
    """Split the audit's 库内ID column into sorted fedb ids and wger ids."""
    fedb_ids: set[str] = set()
    wger_ids: set[int] = set()
    for row in rows:
        value = (row.get("库内ID") or "").strip()
        if value.startswith("fedb:"):
            fedb_ids.add(value[len("fedb:"):])
        elif value.startswith("wger:"):
            number = value[len("wger:"):]
            if not number.isdigit():
                raise CacheError(f"unexpected wger id in match-audit.csv: {value!r}")
            wger_ids.add(int(number))
        elif value != "-":
            raise CacheError(f"unexpected 库内ID value in match-audit.csv: {value!r}")
    return sorted(fedb_ids), sorted(wger_ids)


# ---------------------------------------------------------------------------
# Network (only used by --refresh)
# ---------------------------------------------------------------------------


def http_get(url: str) -> bytes:
    """GET a URL as bytes, with a descriptive UA and a couple of retries."""
    last_error: Exception | None = None
    for attempt in range(1, HTTP_ATTEMPTS + 1):
        try:
            request = urllib.request.Request(
                url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"}
            )
            with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_error = exc
            if attempt < HTTP_ATTEMPTS:
                time.sleep(1.5 * attempt)
    raise RuntimeError(f"GET {url} failed after {HTTP_ATTEMPTS} attempts: {last_error}")


def manifest_entry(path: Path, url: str) -> dict[str, object]:
    raw = path.read_bytes()
    return {
        "path": path.relative_to(ROOT).as_posix(),
        "url": url,
        "retrievedDate": RETRIEVED_DATE,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "bytes": len(raw),
    }


def refresh_cache(declared_sha: str, wger_ids: list[int]) -> list[dict[str, object]]:
    """Download everything once, verify the fedb hash, write the raw cache."""
    fedb_raw = http_get(FEDB_URL)
    fedb_sha = hashlib.sha256(fedb_raw).hexdigest()
    if fedb_sha != declared_sha:
        raise CacheError(
            "free-exercise-db SHA-256 mismatch: downloaded "
            f"{fedb_sha}, SOURCES.md declares {declared_sha}; cache left untouched"
        )
    FEDB_CACHE.parent.mkdir(parents=True, exist_ok=True)
    FEDB_CACHE.write_bytes(fedb_raw)
    print(
        "refresh: free-exercise-db downloaded, "
        f"sha256={fedb_sha} matches declared, bytes={len(fedb_raw)}"
    )

    manifest = [manifest_entry(FEDB_CACHE, FEDB_URL)]
    WGER_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    failed = 0
    for position, wger_id in enumerate(wger_ids):
        url = WGER_URL_TEMPLATE.format(id=wger_id)
        try:
            raw = http_get(url)
            json.loads(raw)  # only keep a cache file that is actually JSON
        except Exception as exc:  # noqa: BLE001 - one bad id must not stop the audit
            failed += 1
            print(f"refresh: WARNING wger id {wger_id} failed: {exc}", file=sys.stderr)
        else:
            path = WGER_CACHE_DIR / f"exerciseinfo-{wger_id}.json"
            path.write_bytes(raw)
            manifest.append(manifest_entry(path, url))
        if position + 1 < len(wger_ids):
            time.sleep(POLITE_DELAY_SECONDS)
    print(f"refresh: wger fetched={len(manifest) - 1} failed={failed} of {len(wger_ids)}")
    manifest.sort(key=lambda entry: entry["path"])
    return manifest


# ---------------------------------------------------------------------------
# Cache loading / validation (plain runs)
# ---------------------------------------------------------------------------


def load_manifest() -> list[dict[str, object]]:
    if not OUTPUT.is_file():
        raise CacheError(
            f"cache manifest missing at {OUTPUT.relative_to(ROOT)}; "
            "run with --refresh first"
        )
    try:
        document = json.loads(OUTPUT.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise CacheError(f"cache manifest unreadable at {OUTPUT.relative_to(ROOT)}: {exc}") from exc
    manifest = document.get("cacheManifest")
    if not isinstance(manifest, list) or not manifest:
        raise CacheError(
            f"cache manifest in {OUTPUT.relative_to(ROOT)} is empty or malformed; "
            "run with --refresh"
        )
    return manifest


def load_cached_files(manifest: list[dict[str, object]]) -> dict[str, bytes]:
    """Verify every manifest entry (SHA-256 + byte count) and return its bytes."""
    cached: dict[str, bytes] = {}
    for entry in manifest:
        try:
            relative = str(entry["path"])
            expected_sha = str(entry["sha256"])
            expected_bytes = int(entry["bytes"])
        except (KeyError, TypeError, ValueError) as exc:
            raise CacheError(f"malformed cache manifest entry: {entry!r}") from exc
        if relative in cached:
            raise CacheError(f"duplicate cache manifest path: {relative}")
        path = ROOT / relative
        if not path.is_file():
            raise CacheError(f"cache file missing: {relative}; run with --refresh")
        raw = path.read_bytes()
        actual_sha = hashlib.sha256(raw).hexdigest()
        if actual_sha != expected_sha or len(raw) != expected_bytes:
            raise CacheError(
                f"cache file corrupt: {relative} "
                f"(sha256 {actual_sha} != {expected_sha} or bytes {len(raw)} != {expected_bytes}); "
                "run with --refresh"
            )
        cached[relative] = raw
    return cached


# ---------------------------------------------------------------------------
# Derivation
# ---------------------------------------------------------------------------


def wger_entry(exercise: dict) -> dict[str, object]:
    """Project one wger exerciseinfo response onto the review fields."""
    english_name = next(
        (
            translation.get("name")
            for translation in exercise.get("translations") or []
            if translation.get("language") == 2  # wger language 2 = English
        ),
        None,
    )
    license_info = exercise.get("license") or {}
    return {
        "id": exercise["id"],
        "uuid": exercise["uuid"],
        "name": english_name,
        "licenseShortName": license_info.get("short_name"),
        "licenseFullName": license_info.get("full_name"),
        "licenseURL": license_info.get("url"),
        "licenseAuthor": exercise.get("license_author"),
    }


def build_document(
    manifest: list[dict[str, object]],
    declared_sha: str,
    audit_rows: list[dict[str, str]],
    attribution_rows: list[dict[str, str]],
    fedb_ids: list[str],
    wger_ids: list[int],
    *,
    strict_cache: bool,
) -> dict[str, object]:
    """Build the deterministic verification document from the cache + inputs."""
    cached = load_cached_files(manifest)

    # free-exercise-db -----------------------------------------------------
    fedb_relative = FEDB_CACHE.relative_to(ROOT).as_posix()
    fedb_manifest = next((e for e in manifest if e["path"] == fedb_relative), None)
    if fedb_manifest is None:
        raise CacheError(f"cache manifest has no entry for {fedb_relative}; run with --refresh")
    fedb_raw = cached[fedb_relative]
    fedb_sha = hashlib.sha256(fedb_raw).hexdigest()
    try:
        library = json.loads(fedb_raw)
        by_id = {exercise["id"]: exercise for exercise in library}
    except (ValueError, KeyError, TypeError) as exc:
        raise CacheError(f"cached free-exercise-db JSON is unusable: {exc}") from exc
    fedb_missing = [catalog_id for catalog_id in fedb_ids if catalog_id not in by_id]
    fedb_exercises = {
        catalog_id: {
            "name": by_id[catalog_id].get("name"),
            "equipment": by_id[catalog_id].get("equipment"),
            "primaryMuscles": by_id[catalog_id].get("primaryMuscles"),
            "secondaryMuscles": by_id[catalog_id].get("secondaryMuscles"),
            "category": by_id[catalog_id].get("category"),
        }
        for catalog_id in fedb_ids
        if catalog_id in by_id
    }

    # wger -----------------------------------------------------------------
    wger_prefix = WGER_CACHE_DIR.relative_to(ROOT).as_posix() + "/"
    wger_pattern = re.compile(re.escape(wger_prefix) + r"exerciseinfo-(\d+)\.json")
    wger_raw_by_id: dict[int, bytes] = {}
    for entry in manifest:
        match = wger_pattern.fullmatch(str(entry["path"]))
        if match is None:
            continue
        wger_id = int(match.group(1))
        if wger_id in wger_raw_by_id:
            raise CacheError(f"cache manifest lists wger id {wger_id} twice")
        wger_raw_by_id[wger_id] = cached[str(entry["path"])]

    wger_entries: dict[str, dict[str, object]] = {}
    wger_failed: list[int] = []
    uuids: dict[str, list[int]] = {}
    missing_english: list[int] = []
    for wger_id in wger_ids:
        raw = wger_raw_by_id.get(wger_id)
        if raw is None:
            wger_failed.append(wger_id)
            continue
        try:
            entry = wger_entry(json.loads(raw))
        except (ValueError, KeyError, TypeError) as exc:
            if strict_cache:
                raise CacheError(f"cached wger response for id {wger_id} is unusable: {exc}") from exc
            wger_failed.append(wger_id)
            continue
        wger_entries[str(wger_id)] = entry
        uuids.setdefault(str(entry["uuid"]), []).append(wger_id)
        if entry["name"] is None:
            missing_english.append(wger_id)
    if strict_cache and wger_failed:
        raise CacheError(
            f"cache incomplete for wger ids {wger_failed}; run with --refresh"
        )

    duplicate_uuid_ids = sorted(
        wger_id for ids in uuids.values() if len(ids) > 1 for wger_id in ids
    )

    # wger-attribution.csv cross-check ------------------------------------
    attribution = {int(row["wger_id"]): row for row in attribution_rows}
    attribution_mismatches: list[dict[str, object]] = []
    for wger_id in wger_ids:
        entry = wger_entries.get(str(wger_id))
        expected = attribution.get(wger_id)
        if entry is None or expected is None:
            continue
        for field, attribution_field, entry_field in ATTRIBUTION_FIELDS:
            expected_value = expected.get(attribution_field)
            actual_value = entry.get(entry_field)
            expected_text = "" if expected_value is None else str(expected_value)
            actual_text = "" if actual_value is None else str(actual_value)
            if expected_text != actual_text:
                attribution_mismatches.append(
                    {
                        "wgerId": wger_id,
                        "field": field,
                        "attributionValue": expected_text,
                        "apiValue": actual_text,
                    }
                )
    attribution_mismatches.sort(key=lambda item: (item["wgerId"], item["field"]))

    wger_dates = sorted(
        {str(entry["retrievedDate"]) for entry in manifest if wger_pattern.fullmatch(str(entry["path"]))}
    )

    checks = {
        "auditRows": len(audit_rows),
        "attributionRows": len(attribution_rows),
        "fedbIdsReferenced": len(fedb_ids),
        "fedbIdsMissing": fedb_missing,
        "fedbExerciseCount": len(library),
        "fedbSha256MatchesDeclared": fedb_sha == declared_sha,
        "wgerIdsReferenced": len(wger_ids),
        "wgerIdsFetched": len(wger_entries),
        "wgerFetchFailed": wger_failed,
        "wgerEnglishNamesMissing": missing_english,
        "wgerUuidUnique": not duplicate_uuid_ids,
        "wgerUuidDuplicates": duplicate_uuid_ids,
        "wgerAttributionIdsMatchAuditIds": set(attribution) == set(wger_ids),
        "wgerAttributionMismatches": attribution_mismatches,
    }

    return {
        "schemaVersion": SCHEMA_VERSION,
        "freeExerciseDB": {
            "sourceURL": FEDB_URL,
            "ref": FEDB_REF,
            "retrievedDate": fedb_manifest["retrievedDate"],
            "sha256": fedb_sha,
            "declaredSha256": declared_sha,
            "exerciseCount": len(library),
            "idField": "id",
            "exercises": fedb_exercises,
        },
        "wger": {
            "sourceURLTemplate": WGER_URL_TEMPLATE,
            "retrievedDate": wger_dates[-1] if wger_dates else None,
            "entries": wger_entries,
        },
        "checks": checks,
        "cacheManifest": sorted(manifest, key=lambda entry: entry["path"]),
    }


# ---------------------------------------------------------------------------
# Output / reporting
# ---------------------------------------------------------------------------


def write_document(document: dict[str, object]) -> None:
    """Write deterministic JSON: sorted keys, fixed separators, trailing newline."""
    text = json.dumps(
        document,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
        separators=(",", ": "),
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text + "\n", encoding="utf-8")


def print_summary(document: dict[str, object]) -> None:
    checks = document["checks"]
    fedb = document["freeExerciseDB"]
    relative_output = OUTPUT.relative_to(ROOT).as_posix()

    print(
        f"fedb: referenced={checks['fedbIdsReferenced']} "
        f"missing={len(checks['fedbIdsMissing'])} "
        f"exerciseCount={checks['fedbExerciseCount']} "
        f"sha256MatchDeclared={'yes' if checks['fedbSha256MatchesDeclared'] else 'NO'}"
    )
    print(f"fedb: declaredSha256={fedb['declaredSha256']}")
    print(f"fedb: actualSha256={fedb['sha256']}")
    print(
        f"wger: referenced={checks['wgerIdsReferenced']} "
        f"fetched={checks['wgerIdsFetched']} "
        f"failed={len(checks['wgerFetchFailed'])} "
        f"uuidUnique={'yes' if checks['wgerUuidUnique'] else 'NO'} "
        f"attributionMismatches={len(checks['wgerAttributionMismatches'])}"
    )
    if checks["fedbIdsMissing"]:
        print(f"WARNING: fedb ids missing from exercises.json: {checks['fedbIdsMissing']}")
    if checks["wgerFetchFailed"]:
        print(f"WARNING: wger ids that failed to fetch: {checks['wgerFetchFailed']}")
    if checks["wgerEnglishNamesMissing"]:
        print(f"WARNING: wger ids without English translation: {checks['wgerEnglishNamesMissing']}")
    if not checks["wgerUuidUnique"]:
        print(f"WARNING: duplicate wger uuids at ids: {checks['wgerUuidDuplicates']}")
    if checks["wgerAttributionMismatches"]:
        print(
            "WARNING: wger attribution mismatches: "
            f"{[m['wgerId'] for m in checks['wgerAttributionMismatches']]}"
        )
    if not checks["wgerAttributionIdsMatchAuditIds"]:
        print("WARNING: wger-attribution.csv ids differ from match-audit.csv wger ids")
    print(f"output: {relative_output}")


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify free-exercise-db and wger sources, cache them, and write verified-sources.json."
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="re-download the sources, update the cache/manifest, then rewrite the JSON",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        declared_sha = declared_fedb_sha(SOURCES_MD)
        audit_rows = read_csv(AUDIT_CSV)
        attribution_rows = read_csv(ATTRIBUTION_CSV)
        fedb_ids, wger_ids = referenced_ids(audit_rows)

        if args.refresh:
            manifest = refresh_cache(declared_sha, wger_ids)
        else:
            manifest = load_manifest()

        document = build_document(
            manifest,
            declared_sha,
            audit_rows,
            attribution_rows,
            fedb_ids,
            wger_ids,
            strict_cache=not args.refresh,
        )
        write_document(document)
        print_summary(document)
        return 0
    except CacheError as exc:
        print(f"verify_sources: ERROR: {exc}", file=sys.stderr)
        return 1
    except RuntimeError as exc:  # network failure during --refresh
        print(f"verify_sources: ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
