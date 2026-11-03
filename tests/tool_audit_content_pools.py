"""Throwaway content audit: per stage x region x node type, how many events can be rolled (requires on region, stage; flags/crew/jumps ignored, once ignored).
Usage: python3 tests/tool_audit_content_pools.py <dump> <repo>"""
import json, sys, collections
D, R = sys.argv[1] + '/', sys.argv[2] + '/'
events = json.load(open(D + 'events.json')); regions = {r['id']: r for r in json.load(open(D + 'regions.json'))}
def lst(v): return v if isinstance(v, list) else ([] if v is None else [v])
types = ['wreck_field', 'distress', 'trader', 'asteroid_field', 'pirate', 'anomaly', 'patrol', 'empty']
def ok(e, rid, s):
    r = e.get('requires', {}); reg = regions[rid]
    if 'stage_min' in r and s < r['stage_min']: return False
    if 'stage_max' in r and s > r['stage_max']: return False
    if 'region' in r and not any(x == rid or x == reg.get('events') for x in lst(r['region'])): return False
    if e.get('weight', 10) == 0: return False
    return True
goto = set()
for e in events:
    for c in e.get('choices', []):
        for o in c.get('outcomes', []):
            g = o.get('effects', {}).get('goto')
            if g: goto.add(g)
            g = (o.get('after_win') or {}).get('effects', {}).get('goto')
            if g: goto.add(g)
ev = [e for e in events if e['id'] not in goto]
# by stage over all regions available at that stage: weight of regions
print('region stage windows:')
for rid, r in sorted(regions.items(), key=lambda x: x[1]['stages'][0]): print('  %-22s stages %d-%d weight %s rarity %s' % (rid, r['stages'][0], r['stages'][1], r['weight'], r['rarity']))
print()
print('events a region can roll per type, at stage s (generic = no region; pool = generic + regional):')
tab = {}
for rid, r in regions.items():
    if rid == 'gate_approaches': continue
    for s in range(int(r['stages'][0]), int(r['stages'][1]) + 1):
        row = {}
        for t in types:
            row[t] = sum(1 for e in ev if e['type'] == t and ok(e, rid, s))
        tab[(rid, s)] = row
thin = []
for (rid, s), row in sorted(tab.items(), key=lambda x: (x[0][1], x[0][0])):
    low = {t: n for t, n in row.items() if n < 12}
    if min(row.values()) < 12 or True: pass
    thin.append((rid, s, row))
# summary: min and median pool per type at each stage across regions
for s in range(1, 9):
    rows = [row for (rid, st), row in tab.items() if st == s]
    if not rows: continue
    print('stage %d (%d regions): ' % (s, len(rows)) + ', '.join('%s %d-%d' % (t[:6], min(r[t] for r in rows), max(r[t] for r in rows)) for t in types))
# early stages: the actual starting region(s)
print()
for rid in ['clan_space', 'boneyard', 'concord_space', 'lumen_space', 'human_core']:
    if rid in regions:
        print(rid, [ (s, sum(tab[(rid, s)].values())) for s in range(int(regions[rid]['stages'][0]), int(regions[rid]['stages'][1]) + 1)], tab[(rid, int(regions[rid]['stages'][0]))])
# regions with fewest total events (distinct, ignoring stage)
tot = {}
for rid, r in regions.items():
    tot[rid] = sum(1 for e in ev if e['type'] in types and ok(e, rid, int(r['stages'][0])) or (e['type'] in types and ok(e, rid, int(r['stages'][1]))))
print('thinnest regions (events that can roll at any stage):', sorted(tot.items(), key=lambda x: x[1])[:8])
# regional vs generic counts
gen = collections.Counter(e['type'] for e in ev if 'region' not in e.get('requires', {}) and e['type'] in types)
print('generic (all-region) events per type:', dict(gen))
stagebanded = sum(1 for e in ev if ('stage_min' in e.get('requires', {}) or 'stage_max' in e.get('requires', {})) and e['type'] in types)
print('events with a stage band:', stagebanded, 'of', sum(1 for e in ev if e['type'] in types))
