"""Engine wave 1 preview sheet (3x). Reads the delivered PNG/JSON files of the 19 engines back and lays out
 1. each line as a tier ladder (Mk1 -> Mk5), every engine mounted through 2 wall rows (outside half above, core below), exhaust on;
 2. every engine's frames, labelled (on 0-2, off, damaged 0-1, disabled), each mounted through the wall;
 3. all 19 engines at 1x (actual size) on one hull.
Usage: python3 sheet_engines1.py [out.png]      (also: python3 sheet_engines1.py --check   palette / frame size / glow size checks of the 15 new engines)"""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import *
from preview import load, split
from sheet_weapons import wall_rows, space_bg, floor_bg
from sheet_v2 import text

K = 3
COMP = os.path.join(ART, 'components')
LADDERS = [('CONCORD THRUSTER  STANDARD', ['engine_mk1', 'engine_mk2', 'engine_mk3', 'engine_mk4', 'engine_mk5']),
           ('KICKJET  SCRAP', ['engine_scrap_mk1', 'engine_scrap_mk2', 'engine_scrap_mk3', 'engine_scrap_mk4']),
           ('ION DRIVE  NEON', ['engine_neon_mk1', 'engine_neon_mk2', 'engine_neon_mk3', 'engine_neon_mk4']),
           ('STRAFE JETS  STANDARD', ['strafe_jets_mk1', 'strafe_jets_mk2', 'strafe_jets_mk3']),
           ('LONG-BURN DRIVE  STANDARD', ['longburn_mk1', 'longburn_mk2', 'longburn_mk3'])]
NAMES = {'engine_mk1': 'Concord Thruster Mk1', 'engine_mk2': 'Concord Thruster Mk2', 'engine_mk3': 'Concord Thruster Mk3', 'engine_mk4': 'Concord Thruster Mk4', 'engine_mk5': 'Concord Thruster Mk5',
         'engine_scrap_mk1': 'Kickjet', 'engine_scrap_mk2': 'Kickjet Deluxe', 'engine_scrap_mk3': 'Double Kick', 'engine_scrap_mk4': 'Thunderknuckle',
         'engine_neon_mk1': 'Ion Drive: Glimmer', 'engine_neon_mk2': 'Ion Drive: Halo', 'engine_neon_mk3': 'Ion Drive: Corona', 'engine_neon_mk4': 'Ion Drive: Zenith',
         'strafe_jets_mk1': 'Strafe Jets Mk1', 'strafe_jets_mk2': 'Strafe Jets Mk2', 'strafe_jets_mk3': 'Strafe Jets Mk3',
         'longburn_mk1': 'Long-Burn Drive Mk1', 'longburn_mk2': 'Long-Burn Drive Mk2', 'longburn_mk3': 'Long-Burn Drive Mk3'}
NEW = [i for _, ids in LADDERS for i in ids if i not in ('engine_mk1', 'engine_mk2', 'engine_scrap_mk1', 'engine_neon_mk1')]
FRAMES = [('on', 0), ('on', 1), ('on', 2), ('off', 0), ('damaged', 0), ('damaged', 1), ('disabled', 0)]
PAD, TOP = 12, 44

class Eng:
    """one engine read back from art/components: both halves, every frame, every glow frame."""
    def __init__(s, id_):
        s.id = id_; s.half = {}
        for part, nm in (('in', id_), ('out', id_ + '_out')):
            J = json.load(open(os.path.join(COMP, nm + '.json')))
            fw, fh = J['frame']
            fr = split(load('components/' + nm + '.png'), fw, fh)
            gl = None
            if 'glow' in J:
                g = J['glow']; gl = (split(load('components/' + g['image']), *g['frame']), g['offset'], g['anims'])
            s.half[part] = (J, fr, gl)
        s.w = s.half['out'][0]['frame'][0]; s.oh = s.half['out'][0]['frame'][1]
    def pick(s, part, anim, i):
        J, fr, gl = s.half[part]
        st, n, fps = J['anims'][anim]
        f = fr[st + i % n]; g = None
        if gl and anim in gl[2]: g = gl[0][gl[2][anim][0] + i % n]
        return f, g, (gl[1] if gl else (0, 0))

