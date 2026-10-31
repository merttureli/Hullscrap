"""Hand weapons for the six race-wave-1 races (art/items/): 12 held sprites (each is also the item's icon) + 8 muzzle flashes (art/items/fx/).
Same format as sp_items.py: interior-only art facing UP, outlined on export, `grip` = the pixel the hand closes on, `muzzle` = where shots / the
tip are (interior coords), class = the arm pose, an optional soft glow layer. No new palette colours: only the letters the race tech already uses.
Race signatures (docs/waves/racial_tech_1.md): Kett amber chitin (y/a/u, seams n, joints q/Q) with dark compound-eye lamps and green venom;
Mire wet teal housings (U/T/t), brass pipes (y/a/u), red hand-wheels (r), glass and steam (c/C/H); Sporeling cream and brown (f/Q/q/n) grown housings,
violet spore sacs (X/V/Z), gill lines; Gauntling mismatched steel / rust / copper (a/u) with colour-coded wires and cyan arcs; Prismatic faceted violet
and navy (V/Z/N/J) with cyan / magenta / white cores; Grundl dark riveted gunmetal (E/D/W) with amber stencils and chains.
ORDER lists the ids; export_all() writes the items and the flashes (build_all.py calls it); python3 hand_race.py does just that.
The glow of an item is "strongest light wins" per pixel (glow_max), so every glow pixel is an exact palette hue (only its alpha varies)."""
import os, json
from px import *
import pal_races1          # noqa: F401  the three Mire greens (T t U) must exist before the sprites are drawn
import pal_lines           # noqa: F401  navy, neon cyan / magenta and violet letters
from mach import glow
import sp_items
from sp_fx import PAD

def A(name, rows, w, h):
    """a strictly rectangular ASCII sprite of w x h."""
    return from_art(art_strict(rows, w, h, name))

