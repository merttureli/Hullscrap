#!/usr/bin/env python3
"""Writes data/ship_styles.json (the race styles) and the `style` blocks of the factions without one (concord, hollow in data/enemy_tables.json;
barons, leviathans in their packs' enemy_tables.json) from the compact table below. Run from the repo root: python3 tests/tool_make_ship_styles.py
The prototype styles (kett, prismatic, grundl and the four gangs) are kept as they are in the files; this only adds the others.
Everything the table says is data: tune the generated JSON, or this table and re-run (it never touches a style that is already in the file)."""
import json, glob, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
tables = json.load(open('data/enemy_tables.json'))['factions']


def star(n, r_out=0.46, r_in=0.2):
    pts = []
    for i in range(2 * n):
        a = -math.pi / 2 + i * math.pi / n
        r = r_out if i % 2 == 0 else r_in
        pts.append([round(0.5 + r * math.cos(a), 3), round(0.5 + r * math.sin(a), 3)])
    return pts


def ngon(n, r=0.45, rot=-math.pi / 2):
    return [[round(0.5 + r * math.cos(rot + i * 2 * math.pi / n), 3), round(0.5 + r * math.sin(rot + i * 2 * math.pi / n), 3)] for i in range(n)]


def P(pts, fill=False): return {"poly": pts, "fill": fill}
def C(x, y, r, fill=False): return {"circle": [x, y, r], "fill": fill}
def L(*pts): return {"line": [v for p in pts for v in p]}