def mount(e, anim='on', i=0, pad=PAD, top=TOP, glow_on=True, space=True):
    """the outside half, 2 wall rows, the core: one engine mounted through a hull, the exhaust drawn."""
    oh = e.oh; wy = top + 48                       # the wall sits at one height for every engine (4x3 outsides rise higher)
    top = wy - oh
    W = e.w + 2 * pad; H = wy + 32 + 36 + 6
    img = Rgba(W, H, RGB['F'] + (255,))
    space_bg(img, 0, wy); floor_bg(img, wy + 32, H)
    img.blit_spr(wall_rows((W + 15) // 16 * 16), 0, wy)
    f, g, off = e.pick('out', anim, i)
    img.blit_rgba(f, pad, top)
    iy = wy + 32 + e.half['in'][0]['offset'][1]
    fi, gi, offi = e.pick('in', anim, i)
    img.blit_rgba(fi, pad, iy)
    if glow_on:
        if g: img.blit_rgba(g, pad + off[0], top + off[1], 1, add=True)
        if gi: img.blit_rgba(gi, pad + offi[0], iy + offi[1], 1, add=True)
    return img

def build(out):
    es = {i: Eng(i) for _, ids in LADDERS for i in ids}
    GAP = 14
    # ---- sizes
    ladder_h = (TOP + 48 + 32 + 36 + 6) * K + 40
    W = 2000
    frame_w = (64 + 2 * PAD + 4) * K
    row_h = lambda e: (TOP + 48 + 32 + 36 + 6) * K + 44
    H = 40 + len(LADDERS) * ladder_h + 40 + sum(row_h(es[i]) + 14 for _, ids in LADDERS for i in ids) + 60 + (TOP + 48 + 32 + 36) + 120
    cv = Rgba(W, H, (60, 66, 80, 255))
    y = 10
    text(cv, 16, y, 'HULLSCRAP ENGINE WAVE 1  3X  19 ENGINES  15 NEW  TIER LADDERS, EVERY FRAME, ACTUAL SIZE', 'H', 3); y += 34
    # ---- 1. ladders
    for title, ids in LADDERS:
        text(cv, 16, y, title, 'a', 4); y += 26
        x = 16
        for id_ in ids:
            e = es[id_]; im = mount(e, 'on', 1)
            cv.blit_rgba(im, x, y, K)
            text(cv, x + PAD * K, y + im.h * K + 4, NAMES[id_].upper(), 'M' if id_ in NEW else 'S', 2)
            x += (e.w + 2 * PAD + 2) * K + 6
        y += ladder_h - 26 + 22
    # ---- 2. every frame
    text(cv, 16, y, 'EVERY ENGINE  FRAMES  OUTSIDE ABOVE THE WALL  CORE BELOW', 'a', 4); y += 32
    for title, ids in LADDERS:
        for id_ in ids:
            e = es[id_]; Jo, Ji = e.half['out'][0], e.half['in'][0]
            text(cv, 16, y, '%s  %s  CORE %dX%d OFFSET %d,%d  OUT %dX%d  %s' % (id_, 'NEW' if id_ in NEW else 'EXISTING', Ji['frame'][0], Ji['frame'][1], Ji['offset'][0], Ji['offset'][1], Jo['frame'][0], Jo['frame'][1], NAMES[id_]), 'H' if id_ in NEW else 'S', 3)
            y += 22
            x = 16
            for (anim, i) in FRAMES:
                im = mount(e, anim, i)
                cv.blit_rgba(im, x, y, K)
                lbl = '%s %d' % (anim, i) if anim in ('on', 'damaged') else anim
                text(cv, x + PAD * K, y + im.h * K + 4, lbl.upper(), 'M', 3)
                x += (e.w + 2 * PAD + 2) * K + 4
            y += row_h(e) - 22 + 14
    # ---- 3. all 19 at 1x on one hull
    y += 10
    text(cv, 16, y, 'ALL 19 ENGINES AT 1X  ACTUAL SIZE  EXHAUST ON', 'a', 4); y += 32
    tot = sum(es[i].w + 8 for _, ids in LADDERS for i in ids) + 8
    top = TOP; wy = top + 48
    img = Rgba(max(tot, 100), wy + 32 + 36 + 8, RGB['F'] + (255,))
    space_bg(img, 0, wy); floor_bg(img, wy + 32, img.h)
    img.blit_spr(wall_rows((img.w + 15) // 16 * 16), 0, wy)
    x = 8
    for _, ids in LADDERS:
        for id_ in ids:
            e = es[id_]
            f, g, off = e.pick('out', 'on', 1); img.blit_rgba(f, x, wy - e.oh)
            fi, gi, offi = e.pick('in', 'on', 1); iy = wy + 32 + e.half['in'][0]['offset'][1]; img.blit_rgba(fi, x, iy)
            if g: img.blit_rgba(g, x + off[0], wy - e.oh + off[1], 1, add=True)
            if gi: img.blit_rgba(gi, x + offi[0], iy + offi[1], 1, add=True)
            x += e.w + 8
    cv.blit_rgba(img, 16, y, 1)
    cv.blit_rgba(img, 16, y + img.h + 12, 1) if False else None
    cv.save(out)
    print(out, cv.w, cv.h)

def check():
    """palette, frame size and glow size checks of the 15 new engines (build.py's validate() only walks tiles, fx and projectiles)."""
    pal = {tuple(RGB[c]) for c in RGB}
    bad = 0
    for id_ in NEW:
        for nm in (id_, id_ + '_out'):
            J = json.load(open(os.path.join(COMP, nm + '.json')))
            im = load('components/' + nm + '.png')
            fw, fh = J['frame']
            if im.w % fw or im.h != fh: print('FRAME MISMATCH', nm, (im.w, im.h), (fw, fh)); bad += 1
            n = max(s + c for (s, c, f) in J['anims'].values())
            if im.w // fw != n: print('FRAME COUNT', nm, im.w // fw, n); bad += 1
            for row in im.p:
                for p in row:
                    if p[3] and (tuple(p[:3]) not in pal or p[3] != 255): print('OFF-PALETTE / ALPHA', nm, p); bad += 1; break
            g = J.get('glow')
            if g:
                gi = load('components/' + g['image'])
                gw, gh = g['frame']
                if gi.w % gw or gi.h != gh: print('GLOW FRAME MISMATCH', nm, (gi.w, gi.h), (gw, gh)); bad += 1
                for a, (s, c, f) in g['anims'].items():
                    if a not in J['anims'] or s + c > gi.w // gw: print('GLOW ANIM', nm, a); bad += 1
            exp = {'on': 3, 'off': 1, 'damaged': 2, 'disabled': 1}
            if {a: v[1] for a, v in J['anims'].items()} != exp: print('ANIMS', nm, J['anims']); bad += 1
    print('engines1 check:', 'OK' if not bad else '%d problems' % bad)
    return bad

if __name__ == '__main__':
    if '--check' in sys.argv: sys.exit(1 if check() else 0)
    build(sys.argv[1] if len(sys.argv) > 1 else os.path.join(PREVIEW, 'engines1_sheet.png'))
