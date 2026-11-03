"""Throwaway content audit: reads the JSON of tests/tool_audit_content_walk.gd. Usage: python3 tests/tool_audit_content_walk.py <walk.json> <dump>"""
import json, sys, collections, statistics as st
w = json.load(open(sys.argv[1])); D = sys.argv[2] + '/'
events = {e['id']: e for e in json.load(open(D + 'events.json'))}
print('runs', w['runs'], 'roam', w['roam'])
for last, rows in w['by_last'].items():
    d = [r['distinct'] for r in rows]; dr = [r['draws'] for r in rows]; rp = [r['repeats'] for r in rows]
    # runs with any repeat
    anyrep = sum(1 for r in rows if r['repeats'] > 0)
    # non-page event draws only
    pagedraws = []
    top = collections.Counter()
    for r in rows:
        for k, n in r['seen'].items(): top[k] += n
    print('through stage %s: distinct mean %.1f (min %d max %d), draws mean %.1f, repeat-draws mean %.1f, runs with a repeat %d%%' % (last, st.mean(d), min(d), max(d), st.mean(dr), st.mean(rp), 100 * anyrep // len(rows)))
tot = collections.Counter(); runs_with = collections.Counter()
for r in w['by_last']['8']:
    for k, n in r['seen'].items(): tot[k] += n; runs_with[k] += 1
print('distinct events seen over all 8-stage runs:', len(tot), 'of', len([e for e in events.values()]))
bytype = collections.Counter(); alltype = collections.Counter()
for e in events.values(): alltype[e['type']] += 1
for k in tot: bytype[events[k]['type']] += 1
for t in alltype: print('  %-15s seen %3d of %3d' % (t, bytype[t], alltype[t]))
# most repeated
rep = collections.Counter()
for r in w['by_last']['8']:
    for k, n in r['seen'].items():
        if n > 1: rep[k] += n - 1
print('most repeated (extra shows over all runs):', rep.most_common(15))
# repeats in stage 1-3 per type
t3 = collections.Counter(); d3 = collections.Counter()
for r in w['by_last']['3']:
    for k, n in r['seen'].items():
        t = events[k]['type']; d3[t] += n; t3[t] += n - 1
print('stage 1-3 draws by type, repeat share:', {t: (d3[t], round(t3[t] / d3[t], 2)) for t in d3})
json.dump({'seen_ids': sorted(tot)}, open(D + 'walk_seen_' + ('roam' if w['roam'] else 'pace') + '.json', 'w'))
