"""Preview sheets for the gun art (3x, labelled): before / after through a wall, and the race guns grouped by race.
Usage: python3 gun_sheets.py [out_dir] [old_dir]    (old_dir = a copy of the previous art/components, for the 'before' cells)"""
import json, os, struct, sys, zlib
from px import *
import gun_samples as gs
import gun_recipes as gr
from sheet_v2 import text

COMP = ART + '/components'

def load(path):
    d = open(path, 'rb').read(); pos, idat, w, h = 8, b'', 0, 0
    while pos < len(d):
        n = struct.unpack('>I', d[pos:pos + 4])[0]; t = d[pos + 4:pos + 8]; body = d[pos + 8:pos + 8 + n]; pos += 12 + n
        if t == b'IHDR': w, h = struct.unpack('>II', body[:8])
        elif t == b'IDAT': idat += body
    raw = zlib.decompress(idat); img = Rgba(w, h)
    for y in range(h):
        row = raw[y * (w * 4 + 1) + 1:(y + 1) * (w * 4 + 1)]
        for x in range(w): img.p[y][x] = list(row[x * 4:x * 4 + 4])
    return img

def crop(img, k, fw, fh):
    o = Rgba(fw, fh)
    for y in range(fh):
        for x in range(fw): o.p[y][x] = list(img.p[y][k * fw + x])
    return o

