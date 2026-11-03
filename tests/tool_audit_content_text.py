"""Throwaway content audit: typos and text-format problems in everything a player reads. Usage: python3 tests/tool_audit_content_text.py <dump> <repo>"""
import json, sys, re, collections, glob
D, R = sys.argv[1] + '/', sys.argv[2] + '/'
L = lambda n: json.load(open(D + n + '.json'))
texts = []  # (where, text)
def add(w, t):
    if isinstance(t, str) and t.strip(): texts.append((w, t))
for e in L('events'):
    add(e['id'] + ':title', e.get('title')); add(e['id'] + ':text', e.get('text'))
    for i, c in enumerate(e.get('choices', [])):
        add('%s:choice%d' % (e['id'], i), c.get('text'))
        for j, o in enumerate(c.get('outcomes', [])):
            add('%s:c%d.o%d' % (e['id'], i, j), o.get('text'))
            if o.get('after_win'): add('%s:c%d.o%d.after_win' % (e['id'], i, j), o['after_win'].get('text'))
    if e.get('after_win'): add(e['id'] + ':after_win', e['after_win'].get('text'))
for k, l in L('logs').items(): add('log:' + k, l.get('title')); add('log:' + k, l.get('text'))
for kind in ('components', 'items', 'materials', 'species', 'characters', 'unlocks', 'endings'):
    for c in L(kind):
        for f in ('blurb', 'lore', 'how', 'obtained', 'text'):
            add('%s:%s.%s' % (kind, c['id'], f), c.get(f))
for s in L('ships'):
    add('ship:' + s['id'], (s.get('design') or {}).get('blurb') if isinstance(s.get('design'), dict) else s.get('blurb'))
def strings(o, path, out):
    if isinstance(o, dict):
        for k, v in o.items(): strings(v, path + '.' + k, out)
    elif isinstance(o, list):
        for i, v in enumerate(o): strings(v, path + '[%d]' % i, out)
    elif isinstance(o, str) and len(o) > 25 and ' ' in o and not o.startswith('res://') and not o.startswith('#'): out.append((path, o))
for f in ['advisor', 'morale', 'boarding', 'mods', 'wardens', 'endings', 'crew', 'backstory', 'hazards', 'tide', 'lines', 'sectors_x']:
    try: d = json.load(open(R + 'data/%s.json' % f))
    except Exception: continue
    out = []; strings(d, f, out)
    out = [(p, t) for p, t in out if not p.endswith('_doc')]
    texts.extend(out)
for f in glob.glob(R + 'data/packs/*/*.json'):
    if f.endswith('logs.json') or f.endswith('names.json'): continue
print('text strings', len(texts))
allw = collections.Counter()
for w, t in texts:
    for m in [x.strip("'") for x in re.findall(r"[A-Za-z']+", t)]: allw[m.lower()] += 1
voc = {w for w, n in allw.items() if n >= 6 and len(w) >= 4}
def ed1(a, b):
    if abs(len(a) - len(b)) > 1 or a == b: return False
    if len(a) == len(b):
        d = [i for i in range(len(a)) if a[i] != b[i]]
        return len(d) == 1 or (len(d) == 2 and d[1] == d[0] + 1 and a[d[0]] == b[d[1]] and a[d[1]] == b[d[0]])
    if len(a) > len(b): a, b = b, a
    for i in range(len(b)):
        if a == b[:i] + b[i + 1:]: return True
    return False
cand = collections.defaultdict(list)
for w, n in allw.items():
    if n <= 2 and len(w) >= 5 and w not in voc:
        for v in voc:
            if ed1(w, v) and len(w) >= 6 and not (w.startswith(v[:-1]) or v.startswith(w[:-1])) and not (w.rstrip('s').rstrip("'") == v.rstrip('s')):
                cand[w].append(v); break
print('--- rare words one edit away from a common word (possible typos):')
where = collections.defaultdict(list)
for wh, t in texts:
    for m in set([x.strip("'") for x in re.findall(r"[A-Za-z']+", t)]):
        if m.lower() in cand: where[m.lower()].append(wh)
for w, vs in sorted(cand.items()): print('  ', w, '~', vs[0], where[w][:2], allw[w])
print('--- doubled words')
for wh, t in texts:
    for m in re.finditer(r'\b([A-Za-z]{2,})\s+\1\b', t, re.I):
        if m.group(1).lower() not in ('that', 'had'): print('  ', wh, '|', t[max(0, m.start() - 25):m.end() + 25].replace('\n', ' '))
print('--- spacing / punctuation')
cnt = collections.Counter()
for wh, t in texts:
    for pat, name in [(r'[a-z][.!?][A-Z][a-z]', 'no space after stop'), (r'\s,', 'space before comma'), (r'  +', 'double space'), (r'\s+$', 'trailing space'), (r'\.\.(?!\.)', 'two dots'), (r',,', 'double comma'), (r'\bi\b', 'lowercase i'), (r'\bteh\b|\brecieve|\bseperate|\boccured|\bwich\b|\bthier\b|\bdont\b|\bcant\b|\bwont\b', 'common misspelling')]:
        if re.search(pat, t):
            cnt[name] += 1
            if cnt[name] <= 6: print('  ', name, wh, '|', re.search(pat, t).group(0)[:30], '|', t[:70].replace('\n', ' '))
    if t.count('"') % 2 == 1: cnt['odd double quotes'] += 1; print('   odd quotes', wh, t[:70])
print(dict(cnt))
dash = sum(1 for _, t in texts if '—' in t); print('texts with em dash', dash, 'of', len(texts))