EMB = {
    "human": [C(0.5, 0.5, 0.44), P(star(5, 0.32, 0.14), True)],
    "basalt": [P([[0.05, 0.9], [0.4, 0.15], [0.62, 0.55], [0.75, 0.35], [0.95, 0.9]], False), L([0.05, 0.9], [0.95, 0.9])],
    "emberkin": [P([[0.5, 0.05], [0.78, 0.45], [0.7, 0.9], [0.3, 0.9], [0.22, 0.45]], False), P([[0.5, 0.45], [0.6, 0.8], [0.4, 0.8]], True)],
    "fenn": [P([[0.1, 0.9], [0.1, 0.1], [0.4, 0.45]], True), P([[0.9, 0.9], [0.9, 0.1], [0.6, 0.45]], True), L([0.1, 0.9], [0.9, 0.9])],
    "mire": [P([[0.5, 0.05], [0.8, 0.55], [0.75, 0.85], [0.5, 0.95], [0.25, 0.85], [0.2, 0.55]], False), L([0.3, 0.65], [0.5, 0.75], [0.7, 0.65])],
    "sporeling": [P([[0.08, 0.55], [0.2, 0.25], [0.5, 0.1], [0.8, 0.25], [0.92, 0.55]], True), P([[0.42, 0.55], [0.42, 0.92], [0.58, 0.92], [0.58, 0.55]], False)],
    "gauntling": [P(ngon(8, 0.46, math.pi / 8), False), C(0.5, 0.5, 0.17, True)],
    "vellum": [P([[0.1, 0.1], [0.7, 0.1], [0.9, 0.3], [0.9, 0.9], [0.1, 0.9]], False), L([0.7, 0.1], [0.7, 0.3], [0.9, 0.3])],
    "oorth": [P([[0.15, 0.95], [0.15, 0.4], [0.5, 0.05], [0.85, 0.4], [0.85, 0.95]], False), C(0.5, 0.5, 0.09, True)],
    "drakkin": [L([0.2, 0.08], [0.35, 0.92]), L([0.5, 0.08], [0.6, 0.92]), L([0.8, 0.08], [0.85, 0.92])],
    "wisp": [L([0.5, 0.5], [0.58, 0.45], [0.62, 0.55], [0.5, 0.68], [0.32, 0.6], [0.28, 0.38], [0.45, 0.2], [0.72, 0.25], [0.85, 0.5])],
    "hullkin": [C(0.3, 0.7, 0.18, True), C(0.7, 0.7, 0.18, True), C(0.5, 0.3, 0.18, True)],
    "lantern": [P([[0.3, 0.2], [0.7, 0.2], [0.75, 0.85], [0.25, 0.85]], False), L([0.38, 0.1], [0.62, 0.1]), C(0.5, 0.52, 0.1, True)],
    "revenant": [C(0.5, 0.5, 0.42), L([0.2, 0.8], [0.8, 0.2])],
    "choir": [L([0.3, 0.1], [0.3, 0.6], [0.7, 0.6], [0.7, 0.1]), L([0.5, 0.6], [0.5, 0.95])],
    "rattler": [P([[0.55, 0.05], [0.25, 0.55], [0.48, 0.55], [0.4, 0.95], [0.78, 0.4], [0.52, 0.4]], True)],
    "tessellate": [P([[0.08, 0.08], [0.46, 0.08], [0.46, 0.46], [0.08, 0.46]], True), P([[0.54, 0.54], [0.92, 0.54], [0.92, 0.92], [0.54, 0.92]], True), P([[0.54, 0.08], [0.92, 0.08], [0.92, 0.46], [0.54, 0.46]], False), P([[0.08, 0.54], [0.46, 0.54], [0.46, 0.92], [0.08, 0.92]], False)],
    "sable": [L([0.5, 0.05], [0.5, 0.75]), L([0.5, 0.75], [0.3, 0.9], [0.15, 0.7]), L([0.5, 0.75], [0.7, 0.9], [0.85, 0.7]), C(0.5, 0.12, 0.07)],
    "quillback": [L([0.5, 0.92], [0.1, 0.3]), L([0.5, 0.92], [0.3, 0.1]), L([0.5, 0.92], [0.5, 0.05]), L([0.5, 0.92], [0.7, 0.1]), L([0.5, 0.92], [0.9, 0.3])],
    "kite": [P([[0.5, 0.05], [0.8, 0.4], [0.5, 0.75], [0.2, 0.4]], False), L([0.5, 0.75], [0.4, 0.88], [0.55, 0.95])],
    "warden_frame": [P([[0.08, 0.08], [0.92, 0.08], [0.92, 0.92], [0.08, 0.92]], False), P([[0.3, 0.3], [0.7, 0.3], [0.7, 0.7], [0.3, 0.7]], False), L([0.08, 0.08], [0.3, 0.3]), L([0.92, 0.92], [0.7, 0.7])],
    "murrow": [L([0.12, 0.2], [0.88, 0.8]), L([0.88, 0.2], [0.12, 0.8]), C(0.5, 0.5, 0.1, True)],
    "siltborn": [C(0.5, 0.5, 0.42), L([0.1, 0.4], [0.9, 0.4]), L([0.12, 0.62], [0.88, 0.62])],
    "corvin": [L([0.05, 0.3], [0.3, 0.7], [0.5, 0.35], [0.7, 0.7], [0.95, 0.3]), C(0.5, 0.8, 0.07, True)],
    "brine": [P([[0.15, 0.95], [0.1, 0.4], [0.3, 0.1], [0.45, 0.4], [0.35, 0.5], [0.3, 0.3], [0.25, 0.5], [0.3, 0.95]], False), P([[0.85, 0.95], [0.9, 0.4], [0.7, 0.1], [0.55, 0.4], [0.65, 0.5], [0.7, 0.3], [0.75, 0.5], [0.7, 0.95]], False)],
    "echo": [C(0.36, 0.5, 0.3), C(0.64, 0.5, 0.3)],
    "ferro": [L([0.2, 0.1], [0.2, 0.6]), L([0.8, 0.1], [0.8, 0.6]), L([0.2, 0.6], [0.3, 0.85], [0.5, 0.92], [0.7, 0.85], [0.8, 0.6]), L([0.12, 0.1], [0.28, 0.1]), L([0.72, 0.1], [0.88, 0.1])],
    # factions without a style
    "concord": [C(0.5, 0.5, 0.44), L([0.5, 0.15], [0.5, 0.85]), L([0.2, 0.35], [0.8, 0.35]), L([0.2, 0.35], [0.12, 0.6], [0.28, 0.6], [0.2, 0.35]), L([0.8, 0.35], [0.72, 0.6], [0.88, 0.6], [0.8, 0.35])],
    "hollow": [C(0.5, 0.5, 0.4), L([0.2, 0.2], [0.8, 0.8]), C(0.5, 0.5, 0.06, True)],
    "barons": [P([[0.08, 0.8], [0.08, 0.3], [0.28, 0.5], [0.5, 0.15], [0.72, 0.5], [0.92, 0.3], [0.92, 0.8]], False), L([0.08, 0.92], [0.92, 0.92])],
    "leviathans": [L([0.5, 0.92], [0.5, 0.55], [0.25, 0.3], [0.1, 0.05]), L([0.5, 0.55], [0.75, 0.3], [0.9, 0.05]), L([0.5, 0.92], [0.42, 0.98])],
}