def jdump(obj, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f: json.dump(obj, f, indent=1); f.write('\n')

HAND = {}
def item(id, spr, grip, muzzle, cls, culture, foregrip=None, glow=None, notes=''):
    HAND[id] = dict(id=id, spr=spr, grip=grip, muzzle=muzzle, cls=cls, culture=culture, foregrip=foregrip, glow=glow or [], notes=notes)

def tube(s, x, y, w, h, hi='M', mid='S', lo='W'):
    """a vertical bar with a light left edge and a dark right edge."""
    for j in range(h):
        for i in range(w): s.put(x + i, y + j, hi if i == 0 else lo if i == w - 1 else mid)

def band(s, x, y, w, hi, mid, lo, h=1):
    """a clamp / collar: a horizontal band, light on the left, dark on the right."""
    for j in range(h):
        for i in range(w): s.put(x + i, y + j, hi if i == 0 else lo if i == w - 1 else mid)

def shade_edges(s, base, hi, lo):
    """recolour `base` pixels that border empty space: hi on the top / left, lo on the bottom / right (top-left light)."""
    n = s.copy()
    for y in range(s.h):
        for x in range(s.w):
            if s.g[y][x] != base: continue
            if s.get(x, y + 1) == '.' or s.get(x + 1, y) == '.': n.g[y][x] = lo
            elif s.get(x, y - 1) == '.' or s.get(x - 1, y) == '.': n.g[y][x] = hi
    s.g = n.g

def stroke(s, pts, c, w=2):
    """a w-px thick polyline."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1):
            x = x0 + round((x1 - x0) * i / n); y = y0 + round((y1 - y0) * i / n)
            for j in range(w):
                for k in range(w): s.put(x + k, y + j, c)

# ===================================================================== KETT: amber chitin, green venom, dark compound-eye lamps
# ---- sting_pistol: a grown needle gun. A cream needle through a chitin collar, a green venom sac under a hex window, an eye-lamp sight.
item('sting_pistol', A('sting_pistol', """
...H...
...f...
...f...
..yfQ..
.yaaau.
.agggu.
.agHgu.
.agggu.
.yaaau.
.unrnu.
..aqu..
..qQn..
..QQn..
..qQn..
...n...
""", 7, 15), grip=(3, 12), muzzle=(3, -1), cls='pistol', culture='kett',
     glow=[('g', (107, 211, 74), 2.6, 0.55), ('r', (224, 65, 59), 2.0, 0.5)],
     notes='Kett sting pistol: a cream chitin needle through an amber collar, a green venom sac behind a window, a dark compound-eye lamp for a sight. Short, quick, light.')

# ---- hive_prod: a long chitin pole with a pair of honeycomb cells (one yellow, one green) round a stinger, a wrapped grip, an eye-lamp in the pommel.
s = A('hive_prod', """
...H...
...f...
..yfQ..
..uuu..
.uyyyu.
.uyHyu.
.auuua.
.ugggu.
.ugHgu.
..uuu..
""", 7, 10)
t = Spr(7, 25); t.stamp(0, 0, s.rows()); s = t
for y in range(10, 22): tube(s, 2, y, 3, 1, 'y', 'a', 'u')
for y in (13, 21): band(s, 1, y, 5, 'Q', 'q', 'n')                      # joints
for y in range(15, 21):                                                 # wrapped grip
    s.put(2, y, 'Q'); s.put(3, y, 'q'); s.put(4, y, 'n')
for y in (16, 18): s.hline(2, y, 3, 'n')
s.stamp(1, 22, """
.yaaau.
.unrnu.
..aua..
""".strip('\n'))
item('hive_prod', s, grip=(3, 18), muzzle=(3, -1), cls='melee', culture='kett',
     glow=[('g', (107, 211, 74), 2.4, 0.5), ('y', (255, 210, 58), 2.0, 0.4)],
     notes='Kett hive prod: a long amber chitin pole topped by two honeycomb cells (one yellow, one green) round a cream stinger; a quick jab. Wrapped grip, a dark eye-lamp in the pommel.')

# ===================================================================== MIRE: wet teal housings, brass pipes, red hand-wheels, glass and steam
# ---- bubble_rifle: a flared brass mouth on a steel pipe, a glass foam tank (bubbles in it) in a teal housing, a red hand-wheel valve, a rubber grip.
s = Spr(9, 31)
s.stamp(0, 0, """
.yaaaaau.
..yaaau..
...aua...
""")
tube(s, 3, 3, 3, 11, 'L', 'M', 'S')
for y in (5, 9): band(s, 2, y, 5, 'y', 'a', 'u')
s.stamp(0, 14, """
.yaaaaau.
UTTTTTTtt
UTNNNNNTt
UTNcHNNTt
UTNNcNNTt
UTNHNcNTt
UTNNNNNTt
UTTTTTTtt
.yaaaaau.
""")
s.stamp(0, 23, """
..UTTTt..
..UTTTt..
""")
for y in range(25, 31): tube(s, 3, y, 3, 1, 'T', 't', 'E')
for y in (26, 28): s.hline(3, y, 3, 'E')
s.stamp(5, 10, """
.rr
rLr
.rr
""")
item('bubble_rifle', s, grip=(4, 26), foregrip=(4, 11), muzzle=(4, -1), cls='rifle', culture='mire',
     glow=[('c', (60, 242, 255), 2.4, 0.5)],
     notes='Mire bubble rifle: a flared brass mouth on a steel pipe, a glass foam tank in a wet teal housing with bubbles in it, a red hand-wheel valve, a rubber grip. Fires foam; foam puts fires out.')

# ---- hook_gaff: a boathook. A steel pole with teal grip wraps and a red hand-wheel pommel, a brass socket, a big curved steel crook with a point.
s = Spr(11, 31)
stroke(s, [(6, 12), (6, 6), (5, 3), (3, 1), (1, 2), (0, 4), (0, 7), (1, 9)], 'S', 2)
shade_edges(s, 'S', 'M', 'W')
s.put(3, 1, 'L'); s.put(4, 1, 'L'); s.put(2, 2, 'L'); s.put(1, 9, 'L')
s.put(0, 4, 'M'); s.put(0, 5, 'M')
for y in range(12, 31): tube(s, 6, y, 3, 1, 'M', 'S', 'W')
band(s, 5, 10, 5, 'y', 'a', 'u', 3)
for y in range(16, 25): s.put(6, y, 'U' if y % 2 else 'T'); s.put(7, y, 'T' if y % 2 else 't'); s.put(8, y, 't')
for y in (18, 20, 22): s.hline(6, y, 3, 'E')
s.stamp(5, 26, """
.rr.
rLLr
.rr.
""".strip('\n'))
s.stamp(6, 29, """
yau
""")
item('hook_gaff', s, grip=(7, 20), muzzle=(5, -1), cls='melee', culture='mire',
     notes='Mire hook gaff: a boathook. A steel pole with teal grip wraps, a brass socket, a big curved steel crook with a point, a red hand-wheel at the butt.')

# ===================================================================== SPORELING: grown cream and brown housings, violet spore sacs, gill lines
# ---- spore_puffer: a puffball bellows. A cream nozzle on a ribbed bellows, a violet spore sac with gills, a brown handle.
item('spore_puffer', A('spore_puffer', """
...fff...
...fnf...
...fQf...
..fQQQq..
.XXVVVZ..
XXHXVVZZ.
XXXVpVZZ.
XVVVVVVZ.
.VVVVVZZ.
..ZZZZZ..
..fQQQq..
..ffQqq..
...fQq...
...qQn...
...QQn...
...qQn...
....n....
""", 9, 17), grip=(4, 14), muzzle=(4, -1), cls='tool', culture='sporeling',
     glow=[('XV', (196, 160, 240), 2.6, 0.45)],
     notes='Sporeling spore puffer: a cream nozzle on a ribbed bellows, a violet spore sac with gills, a brown handle. Puffs spores that put a target to sleep.')

# ---- thorn_lash: a whip of thorns. A leaf-wrapped grip with a violet bulb pommel, a long curling vine bristling with cream thorns, a violet bud at the tip.
s = Spr(11, 31)
OFF = [0, 1, 2, 2, 2, 1, 0, -1, -2, -2, -2, -1, 0, 1, 1, 0]            # the vine's sway, y = 4..19
for k, off in enumerate(OFF):
    y = 4 + k
    s.put(4 + off, y, 'Q'); s.put(5 + off, y, 'q')
for k in (1, 4, 7, 10, 13):                                              # thorns, alternating sides, pointing up and out
    y = 4 + k; off = OFF[k]
    if k % 2:                                                            # right
        s.put(6 + off, y, 'f'); s.put(7 + off, y - 1, 'f'); s.put(7 + off, y, 'Q')
    else:                                                                # left
        s.put(3 + off, y, 'f'); s.put(2 + off, y - 1, 'f'); s.put(2 + off, y, 'Q')
for y in range(20, 31): tube(s, 4, y, 3, 1, 'Q', 'q', 'n')
for y in range(21, 28): s.put(4, y, 'U' if y % 2 else 'T'); s.put(5, y, 'T' if y % 2 else 't'); s.put(6, y, 't')
for y in (22, 24, 26): s.hline(4, y, 3, 'n')
s.stamp(3, 0, """
.XX.
XHVZ
XVVZ
.ZZ.
""".strip('\n'))
s.stamp(3, 27, """
.XXV.
XHVVZ
.ZZZ.
""".strip('\n'))
item('thorn_lash', s, grip=(5, 24), muzzle=(5, -1), cls='melee', culture='sporeling',
     glow=[('XV', (196, 160, 240), 2.4, 0.45)],
     notes='Sporeling thorn lash: a whip of thorns. A brown vine bristling with cream thorns, a violet bud at the tip, a leaf-wrapped grip and a violet bulb pommel.')

# ===================================================================== GAUNTLING: mismatched scrap, copper coils, colour-coded wires, cyan arcs
# ---- rivet_fist: a rivet driver bolted to the forearm. A hot rivet in a copper-wound nozzle, a wide knuckle block of mismatched plates (pale steel, rust) with a row of rivet heads, a strapped forearm brace.
item('rivet_fist', A('rivet_fist', """
....cLc....
...EMMSE...
...EMSWE...
...EyaaE...
...EuuuE...
...EyaaE...
...EuuuE...
..EEEEEEE..
EMLMEEEMLME
ELMSSSSuuWE
EMSSLSSuQuE
EMSSSSSuuuE
EMSLSSSuQuE
EWSSSSSuuuE
.EEEEEEEEE.
..EMSSSWE..
..EMSLSWE..
..EEEEEEE..
..qQQQQqn..
..nnnLnnn..
..qQQQQqn..
..nnnnnnn..
...nnnnn...
""", 11, 23), grip=(5, 16), foregrip=(5, 5), muzzle=(5, -1), cls='heavy', culture='gauntling',
     glow=[('c', (60, 242, 255), 2.4, 0.55)],
     notes='Gauntling rivet fist: a rivet driver bolted to the forearm. A hot rivet in a copper-wound nozzle, a wide knuckle block of mismatched plates (pale steel, rust) with a row of rivet heads, a strapped forearm brace. It pierces (later).')

# ---- arc_welder: a welding torch. Twin ball electrodes with a live cyan arc across them, a copper coil, a colour-coded wire down to a patched handle.
item('arc_welder', A('arc_welder', """
.LH.c.HL.
.MLcCcLM.
..S.c.W..
..S...W..
..MSSSW..
.MyaaauW.
.MuuuunW.
.MyaaauW.
.MuuuunW.
.MyaaauW.
..WSSSE..
..SrgbE..
..qQQnn..
..QQQn...
..qQQn...
..qQnn...
""", 9, 16), grip=(4, 13), muzzle=(4, -1), cls='tool', culture='gauntling',
     glow=[('cC', (60, 242, 255), 2.6, 0.6)],
     notes='Gauntling arc welder: twin ball electrodes with a live cyan arc between them, a copper coil, a colour-coded wire to a patched handle. Repairs, and shocks organic targets (later).')

# ===================================================================== PRISMATIC: faceted violet and navy, cyan / magenta / white light cores
# ---- lens_pistol: a faceted violet body with a ring lens at the muzzle splitting a cyan core.
item('lens_pistol', A('lens_pistol', """
..cHc..
.cCcCc.
.cH.Hc.
..cCc..
.XVZZZ.
.XVmZN.
.VVcZN.
.VVZZN.
..VZN..
..jJI..
..ZJI..
..ZIN..
..ZIN..
...N...
""", 7, 14), grip=(3, 11), muzzle=(3, -1), cls='pistol', culture='prismatic',
     glow=[('cHC', (60, 242, 255), 2.6, 0.6), ('m', (255, 79, 216), 2.2, 0.5)],
     notes='Prismatic lens pistol: a faceted violet body, a ring lens at the muzzle that focuses a cyan core, a magenta light in the receiver. Range +20%.')

# ---- shard_lance: a long faceted violet-and-navy shaft with cyan edge lines, a big crystal head and a floating shard either side, a magenta core.
s = Spr(9, 41)
s.stamp(0, 0, """
....H....
...cHc...
..cCHcC..
.cCcHcCB.
.cCCcCBB.
..CBcCB..
..cBCBB..
...BcB...
....B....
""")
s.put(0, 6, 'c'); s.put(8, 7, 'c'); s.put(0, 8, 'C'); s.put(8, 9, 'C')    # two orbiting shards
for y in range(9, 33):
    s.put(3, y, 'X'); s.put(4, y, 'V'); s.put(5, y, 'Z')
    s.put(2, y, 'J'); s.put(6, y, 'N')
for y in (12, 13, 20, 21):
    s.hline(1, y, 7, 'j' if y % 2 else 'J')
    s.put(4, y, 'c')
s.put(4, 16, 'm'); s.put(4, 17, 'H'); s.put(4, 18, 'm')
s.stamp(0, 33, """
..NJVZIN.
..IJVZNN.
...IVZN..
....ZN...
""")
for y in range(37, 41): tube(s, 3, y, 3, 1, 'Z', 'N', 'N')
item('shard_lance', s, grip=(4, 34), foregrip=(4, 17), muzzle=(4, -1), cls='heavy', culture='prismatic',
     glow=[('cH', (60, 242, 255), 2.8, 0.7), ('m', (255, 79, 216), 2.2, 0.55)],
     notes='Prismatic shard lance: a long faceted violet and navy shaft with cyan edge lines, a magenta core, a big cyan crystal head with a shard floating either side. Its shots split on hit (later).')

# ===================================================================== GRUNDL: dark riveted freight metal, amber stencils, chains
# ---- freight_hammer: a dock sledge. A squared riveted gunmetal head with an amber stencil band, a long haft with a hazard-tape grip, a wrist chain.
s = Spr(13, 38)
s.stamp(0, 0, """
.EEEEEEEEEEE.
EWSSSSSSSSSWE
EMLMSSSSSSSWE
EMEMMSSSSSSWE
EMMSaaaaaaSWE
EMSSannannSWE
EMSSaaaaaaSWE
EMMSSSSSSSWWE
EMLMMSSSSSWWE
EDDDDDDDDDDDE
.EEEEEEEEEEE.
""")
for (x, y) in ((1, 1), (11, 1), (1, 8), (11, 8)): s.put(x, y, 'L')
for y in range(11, 33): tube(s, 5, y, 3, 1, 'E', 'W', 'D')
for y in range(17, 30):
    c = ('a', 'D')[(y // 2) % 2]
    s.put(5, y, c); s.put(6, y, c); s.put(7, y, 'D' if c == 'a' else 'a')
band(s, 4, 11, 5, 'S', 'M', 'W')
s.stamp(4, 30, """
.SMMW.
.WSSE.
""".strip('\n'))
loop = [(4, 33), (3, 34), (3, 35), (4, 36), (5, 37), (6, 37), (7, 37), (8, 36), (9, 35), (9, 34), (8, 33)]      # a chain wrist loop: links alternate light and dark
for k, (x, y) in enumerate(loop): s.put(x, y, 'M' if k % 2 == 0 else 'W')
s.put(3, 34, 'L')
item('freight_hammer', s, grip=(6, 24), muzzle=(6, -1), cls='melee', culture='grundl',
     notes='Grundl freight hammer: a long-hafted dock sledge. A squared riveted gunmetal head with an amber stencil band, a hazard-taped haft, a wrist chain. Knocks a target back (later).')

# ---- chain_gun: a belt-fed heavy. A ribbed barrel jacket, a gunmetal receiver with an amber stencil and lamps, a belt of brass slugs on a chain, a pistol grip.
s = Spr(11, 38)
tube(s, 3, 0, 3, 4, 'M', 'S', 'W'); s.put(4, 0, 'D')
tube(s, 1, 3, 7, 11, 'S', 'W', 'E')
for y in (5, 8, 11): s.hline(1, y, 7, 'E'); s.hline(1, y + 1, 7, 'D')
for y in (3, 4, 6, 7, 9, 10, 12, 13): s.put(2, y, 'M')
s.stamp(0, 14, """
.EEEEEEEE.
EMLMSSSWWE
ELSSSSSSWE
ESSaaaaSWE
ESSannaSWE
ESSaaaaSWE
EMSSSSSSWE
EMSSSSSSWE
EMSSEEESWE
EWDEaoyEDE
EWDEEEEEDE
.EEEEEEEE.
""".strip('\n'))
s.put(1, 15, 'L'); s.put(7, 15, 'L')
# the belt: brass slugs on a chain hanging from the feed port down the right side
for k in range(5):
    y = 17 + k * 3
    s.put(9, y, 'y'); s.put(10, y, 'a'); s.put(9, y + 1, 'a'); s.put(10, y + 1, 'u')
    s.put(9, y + 2, 'M' if k % 2 else 'W'); s.put(10, y + 2, 'W')
for y in range(26, 38): tube(s, 2 if y < 34 else 3, y, 5 if y < 34 else 3, 1, 'E', 'W', 'D')
for y in (29, 31, 33, 35): s.hline(2 if y < 34 else 3, y, 5 if y < 34 else 3, 'D')
band(s, 1, 26, 7, 'S', 'W', 'E')
item('chain_gun', s, grip=(4, 31), foregrip=(4, 16), muzzle=(4, -1), cls='heavy', culture='grundl',
     glow=[('oy', (255, 138, 30), 2.4, 0.5)],
     notes='Grundl chain gun: a ribbed barrel jacket, a dark riveted receiver with an amber stencil and lamps, a belt of brass slugs on a chain, a pistol grip. Lighter slugs, faster.')

ORDER = ['sting_pistol', 'hive_prod', 'bubble_rifle', 'hook_gaff', 'spore_puffer', 'thorn_lash',
         'rivet_fist', 'arc_welder', 'lens_pistol', 'shard_lance', 'freight_hammer', 'chain_gun']

# ===================================================================== muzzle flashes (art/items/fx/muzzle_<name>): faces UP, the muzzle anchor at the base
def F(name, k, rows, w, h):
    return from_art(art_strict(rows, w, h, '%s f%d' % (name, k)))

def ring(s, cx, cy, r, c='c', hi='H'):
    """a bubble: r 0 = one pixel, 1 = a 3x3 diamond ring, 2 = a 5x5 round ring; a highlight pixel on its upper left."""
    if r == 0: s.put(cx, cy, hi); return
    pts = {1: [(0, -1), (-1, 0), (1, 0), (0, 1)], 2: [(-1, -2), (0, -2), (1, -2), (-2, -1), (2, -1), (-2, 0), (2, 0), (-2, 1), (2, 1), (-1, 2), (0, 2), (1, 2)]}[r]
    for dx, dy in pts: s.put(cx + dx, cy + dy, c)
    s.put(cx - r + 1, cy - r + 1, hi)

def blob(s, cx, cy, r, tones='XVZ'):
    """a flat puff: a disc, light upper left, dark lower right."""
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            d = (x - cx) ** 2 + (y - cy) ** 2
            if d <= r * r + r // 2:
                s.put(x, y, tones[0] if (x - cx) + (y - cy) < -r else tones[2] if (x - cx) + (y - cy) > r else tones[1])

def bolt(s, pts, core='H', halo='c'):
    allp = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1): allp.append((x0 + round((x1 - x0) * i / n), y0 + round((y1 - y0) * i / n)))
    for (x, y) in allp:
        for dx in (-1, 1):
            if s.get(x + dx, y) == '.': s.put(x + dx, y, halo)
    for (x, y) in allp: s.put(x, y, core)

def fx_sting():
    f = [F('sting', 0, """
....H....
....f....
....f....
....f....
g...f...g
.g.gfg.g.
..ggHgg..
..gfHfg..
...gfg...
....g....
....g....
....g....
....g....
""", 9, 13), F('sting', 1, """
.........
.........
....f....
....f....
....f....
g...f...g
.g.gfg.g.
..ggfgg..
...gHg...
....g....
....g....
....g....
....g....
""", 9, 13), F('sting', 2, """
.........
.........
.........
.........
....g....
.........
..g...g..
....f....
...g.g...
....g....
.........
....g....
....g....
""", 9, 13)]
    return f, (4, 12)

def fx_bubble():
    out = []
    for k in range(3):
        s = Spr(13, 15)
        if k == 0:
            ring(s, 6, 10, 2); ring(s, 2, 12, 1); ring(s, 10, 12, 1); ring(s, 6, 6, 1); ring(s, 4, 8, 0); ring(s, 9, 8, 0)
            s.put(6, 14, 'c'); s.put(6, 13, 'c')
        elif k == 1:
            ring(s, 6, 6, 2); ring(s, 2, 9, 1); ring(s, 10, 9, 1); ring(s, 6, 12, 1); ring(s, 3, 4, 0); ring(s, 10, 3, 0); ring(s, 8, 10, 0)
            s.put(6, 14, 'c')
        else:
            for (x, y) in ((6, 2), (2, 5), (10, 5), (4, 8), (8, 8)):
                s.put(x, y, 'H'); s.put(x - 1, y, 'c'); s.put(x + 1, y, 'c'); s.put(x, y - 1, 'c'); s.put(x, y + 1, 'c')
            ring(s, 6, 11, 0); ring(s, 1, 10, 0); ring(s, 11, 10, 0)
        out.append(s)
    return out, (6, 14)

def fx_puff():
    out = []
    for k in range(3):
        s = Spr(15, 15)
        if k == 0:
            blob(s, 7, 11, 2); blob(s, 4, 12, 1); blob(s, 10, 12, 1)
            for (x, y) in ((7, 7), (3, 9), (11, 9), (6, 5)): s.put(x, y, 'y')
        elif k == 1:
            blob(s, 7, 7, 3); blob(s, 3, 10, 2); blob(s, 11, 10, 2); blob(s, 7, 12, 1)
            for (x, y) in ((7, 2), (2, 6), (12, 6), (5, 3), (10, 3), (7, 10)): s.put(x, y, 'y' if (x + y) % 2 else 'f')
        else:
            blob(s, 7, 3, 2); blob(s, 2, 6, 1); blob(s, 12, 6, 1); blob(s, 4, 9, 1); blob(s, 10, 9, 1)
            for (x, y) in ((7, 0), (4, 2), (11, 2), (1, 3), (13, 3), (7, 7), (7, 12)): s.put(x, y, 'y' if (x + y) % 2 else 'f')
        out.append(s)
    return out, (7, 14)

def fx_rivet():
    f = [F('rivet', 0, """
......y......
......H......
......H......
..M...y...M..
...o..y..o...
....o.y.o....
.o...oyo...o.
..oo.oyo.oo..
...oooyooo...
....oyyyo....
....oyHyo....
.....oyo.....
......o......
......o......
......o......
......o......
......o......
""", 13, 17), F('rivet', 1, """
.............
.............
......y......
......y......
.c....y....c.
..M...y...M..
...o.ooo.o...
....ooyoo....
...ooyyyoo...
....oyHyo....
.....oyo.....
......o......
......o......
......o......
......o......
......o......
......o......
""", 13, 17), F('rivet', 2, """
.............
.............
.............
.............
.............
...M.....M...
.............
.c....y....c.
.............
.....o.o.....
......o......
......o......
......o......
......o......
......o......
......o......
......o......
""", 13, 17)]
    return f, (6, 16)

def fx_weld():
    out = []
    for pts, extra in (([(5, 10), (3, 8), (6, 6), (4, 3), (5, 0)], [(8, 4, 'c'), (1, 6, 'C')]),
                       ([(5, 10), (7, 7), (4, 5), (6, 2), (5, 0)], [(2, 3, 'c'), (9, 6, 'C')]),
                       ([(5, 10), (4, 7), (6, 4), (5, 2)], [(1, 4, 'C'), (9, 3, 'c')])):
        s = Spr(11, 11); bolt(s, pts, 'H', 'c')
        for (x, y, c) in extra: s.put(x, y, c)
        out.append(s)
    return out, (5, 10)

def fx_lens():
    f = [F('lens', 0, """
.....c.....
.....H.....
....cHc....
....cHc....
....cHc....
....cHc....
....cHc....
....cHc....
.c..cHc..c.
..c.cHc.c..
...ccHcc...
..ccHHHcc..
.ccHHyHHcc.
..ccHHHcc..
...ccHcc...
....cHc....
.....c.....
""", 11, 17), F('lens', 1, """
m....c....c
.m...H...c.
..m.cHc.c..
...mcHcc...
....cHc....
....cHc....
....cHc....
....cHc....
....cHc....
....cHc....
...ccHcc...
..ccHHHcc..
..cHHyHHc..
..ccHHHcc..
...ccHcc...
....cHc....
.....c.....
""", 11, 17), F('lens', 2, """
...........
.....c.....
...........
.....c.....
...........
.....H.....
...........
.m.......c.
...........
.....c.....
....c.c....
...c.H.c...
....cHc....
...........
.....c.....
.....c.....
.....c.....
""", 11, 17)]
    return f, (5, 16)

SH = [".c.", "cHC", "CCB", ".CB", ".B."]
def put_shard(s, x, y, rows=SH):
    for j, r in enumerate(rows):
        for i, c in enumerate(r): s.put(x + i, y + j, c)

def fx_shard():
    out = []
    for k in range(3):
        s = Spr(15, 19)
        if k == 0:
            put_shard(s, 6, 8); put_shard(s, 2, 11); put_shard(s, 10, 11)
            for y in (15, 16, 17, 18): s.put(7, y, 'C' if y % 2 else 'c')
        elif k == 1:
            put_shard(s, 6, 3); put_shard(s, 1, 7); put_shard(s, 11, 7); put_shard(s, 6, 11)
            s.put(7, 17, 'c'); s.put(7, 18, 'C')
        else:
            for (x, y) in ((7, 1), (3, 3), (11, 3), (1, 7), (13, 7), (7, 6), (5, 11), (9, 11)):
                s.put(x, y, 'H'); s.put(x, y - 1, 'c'); s.put(x - 1, y, 'c'); s.put(x + 1, y, 'c'); s.put(x, y + 1, 'c')
            s.put(7, 17, 'c'); s.put(7, 18, 'c')
        out.append(s)
    return out, (7, 18)

def fx_chain():
    f = [F('chain', 0, """
.....y.....
.....y.....
.....y.....
....oyo....
....oyo....
a..ooyoo..a
.a.oyHyo.a.
...oyHyo...
....oyo....
.....o.....
.....o.....
.....o.....
.....o.....
.....o.....
.....o.....
""", 11, 15), F('chain', 1, """
...........
...........
.....y.....
.....y.....
....oyo....
...ooyoo...
a..oyHyo..a
.a..oyo..a.
.....o.....
.....o.....
.....o.....
.....o.....
.....o.....
.....o.....
.....o.....
""", 11, 15), F('chain', 2, """
...........
...........
...........
...........
.....y.....
....ooo....
...oyHyo...
..a.ooo.a..
.....o.....
.....o.....
.....o.....
.....o.....
.....o.....
.....o.....
.....o.....
""", 11, 15)]
    return f, (5, 14)

# name -> (builder, mode, fps, glow rgb, glow radius, glow letters, the items it is for, class label)
FX = {
 'sting':  (fx_sting,  'once', 24, (107, 211, 74), 4, 'H', ['sting_pistol'], 'pistol (sting_pistol)'),
 'bubble': (fx_bubble, 'once', 16, (60, 242, 255), 5, 'H', ['bubble_rifle'], 'rifle (bubble_rifle)'),
 'puff':   (fx_puff,   'once', 12, (196, 160, 240), 6, 'y', ['spore_puffer'], 'tool (spore_puffer)'),
 'rivet':  (fx_rivet,  'once', 20, (255, 138, 30), 5, 'yH', ['rivet_fist'], 'heavy (rivet_fist)'),
 'weld':   (fx_weld,   'once', 24, (60, 242, 255), 5, 'H', ['arc_welder'], 'tool (arc_welder)'),
 'lens':   (fx_lens,   'once', 24, (60, 242, 255), 5, 'H', ['lens_pistol'], 'pistol (lens_pistol)'),
 'shard':  (fx_shard,  'once', 18, (60, 242, 255), 6, 'H', ['shard_lance'], 'heavy (shard_lance)'),
 'chain':  (fx_chain,  'once', 24, (255, 138, 30), 5, 'yH', ['chain_gun'], 'heavy (chain_gun)'),
}

def glow_max(layer, cx, cy, r, rgb, strength, power=1.6):
    """a soft disc where the strongest light wins per pixel (no blending), so every glow pixel keeps an exact palette hue."""
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if not (0 <= x < layer.w and 0 <= y < layer.h): continue
            d = ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) ** 0.5
            if d >= r: continue
            a = int(255 * strength * (1 - d / r) ** power)
            if a > 5 and a > layer.p[y][x][3]: layer.p[y][x] = list(rgb) + [a]

GLOW_BOOST = 1.3          # the strongest-wins glow has no additive build-up, so each strength is lifted a little to match the older item glows

def item_glow(it, margin=0):
    """the item's soft glow layer ((w + 2 * margin + 2 * GLOW_PAD) square-ish; margin 1 lines up with the outlined export frame), palette hues only."""
    sp = it['spr']; P = sp_items.GLOW_PAD
    g = Rgba(sp.w + 2 * margin + 2 * P, sp.h + 2 * margin + 2 * P)
    for chars, rgb, r, st in it['glow']:
        for y in range(sp.h):
            for x in range(sp.w):
                if sp.g[y][x] in chars: glow_max(g, x + margin + P + 0.5, y + margin + P + 0.5, r, rgb, min(1.0, st * GLOW_BOOST))
    return g

def kit_items(ids=None):
    """-> {id: {'spr', 'grip', 'muzzle', 'cls', 'glow'}} for sp_compose.SKit (interior coords; the compositor outlines after rotating)."""
    out = {}
    for k in (ids or ORDER):
        it = HAND[k]
        out[k] = {'spr': it['spr'], 'grip': tuple(it['grip']), 'muzzle': tuple(it['muzzle']), 'cls': it['cls'],
                  'glow': item_glow(it) if it['glow'] else None}
    return out

def fx_glow(spr, rgb, r, chars):
    g = Rgba(spr.w + 2 * PAD, spr.h + 2 * PAD)
    for y in range(spr.h):
        for x in range(spr.w):
            if spr.g[y][x] in chars: glow(g, x + PAD + 0.5, y + PAD + 0.5, r * 0.7, rgb, 0.55, 1.8)
    return g

def export_items():
    di = ART + '/items'
    for k in ORDER:
        it = HAND[k]
        spr = sp_items.outlined_item(it)
        save(spr, '%s/%s.png' % (di, k))
        J = {'frame': [spr.w, spr.h], 'anchors': sp_items.anchors(it), 'class': it['cls'], 'pose': it['cls'], 'culture': it['culture'],
             'notes': 'faces UP. grip = where the hand closes (goes on the arms pose mount of the item\'s class); muzzle = where shots, spray, sparks or the '
                      'tip are. This one sprite is both the held item and the item\'s icon. ' + it['notes']}
        if it['glow']:
            gl = item_glow(it, margin=1)
            gl.save('%s/%s_glow.png' % (di, k))
            J['glow'] = {'image': k + '_glow.png', 'frame': [gl.w, gl.h], 'offset': [-sp_items.GLOW_PAD, -sp_items.GLOW_PAD], 'blend': 'add (preferred) or alpha-over'}
        jdump(J, '%s/%s.json' % (di, k))
    for name, (fn, mode, fps, rgb, r, chars, items, label) in FX.items():
        frames, org = fn()
        w, h = frames[0].w, frames[0].h
        base = '%s/fx/muzzle_%s' % (di, name)
        save(sheet(frames, len(frames), w, h), base + '.png')
        gl = [fx_glow(f, rgb, r, chars) for f in frames]
        out = Rgba(gl[0].w * len(gl), gl[0].h)
        for i, g in enumerate(gl): out.blit_rgba(g, i * g.w, 0)
        out.save(base + '_glow.png')
        jdump({'frame': [w, h], 'mode': mode, 'anims': {'play': [0, len(frames), fps]}, 'anchors': {'muzzle': list(org)}, 'for_class': [label], 'for_item': items,
               'glow': {'image': 'muzzle_%s_glow.png' % name, 'frame': [gl[0].w, gl[0].h], 'offset': [-PAD, -PAD],
                        'anims': {'play': [0, len(frames), fps]}, 'blend': 'add (preferred) or alpha-over'},
               'notes': 'Hand-weapon muzzle flash, faces UP (rotation 0): put the muzzle anchor on the weapon\'s muzzle point and rotate with the weapon. Plays once per use.'},
              base + '.json')

def export_all():
    export_items()
    return len(ORDER), len(FX)

if __name__ == '__main__':
    print(export_all())
