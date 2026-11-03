"""Throwaway content audit: events, flags, logs, items, recipes reachable? Usage: python3 tests/tool_audit_content_reach.py <dump> <repo>"""
import json, sys, re, collections
D, R = sys.argv[1] + '/', sys.argv[2] + '/'
L = lambda n: json.load(open(D + n + '.json'))
J = lambda p: json.load(open(R + p))
events = {e['id']: e for e in L('events')}
regions = {r['id']: r for r in L('regions')}
tags = {r.get('events', r['id']) for r in regions.values()} | set(regions)
logs = L('logs')
def lst(v): return v if isinstance(v, list) else ([] if v is None else [v])
setf = collections.defaultdict(list); reqf = collections.defaultdict(list); notf = collections.defaultdict(list)
named_logs = collections.defaultdict(list); goto = set()
items_given = collections.defaultdict(list)
def effs(e):
    for c in e.get('choices', []):
        for o in c.get('outcomes', []):
            yield c, o, o.get('effects', {})
            aw = o.get('after_win')
            if aw: yield c, o, aw.get('effects', {})
    aw = e.get('after_win')
    if aw: yield None, None, aw.get('effects', {})
for eid, e in events.items():
    r = e.get('requires', {})
    for f in lst(r.get('flag')): reqf[f].append(eid)
    for f in lst(r.get('not_flag')): notf[f].append(eid)
    for c in e.get('choices', []):
        cr = c.get('requires', {})
        for f in lst(cr.get('flag')): reqf[f].append(eid + '#choice')
    for c, o, ef in effs(e):
        for f in lst(ef.get('flag')): setf[f].append(eid)
        for l in lst(ef.get('log')): named_logs[l].append(eid)
        if ef.get('goto'): goto.add(ef['goto'])
        for i in (ef.get('items') or {}): items_given[i].append(eid)
        if 'clears' in ef: pass
        for b in lst(ef.get('blueprint')): items_given['bp:' + b].append(eid)
auto = re.compile(r'^(at_|in_|variant_|known_|debt_missed$|debt_free$)')
wardens = J('data/wardens.json')
print('--- required flags never set by any effect (excluding code-set):')
dead_req = {}
for f, who in sorted(reqf.items()):
    if f in setf or auto.match(f): continue
    dead_req[f] = who
    print(' ', f, '<-', who[:4], len(who))
print('--- flags set and never read:', len([f for f in setf if f not in reqf and f not in notf]))
# events by type
bytype = collections.Counter(e['type'] for e in events.values())
print(bytype)
# unreachable events
POI = J('data/sectors.json')['poi_types']
nodes_types = set()
for p in POI.values():
    ev = p['event']; nodes_types |= set(ev) if isinstance(ev, dict) else {ev}
for n in J('data/sectors.json')['nodes'].values(): pass
print('POI event types', nodes_types)
unreach = []
for eid, e in events.items():
    t = e['type']; r = e.get('requires', {})
    why = []
    if t in ('page',) or eid in goto: 
        if eid not in goto and t == 'page': why.append('page nobody goes to')
        # pages fine
        if why: unreach.append((eid, why)); 
        continue
    if t in ('boarding_npc', 'boarding_site', 'debt', 'station', 'hollow'):
        pass
    elif t not in nodes_types and t != 'gate': why.append('type %s has no POI' % t)
    if e.get('weight', 10) in (0,) : why.append('weight 0 not a goto target')
    for rg in lst(r.get('region')):
        if rg not in tags: why.append('region %s unknown' % rg)
    if 'stage_min' in r and 'stage_max' in r and r['stage_min'] > r['stage_max']: why.append('stage range empty')
    for f in lst(r.get('flag')):
        if f in dead_req: why.append('flag %s never set' % f)
    if r.get('stage_min', 0) > 9: why.append('stage_min>9')
    if why: unreach.append((eid, why))
print('--- unreachable events:', len(unreach))
for u in unreach: print(' ', u)
# unreachable by stage: region stage windows
# logs
lid = {l for l in logs}
print('--- logs total', len(lid), 'never named by an event effect:', len([l for l in lid if l not in named_logs]))
# the rest can be in containers aboard / debris? check code use
print('  ', [l for l in lid if l not in named_logs][:60])
json.dump({'dead_req': dead_req, 'unreach': unreach}, open(D + 'reach.json', 'w'))