# hull presets: (prow, tail, band gun/bridge/core/aux/engine, jitter_w, asym, ops, extras). Every one has 4+ chamfers or arcs so a hull is never a box.
def ops(tip=2, shoulder=(2, 3), stern=2, wedge=None, spikes=None, arc=False):
    o = []
    if wedge: o.append({"op": "wedge", "at": "bow", "slope": [wedge], "chance": 1.0})
    if arc:
        o += [{"op": "arc", "at": "tip", "count": [2, 2]}, {"op": "chamfer", "at": "shoulder", "kind": ["45"], "n": list(shoulder)}, {"op": "arc", "at": "stern_end", "count": [2, 2]}, {"op": "chamfer", "at": "stern_end", "kind": ["45"], "n": [1, 2]}]
    else:
        o += [{"op": "chamfer", "at": "tip", "kind": ["45"], "n": [tip, tip + 1]}, {"op": "chamfer", "at": "shoulder", "kind": ["45"], "n": list(shoulder)}, {"op": "chamfer", "at": "stern_end", "kind": ["45"], "n": [stern, stern + 1]}]
    if spikes: o.append({"op": "spikes", "count": list(spikes), "depth": 1})
    return o


def hull(prow, tail, band, jw=(0, 0), asym=False, op=None, **extra):
    h = {"prow": list(prow), "tail": list(tail), "band": dict(zip(["gun", "bridge", "core", "aux", "engine"], band)), "jitter_w": list(jw), "jitter_c": 0, "asym": asym, "ops": op or ops()}
    h.update(extra)
    return h


PRESETS = {
    "wedge": hull((3, 5), (0, 2), (0.3, 0.7, 0.9, 0.85, 1.0), (0, 2), True, ops(wedge="45", spikes=(2, 3))),          # long narrow bow, wide stern
    "brick": hull((0, 0), (0, 0), (0.75, 1.0, 1.0, 1.0, 1.0), (2, 4), False, ops(1, (1, 1), 1), max_fill=0.93),      # a wide slab
    "needle": hull((4, 6), (2, 4), (0.25, 0.45, 0.6, 0.5, 0.4), (0, 0), False, ops(2, (3, 4), 2, "45")),             # long, thin, symmetric
    "hammer": hull((0, 1), (1, 3), (1.0, 0.55, 0.8, 0.6, 0.5), (0, 2), False, ops(1, (2, 3), 2)),                    # a wide bow on a narrow neck
    "dumbbell": hull((1, 2), (0, 1), (0.85, 0.4, 0.4, 0.45, 0.85), (0, 0), False, ops(3, (3, 4), 3)),                  # wide at both ends
    "bulb": hull((1, 2), (1, 2), (0.4, 0.7, 1.0, 1.0, 0.75), (0, 2), False, ops(arc=True)),                          # a rounded belly
    "round": hull((0, 1), (0, 1), (0.55, 0.9, 1.0, 0.95, 0.75), (2, 3), False, ops(arc=True)),                       # homestead round
    "tri": hull((2, 4), (0, 1), (0.3, 0.5, 0.7, 0.9, 1.0), (0, 0), False, ops(2, (2, 4), 1, "45")),                  # a wide stern
    "inverse": hull((0, 1), (3, 5), (1.0, 0.9, 0.7, 0.5, 0.3), (0, 0), False, ops(1, (2, 3), 3)),                    # a wide bow
    "ragged": hull((1, 3), (0, 2), (0.45, 0.7, 0.95, 0.8, 0.7), (1, 4), True, ops(2, (1, 2), 1, "45", (3, 5))),      # asymmetric junk
    "facet": hull((3, 5), (2, 4), (0.3, 0.6, 1.0, 0.75, 0.4), (0, 0), False, ops(3, (3, 5), 3, "45"), spine="neon_lattice"),  # symmetric points
    "cross": hull((2, 3), (1, 2), (0.45, 0.6, 1.0, 0.6, 0.5), (0, 2), False, ops(2, (2, 3), 2)),                      # wide only in the middle
}

