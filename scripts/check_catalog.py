"""Validate roster coverage and online/offline catalog parity before building."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'data/catalog.json').read_bytes()
assert source == (root / 'mobile/assets/catalog.json').read_bytes(), 'Catalog copies differ'
catalog = json.loads(source)
manifest = json.loads((root / 'data/roster-133-manifest.json').read_text())
heroes = catalog['heroes']
assert len(heroes) == manifest['expected_count'] == 133
assert sorted(h['name'] for h in heroes) == sorted(manifest['names'])
assert len({h['id'] for h in heroes}) == len(heroes)
assert len({h['name'].casefold() for h in heroes}) == len(heroes)
for hero in heroes:
    assert hero['roles'] and set(hero['roles']) <= {'Roam', 'Jungle', 'Mid', 'EXP', 'Gold'}, hero['id']
    assert hero['damage'] in {'physical', 'magic', 'mixed'}, hero['id']
    assert hero['tags'] and len(set(hero['tags'])) == len(hero['tags']), hero['id']
old = json.loads((root / 'data/catalogs/baseline-2026-11-07.json').read_text())
assert len(old['heroes']) == 104
assert {h['id'] for h in old['heroes']} | set(manifest['added_ids']) == {h['id'] for h in heroes}
assert len(manifest['added_ids']) == 29
print('PASS: 133 unique heroes, 29 additions, valid lanes/damage, identical online/offline catalogs, historical baseline retained.')
