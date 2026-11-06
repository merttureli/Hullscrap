"""The nine parts that drew as placeholders (owner playtest, 2026-11-06): the five smelters (lines_smelter.py) and the afterburner, inertial
dampener, battering bow and Ma's Kettle (lines_extra_parts.py). build_all.py exports them with every other component; this runs just them.
  python3 parts_art.py                  export the 10 files' PNG + glow + JSON into art/components and check them
  python3 parts_art.py --check          only check (hard pixels: palette colours at alpha 0/255; frame sizes; anims and glow anims inside their strips)
  python3 parts_art.py --sheet out.png  the review sheet: every frame at game scale (2x) on the floor, a 0.5-zoom column, two neighbours per family
Stdlib only."""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import *
import comp_base, lines_smelter, lines_extra_parts
from build import read_png

ALL = lines_smelter.ALL + lines_extra_parts.ALL
COMP = os.path.join(ART, 'components')

def parts():
    return [C() if isinstance(C, type) else C for C in ALL]

def export():
    for c in parts():
        _, _, J = comp_base.export(c)
        print(c.id, J['frame'], list(J['anims']))

def palette():
    out = set()
    for line in open(os.path.join(ART, 'palette.gpl')).read().splitlines():
        bits = line.split('\t')
        if len(bits) == 2 and bits[1].startswith('#'): out.add(tuple(int(bits[1][1 + i:3 + i], 16) for i in (0, 2, 4)))
    return out

