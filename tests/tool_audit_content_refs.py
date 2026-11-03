"""Throwaway content audit: dangling ids and unreachable content. Reads the dump of tests/tool_audit_content_dump.gd.
Usage: python3 tests/tool_audit_content_refs.py <dump dir> <repo root>"""
import json, sys, glob, os, re
D, R = sys.argv[1] + '/', sys.argv[2] + '/'
L = lambda n: json.load(open(D + n + '.json'))
J = lambda p: json.load(open(R + p))
comps = {c['id']: c for c in L('components')}
items = {c['id']: c for c in L('items')}
mats = {c['id']: c for c in L('materials')}
hw = {c['id']: c for c in L('hand_weapons')}
recs = {c['id']: c for c in L('recipes')}
species = {c['id']: c for c in L('species')}
events = {e['id']: e for e in L('events')}
logs = L('logs')
unl = {c['id']: c for c in L('unlocks')}
regions = {c['id']: c for c in L('regions')}
ships = {c['id']: c for c in L('ships')}
chars = {c['id']: c for c in L('characters')}
anyitem = set(comps) | set(items) | set(mats) | set(hw) | {'credits', 'fuel'}
bad = []
def B(where, msg): bad.append((where, msg)); print('BROKEN', where, msg)

# recipes
for rid, r in recs.items():
    o = r['output']['item']
    if o not in anyitem: B('data/recipes.json:' + rid, 'output %s unknown' % o)
    for m in r.get('materials', {}):
        if m not in anyitem: B('data/recipes.json:' + rid, 'material %s unknown' % m)
    for t in r.get('tools', []):
        if t not in anyitem and t not in recs: B('data/recipes.json:' + rid, 'tool %s unknown' % t)
outs = {}
for rid, r in recs.items(): outs.setdefault(r['output']['item'], []).append(rid)
# components with no recipe and not unique -> only findable/bought/starter
norec = [c for c in comps if c not in outs]
print('components without recipe', len(norec), norec)
# recipes whose output is something nobody can use
# start known
sk = J('data/recipes.json')['start_known']
for s in sk:
    if s not in recs and s not in anyitem: B('data/recipes.json:start_known', s)
# shops
dr = J('data/drift.json')
sh = dr['shops']
for k in ['common', 'materials', 'drone', 'mods']:
    for i in sh[k]:
        if i not in anyitem: B('data/drift.json:shops.' + k, i)
for rid in sh['blueprints']:
    if rid not in recs: B('data/drift.json:shops.blueprints', rid)
for k in ('common','mods'):
    pass
# station stock in regions
for rid, r in regions.items():
    for i in r.get('stock', {}):
        if i not in anyitem: B('regions/%s stock' % rid, i)
    for sp in r.get('recruit', {}):
        if sp not in species: B('regions/%s recruit' % rid, sp)
    if r.get('home_species') and r['home_species'] not in species: B('regions/%s home_species' % rid, r['home_species'])
# boarding
bo = J('data/boarding.json')
for t, tab in bo['tables'].items():
    for o in tab:
        i = o['item']
        if i != 'mod' and i not in anyitem: B('data/boarding.json tables.' + t, i)
for k, kc in bo['kinds'].items():
    for m in kc.get('bonus', []):
        if isinstance(m, dict) and m['item'] != 'mod' and m['item'] not in anyitem: B('boarding kinds.%s.bonus' % k, m['item'])
for b in bo['kit']['bodies']:
    if b not in anyitem: B('boarding kit.bodies', b)
for k in bo['armor']:
    if k != '_doc' and k not in anyitem: B('boarding armor', k)
for k, e in bo['enemies'].items():
    if k == '_doc': continue
    if e.get('weapon') and e['weapon'] not in hw and e['weapon'] not in anyitem: B('boarding enemies.' + k, 'weapon ' + e['weapon'])
for k, p in bo['people'].get('roles', {}).items():
    if isinstance(p, dict) and p.get('weapon') and p['weapon'] not in hw: B('boarding people.roles.' + k, 'weapon ' + p['weapon'])
    if isinstance(p, dict) and p.get('hostile') and p['hostile'] not in bo['enemies']: B('boarding people.roles.' + k, 'hostile ' + p['hostile'])