# race: base, label, roles, family (dominant colour name), tint, accent, floor, wall, glow, dressing, preset, signature note
R = [
    ("human", "concord", "Human", "cutter frigate cruiser", "blue", "#7aa4e8", "#f2f6ff", "#9ec0ff", "#4a78c8", "#aaccff", [("spars", (3, 5), "any", True, 3.2)], "hammer"),
    ("basalt", "clans", "Basalt", "chunk quarrier slab-ship", "grey", "#8a8a90", "#d8d2c0", "#a8a49c", "#5c5a58", "#ffb060", [("slabs", (5, 8), "any", False, 0.9)], "brick"),
    ("emberkin", "wardens", "Emberkin", "spark kiln forge", "orange", "#e8782a", "#ffd060", "#ff9a40", "#a8480e", "#ff8030", [("fins", (4, 6), "flank", True, 3.0)], "tri"),
    ("fenn", "clans", "Fenn", "scamp haggler barter-ship", "yellow", "#e8d050", "#6a4a20", "#f0e080", "#a89030", "#fff090", [("lanterns", (6, 9), "any", False, 1.4)], "hammer"),
    ("mire", "concord", "Mire", "ripple bogger fenwalker", "teal", "#3ab0a0", "#e0fff4", "#70d8c8", "#1a6860", "#60ffe0", [("tarps", (4, 6), "flank", False, 1.0)], "bulb"),
    ("sporeling", "wardens", "Sporeling", "puffball bloom garden", "lime", "#8ad040", "#f0ffb0", "#b8f070", "#4a7a20", "#c8ff60", [("pods", (6, 10), "any", False, 1.3)], "bulb"),
    ("gauntling", "clans", "Gauntling", "welder patchwork rebuild", "steel", "#8898a8", "#ff9040", "#98a8b8", "#506070", "#ffa050", [("scrap", (5, 8), "any", False, 1.3)], "ragged"),
    ("vellum", "wardens", "Vellum", "fold crease origami", "white", "#f4efe0", "#e8c8a0", "#fff8e8", "#c8c0a8", "#fff0c0", [("tarps", (3, 5), "any", True, 0.9)], "round"),
    ("oorth", "concord", "Oorth", "hush veil quietude", "indigo", "#5a5ab8", "#c8b8ff", "#7a78d8", "#34346a", "#a8a0ff", [("spars", (2, 4), "any", True, 4.0)], "hammer"),
    ("drakkin", "clans", "Drakkin", "fang claw wyrm", "maroon", "#a02838", "#f0c040", "#c04050", "#601020", "#ffb040", [("ribs", (8, 12), "flank", False, 1.4)], "inverse"),
    ("wisp", "wardens", "Wisp", "flicker streamer stormcloud", "cyan", "#50d8f0", "#e8ffff", "#90f0ff", "#287898", "#a0f8ff", [("fins", (6, 9), "any", True, 2.4)], "facet"),
    ("hullkin", "clans", "Hullkin", "barnacle reef-hulk drydock", "sand", "#d8b878", "#a8683a", "#e8d098", "#9a7a48", "#ffc880", [("scrap", (8, 12), "any", False, 0.9)], "round"),
    ("lantern", "concord", "Lantern", "moth glowwing beacon", "peach", "#f8b088", "#fff0d0", "#ffd0a8", "#c07850", "#ffd890", [("lanterns", (3, 5), "front", True, 1.8)], "tri"),
    ("revenant", "hollow", "Revenant", "wraith husk lingerer", "black", "#42464e", "#c0ffd0", "#58606c", "#22262e", "#80ffa0", [("spars", (3, 6), "any", False, 3.0)], "ragged"),
    ("choir", "wardens", "Choir", "chime anthem chantry", "pink", "#f0a8d8", "#fff0fa", "#ffd0ee", "#b06890", "#ffc0f0", [("shards", (5, 8), "any", True, 2.0)], "facet"),
    ("rattler", "clans", "Rattler", "scrapling gremlin heap", "copper", "#c8784a", "#ffe0a0", "#e09868", "#7a4020", "#ffb868", [("ribs", (6, 10), "any", False, 1.0)], "ragged"),
    ("tessellate", "concord", "Tessellate", "tile mosaic lattice-ship", "mint", "#90e8c0", "#ffffff", "#c0fff0", "#50a888", "#b0ffe0", [("slabs", (5, 8), "any", True, 0.7)], "brick"),
    ("sable", "clans", "Sable", "boarder slipknot reaver", "navy", "#2c3c70", "#ff7050", "#4a5c9a", "#18204a", "#ff8860", [("spikes", (5, 8), "any", False, 1.6)], "wedge"),
    ("quillback", "clans", "Quillback", "pricker duellist porcupine", "khaki", "#b0a060", "#6a5028", "#d0c488", "#7a6a38", "#ffd878", [("spikes", (9, 14), "flank", False, 1.5)], "cross"),
    ("kite", "clans", "Kite", "skimmer tumbler windrider", "lilac", "#b8a0e8", "#ffffff", "#d8c8ff", "#7864b0", "#e0d0ff", [("fins", (3, 5), "any", True, 2.8)], "tri"),
    ("warden_frame", "wardens", "Warden-frame", "unit keeper-frame bastion-frame", "slate", "#5a8898", "#a8f0e0", "#78a8b8", "#304c5c", "#80f8e0", [("spars", (4, 6), "stern", True, 2.6)], "cross"),
    ("murrow", "clans", "Murrow", "digger borer tunneller", "umber", "#7a5a3a", "#e0b070", "#9a7a54", "#4a3220", "#ffb060", [("slabs", (4, 7), "bow", False, 1.1)], "inverse"),
    ("siltborn", "wardens", "Siltborn", "drifter float gasbag", "mauve", "#a888a8", "#f0e0f0", "#c8a8c8", "#705070", "#f0c0f0", [("pods", (4, 6), "any", True, 2.0)], "bulb"),
    ("corvin", "clans", "Corvin", "scrounger crow carrion-ship", "charcoal", "#585868", "#e0e0f8", "#707084", "#303040", "#c0c8ff", [("lanterns", (3, 5), "any", False, 1.2)], "hammer"),
    ("brine", "concord", "Brine", "shellback dockhand crabber", "coral", "#f08068", "#fff0e0", "#ffa090", "#a04838", "#ffb0a0", [("slabs", (4, 6), "front", True, 1.0)], "round"),
    ("echo", "wardens", "Echo", "mimic reflection double", "silver", "#d0d8e8", "#ffffff", "#e8eef8", "#8890a0", "#f0f8ff", [("shards", (4, 6), "any", False, 1.6)], "wedge"),
    ("ferro", "clans", "Ferro", "slick magnet flux-ship", "gunmetal", "#506078", "#a0c0ff", "#687890", "#283448", "#90b8ff", [("shards", (7, 11), "stern", False, 1.8)], "needle"),
]
# factions without a style
F = [
    ("concord", "Concord", "patrol frigate cruiser", "silver2", "#b8c4d8", "#2a4a8a", "#e8f0ff", "#9aa8c0", "#e0e8f8", [("ribs", (7, 11), "flank", False, 1.1)]),
    ("hollow", "Hollow", "echo gap absence", "void", "#4a4458", "#b8f0d8", "#1a1822", "#3a3448", "#90ffd0", [("shards", (5, 8), "any", False, 2.2)]),
    ("barons", "Baron", "tithe-cutter sovereign tyrant", "maroon2", "#8a2a48", "#f0c040", "#ffe090", "#a03a58", "#ffd060", [("lanterns", (4, 6), "front", True, 1.6)]),
    ("leviathans", "Leviathan", "calf starwhale grandmother", "deepblue", "#2a5a98", "#90e0ff", "#a8d8ff", "#3a70b0", "#80d0ff", [("ribs", (10, 15), "flank", True, 1.7)]),
]


