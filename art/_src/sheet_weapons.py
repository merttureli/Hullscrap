"""Weapons preview sheet. Per weapon: every frame of the inside half, the outside half and the barrel (3x, labelled, with glow),
then the whole hull mount assembled on a thick hull (outside half, 2 wall rows, inside half) with the barrel at 0, 45 and -60 degrees,
and at the end a row at 1x (actual size). Usage: python3 sheet_weapons.py [out.png] [weapon ids...]"""
import sys
from px import *
import comp_base
from wbase import OutHalf, FLANGE
from compose import rotate
from sheet_v2 import text

SPACE = (14, 18, 28)
ORDER = ['laser_mk1', 'laser_mk2', 'pulse_mk1', 'pulse_mk2', 'artemis_mk1', 'ion_blast_mk1', 'breach_harpoon', 'heat_lance_neon',
         'shrapnel_cannon_scrap', 'bolt_thrower_scrap', 'laser_turret_mk1', 'rattle_burst_scrap', 'siren_ion_neon', 'leech_laser']
def all_weapons():
    import comp_weapons
    by = {C.id: C for C in comp_weapons.WEAPONS}
    return [by[i] for i in ORDER if i in by]

class Data:
    """exports a weapon once and keeps every frame."""
    def __init__(s, C):
        s.c = c = C()
        s.fin, s.gin, s.Jin = comp_base.export(c, PREVIEW + '/comp_tmp')
        s.oc = OutHalf(c)
        s.fout, s.gout, s.Jout = comp_base.export(s.oc, PREVIEW + '/comp_tmp')
        s.bfr = {(st, i): c.barrel_frame(st, i) for (_, st, n, _) in c.banims for i in range(n)}
        s.bgl = {(st, i): c.barrel_glow_frame(st, i) for (_, st, n, _) in c.banims for i in range(n) if st != 'disabled'}
    def frame(s, J, frames, gframes, anim, i):
        st, cnt, fps = J['anims'][anim]
        g = J.get('glow', {}).get('anims', {}).get(anim)
        return frames[st + i], (gframes[g[0] + i] if g else None)

