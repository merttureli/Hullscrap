"""Preview sheets for the G2 guns (3x, labelled, each gun through a wall with its breech): one per family, the anims, the breeches.
Usage: python3 gun_sheets_g2.py [out_dir]"""
import sys
from px import *
import gun_samples as gs
import gun_sheets as gsh
import gun_recipes_g2 as g2
from gun_sheets import scene, COMP, load, crop
import json

FAMS = [('laser', 'LASER'), ('pulse', 'PULSE'), ('ion', 'ION'), ('flak', 'FLAK'), ('missile', 'MISSILE'), ('beam', 'BEAM'), ('slug', 'SLUG'), ('pd', 'POINT DEFENCE')]
NOTE = {'chain': 'ROTARY CLUSTER', 'charge': '3 CAPACITOR RINGS', 'burst': 'BARRELS STAGGERED', 'heavy': 'DOUBLE SLEEVE BRAKE', 'long': 'LONG BARREL', 'lance': 'SPINAL SLEEVE RINGS', 'light': 'LIGHT'}

def cell(pid, **kw):
    g = g2.GUNS2[pid]
    k = dict(kw)
    k.setdefault('pad', 30 if g.aim != 'fixed' else 20)
    return (scene(COMP, pid, **k), g.label, g.shape.upper() + ' ' + g.line.upper() + (' ' + (g.breech_ver or '').upper() if g.breech_ver else ''))

def families(out):
    for f, nm in FAMS:
        ids = [k for k, g in g2.GUNS2.items() if g.fam == f]
        if f == 'pulse': ids += ['gun_strip'] if 'gun_strip' not in ids else []
        gs.grid([cell(p) for p in ids], 3, 2400, title='G2 GUNS, %s FAMILY: THE NEW GUNS MOUNTED THROUGH A WALL WITH THEIR BREECH (3X)' % nm).save('%s/gun-art-g2_%s.png' % (out, f)); print(f)

def anims(out):
    cells = []
    for k in range(4): cells.append((scene(COMP, 'laser_chain', bstate='spin', bi=k, pad=20), 'CHAIN SPIN %d' % k, 'LASER CHAIN, A QUARTER TURN A STEP'))
    for k in range(4): cells.append((scene(COMP, 'ion_charge', bstate='charge', bi=k, pad=30), 'CHARGE %d' % k, 'ION CHARGE, %d RING%s LIT' % (k, '' if k == 1 else 'S')))
    for k in range(3): cells.append((scene(COMP, 'slug_spinal', bstate='charge', bi=k, pad=20), 'SPINAL CHARGE %d' % k, 'SLUG SPINAL STORES 2'))
    for deg in (-70, -20, 35, 80): cells.append((scene(COMP, 'pd_mk3', deg=deg, pad=30), 'PD TRACKING %d' % deg, 'PD MK III TURNS ON ITS RING'))
    for k in range(5): cells.append((scene(COMP, 'gun_strip', bstate='fire', bi=k, stag=True, pad=20), 'STRIP FIRE %d' % k, 'STAGGERED: EACH BARREL ONE FRAME BEHIND'))
    for k in range(3): cells.append((scene(COMP, 'heavy_battery', bstate='fire', bi=k, stag=True, pad=20), 'HEAVY BATTERY %d' % k, 'STAGGERED'))
    gs.grid(cells, 3, 2400, title='G2 ANIMS: CHAIN SPIN (4), CHARGE RINGS (0-3), PD TRACKING, STAGGERED FIRE OF A STRIP AND A BATTERY').save('%s/gun-art-g2_anims.png' % out); print('anims')

def breeches(out):
    cells = []
    ids = list(g2.GUNS2) + list(g2.BARONS)
    for pid in ids:
        g = g2.GUNS2.get(pid) or g2.gr.GUNS[pid]
        J = json.load(open('%s/%s.json' % (COMP, pid))); fw, fh = J['frame']
        img = load('%s/%s.png' % (COMP, pid)); gl = load('%s/%s' % (COMP, J['glow']['image']))
        MW = max(fw + 16, 104); m = Rgba(MW, fh + 16, RGB['F'] + (255,))
        m.blit_rgba(crop(img, 0, fw, fh), (MW - fw) // 2, 12)
        gf = J['glow']['frame']; m.blit_rgba(crop(gl, 0, gf[0], gf[1]), 8 - 8, 12 - 8, 1, add=True) if False else None
        cells.append((m, g.label, '%dX%d %s%s' % (g.in_cells[0], g.in_cells[1], g.fam.upper(), ' GOLD' if g.race == 'barons' else '')))
    gs.grid(cells, 3, 2400, title='G2 BREECHES (INSIDE HALVES): 2X2, 4X2, 2X4. FAMILY CORE, FEED OR CAPACITOR DETAIL, LINE TRIM. PLUS THE THREE BARON GUNS IN GOLD').save('%s/gun-art-g2_breeches.png' % out); print('breeches')

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '/home/user/hs/shots'
    which = sys.argv[2:] or ['families', 'anims', 'breeches']
    for w in which: globals()[w](out)