def scene(d, pid, state='on', bstate='idle', bi=0, deg=0, pad=18, top_extra=14):
    """the gun `pid` of art directory d: outside half in space, a 2-row wall, the (unchanged) inside half on the floor; barrels at the pivots."""
    J = json.load(open('%s/%s_out.json' % (d, pid))); B = J['barrel']
    fw, fh = J['frame']; on = J['anims'][state]
    out = crop(load('%s/%s_out.png' % (d, pid)), on[0], fw, fh)
    og = None
    if 'glow' in J and state in J['glow']['anims']:
        a = J['glow']['anims'][state]; gfw, gfh = J['glow']['frame']; og = crop(load('%s/%s' % (d, J['glow']['image'])), a[0], gfw, gfh)
    ig = None; I = {}
    if os.path.exists('%s/%s.json' % (COMP, pid)):
        I = json.load(open('%s/%s.json' % (COMP, pid))); ifw, ifh = I['frame']
        inn = crop(load('%s/%s.png' % (COMP, pid)), I['anims']['on'][0], ifw, ifh)
        if 'glow' in I: gfw, gfh = I['glow']['frame']; ig = crop(load('%s/%s' % (COMP, I['glow']['image'])), I['glow']['anims']['on'][0], gfw, gfh)
    else:                                                                       # no inside art exists for this gun yet: the module breech stands in
        bs, bgl = gr.GUNS[pid].breech(); ifw, ifh = bs.w, bs.h; inn = Rgba(ifw, ifh); inn.blit_spr(bs, 0, 0)
        ig = bgl; I = {'glow': {'offset': [-gs.OPAD, -gs.OPAD]}}
    bimg = load('%s/%s' % (d, B['image'])); bfw, bfh = B['frame']
    bk = B['anims'][bstate]
    spr = crop(bimg, bk[0] + bi, bfw, bfh)
    bg = None
    if 'glow' in B and bstate in B['glow']['anims']:
        a = B['glow']['anims'][bstate]; gfw, gfh = B['glow']['frame']; bg = crop(load('%s/%s' % (d, B['glow']['image'])), a[0] + bi, gfw, gfh)
    pivots = B.get('pivots_on_base') or [B['pivot_on_base']]
    pb = B['pivot_on_barrel']
    oh = fh - 4
    reach = max(pb[1] - 0, 10) if True else 0
    top = max(oh and 12, pb[1] - min(p[1] for p in pivots) + top_extra) + (8 if bstate == 'fire' else 0)
    W = max(fw, ifw) + 2 * pad
    H = top + oh + 32 + ifh - 4 + 12
    img = Rgba(W, H, RGB['F'] + (255,))
    wy = top + oh
    gs.space_bg(img, 0, 0, W, wy, len(pid)); gs.floor_bg(img, 0, wy + 32, W, H)
    img.blit_spr(gs.wall_rows(W), 0, wy)
    ox = (W - fw) // 2
    img.blit_rgba(out, ox, top)
    ix = (W - ifw) // 2
    if ifw < fw: ix = ox + ((fw // 16 - ifw // 16) // 2) * 16
    iy = wy + 32 - 4
    img.blit_rgba(inn, ix, iy)
    if og is not None: img.blit_rgba(og, ox - gs.OPAD, top - gs.OPAD, 1, add=True)
    if ig is not None: img.blit_rgba(ig, ix + I['glow']['offset'][0], iy + I['glow']['offset'][1] + 4, 1, add=True)
    for (px, py) in pivots:
        gs.place_barrel(img, (Spr(1, 1), None, (0, 0)), 0, 0, 0) if False else None
        bx, by = ox + px - pb[0], top + py - pb[1]
        if deg:
            from compose import rotate
            S = 2 * max(bfw, bfh) + 4; h = S // 2
            cv = Rgba(S, S); cv.blit_rgba(spr, h - pb[0], h - pb[1])
            img.blit_rgba(gs.turn_rgba(cv, deg, h, h), ox + px - h, top + py - h)
        else:
            img.blit_rgba(spr, bx, by)
            if bg is not None: img.blit_rgba(bg, bx - gs.BPAD if 'glow' in B and False else bx + B['glow']['offset'][0], by + B['glow']['offset'][1], 1, add=True)
    return img

SHEETS = [
 ('1', 'CASEMATES 4X2 (FIXED): TODAY BEFORE, NEW AFTER, MOUNTED THROUGH A WALL. THE INSIDE HALF IS UNCHANGED', ['laser_mk1', 'laser_mk2', 'pulse_mk1', 'pulse_mk2', 'ion_blast_mk1', 'artemis_mk1', 'bolt_thrower_scrap', 'basalt_magma_spitter', 'emberkin_cinder_mortar', 'gauntling_arc_hammer', 'mire_bog_mortar', 'sporeling_spore_cannon', 'prismatic_refractor']),
 ('2', 'POINT 2X2 AND DOME 3X3 TURRETS: BEFORE, AFTER', ['laser_turret_mk1', 'rattle_burst_scrap', 'sovereign_turret', 'fenn_twitch_cannon', 'kett_drone_picket', 'prismatic_glimmer_turret', 'human_flak_screen',
                                                             'leech_laser', 'siren_ion_neon', 'emberkin_flare_turret', 'fenn_spark_lattice', 'gauntling_tesla_picket', 'grundl_barge_flak', 'mire_mist_projector', 'sporeling_pollen_turret']),
 ('3', 'SPONSON 3X2, LONG BARRELS 2X4 AND HEAVY CANNONS 4X3: BEFORE, AFTER', ['basalt_pumice_flak', 'human_concord_railgun', 'gilded_lance', 'heat_lance_neon', 'prismatic_prism_lens', 'emberkin_pyre_lance', 'mire_steam_lance', 'breach_harpoon', 'grundl_grapple_harpoon',
                                                                        'shrapnel_cannon_scrap', 'basalt_quarry_driver', 'grundl_slug_mortar', 'baron_tithe_gun']),
 ('4', 'FLUSH PODS 4X1 AND BROADSIDE BATTERIES 6X2: BEFORE, AFTER', ['human_volley_rack', 'kett_hive_swarm_launcher', 'sporeling_rot_pod', 'fenn_market_missile', 'gauntling_scrap_shotgun', 'kett_chitin_thrower']),
]
def pair(old, pid, kw={}):
    g = gr.GUNS[pid]
    k = dict(kw)
    if g.aim != 'fixed': k['pad'] = 30
    a = scene(COMP, pid, **k)
    if os.path.exists('%s/%s_out.json' % (old, pid)): b = scene(old, pid, **k)
    else:
        b = Rgba(a.w, a.h, RGB['F'] + (255,)); text(b, 8, a.h // 2 - 20, 'NO ART', 'H', 3); text(b, 8, a.h // 2 + 4, 'TODAY', 'L', 3)
    return [(b, 'BEFORE', pid.upper()), (a, 'AFTER', g.shape.upper() + ' ' + g.fam.upper() + (' ' + g.race.upper() if g.race else ''))]

def before_after(out, old):
    for n, title, ids in SHEETS:
        cells = []
        for pid in ids:
            kw = {}
            cells += pair(old, pid, kw)
        gs.grid(cells, 3, 2400, title=title).save('%s/gun-art-all_before_after_%s.png' % (out, n)); print('sheet', n)

RACES = [('HUMAN', ['laser_mk1', 'human_concord_railgun', 'human_flak_screen', 'human_volley_rack']),
         ('KETT', ['kett_drone_picket', 'kett_chitin_thrower', 'kett_hive_swarm_launcher']),
         ('BASALT', ['basalt_magma_spitter', 'basalt_pumice_flak', 'basalt_quarry_driver']),
         ('EMBERKIN', ['emberkin_flare_turret', 'emberkin_cinder_mortar', 'emberkin_pyre_lance']),
         ('FENN', ['fenn_twitch_cannon', 'fenn_spark_lattice', 'fenn_market_missile']),
         ('MIRE', ['mire_mist_projector', 'mire_bog_mortar', 'mire_steam_lance']),
         ('GAUNTLING', ['gauntling_arc_hammer', 'gauntling_scrap_shotgun', 'gauntling_tesla_picket']),
         ('PRISMATIC', ['prismatic_glimmer_turret', 'prismatic_refractor', 'prismatic_prism_lens']),
         ('GRUNDL', ['grundl_barge_flak', 'grundl_grapple_harpoon', 'grundl_slug_mortar']),
         ('SPORELING', ['sporeling_pollen_turret', 'sporeling_spore_cannon', 'sporeling_rot_pod']),
         ('BARONS', ['sovereign_turret', 'gilded_lance', 'baron_tithe_gun']),
         ('LEECH AND SIREN', ['leech_laser', 'siren_ion_neon'])]
def races(out):
    """the race guns grouped by race: one cell per gun, the race on its label, a gap between races."""
    cells = []
    for nm, ids in RACES:
        for pid in ids:
            g = gr.GUNS[pid]; k = {'pad': 30} if g.aim != 'fixed' else {}
            cells.append((scene(COMP, pid, **k), nm, pid.upper().replace('_', ' ')))
    gs.grid(cells, 3, 3000, title='RACE GUNS BY RACE: HUMAN KETT BASALT EMBERKIN FENN MIRE GAUNTLING PRISMATIC GRUNDL SPORELING BARONS LEECH SIREN. EACH KEEPS ITS HOMELAND COLOUR WING MOTIF AND TIP').save('%s/gun-art-all_races.png' % out); print('races')

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '/home/user/hs/shots'
    old = sys.argv[2] if len(sys.argv) > 2 else '/tmp/claude-0/-home-user/2fe481dc-7c04-5e24-b286-37a000ee4cff/scratchpad/old'
    before_after(out, old); races(out)