def check():
    pal, bad = palette(), 0
    for c in parts():
        J = json.load(open(os.path.join(COMP, c.id + '.json')))
        w, h, rows = read_png(os.path.join(COMP, c.id + '.png'))
        fw, fh = J['frame']
        if w % fw or h != fh: print('FRAME', c.id, (w, h), J['frame']); bad += 1
        if list(J['cells']) != [fw // 16, (fh - (4 if J.get('offset') else 0)) // 16]: print('CELLS', c.id, J['cells'], J['frame']); bad += 1
        n = w // fw
        for name, (st, cnt, fps) in J['anims'].items():
            if st + cnt > n: print('ANIM', c.id, name); bad += 1
        for y, row in enumerate(rows):
            for x in range(w):
                r, g, b, a = row[x * 4:x * 4 + 4]
                if a not in (0, 255): print('ALPHA', c.id, x, y, a); bad += 1
                elif a and (r, g, b) not in pal: print('OFF-PALETTE', c.id, x, y, (r, g, b)); bad += 1
        G = J.get('glow')
        if G:
            gw, gh, grows = read_png(os.path.join(COMP, G['image']))
            gfw, gfh = G['frame']
            if gw % gfw or gh != gfh: print('GLOW FRAME', c.id); bad += 1
            for name, (st, cnt, fps) in G['anims'].items():
                if st + cnt > gw // gfw or name not in J['anims']: print('GLOW ANIM', c.id, name); bad += 1
    print('parts_art check:', 'OK' if not bad else '%d problems' % bad)
    return bad

# ------------------------------------------------------------------ the review sheet
class Cv:
    """a plain RGB canvas (bytearray rows); sprites go over it hard, glow layers are added."""
    def __init__(s, w, h, rgb):
        s.w, s.h = w, h
        s.p = [bytearray(bytes(rgb) * w) for _ in range(h)]
    def rect(s, x, y, w, h, rgb):
        for yy in range(max(0, y), min(s.h, y + h)):
            s.p[yy][max(0, x) * 3:min(s.w, x + w) * 3] = bytes(rgb) * (min(s.w, x + w) - max(0, x))
    def put(s, x, y, rgb):
        if 0 <= x < s.w and 0 <= y < s.h: s.p[y][x * 3:x * 3 + 3] = bytes(rgb)
    def blit(s, img, x, y, k=2, add=False):
        w, h, rows = img
        for j in range(h):
            row = rows[j]
            for i in range(w):
                r, g, b, a = row[i * 4:i * 4 + 4]
                if not a: continue
                for dy in range(k):
                    yy = y + j * k + dy
                    if not (0 <= yy < s.h): continue
                    for dx in range(k):
                        xx = x + i * k + dx
                        if not (0 <= xx < s.w): continue
                        d = s.p[yy]
                        if add:
                            t = a / 255.0
                            d[xx * 3] = min(255, int(d[xx * 3] + r * t)); d[xx * 3 + 1] = min(255, int(d[xx * 3 + 1] + g * t)); d[xx * 3 + 2] = min(255, int(d[xx * 3 + 2] + b * t))
                        else:
                            d[xx * 3:xx * 3 + 3] = bytes((r, g, b))
    def text(s, x, y, txt, rgb, k=2):
        from sheet_v2 import F35
        for ch in txt.upper():
            gl = F35.get(ch, F35[' '])
            for i, b in enumerate(gl):
                if b == '1': s.rect(x + (i % 3) * k, y + (i // 3) * k, k, k, rgb)
            x += 4 * k
    def save(s, path):
        save_rgba(path, s.w, s.h, b''.join(bytes(b for px_ in range(s.w) for b in (row[px_ * 3], row[px_ * 3 + 1], row[px_ * 3 + 2], 255)) for row in s.p))

def crop(img, i, fw, fh):
    w, h, rows = img
    return (fw, fh, [row[i * fw * 4:(i + 1) * fw * 4] for row in rows[:fh]])

class Sheet:
    """one component read back from art/components: its frames and glow frames by animation name."""
    def __init__(s, cid):
        s.id = cid
        s.J = json.load(open(os.path.join(COMP, cid + '.json')))
        s.img = read_png(os.path.join(COMP, cid + '.png'))
        G = s.J.get('glow'); s.G = G
        s.gimg = read_png(os.path.join(COMP, G['image'])) if G else None
    def frames(s):
        out = []
        for name, (st, cnt, fps) in sorted(s.J['anims'].items(), key=lambda kv: kv[1][0]):
            for q in range(cnt): out.append((name, q))
        return out
    def frame(s, name, q):
        st, cnt, fps = s.J['anims'][name]
        fw, fh = s.J['frame']
        f = crop(s.img, st + q % cnt, fw, fh)
        g = None
        if s.G:
            gn = name if name in s.G['anims'] else ('on' if name not in ('off', 'disabled') and 'on' in s.G['anims'] else None)
            if gn: g = crop(s.gimg, s.G['anims'][gn][0] + q % s.G['anims'][gn][1], *s.G['frame'])
        return f, g

FLOOR, GRID, SPACE, BG = RGB['F'], RGB['G'], (12, 14, 22), (40, 44, 52)
TXT, DIM, HEAD = RGB['L'], RGB['S'], RGB['a']

def floor(cv, x, y, w, h, k):
    cv.rect(x, y, w, h, FLOOR)
    for yy in range(y, y + h, 16 * k): cv.rect(x, yy, w, 1, GRID)
    for xx in range(x, x + w, 16 * k): cv.rect(xx, y, 1, h, GRID)

def cell_size(sh, k, mount):
    fw, fh = sh.J['frame']
    if mount: return (max(fw, mount.J['frame'][0]) + 24) * k, (mount.J['frame'][1] + 16 + 32 + 8 + 30) * k
    return (fw + 20) * k, (fh + 20) * k

def draw_cell(cv, x, y, sh, name, q, k, mount=None):
    """one frame on the floor (a mount: the outside half in space above a wall row, the inside half on the floor under it)."""
    W, H = cell_size(sh, k, mount)
    if not mount:
        floor(cv, x, y, W, H, k)
        f, g = sh.frame(name, q)
        cv.blit(f, x + 10 * k, y + 10 * k, k)
        if g: cv.blit(g, x + (10 + sh.G['offset'][0]) * k, y + (10 + sh.G['offset'][1]) * k, k, add=True)
        return W, H
    wy = y + (mount.J['frame'][1] + 30) * k
    cv.rect(x, y, W, wy - y, SPACE)
    for n in range(24): cv.rect(x + (n * 37 + 11) % W, y + (n * 53 + 7) % (wy - y), k, k, (120, 130, 160))
    for cx in range(0, W, 16 * k):
        cv.rect(x + cx, wy, min(16 * k, W - cx), 16 * k, RGB['D']); cv.rect(x + cx, wy, min(16 * k, W - cx), k, RGB['E'])
    floor(cv, x, wy + 16 * k, W, y + H - wy - 16 * k, k)
    on_out = name if name in mount.J['anims'] else 'on'
    fo, go = mount.frame(on_out, q)
    mid = x + W // 2
    ox = mid - mount.J['frame'][0] * k // 2; oy = wy - mount.J['frame'][1] * k + 4 * k
    cv.blit(fo, ox, oy, k)
    fi, gi = sh.frame(name, q)
    ix = mid - sh.J['frame'][0] * k // 2; iy = wy + 16 * k + sh.J['offset'][1] * k
    cv.blit(fi, ix, iy, k)
    if go: cv.blit(go, ox + mount.G['offset'][0] * k, oy + mount.G['offset'][1] * k, k, add=True)
    if gi: cv.blit(gi, ix + sh.G['offset'][0] * k, iy + sh.G['offset'][1] * k, k, add=True)
    return W, H

GROUPS = [
    ('SMELTERS  (processing_1, family smelter, manned)', ['smelter_scrap_mk1', 'smelter_mk1', 'smelter_mk2', 'smelter_mk3', 'smelter_neon_mk1'], ['fabricator', 'radiator']),
    ('AFTERBURNER  (engine, standard, tier 2: inside 4x2 + outside 4x2)', ['afterburner'], ['engine_mk2', 'engine_mk3']),
    ('INERTIAL DAMPENER  (utility, standard, 2x2)', ['inertial_dampener'], ['human_comms_array', 'basalt_gravity_anchor']),
    ('BATTERING BOW  (ram, scrap, 4x2, outward is up)', ['battering_bow'], ['engine_scrap_mk3', 'bolt_thrower_scrap']),
    ("MA'S KETTLE  (reactor, scrap, 4x4)", ['reactor_scrap_kettle'], ['reactor_scrap_mk1', 'reactor_mk2']),
]
NAMES = {'smelter_scrap_mk1': 'Slag Pot', 'smelter_mk1': 'Smelter Mk1', 'smelter_mk2': 'Smelter Mk2', 'smelter_mk3': 'Smelter Mk3', 'smelter_neon_mk1': 'Plasma Forge',
         'afterburner': 'Afterburner', 'inertial_dampener': 'Inertial Dampener', 'battering_bow': 'Battering Bow', 'reactor_scrap_kettle': "Ma's Kettle"}

def sheet(path, K=2):
    rows = []                                                     # (label, sheet, mount, frames, neighbour?)
    for title, ids, nbrs in GROUPS:
        rows.append(('#', title))
        for cid in ids + nbrs:
            sh = Sheet(cid)
            mount = Sheet(cid + '_out') if os.path.exists(os.path.join(COMP, cid + '_out.json')) else None
            fr = sh.frames() if cid in ids else [f for f in sh.frames() if f in (('on', 0), ('off', 0), ('damaged', 0), ('disabled', 0))]
            rows.append((('%s  %s' % (NAMES.get(cid, cid), cid)) + ('' if cid in ids else '   (NEIGHBOUR, existing art)'), sh, mount, fr, cid not in ids))
    Wmax, Htot = 0, 60
    for r in rows:
        if r[0] == '#': Htot += 34; continue
        _, sh, mount, fr, nb = r
        w, h = cell_size(sh, K, mount)
        Wmax = max(Wmax, 16 + len(fr) * (w + 8) + 40 + (w // K + 16))
        Htot += h + 40
    cv = Cv(Wmax, Htot, BG)
    cv.text(16, 16, 'PARTS ART  (owner playtest 2026-11-06)  GAME SCALE 2X  /  RIGHT: 0.5 ZOOM (1X)', TXT, 3)
    y = 60
    for r in rows:
        if r[0] == '#':
            cv.rect(16, y + 4, Wmax - 32, 2, DIM); cv.text(16, y + 12, r[1], HEAD, 3); y += 34; continue
        label, sh, mount, fr, nb = r
        cv.text(16, y + 4, label, DIM if nb else TXT, 2)
        y += 18
        x = 16
        w, h = cell_size(sh, K, mount)
        for (name, q) in fr:
            draw_cell(cv, x, y, sh, name, q, K, mount)
            cv.text(x + 4, y + h + 4, '%s %d' % (name, q), DIM, 2)
            x += w + 8
        x += 32
        draw_cell(cv, x, y, sh, 'on', 0, 1, mount)
        cv.text(x, y + h // K + 4, '0.5 ZOOM', DIM, 2)
        y += h + 22
    cv.save(path)
    print('sheet', path, (cv.w, cv.h))

if __name__ == '__main__':
    if '--sheet' in sys.argv:
        sheet(sys.argv[sys.argv.index('--sheet') + 1])
    else:
        if '--check' not in sys.argv:
            import pal_guns; pal_guns.register()
            export()
        sys.exit(1 if check() else 0)
