"""Racial tech preview sheet, group b (Mire, Sporeling, Gauntling, Prismatic, Grundl). Per race: every weapon mounted through a 2-row hull wall (3x: ready; 2x: firing, damaged, disabled),
every component on the floor or through the wall (3x: on; 2x: off, damaged, disabled), then all the projectiles and impacts (4x, with glow) on a space backdrop.
Usage: python3 sheet_tech_b.py [out.png]   (run build_tech_b.py first: the engines and projectiles are read back from art/)"""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import *
from preview import load, split, meta
import pal_races1
import sheet_weapons as SW
import sheet_engines1 as SE
from sheet_v2 import text
import comp_base, tech_b

def conv(o):
    """preview.load gives px_structure.Rgba surfaces; px.Rgba has the scaling."""
    n = Rgba(o.w, o.h); n.p = [[list(q) for q in row] for row in o.p]; return n

W = 2400
BG = (60, 66, 80, 255)
NOTES = {'mire': 'WET GREEN-TEAL, STEEL AND BRASS PIPES, RED HAND-WHEELS, STEAM VALVES',
         'sporeling': 'GROWN CREAM AND BROWN HOUSINGS, VIOLET SPORE SACS, GILLS',
         'gauntling': 'MISMATCHED SCRAP, COPPER COILS, CYAN ELECTRIC ARCS',
         'prismatic': 'FACETED VIOLET CRYSTAL, CYAN AND MAGENTA LIGHT CORES',
         'grundl': 'HEAVY RIVETED FREIGHT METAL, AMBER STENCILS, CHAINS'}

def comp_frames(c):
    frames, gframes, J = comp_base.export(c, PREVIEW + '/comp_tmp')
    return frames, gframes, J

def comp_scene(c, data, anim, i, K, pad=8):
    """a 2x2 or 4x4 component on the floor with its glow."""
    frames, gframes, J = data
    st, n, fps = J['anims'][anim]
    f = frames[st + i % n]
    g = J.get('glow', {}).get('anims', {}).get(anim)
    gl, gt, gr, gb = c.glow_pad
    img = Rgba(c.w + 2 * pad + gl + gr, c.h + 2 * pad + gt + gb, RGB['F'] + (255,))
    for y in range(img.h):
        for x in range(img.w): img.p[y][x] = list(RGB['G'] if ((x - gl - pad + 16) % 16 == 0 or (y - gt - pad + 16) % 16 == 0) else RGB['F']) + [255]
    img.blit_spr(f, pad + gl, pad + gt)
    if g: img.blit_rgba(gframes[g[0] + i % n], pad, pad, 1, add=True)
    return img