def ent(kind, count, where, sym, ln):
    e = {"kind": kind, "count": list(count), "where": where, "len": ln}
    if sym: e["sym"] = True
    return e


def style(label, roles, tint, accent, floor, wall, glow, dressing, emblem, patch=None):
    s_, m_, l_ = roles.split() if len(roles.split()) == 3 else (roles.split()[0], roles.split()[1], roles.split()[-1])
    return {"label": label, "roles": {"small": s_, "medium": m_, "large": l_},
            "palette": {"tint": tint, "accent": accent, "lamp": glow, "glow": glow, "floor": floor, "wall": wall, "patch": patch or ["#ffffff", "#e8e8e8"]},
            "dressing": [ent(*d) for d in dressing], "emblem": {"prims": emblem}}


def prefer_of(base, rid):
    """Two or three weapons of the base faction's menu a race with no pack of its own leans on (weights x3)."""
    ids = [m["id"] for m in tables[base]["parts"]["weapons"]]
    n = sum(ord(c) for c in rid)
    pick = {ids[n % len(ids)], ids[(n // 3 + 1) % len(ids)]}
    return {i: 2.0 for i in pick}


# the signature parts of the race packs (data/packs/tech_<race>): weapons, shield, engine
def pack_parts(rid):
    path = 'data/packs/tech_%s/components.json' % rid
    if not os.path.exists(path):
        return None
    d = json.load(open(path)); d = d.get('components', d)
    w = json.load(open('data/packs/tech_%s/weapons.json' % rid)); w = w.get('weapons', w)
    wd = w if isinstance(w, dict) else {x['id']: x for x in w}
    weapons, shields, engines = [], [], []
    for c in d:
        t = int(c.get('tier', 1))
        frm = {1: 0, 2: 30, 3: 60}.get(t, 60)
        if c['family'] == 'weapon' and c['id'] in wd:
            x = wd[c['id']]
            dmg = float(x['damage']) * float(x['shots']) * {"laser": 1.0, "bolt": 0.9, "flak": 0.5, "missile": 1.15, "beam": 0.9}.get(x['kind'], 1.0)
            weapons.append({"id": c['id'], "cost": {1: 10, 2: 14, 3: 20}.get(t, 14), "weight": 3, "from": frm, "_dmg": dmg})
        elif c['family'] == 'shield':
            lay = int(c.get('stats', {}).get('layers', 2))
            shields.append({"id": c['id'], "cost": {2: 14, 3: 30, 4: 36}.get(lay, 30), "weight": 3, "from": {2: 0, 3: 60, 4: 36}.get(lay, 60)})
        elif c['family'] == 'engine':
            engines.append({"id": c['id'], "cost": 12, "from": 40})
    return weapons, shields, engines


def build_race(rid, base, label, roles, fam, tint, accent, floor, wall, glow, dressing, preset):
    st = {"base": base, "crew": {"species": [rid]}, "hull": json.loads(json.dumps(PRESETS[preset])),
          "style": style(label, roles, tint, accent, floor, wall, glow, dressing, EMB[rid])}
    if base != "clans" and base != "concord" and base != "wardens" and base != "hollow":
        pass
    st["style"]["palette"]["wall"] = wall
    pp = pack_parts(rid)
    bw = tables[base]["parts"]["weapons"]
    if pp and pp[0]:
        weapons, shields, engines = pp
        mid = sorted(bw, key=lambda m: m["cost"])[:2]
        sig = []
        for w in weapons:
            w.pop("_dmg", None)
            if base == "wardens":
                w["from"] = max(w["from"], 30)  # the base is anaemic at stage 1: so is the race
            sig.append(w)
        st["parts"] = {"weapons": [dict(m, weight=2) for m in mid] + sig}
        if shields:
            if base == "wardens":
                for sh in shields:
                    sh["from"] = max(sh["from"], 36)  # as the base's own shields: none at stage 1
            st["parts"]["shields"] = [dict(m) for m in tables[base]["parts"]["shields"][-1:]] + shields
        if engines: st["parts"]["engines"] = [dict(m) for m in sorted(tables[base]["parts"]["engines"], key=lambda m: m["cost"])[:1]] + engines
    else:
        st["prefer"] = {"weapons": prefer_of(base, rid)}
    return st


def fmt(v, depth=0):
    """JSON with the first three levels on lines (tabs) and everything deeper on one line, like the other data files."""
    if depth >= 3 or not isinstance(v, (dict, list)) or not v:
        return json.dumps(v)
    pad = '\t' * (depth + 1)
    if isinstance(v, dict):
        return '{\n' + ',\n'.join('%s%s: %s' % (pad, json.dumps(k), fmt(x, depth + 1)) for k, x in v.items()) + '\n' + '\t' * depth + '}'
    return '[\n' + ',\n'.join(pad + fmt(x, depth + 1) for x in v) + '\n' + '\t' * depth + ']'


def main():
    path = 'data/ship_styles.json'
    d = json.load(open(path))
    for r in R:
        rid = r[0]
        if rid in d["races"]:
            continue
        d["races"][rid] = build_race(*r)
    open(path, 'w').write(fmt(d) + '\n')
    # faction styles: the block is put in as text before the faction's "hull" (the files are hand-formatted)
    for fid, label, roles, fam, tint, accent, floor, wall, glow, dressing in F:
        for p in ['data/enemy_tables.json', 'data/packs/faction_%s/enemy_tables.json' % fid]:
            if not os.path.exists(p):
                continue
            text = open(p).read()
            t = json.loads(text)
            if fid in t['factions'] and 'style' not in t['factions'][fid]:
                i = text.index('"%s": {' % fid)
                j = text.index('"hull": {', i)
                blk = json.dumps(style(label, roles, tint, accent, floor, wall, glow, dressing, EMB[fid]))
                text = text[:j] + '"style": ' + blk + ',\n\t\t\t' + text[j:]
                json.loads(text)
                open(p, 'w').write(text)
    print(len(d["races"]), "races")


if __name__ == '__main__':
    main()
