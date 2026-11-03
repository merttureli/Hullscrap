"""Throwaway content audit: where each material/item can be found, recipes whose inputs have no source, items nobody wants.
Usage: python3 tests/tool_audit_content_econ.py <dump> <repo>"""
import json, sys, re, collections
D, R = sys.argv[1] + '/', sys.argv[2] + '/'
L = lambda n: json.load(open(D + n + '.json'))
J = lambda p: json.load(open(R + p))
comps = {c['id']: c for c in L('components')}; items = {c['id']: c for c in L('items')}; mats = {c['id']: c for c in L('materials')}
recs = {c['id']: c for c in L('recipes')}; events = {e['id']: e for e in L('events')}; regions = {r['id']: r for r in L('regions')}
src = collections.defaultdict(set)
deb = J('data/debris.json')
def walk(o, cb, path=''):
    if isinstance(o, dict):
        cb(o, path)
        for k, v in o.items(): walk(v, cb, path + '/' + k)
    elif isinstance(o, list):
        for v in o: walk(v, cb, path)
# debris types
for t in deb['types']:
    for i in t.get('yield', {}): src[i].add('debris:' + t['id'])
    for k in t:
        if k not in ('id','name','weight','size','art','color','yield','hp','rare','sealed','roll','notes','blurb'): print('debris', t['id'], k, json.dumps(t[k])[:100])
    if 'roll' in t:
        for o in t['roll']: src[o['item']].add('debris:' + t['id'] + '.roll')
# boarding tables
bo = J('data/boarding.json')
for tn, tab in bo['tables'].items():
    for o in tab: src[o['item']].add('board:' + tn)
for k, kc in bo['kinds'].items():
    for o in kc.get('bonus', []):
        if isinstance(o, dict): src[o['item']].add('board:%s.bonus' % k)
for rid, r in regions.items():
    for i in r.get('stock', {}): src[i].add('station:' + rid)
for k in ('common', 'materials', 'drone', 'mods'):
    for i in J('data/drift.json')['shops'][k]: src[i].add('shop:' + k)
for rid in J('data/drift.json')['shops']['blueprints']: src['bp:' + rid].add('shop')
for eid, e in events.items():
    for c in e.get('choices', []):
        for o in c.get('outcomes', []):
            for ef in [o.get('effects', {})] + ([o['after_win']['effects']] if o.get('after_win') else []):
                for i, n in (ef.get('items') or {}).items():
                    if (n if isinstance(n, (int, float)) else 1) > 0: src[i].add('event:' + eid)
                for b in (ef.get('blueprint') if isinstance(ef.get('blueprint'), list) else [ef.get('blueprint')] if ef.get('blueprint') else []): src['bp:' + b].add('event:' + eid)
# enemy loot / drift loot
dr = J('data/drift.json'); print('drift.loot', json.dumps(dr['loot'])[:600])
et = J('data/enemy_tables.json')
def cb2(o, p):
    if 'item' in o and isinstance(o['item'], str): src[o['item']].add('enemy_tables' + p)
walk(et, cb2)
# starters
import glob
for f in glob.glob(R + 'data/ships/*.json') + glob.glob(R + 'data/packs/*/ships/*.json'):
    d = json.load(open(f))
    for i in (d.get('cargo') or {}): src[i].add('starter')
print()
print('=== materials and sources')
for m in mats: print(m, mats[m]['rarity'], sorted(src[m])[:6], len(src[m]))
# smelter outputs
for rid, r in recs.items():
    if r.get('category') == 'material' or r.get('station') == 'smelter': src[r['output']['item']].add('smelter:' + rid)
print('=== recipe inputs with no source at all')
for rid, r in recs.items():
    for m in r['materials']:
        if not src[m]: print('  NO SOURCE', rid, 'needs', m)
print('=== items.json items: sources')
for i, it in items.items():
    if not src[i] and i not in ('hand_ammo',): print('  no source:', i, it.get('kind'))
print('=== components: sources (recipe, station stock, shop, loot, event, starter)')
learn = set(J('data/recipes.json')['start_known'])
outs = {r['output']['item']: rid for rid, r in recs.items()}
nosrc = []
for c, cc in comps.items():
    if c in outs or src[c]: continue
    nosrc.append(c)
print('components with neither recipe nor any source:', nosrc)
# recipes: where blueprint comes from
print('=== recipes not in start_known and no explicit teacher (reachable only via random scan/board pick):')
n = 0
for rid in recs:
    if rid not in learn and not src['bp:' + rid]: n += 1
print(n, 'of', len(recs))
json.dump({k: sorted(v) for k, v in src.items()}, open(D + 'sources.json', 'w'))