for th, t in bo['themes'].items():
    if th == '_doc': continue
    for i in t.get('loot', {}).get('tilt', {}):
        if i not in anyitem and i != 'mod': B('boarding themes.%s.loot.tilt' % th, i)
    for sp in t.get('species', {}):
        if sp not in species: B('boarding themes.%s.species' % th, sp)
    for rg in t.get('regions', []):
        if rg not in regions and rg not in {r.get('events') for r in regions.values()}: B('boarding themes.%s.regions' % th, rg)
    for f in t.get('foes', {}).get('mix', {}):
        if f not in bo['enemies']: B('boarding themes.%s.foes.mix' % th, f)
    for f in t.get('foes', {}).get('add', {}):
        if f not in bo['enemies']: B('boarding themes.%s.foes.add' % th, f)
    for r in t.get('npc', {}).get('roles', {}):
        if r not in bo['people']['roles']: B('boarding themes.%s.npc.roles' % th, r)
for k in bo['people'].get('shop', {}).get('items', []) if isinstance(bo['people'].get('shop', {}).get('items'), list) else []:
    pass
# mods
mods = J('data/mods.json')['mods']
for m in mods:
    for t in (1, 2, 3):
        if '%s_mk%d' % (m['id'], t) not in items: B('data/mods.json', '%s_mk%d not in items' % (m['id'], t))
    for r in m.get('rare', []):
        if r not in mats: B('data/mods.json rare', r)
# debris
deb = J('data/debris.json')
print('debris keys', list(deb))
def walk(o, path, cb):
    if isinstance(o, dict):
        for k, v in o.items(): walk(v, path + '.' + k, cb)
    elif isinstance(o, list):
        for i, v in enumerate(o): walk(v, path + '[%d]' % i, cb)
    else: cb(path, o)
def chk_item_keys(o, path):
    if isinstance(o, dict):
        if 'item' in o and isinstance(o['item'], str) and o['item'] not in anyitem and o['item'] != 'mod':
            B(path, 'item ' + o['item'])
        for k, v in o.items(): chk_item_keys(v, path + '.' + k)
    elif isinstance(o, list):
        for i, v in enumerate(o): chk_item_keys(v, path + '[%d]' % i)
chk_item_keys(deb, 'data/debris.json')
# enemy tables
et = J('data/enemy_tables.json'); chk_item_keys(et, 'data/enemy_tables.json')
# advisor
adv = J('data/advisor.json'); prog = J('data/progression.json')
pk = set()
for s in prog['stages'].values(): pk |= set(s)
src = open(R + 'scripts/sim/advisor.gd').read()
for st, goals in adv['stages'].items():
    for g in goals:
        chs = g['check'] if isinstance(g['check'], list) else [g['check']]
        for ch in chs:
            for k, v in ch.items():
                if isinstance(v, str) and v.startswith('p:') and v[2:] not in prog['stages'][st]: B('advisor.json stage %s %s' % (st, g['id']), 'p:%s missing in progression.json stage %s' % (v[2:], st))
                if k not in adv['labels']: B('advisor.json stage %s %s' % (st, g['id']), 'check key %s has no label' % k)
        for f in ('title', 'why'):
            for m in re.findall(r'\{(=?)([a-z_]+)(?::[^}]*)?\}', g[f]):
                if m[0] == '=':
                    if m[1] not in prog['stages'][st] and m[1] not in ('guns','layers'): B('advisor.json %s' % g['id'], '{=%s} not in progression' % m[1])
                elif m[1] not in adv['keywords']: B('advisor.json %s' % g['id'], 'keyword {%s} unknown' % m[1])
print('advisor.gd mentions of tips:', re.findall(r'"(first_[a-z_]+|low_fuel)"', src))
tips = {t['id'] for t in adv['tips']}
used = set(re.findall(r'"(first_[a-z_]+|low_fuel)"', src))
print('tips never referenced by code:', tips - used, ' referenced but no text:', used - tips)
warn = set(adv['warnings'])
print('warning keys in code:', set(re.findall(r'"(outgunned|fuel|skulls|toll|hull|cliff|power|mass|scrap|blueprints)"', src)), 'json', warn)
# unlocks payloads
for uid, u in unl.items():
    p = u.get('payload', {})
    if u['kind'] == 'starter_ship' and p.get('ship') not in {s.get('design', {}).get('id', s['id']) for s in ships.values()} and p.get('ship') not in ships:
        B('unlocks:' + uid, 'ship %s not found' % p.get('ship'))
# ships components
print('ships', len(ships))
# characters
for cid, c in chars.items():
    if c.get('species') not in species: B('characters:' + cid, 'species %s' % c.get('species'))
json.dump(bad, open(D + 'bad_refs.json', 'w'))
print('TOTAL BROKEN', len(bad))