def build(out):
    jobs = []                                           # (height, draw)
    ds = {}
    for name, mod in tech_b.RACES:
        weapons = [SW.Data(C) for C in mod.WEAPONS]
        comps = []
        for C in mod.COMPS:
            c = C() if isinstance(C, type) else C
            comps.append(c)
        # --- rows
        wA = [SW.scene(d, 0) for d in weapons]
        wB = [SW.scene(d, 0, bstate='fire', bi=0, istate='fire', ii=0) for d in weapons] + \
             [SW.scene(d, 0, bstate='damaged', bi=0, ostate='damaged', oi=0, istate='damaged', ii=0) for d in weapons] + \
             [SW.scene(d, 0, bstate='disabled', bi=0, ostate='disabled', oi=0, istate='disabled', ii=0) for d in weapons]
        engines = {c.id: SE.Eng(c.id) for c in comps if c.id.endswith('_engine') or c.id.endswith('_thrusters')}
        halves = {c.id: c for c in comps}
        cA, cC = [], []
        for c in comps:
            if c.id.endswith('_out'): continue
            if c.id in engines:
                e = engines[c.id]
                cA.append(('mount', SE.mount(e, 'on', 0))); cC += [('mount', SE.mount(e, 'off', 0)), ('mount', SE.mount(e, 'damaged', 0)), ('mount', SE.mount(e, 'disabled', 0))]
            else:
                dt = comp_frames(c)
                cA.append(('flat', comp_scene(c, dt, 'on', 1, 3)))
                cC += [('flat', comp_scene(c, dt, a, 0, 2)) for a in ('off', 'damaged', 'disabled')]
        jobs.append((name, wA, wB, cA, cC, weapons, [c for c in comps if not c.id.endswith('_out')]))
    # heights
    def rowA_h(j): return max(max(a.h for a in j[1]) * 3, max(s.h for _, s in j[3]) * 3) + 40
    def rowB_h(j): return max(a.h for a in j[2]) * 2 + 30
    def rowC_h(j): return max(s.h for _, s in j[4]) * 2 + 30
    proj_h = 15 * 150 // 2 + 120
    H = 30 + sum(60 + rowA_h(j) + rowB_h(j) + rowC_h(j) + 40 for j in jobs) + proj_h + 60
    cv = Rgba(W, H, BG)
    y = 14
    text(cv, 16, y, 'HULLSCRAP RACIAL TECH GROUP B: MIRE SPORELING GAUNTLING PRISMATIC GRUNDL  15 WEAPONS 15 COMPONENTS 15 PROJECTILES + IMPACTS', 'H', 3); y += 40
    for j in jobs:
        name = j[0]
        text(cv, 16, y, name.upper() + ':  ' + NOTES[name], 'a', 3); y += 28
        x = 16
        text(cv, x, y, 'WEAPONS READY 3X: ' + '  '.join(d.c.id.upper() for d in j[5]), 'M', 2)
        y += 18
        ay = y
        for k, a in enumerate(j[1]):
            cv.blit_rgba(a.scaled(3), x, ay, 1); x += a.w * 3 + 14
        x += 20
        text(cv, x, ay - 18, 'COMPONENTS ON 3X: ' + '  '.join(c.id.upper() for c in j[6]), 'M', 2)
        for kind, s in j[3]:
            cv.blit_rgba(s.scaled(3), x, ay, 1); x += s.w * 3 + 14
        y += rowA_h(j) - 18
        text(cv, 16, y, 'WEAPONS 2X: FIRING (3), DAMAGED (3), DISABLED (3)', 'M', 2); y += 18
        x = 16
        for a in j[2]:
            cv.blit_rgba(a.scaled(2), x, y, 1); x += a.w * 2 + 6
        y += rowB_h(j) - 18
        text(cv, 16, y, 'COMPONENTS 2X: OFF, DAMAGED, DISABLED (EACH)', 'M', 2); y += 18
        x = 16
        for kind, s in j[4]:
            cv.blit_rgba(s.scaled(2), x, y, 1); x += s.w * 2 + 6
        y += rowC_h(j) - 18 + 10
        for xx in range(W): cv.p[y][xx] = list(RGB['G']) + [255]
        y += 20
    # ---- projectiles
    import tech_proj
    text(cv, 16, y, 'PROJECTILES AND IMPACTS 4X WITH GLOW: BOLTS FACE UP, BEAMS (STEAM LANCE, TESLA PICKET, PRISM LENS, HARPOON CHAIN) TILE ALONG Y (SHOWN 3 TILES LONG)', 'H', 3); y += 34
    ids = tech_proj.IDS + ['grundl_grapple_harpoon_chain']
    colw = W // 2 - 20
    row_y = y
    for n, id_ in enumerate(ids):
        cx = 16 + (n % 2) * (W // 2); cy = row_y + (n // 2) * 150
        J = meta('projectiles/%s.png' % id_)
        fw, fh = J['frame']
        frames = [conv(f) for f in split(load('projectiles/%s.png' % id_), fw, fh)]
        gJ = J['glow']; gw, gh = gJ['frame']
        gfr = [conv(f) for f in split(load('projectiles/%s' % gJ['image']), gw, gh)]
        tile = J.get('tile') == 'y'
        K = 4
        # space backdrop strip
        bgh = 140
        for yy in range(cy, cy + bgh - 4):
            for xx in range(cx, cx + colw): cv.p[yy][xx] = [14, 18, 28, 255]
        text(cv, cx + 4, cy + 4, id_.upper(), 'H', 2)
        x = cx + 8; yy0 = cy + 22
        for k, f in enumerate(frames):
            if tile:
                for rep in range(3):
                    cv.blit_rgba(gfr[k].scaled(K), x + J['glow']['offset'][0] * K, yy0 + rep * fh * K, 1, add=True)
                    cv.blit_rgba(f.scaled(K), x, yy0 + rep * fh * K, 1)
                x += (fw + 6) * K
            else:
                cv.blit_rgba(f.scaled(K), x, yy0, 1); cv.blit_rgba(gfr[k].scaled(K), x + gJ['offset'][0] * K, yy0 + gJ['offset'][1] * K, 1, add=True)
                x += (fw + 6) * K
        if 'impact' in J:
            I = J['impact']; iw, ih = I['frame']
            fr = [conv(f) for f in split(load('projectiles/' + I['image']), iw, ih)]
            ig = [conv(f) for f in split(load('projectiles/' + I['glow']['image']), *I['glow']['frame'])]
            x = max(x + 20, cx + 330)
            for k, f in enumerate(fr):
                cv.blit_rgba(f.scaled(K), x, yy0 - 8, 1); cv.blit_rgba(ig[k].scaled(K), x + I['glow']['offset'][0] * K, yy0 - 8 + I['glow']['offset'][1] * K, 1, add=True)
                x += (iw + 4) * K
    cv.save(out)
    return cv.w, cv.h

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else PREVIEW + '/art_tech_b.png'
    print(build(out))
