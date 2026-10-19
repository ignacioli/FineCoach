#!/usr/bin/env python3
"""Write the approved CX-D4/D9/D12/D15 catalog from frozen inputs, offline.

Run: .venv/bin/python -I design/catalog-expansion/tools/write_catalog.py
The pinned 146-entry baseline is the input; expanded output is never re-ingested.
UUIDv5 names encode sourceIdentifier|canonicalName|equipmentClass. Once shipped,
those ids are stable; future renames must update by id rather than regenerate it.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import uuid
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / 'ios/FineCoachApp/Resources/ExerciseCatalog/provenance.json'
# Permanent namespace for the first approved C' expansion; do not change it.
CATALOG_NAMESPACE = uuid.UUID('27145e16-cb8b-5dfc-8e97-7c3162fc9b70')
VERSION = 'm1a.catalog.2026-10-18'
REVIEW_DATE = '2026-10-18'


def load_candidates_module():
    spec = importlib.util.spec_from_file_location('build_candidates', Path(__file__).with_name('build_candidates.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_catalog() -> dict:
    module = load_candidates_module()
    catalog = module.load_baseline_manifest()
    existing = catalog['exercises']
    baseline_ids = {item['id'] for item in existing}
    by_english, by_name, by_uuid = {}, {}, {}
    for item in existing:
        by_english.setdefault(module.norm_english(item['sourceEnglishName']), item)
        by_name.setdefault(item['canonicalName'], item)
        by_uuid.setdefault(item['id'], item)
    built = module.build_entries(module.load_rows(), by_english, by_name, by_uuid)
    candidates = module.merge_entries(built['entries'])
    module.validate_builtin_names(existing, candidates)
    renames = {'单臂哑铃划船': '哑铃支撑划船', '哑铃单手提走': '哑铃提箱走'}
    renamed_ids = {}
    for item in existing:
        old_name = item['canonicalName']
        if old_name in renames:
            item['canonicalName'] = renames[old_name]
            renamed_ids[item['id']] = item['canonicalName']
        if old_name == '单腿腿屈伸':
            item['retired'] = True
        if item['equipmentClass'] == '龙门架':
            item['equipmentClass'] = '绳索'
        if old_name in ('引体向上', '反手引体向上'):
            item['equipmentClass'] = '单杠'
        if old_name in module.EXISTING_EQUIPMENT_OVERRIDES:
            item['equipmentClass'] = module.EXISTING_EQUIPMENT_OVERRIDES[old_name]
    catalog['metadataVersion'] = VERSION
    catalog['provenance']['contentVersion'] = VERSION
    records = catalog['provenance']['records']
    for record in records:
        record['contentVersion'] = VERSION
        if record['recordID'] in renamed_ids:
            old_name = record['canonicalChineseName']
            new_name = renamed_ids[record['recordID']]
            record['canonicalChineseName'] = new_name
            record['attributionRequirement'] = record['attributionRequirement'].replace(old_name, new_name)
            record['reviewerEvidence'] += ' CX-D4 display-name revision approved 2026-10-18; stable id unchanged.'
    for entry in candidates:
        source = entry['source']
        identifier = str(uuid.uuid5(CATALOG_NAMESPACE, '|'.join((source, entry['name'], entry['equipment']))))
        english = ('FineCoach original: ' + entry['name']) if source == 'finecoach-built' else entry['english']
        exercise = {
            'id': identifier,
            'canonicalName': entry['name'],
            'equipmentClass': entry['equipment'],
            'primaryMuscleGroup': entry['primary'],
            'secondaryMuscleGroups': entry['secondary'],
            'recordMode': entry['mode'],
            'sourceEnglishName': english,
            'provenanceRef': identifier,
        }
        if entry['unilateral']:
            exercise['unilateral'] = True
        existing.append(exercise)
        records.append({
            'recordID': identifier,
            'sourceIdentifier': source,
            'authorOrOwner': entry['author'],
            'licenseIdentifier': entry['license_short'],
            'licenseText': entry['license_text'],
            'redistributionAllowed': True,
            'attributionRequirement': '「%s」 / %s — %s. Source: %s. Licensed %s.' % (
                entry['name'], english, entry['author'], source, entry['license_short']),
            'contentVersion': VERSION,
            'reviewDate': REVIEW_DATE,
            'reviewerEvidence': 'FineCoach C′ catalog-review-300 approved 2026-10-18 (Q1–Q10, A1–A3, CX-D12). Frozen source row %s; verified-sources.json. Chinese name is a FineCoach translation or approved original.' % entry['key'],
            'stableExerciseID': identifier,
            'canonicalChineseName': entry['name'],
            'recordMode': entry['mode'],
            'chineseNameSource': 'finecoach-original' if source == 'finecoach-built' else 'finecoach-translation',
            'sourceEnglishName': english,
        })
    ids = [item['id'] for item in existing]
    names = [item['canonicalName'] for item in existing]
    assert len(set(ids)) == len(ids), 'duplicate UUID'
    assert len(set(names)) == len(names), 'CX-D12 duplicate built-in Chinese name'
    assert baseline_ids.issubset(ids), 'baseline id changed'
    assert len(existing) == 146 + len(candidates)
    refs = {record['recordID'] for record in records}
    assert len(refs) == len(records) == len(existing)
    for item in existing:
        uuid.UUID(item['id'])
        assert item['equipmentClass'] in module.EQUIP_ORDER
        assert item['primaryMuscleGroup'] in module.PART_ORDER
        assert set(item['secondaryMuscleGroups']) <= set(module.PART_ORDER)
        assert item['recordMode'] in ('weightReps', 'reps', 'duration')
        assert item['provenanceRef'] in refs
    return catalog


def main() -> None:
    catalog = build_catalog()
    raw = (json.dumps(catalog, ensure_ascii=False, indent=2) + '\n').encode()
    OUTPUT.write_bytes(raw)
    print('baseline=146 added=%d total=%d metadataVersion=%s sha256=%s' % (
        len(catalog['exercises']) - 146, len(catalog['exercises']), VERSION, hashlib.sha256(raw).hexdigest()))


if __name__ == '__main__':
    main()
