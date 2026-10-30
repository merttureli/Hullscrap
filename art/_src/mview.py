"""dev preview for hull mounts: every frame of the inside half, the outside half and the barrel at 3x, then the mount through a 2-row wall."""
import sys, os, json
from px import *
import pal_sector
import comp_base
from mnt import OutHalfW
from wbase import FLANGE
from sheet_v2 import text
from sheet_weapons import wall_rows, space_bg, floor_bg, rot_barrel
TMP = PREVIEW + '/mtmp'

def data(C):
    c = C()
    fin, gin, Jin = comp_base.export(c, TMP)
    oc = OutHalfW(c)
    fout, gout, Jout = comp_base.export(oc, TMP)
    return c, oc, (fin, gin, Jin), (fout, gout, Jout)

def named(J, frames, gframes):
    names, gmap = {}, {}
    for nm, (st, cnt, fps) in J['anims'].items():
        g = J.get('glow', {}).get('anims', {}).get(nm)
        for q in range(cnt):
            names.setdefault(st + q, '%s %d' % (nm, q) if cnt > 1 else nm)
            if g: gmap[st + q] = g[0] + q
    return [(names[i], f, gframes[gmap[i]] if i in gmap else None) for i, f in enumerate(frames)]

def frame_of(D, anim, i):
    fr, gl, J = D
    st, cnt, fps = J['anims'][anim]
    g = J.get('glow', {}).get('anims', {}).get(anim)
    return fr[st + i], (gl[g[0] + i] if g else None)

def scene(c, oc, din, dout, ostate='on', oi=0, istate='on', ii=0, pad=20, top=30, K=1, bstate=None, bi=0, deg=0):
    foot = oc.cells[1] * 16; W = c.w + 2 * pad
    H = top + foot + 32 + 32 + 10
    img = Rgba(W, H, RGB['F'] + (255,))
    wy = top + foot
    space_bg(img, 0, wy); floor_bg(img, wy + 32, H)
    img.blit_spr(wall_rows(W), 0, wy)
    fo, go = frame_of(dout, ostate, oi); fi, gi = frame_of(din, istate, ii)
    ox = pad + (c.w - oc.w) // 2
    img.blit_spr(fo, ox, top)
    iy = wy + 32 - FLANGE
    img.blit_spr(fi, pad, iy)
    if c.has_barrel and bstate:
        b = c.barrel_frame(bstate, bi)
        r, h = rot_barrel(c, b, deg)
        img.blit_spr(r, ox + c.pivot[0] - h, top + c.pivot[1] - h)
    l, t, r_, b_ = c.glow_pad
    ol, ot = oc.glow_pad[0], oc.glow_pad[1]
    if go: img.blit_rgba(go, ox - ol, top - ot, 1, add=True)
    if gi: img.blit_rgba(gi, pad - l, iy - t, 1, add=True)
    if c.has_barrel and bstate and deg == 0 and (bstate, bi) in getattr(c, '_bg', {}):
        pass
    return img

def sheet_for(Cs, path, K=3, W=2400):
    blocks = []
    for C in Cs:
        c, oc, din, dout = data(C)
        blocks.append((c, oc, din, dout))
    H = 20
    for c, oc, din, dout in blocks:
        H += 70 + ((len(din[0]) + 5) // 6) * (din[0][0].h + 24) * K + ((len(dout[0]) + 5) // 6) * (dout[0][0].h + 24) * K + 400
    img = Rgba(W, H, RGB['F'] + (255,))
    y = 10
    for c, oc, din, dout in blocks:
        text(img, 10, y, '%s %dx%d frame %dx%d / out %dx%d' % (c.id, c.cells[0], c.cells[1], c.w, c.h, oc.w, oc.h), 'H', 4); y += 34
        for (D, cc) in ((din, c), (dout, oc)):
            lst = named(D[2], D[0], D[1]); l, t, r, b = cc.glow_pad
            cw, ch = (cc.w + l + r) * K, (cc.h + t + b) * K + 14
            per = max(1, (W - 20) // cw)
            for i, (lbl, f, g) in enumerate(lst):
                x, yy = 10 + (i % per) * cw, y + (i // per) * ch
                img.blit_spr(f, x + l * K, yy + t * K, K)
                if g is not None: img.blit_rgba(g.scaled(K), x, yy, 1, add=True)
                text(img, x + l * K, yy + (cc.h + t) * K + 2, lbl, 'M', 2)
            y += ((len(lst) + per - 1) // per) * ch + 6
        if c.has_barrel:
            x = 10
            for (name, st, n, fps) in c.banims:
                for i in range(n):
                    f = c.barrel_frame(st, i); gg = c.barrel_glow_frame(st, i) if st != 'disabled' else None
                    img.blit_spr(f, x + c.bpad * K, y + c.bpad * K, K)
                    if gg is not None: img.blit_rgba(gg.scaled(K), x, y, 1, add=True)
                    text(img, x + 4, y + (f.h + 2 * c.bpad) * K - 8, '%s %d' % (name, i), 'M', 2)
                    x += (f.w + 2 * c.bpad) * K
            y += (f.h + 2 * c.bpad) * K + 10
        x = 10; sh = 0
        plan = [('on', 0, 'on', 0), ('pulling' if 'pulling' in dout[2]['anims'] else 'on', 2, 'pulling' if 'pulling' in din[2]['anims'] else 'on', 2), ('damaged', 0, 'damaged', 0), ('disabled', 0, 'disabled', 0), ('off', 0, 'off', 0)]
        for (os_, oi, is_, ii) in plan:
            a = scene(c, oc, din, dout, os_, oi, is_, ii, bstate='idle' if c.has_barrel else None)
            img.blit_rgba(a.scaled(K), x, y, 1); x += a.w * K + 14; sh = max(sh, a.h * K)
        y += sh + 24
    img.save(path)
    print(img.w, y)

def zoom(C, picks, path, K=8):
    """picks: [('out'|'in', anim, i)] -> frames side by side at K x with glow."""
    c, oc, din, dout = data(C)
    items = []
    for (w, a, i) in picks:
        D, cc = (dout, oc) if w == 'out' else (din, c)
        f, g = frame_of(D, a, i); items.append((f, g, cc, '%s %s %d' % (w, a, i)))
    Wd = sum((f.w + 16 + 14) * K for f, g, cc, _ in items) + 20
    Hd = max((f.h + cc.glow_pad[1] + cc.glow_pad[3]) * K for f, g, cc, _ in items) + 30
    img = Rgba(Wd, Hd, (30, 34, 44, 255))
    x = 10
    for f, g, cc, lbl in items:
        l, t = cc.glow_pad[0], cc.glow_pad[1]
        img.blit_spr(f, x + l * K, 20 + t * K, K)
        if g is not None: img.blit_rgba(g.scaled(K), x, 20, 1, add=True)
        text(img, x, 4, lbl, 'M', 2)
        x += (f.w + 16 + 14) * K
    img.save(path)
    print(img.w, img.h)