def wall_rows(w, rows=2):
    s = Spr(w, 16 * rows)
    for r in range(rows):
        for cx in range(w // 16):
            x, y = cx * 16, r * 16
            s.rect(x, y, 16, 16, 'D'); s.hline(x, y, 16, 'E')
            for (rx, ry) in ((3, 3), (12, 3), (3, 12), (12, 12)): s.put(x + rx, y + ry, 'W')
    return s

def space_bg(img, y0, y1):
    for y in range(y0, y1):
        for x in range(img.w): img.p[y][x] = list(SPACE) + [255]
    for k in range(40):
        x = (k * 37 + 11) % img.w; y = y0 + (k * 53 + 7) % max(1, (y1 - y0))
        img.p[y][x] = [120 + (k % 3) * 40, 130 + (k % 3) * 40, 160 + (k % 3) * 30, 255]

def floor_bg(img, y0, y1):
    for y in range(y0, y1):
        for x in range(img.w):
            img.p[y][x] = list(RGB['G'] if (x % 16 == 0 or y % 16 == 0) else RGB['F']) + [255]

def rot_barrel(c, spr, deg):
    px, py = c.bpivot_final()
    S = 2 * max(spr.w, spr.h) + 4; h = S // 2
    cv = Spr(S, S); cv.stamp(h - px, h - py, spr.rows())
    return rotate(cv, deg, h, h), h

def scene(d, deg, bstate='idle', bi=0, ostate='on', oi=0, istate='on', ii=0, pad=26, top=46, glow_on=True):
    """outside half + 2 wall rows + inside half on a thick hull, the barrel turned by deg."""
    c = d.c; foot = d.oc.cells[1] * 16
    W = 64 + 2 * pad; H = top + foot + 32 + 32 + 10
    img = Rgba(W, H, RGB['F'] + (255,))
    wy = top + foot
    space_bg(img, 0, wy); floor_bg(img, wy + 32, H)
    img.blit_spr(wall_rows(W), 0, wy)
    fo, go = d.frame(d.Jout, d.fout, d.gout, ostate, oi)
    img.blit_spr(fo, pad, top)
    fi, gi = d.frame(d.Jin, d.fin, d.gin, istate, ii)
    iy = wy + 32 - FLANGE
    img.blit_spr(fi, pad, iy)
    b = d.bfr[(bstate, bi)]
    # rotate the interior look: the (outlined) barrel sprite itself is turned about its pivot
    r, h = rot_barrel(c, b, deg)
    img.blit_spr(r, pad + c.pivot[0] - h, top + c.pivot[1] - h)
    if glow_on:
        l, t_, r_, b_ = d.c.glow_pad
        if go: img.blit_rgba(go, pad - l, top - t_, 1, add=True)
        if gi: img.blit_rgba(gi, pad - l, iy - t_, 1, add=True)
        if deg == 0 and (bstate, bi) in d.bgl:
            bg = d.bgl[(bstate, bi)]; p = c.bpad
            px, py = c.bpivot_final()
            img.blit_rgba(bg, pad + c.pivot[0] - px - p, top + c.pivot[1] - py - p, 1, add=True)
    return img

def block(C, K=3, W=2400):
    d = Data(C); c = d.c
    gl, gt, gr, gb = c.glow_pad
    items = []                           # (kind, label, spr, glow, ... )
    def frames_of(J, frames, gframes):
        out = []
        names = {}
        for nm, (st, cnt, fps) in J['anims'].items():
            for q in range(cnt): names[st + q] = '%s %d' % (nm, q) if cnt > 1 else nm
        gmap = {}
        for nm, (st, cnt, fps) in J['anims'].items():
            g = J.get('glow', {}).get('anims', {}).get(nm)
            for q in range(cnt):
                if g: gmap[st + q] = g[0] + q
        for i, f in enumerate(frames): out.append((names[i], f, gframes[gmap[i]] if i in gmap else None))
        return out
    inside = frames_of(d.Jin, d.fin, d.gin)
    outside = frames_of(d.Jout, d.fout, d.gout)
    bar = []
    for (name, st, n, fps) in c.banims:
        for i in range(n): bar.append(('%s %d' % (name, i) if n > 1 else name, d.bfr[(st, i)], d.bgl.get((st, i))))
    cw, ch = (64 + 2 * 8) * K, (d.fin[0].h + 16) * K
    och = (d.fout[0].h + 16) * K
    bw, bh = d.bfr[('idle', 0)].w, d.bfr[('idle', 0)].h
    bcw, bch = max((bw + 2 * c.bpad) * K, 130), (bh + 2 * c.bpad) * K
    per = max(1, (W - 40) // cw)
    rows_in = (len(inside) + per - 1) // per
    sc_h = scene(d, 0).h * K
    H = 40 + rows_in * (ch + 26) + (och + 26) + (bch + 26) + sc_h + 40
    def draw(img, y0):
        text(img, 20, y0, '%s  %s  INSIDE %dX%d  OUTSIDE %dX%d  BARREL %dX%d' % (c.id, c.line.upper(), 64, d.fin[0].h, 64, d.fout[0].h, bw, bh), 'H', 4)
        y = y0 + 32
        for i, (lbl, f, g) in enumerate(inside):
            x, yy = 20 + (i % per) * cw, y + (i // per) * (ch + 26)
            img.blit_spr(f, x + gl * K, yy + gt * K, K)
            if g is not None: img.blit_rgba(g.scaled(K), x, yy, 1)
            text(img, x + gl * K, yy + ch - 8, 'IN ' + lbl, 'M', 3)
        y += rows_in * (ch + 26)
        x = 20
        for (lbl, f, g) in outside:
            img.blit_spr(f, x + gl * K, y + gt * K, K)
            if g is not None: img.blit_rgba(g.scaled(K), x, y, 1)
            text(img, x + gl * K, y + och - 8, 'OUT ' + lbl, 'M', 3)
            x += cw
        y += och + 26
        x = 20
        for (lbl, f, g) in bar:
            ox = x + (bcw - (bw + 2 * c.bpad) * K) // 2
            img.blit_spr(f, ox + c.bpad * K, y + c.bpad * K, K)
            if g is not None: img.blit_rgba(g.scaled(K), ox, y, 1)
            text(img, x + 6, y + bch - 8, lbl, 'M', 3)
            x += bcw
        y += bch + 26
        x = 20
        if c.aim == 'fixed':       # fixed guns: straight out, plus one gimbal angle
            plan = [(0, 'FIXED 0', {}), (c.gimbal, 'GIMBAL +%d' % c.gimbal, {}),
                    (0, 'FIRE 0', dict(bstate='fire', bi=0, istate='fire', ii=0)), (-c.gimbal, 'FIRE GIMBAL -%d' % c.gimbal, dict(bstate='fire', bi=1, istate='fire', ii=1))]
        else:                      # turrets: 0, 45 and -60
            plan = [(0, 'TURRET 0', {}), (45, 'TURRET 45', {}), (-60, 'TURRET -60', {}),
                    (0, 'FIRE 0', dict(bstate='fire', bi=0, istate='fire', ii=0)), (-60, 'FIRE -60', dict(bstate='fire', bi=1, istate='fire', ii=1))]
        plan += [(0, 'DAMAGED 0', dict(bstate='damaged', bi=0, ostate='damaged', oi=0, istate='damaged', ii=0)),
                 (0, 'DISABLED 0', dict(bstate='disabled', bi=0, ostate='disabled', oi=0, istate='disabled', ii=0))]
        for (deg, lbl, kw) in plan:
            a = scene(d, deg, **kw)
            img.blit_rgba(a.scaled(K), x, y, 1)
            text(img, x + 6, y + a.h * K - 14, lbl, 'H', 3)
            x += a.w * K + 12
    return H, draw, d

def ammo_block(W=2400, K=3):
    import comp_ammo, json
    c = comp_ammo.AmmoRack()
    frames, gframes, J = comp_base.export(c, PREVIEW + '/comp_tmp')
    names = {}
    for nm, (st, cnt, fps) in J['anims'].items():
        for q in range(cnt): names.setdefault(st + q, '%s %d' % (nm, q) if cnt > 1 else nm)
    cw, ch = 41 * K, 36 * K + 22
    per = (W - 40) // cw
    rows = (len(frames) + per - 1) // per
    H = 80 + rows * ch + 16 * 6 + 40
    def draw(img, y0):
        text(img, 20, y0, 'AMMO_RACK  2X2 CELLS  FRAME 32X32: BAYS FILL ONE BY ONE, 3 CONTENTS (MISSILES, SCRAP, SLUGS)', 'H', 4)
        for i, f in enumerate(frames):
            x, y = 20 + (i % per) * cw, y0 + 32 + (i // per) * ch
            img.blit_spr(f, x + 2 * K, y + 2 * K, K)
            text(img, x + 2 * K, y + 32 * K + 6, names.get(i, ''), 'M', 3)
        yy = y0 + 32 + rows * ch + 12
        text(img, 20, yy, 'TILES/WRECK.PNG 16X16 X4: SCORCHED FLOOR, TWISTED PLATE, LOOSE CABLES, BURNT SCRAP', 'H', 4)
        import tile_wreck
        sh = tile_wreck.export(PREVIEW + '/comp_tmp')
        for k in range(4):
            sub = Spr(16, 16)
            for y in range(16):
                for x in range(16): sub.g[y][x] = sh.g[y][16 * k + x]
            fl = Spr(16, 16)
            for y in range(16):
                for x in range(16): fl.g[y][x] = 'G' if (x == 0 or y == 0) else 'F'
            img.blit_spr(fl, 20 + k * 16 * 7, yy + 32, 6); img.blit_spr(sub, 20 + k * 16 * 7, yy + 32, 6)
    return H, draw

def overview(ds, W=2400, K=3):
    sw = scene(ds[0], 0).w * K + 12
    per = max(1, (W - 40) // sw)
    sh = max(scene(d, 0).h for d in ds) * K + 8
    rows = (len(ds) + per - 1) // per
    H = 40 + rows * sh
    def draw(img, y0):
        text(img, 20, y0, 'OVERVIEW: EVERY WEAPON MOUNTED THROUGH A 2-ROW WALL (OUTSIDE HALF, WALL, INSIDE HALF), READY, BARREL 0', 'H', 4)
        for i, d in enumerate(ds):
            a = scene(d, 0)
            x, y = 20 + (i % per) * sw, y0 + 32 + (i // per) * sh
            img.blit_rgba(a.scaled(K), x, y, 1)
            text(img, x + 6, y + 6, d.c.id + (' FIXED' if d.c.aim == 'fixed' else ' TURRET'), 'H', 3)
    return H, draw

def build(path, classes, W=2400):
    bl = [block(C, W=W) for C in classes]
    ds = [d for _, _, d in bl]
    top = overview(ds, W)
    am = ammo_block(W)
    parts = [(top[0], top[1])] + [(h, dr) for h, dr, _ in bl] + [am]
    Ht = 60 + sum(h for h, _ in parts) + 20 * len(parts) + 330
    img = Rgba(W, Ht, RGB['F'] + (255,))
    y = 20
    for h, dr in parts:
        dr(img, y); y += h + 20
        for x in range(W): img.p[y - 10][x] = list(RGB['G']) + [255]
    text(img, 20, y, 'ACTUAL SIZE 1X: EACH WEAPON AS HULL MOUNT (OUTSIDE HALF, 2 WALL ROWS, INSIDE HALF), BARREL UP', 'H', 4)
    x = 20
    for d in ds:
        a = scene(d, 0, pad=10, top=30)
        img.blit_rgba(a, x, y + 36, 1)
        x += a.w + 6
        if x > W - 100: break
    img.save(path)
    return img.w, img.h

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else PREVIEW + '/weapons_sheet.png'
    want = sys.argv[2:]
    classes = [C for C in all_weapons() if not want or C.id in want]
    print(build(out, classes))
