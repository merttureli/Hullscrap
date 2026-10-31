"""Racial tech art, group a (human, basalt, emberkin, fenn, kett): the shared pieces.
Only palette letters that already exist are used (no new colours). Per race one module (techa_<race>.py) lists its parts in ALL;
techa_all.py exports them (components through comp_base.export, projectiles through Proj below) and draws the preview.
Weapons are wbase.Weapon subclasses (inside half, `_out` half, `_barrel`); engines are lines_eng_base.EngBase classes (two halves);
reactors, shields and utilities are lines_kit.LComp classes. Everything is drawn pixel by pixel from the ASCII maps and calls below."""
import os, json
from wbase import *                      # Weapon, OutHalf, St/OSt/BSt, strip, coupling, hatch, turret_ring, FLASH_E ... plus comp_base (Spr, art, bev, glow, Rgba ...)
import lines_kit as LK
from lines_kit import circle, ring, line, thick, col_tones, glow_xy, shift_rect, chamfer_tones
from lines_eng_base import EngBase, Half2, from_full
from px import ART

# glow colours: palette colours only
ORANGE, YEL, RED, AMBER, GREEN, BLUE, CYAN, MAGENTA = (255, 138, 30), (255, 210, 58), (224, 65, 59), (225, 161, 54), (107, 211, 74), (79, 163, 255), (60, 242, 255), (255, 79, 216)
WHITE, VIOLET, PINK = (244, 246, 248), (196, 160, 240), (232, 138, 160)

def hsh(x, y, k=0):
    """deterministic position hash (stone specks, chips): no random module, same result every build."""
    return ((x * 73856093) ^ (y * 19349663) ^ ((k + 1) * 83492791)) & 0xffff

# ------------------------------------------------------------------ materials
def mat(s, x, y, w, h, tone, cham=True):
    """bevelled slab in a tone triple (hi, mid, lo)."""
    bev(s, x, y, w, h, tone[0], tone[1], tone[2], cham=cham)

STEEL, IRON, DIRON = ('M', 'S', 'W'), ('S', 'W', 'E'), ('W', 'E', 'D')
STONE, STONE_D = ('S', 'W', 'E'), ('W', 'E', 'D')
BRASS, BRASS_D = ('y', 'a', 'u'), ('a', 'u', 'n')
CHITIN, CHITIN_D = ('y', 'a', 'u'), ('a', 'u', 'n')
CREAM = ('H', 'f', 'Q')

def stone(s, x, y, w, h, k=0, tone=STONE, specks=True, rough=True, seams=()):
    """a lump of basalt: bevelled, faceted (light plane top-left, dark plane bottom-right), chipped edges, dark crevices, a few specks."""
    bev(s, x, y, w, h, tone[0], tone[1], tone[2])
    if min(w, h) >= 7:
        t = (w + h) // 7 + 1
        for j in range(1, h - 1):
            for i in range(1, w - 1):
                if s.get(x + i, y + j) != tone[1]: continue
                d = i + j
                if d <= t: s.put(x + i, y + j, tone[0])
                elif d >= w + h - 2 - t - 1: s.put(x + i, y + j, 'n' if tone is STONE else tone[2])
    if rough:
        for (cx, cy, dx, dy) in ((x, y, 1, 1), (x + w - 1, y, -1, 1), (x, y + h - 1, 1, -1), (x + w - 1, y + h - 1, -1, -1)):
            hv = hsh(cx, cy, k)
            if hv % 3 != 2: s.erase(cx + dx, cy)
            if hv % 4 < 2: s.erase(cx, cy + dy)
            if hv % 5 == 0: s.erase(cx + dx, cy + dy)
        for i in range(2, w - 2):
            if hsh(x + i, y, k + 3) % 6 == 0: s.erase(x + i, y); s.erase(x + i + 1, y) if i % 2 else None
            if hsh(x + i, y + h - 1, k + 4) % 6 == 0: s.erase(x + i, y + h - 1)
        for j in range(2, h - 2):
            if hsh(x, y + j, k + 5) % 6 == 0: s.erase(x, y + j)
            if hsh(x + w - 1, y + j, k + 6) % 6 == 0: s.erase(x + w - 1, y + j)
    if specks:
        for j in range(2, h - 2):
            for i in range(2, w - 2):
                v = hsh(x + i, y + j, k) % 19
                if v == 0 and s.get(x + i, y + j) == tone[1]: s.put(x + i, y + j, tone[0])
                elif v == 1 and s.get(x + i, y + j) in (tone[1], tone[2]): s.put(x + i, y + j, 'D')
    if min(w, h) >= 9:                                           # crevices: short dark zigzags
        for c in range(1 + (w * h) // 260):
            hv = hsh(x, y, k * 7 + c)
            cx = x + 2 + hv % max(1, w - 6); cy = y + 2 + (hv >> 5) % max(1, h - 6)
            for q in range(4 + hv % 3):
                s.put(cx, cy, 'D') if s.get(cx, cy) not in ('.', 'K') else None
                cx += 1 if (hv >> q) & 1 else 0; cy += 1
                if (hv >> (q + 3)) & 1: cx += 1
    for (a, b) in seams: line(s, a[0], a[1], b[0], b[1], 'D')

def speckle(s, x0, y0, x1, y1, k=0, base='W', hi='S', lo='D', every=19):
    """stone grain on the pixels of tone `base` inside a box: a few lighter specks, a few dark pits."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if s.get(x, y) != base: continue
            v = hsh(x, y, k) % every
            if v == 0: s.put(x, y, hi)
            elif v == 1: s.put(x, y, lo)

def magma(s, pts, on, i=0, w=1):
    """a magma seam through pts: lit = red edge, orange body, yellow core (flickers with i); cold = dark crust."""
    for (a, b) in zip(pts, pts[1:]):
        n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
        for t in range(n + 1):
            x = a[0] + round((b[0] - a[0]) * t / n); y = a[1] + round((b[1] - a[1]) * t / n)
            if on:
                s.put(x, y, 'y' if (t + i) % 4 == 0 else 'o')
                s.put(x + 1, y, 'r') if s.get(x + 1, y) not in ('.', 'o', 'y') and t % 2 == 0 else None
                if w > 1: s.put(x + 1, y, 'o'); s.put(x, y + 1, 'o')
            else:
                s.put(x, y, 'n' if t % 2 else 'D')

def magma_crack(s, pts, i=0):
    """a crack that leaks magma (damaged basalt): dark fissure with a lit pixel here and there that swaps between frames."""
    for (a, b) in zip(pts, pts[1:]):
        n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
        for t in range(n + 1):
            x = a[0] + round((b[0] - a[0]) * t / n); y = a[1] + round((b[1] - a[1]) * t / n)
            if s.get(x, y) != '.': s.g[y][x] = ('o' if (t + i) % 3 == 0 else ('r' if (t + i) % 3 == 1 else 'K'))

def rivet(s, x, y, c='L'):
    s.put(x, y, c)

def lamp2(s, x, y, c, on, w=2, h=2):
    s.rect(x, y, w, h, c if on else 'E')
    if on: s.put(x, y, 'H')

def pipe_h(s, x, y, w, h=3, tone='q', bands=True):
    """a horizontal pipe in brown (copper-ish) with flange bands."""
    hi, mid, lo = {'q': ('Q', 'q', 'n'), 'a': ('y', 'a', 'u'), 's': ('M', 'S', 'W')}[tone]
    ramp = [hi] + [mid] * max(0, h - 2) + [lo]
    for k, c in enumerate(ramp[:h]): s.hline(x, y + k, w, c)
    if bands:
        for bx in range(x + 3, x + w - 2, 9):
            s.vline(bx, y - 1, h + 2, 'M'); s.vline(bx + 1, y - 1, h + 2, 'W')

def pipe_v(s, x, y, h, w=3, tone='q'):
    hi, mid, lo = {'q': ('Q', 'q', 'n'), 'a': ('y', 'a', 'u'), 's': ('M', 'S', 'W')}[tone]
    ramp = [hi] + [mid] * max(0, w - 2) + [lo]
    for k, c in enumerate(ramp[:w]): s.vline(x + k, y, h, c)
    for by in range(y + 3, y + h - 2, 9):
        s.hline(x - 1, by, w + 2, 'M'); s.hline(x - 1, by + 1, w + 2, 'W')

# ------------------------------------------------------------------ inside-half pieces (skinned)
def cable_stub(s, x, y, st, c='g', body=DIRON):
    """INSIDE: the power coupling: a cable stub from the left edge into a socket block with 4 pins and a status lamp."""
    s.rect(0, y + 4, x + 2, 4, 'q'); s.hline(0, y + 4, x + 2, 'Q'); s.hline(0, y + 7, x + 2, 'n')
    mat(s, x, y, 10, 12, body)
    s.rect(x + 2, y + 3, 6, 6, 'D')
    for (dx, dy) in ((3, 5), (6, 5), (3, 7), (6, 7)): s.put(x + dx, y + dy, 'L')
    s.put(x + 8, y + 1, c if st.powered else 'E')

def hatch_k(s, x, y, tone=STEEL, w=11, h=9, latch='a'):
    """INSIDE: the repair hatch crew open, in any tone: a latched panel with a wrench slot."""
    mat(s, x, y, w, h, tone, cham=False)
    s.rect(x + 3, y + h // 2 - 1, w - 6, 2, 'D'); s.put(x + w - 3, y + h // 2 - 1, latch); s.put(x + w - 3, y + h // 2, 'u')
    for (dx, dy) in ((1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)): s.put(x + dx, y + dy, 'W' if tone[0] in 'SMLH' else 'L')

def slits(s, st, x, y, n=5, cw=6, pitch=8, h=2, cold=('E', 'D'), lit=('o', 'y'), hot=('y', 'H'), frame=True, base=('D', 'K')):
    """a row of n glowing slots (the charge indicator of a stone/brass/hive weapon): `lit` while charging, `hot` when ready, flash white on the discharge."""
    if frame: recess(s, x - 2, y - 1, n * pitch + 2, h + 2, base[0], base[1])
    for k in range(n):
        cx = x + k * pitch
        on = st.powered and k < st.lit
        for r in range(h):
            if getattr(st, 'flash', False) and st.powered: c = 'H' if r == 0 else 'L'
            elif st.ready and on: c = hot[0] if r else hot[1]
            elif on: c = lit[0] if r else lit[1]
            else: c = cold[0] if r == 0 else cold[1]
            s.hline(cx, y + r, cw, c)

def slits_glow(g, ox, oy, state, i, x, y, n=5, cw=6, pitch=8, h=2, live=ORANGE, ready=YEL):
    lit = {'charge': i, 'on': 5, 'damaged': 3}.get(state, 0)
    rdy = state in ('on', 'damaged') or (state == 'charge' and i == 5)
    if state == 'damaged' and i == 1: rdy = False
    for k in range(lit): glow(g, ox + x + k * pitch + cw / 2, oy + y + h / 2, 5.5, ready if rdy else live, 0.5, 2.0, sx=1.5)

def dead_slits(s, st, y, ks=(3, 4), x0=STRIP_X, pitch=8, cw=6):
    for k in ks:
        for r in range(2): s.hline(x0 + pitch * k, y + r, cw, 'D' if r else 'E')
    s.put(x0 + pitch * ks[-1] + 2, y, 'r')

# ------------------------------------------------------------------ outside-half pieces
def foot_pad(s, y, tone, x0=6, x1=58, out_h=36):
    """the base pad of a mount: a plate that runs into the flange."""
    mat(s, x0, y, x1 - x0, out_h - y - FLANGE, tone)

def sleeve_block(s, tone, cy=12, bw=26, bh=26, sw=None, k=None):
    """a fixed gun's forward-heavy block in any tone with the barrel sleeve at its outward end and the gimbal pin at (32, cy)."""
    x0 = 32 - bw // 2; top = cy - 10
    sw = sw or bw - 4
    mat(s, x0, top, bw, bh, tone)
    mat(s, 32 - sw // 2, top - 1, sw, 8, tone)
    s.rect(32 - (sw - 8) // 2, top, sw - 8, 6, 'D'); s.hline(32 - (sw - 8) // 2, top, sw - 8, 'K')

def gimbal(s, cy=12, bw=26, tone=('L', 'M', 'S')):
    x0 = 32 - bw // 2
    mat(s, x0 - 1, cy - 3, bw + 2, 5, tone, cham=False)
    s.put(32, cy, 'L'); s.put(33, cy + 1, 'W'); s.put(31, cy, 'M')

def wing(s, x, y, w, h, tone, k=0):
    mat(s, x, y, w, h, tone)

# ------------------------------------------------------------------ damage vocabulary shared by the races
def hurt_pair(s, st, a, b):
    """spark in one place on frame 0, in another on frame 1."""
    spark(s, *(a if st.i == 0 else b), False)

def fallen_chunk(s, x, y, tone=STONE, k=0):
    """a piece of stone broken off and lying on the floor/pad: a small lump."""
    s.stamp(x, y, art("""
.KK.
KSMK
KWSK
.KK.
"""))

def chip(s, x, y, w, h):
    """a bite out of an edge: erase a small block and darken its inner lip."""
    for j in range(h):
        for i in range(w): s.erase(x + i, y + j)

# ------------------------------------------------------------------ projectile export
BLEND = 'add (preferred) or alpha-over'
GLOW_RGB = {'H': WHITE, 'y': YEL, 'o': ORANGE, 'r': RED, 'a': AMBER, 'g': GREEN, 'b': BLUE, 'c': CYAN, 'm': MAGENTA, 'p': PINK, 'L': WHITE, 'M': WHITE, 'V': VIOLET, 'X': VIOLET, 'f': YEL, 'u': AMBER, 'Q': AMBER}

def halo(spr, pad, bands=((1.5, 110), (3.0, 52)), src='HyoraAgbcmpVXfuQ', rgb=None):
    """soft glow layer for a hard-pixel frame: (w+2pad) x (h+2pad), discrete alpha bands in palette hues (the strongest band wins)."""
    g = Rgba(spr.w + 2 * pad, spr.h + 2 * pad)
    rad = bands[-1][0]
    for y in range(spr.h):
        for x in range(spr.w):
            ch = spr.g[y][x]
            if ch not in src: continue
            c = rgb or GLOW_RGB.get(ch, WHITE)
            for yy in range(int(y + pad - rad - 1), int(y + pad + rad + 2)):
                for xx in range(int(x + pad - rad - 1), int(x + pad + rad + 2)):
                    if not (0 <= xx < g.w and 0 <= yy < g.h): continue
                    d = ((xx - x - pad) ** 2 + (yy - y - pad) ** 2) ** 0.5
                    for (md, al) in bands:
                        if d <= md:
                            if al > g.p[yy][xx][3]: g.p[yy][xx] = list(c) + [al]
                            break
    return g

def tile_halo_y(spr, pad, bands, src='HyoraAgbcmpVXfuQ'):
    """glow of a segment that tiles along y: computed on three stacked copies, the middle one kept (it joins seamlessly)."""
    st = Spr(spr.w, spr.h * 3)
    for k in range(3): st.stamp(0, k * spr.h, spr.rows())
    g = halo(st, pad, bands, src)
    o = Rgba(spr.w + 2 * pad, spr.h)
    for y in range(spr.h):
        for x in range(o.w): o.p[y][x] = list(g.p[spr.h + pad + y][x])
    return o

def _strip(frames, rgba=False):
    w, h = frames[0].w, frames[0].h
    if rgba:
        o = Rgba(w * len(frames), h)
        for k, f in enumerate(frames): o.blit_rgba(f, k * w, 0)
        return o
    o = Spr(w * len(frames), h)
    for k, f in enumerate(frames): o.stamp(k * w, 0, f.rows())
    return o

class Proj:
    """One weapon's projectile + impact art in art/projectiles/: `<id>.png/.json/_glow.png` and `<id>_impact.png/.json/_impact_glow.png`.
    Faces UP; `head` is the pixel that sits on the projectile, `tail` where the trail starts. `frames` and `impact` are lists of Spr."""
    def __init__(s, id, frames, impact, head, tail, fps=14, ifps=16, pad=4, ipad=4, bands=((1.5, 110), (3.0, 52)), ibands=((2.0, 110), (4.0, 55)),
                 tile=False, notes='', inotes='', src='HyoraAgbcmpVXfuQ', isrc=None, orientation='up', extra=None):
        s.id, s.frames, s.impact = id, frames, impact
        s.head, s.tail, s.fps, s.ifps, s.pad, s.ipad = head, tail, fps, ifps, pad, ipad
        s.bands, s.ibands, s.tile, s.notes, s.inotes, s.src = bands, ibands, tile, notes, inotes, src
        s.isrc = isrc or src
        s.extra = extra or {}
    def export(s, outdir=None):
        outdir = outdir or ART + '/projectiles'
        os.makedirs(outdir, exist_ok=True)
        w, h = s.frames[0].w, s.frames[0].h
        for f in s.frames: assert (f.w, f.h) == (w, h), (s.id, 'frame size')
        save(_strip(s.frames), '%s/%s.png' % (outdir, s.id))
        if s.tile: gl = [tile_halo_y(f, s.pad, s.bands, s.src) for f in s.frames]
        else: gl = [halo(f, s.pad, s.bands, s.src) for f in s.frames]
        _strip(gl, True).save('%s/%s_glow.png' % (outdir, s.id))
        n = len(s.frames)
        iw, ih = s.impact[0].w, s.impact[0].h
        save(_strip(s.impact), '%s/%s_impact.png' % (outdir, s.id))
        ig = [halo(f, s.ipad, s.ibands, s.isrc) for f in s.impact]
        _strip(ig, True).save('%s/%s_impact_glow.png' % (outdir, s.id))
        m = len(s.impact)
        gl_json = {'image': s.id + '_glow.png', 'frame': [w + 2 * s.pad, h if s.tile else h + 2 * s.pad], 'offset': [-s.pad, 0 if s.tile else -s.pad],
                   'anims': {'fly': [0, n, s.fps]}, 'blend': BLEND}
        if s.tile: gl_json['tile'] = 'y'
        ij = {'image': s.id + '_impact.png', 'frame': [iw, ih], 'anims': {'play': [0, m, s.ifps]}, 'anchor': [iw // 2, ih // 2],
              'glow': {'image': s.id + '_impact_glow.png', 'frame': [iw + 2 * s.ipad, ih + 2 * s.ipad], 'offset': [-s.ipad, -s.ipad], 'anims': {'play': [0, m, s.ifps]}, 'blend': BLEND}}
        J = {'frame': [w, h], 'orientation': 'up: travels towards the top of the image at rotation 0', 'anims': {'fly': [0, n, s.fps]},
             'anchors': {'head': list(s.head), 'tail': list(s.tail)}, 'glow': gl_json, 'impact': ij, 'notes': s.notes}
        if s.tile: J['tile'] = 'y'; J['length'] = h; J['width'] = w
        J.update(s.extra)
        with open('%s/%s.json' % (outdir, s.id), 'w') as f: json.dump(J, f, indent=1); f.write('\n')
        IJ = {'frame': [iw, ih], 'anims': {'play': [0, m, s.ifps]}, 'mode': 'once', 'anchors': {'center': [iw // 2, ih // 2]},
              'glow': ij['glow'], 'notes': s.inotes or ('Hit flare for %s; see %s.json.' % (s.id, s.id))}
        with open('%s/%s_impact.json' % (outdir, s.id), 'w') as f: json.dump(IJ, f, indent=1); f.write('\n')
        return s

# ------------------------------------------------------------------ projectile / impact drawing helpers
import math
def disc(s, cx, cy, r, c):
    circle(s, cx, cy, r, c)

def rays(s, cx, cy, n, r0, r1, cols, phase=0.0, only=None):
    """n short rays from radius r0 to r1 round (cx, cy); the colours run along each ray (list of letters, inner to outer)."""
    for k in range(n):
        if only is not None and k not in only: continue
        a = 2 * math.pi * k / n + phase
        pts = []
        for r in range(r0, r1 + 1):
            p = (int(round(cx + (r + .5) * math.cos(a) - .5)), int(round(cy + (r + .5) * math.sin(a) - .5)))
            if not pts or pts[-1] != p: pts.append(p)
        for t, (x, y) in enumerate(pts): s.put(x, y, cols[min(len(cols) - 1, t * len(cols) // len(pts))])

def dots(s, cx, cy, r, n, c, phase=0.0, step=1):
    """n single pixels on a ring of radius r (specks, droplets, embers)."""
    for k in range(0, n, step):
        a = 2 * math.pi * k / n + phase
        s.put(int(round(cx + r * math.cos(a) - .5)), int(round(cy + r * math.sin(a) - .5)), c)

def shard(s, x, y, c1='M', c2='S'):
    """a 2x2 chunk of rock or chitin: light top-left, shade bottom-right."""
    s.put(x, y, c1); s.put(x + 1, y, c1); s.put(x, y + 1, c2); s.put(x + 1, y + 1, c2)

def spr_from(rows_list):
    return [from_art(r) for r in rows_list]
from px import from_art

def flame(s, x, y, h, w=3, i=0, hot=False):
    """a flame tongue standing on (x, y) (bottom-left of its base), h tall: red root, orange body, yellow tip; the tip leans by frame i."""
    for r in range(h):
        t = r / max(1, h - 1)
        ww = w if t < 0.45 else (max(1, w - 2) if t < 0.85 else 1)
        c = 'r' if t < 0.15 else ('o' if t < 0.55 else ('y' if t < 0.95 else ('H' if hot else 'y')))
        lean = 0 if t < 0.5 else ((i % 3) - 1 if t > 0.75 else 0)
        x0 = x + (w - ww) // 2 + lean
        s.hline(x0, y - r, ww, c)
        if ww >= 3 and 0.25 < t < 0.7 and c == 'o': s.put(x0 + 1, y - r, 'y')

def flame_mass(s, x0, x1, y_base, hmax, i, power=0.7, hot=True, clip=None):
    """a bank of flame between x0..x1 standing on y_base: tall in the middle, ragged (the raggedness moves with frame i), red root, orange body, yellow tips, white core.
    clip(x, y) -> False cuts a pixel (keeps flames inside a window)."""
    cx = (x0 + x1) / 2.0; half = max(1.0, (x1 - x0) / 2.0)
    for x in range(x0, x1 + 1):
        t = 1 - abs(x - cx) / half
        h = int(hmax * max(0.0, t) ** power) + ((x * 7 + i * 5) % 3 - 1)
        for r in range(max(0, h)):
            if clip and not clip(x, y_base - r): continue
            core = hot and abs(x - cx) < half * 0.38 and r < h * 0.6
            if core: c = 'H' if r < h * 0.3 else 'y'
            else: c = 'r' if r == 0 else ('o' if r < h * 0.55 else 'y')
            s.put(x, y_base - r, c)

def flipv(spr):
    n = Spr(spr.w, spr.h); n.g = [r[:] for r in reversed(spr.g)]; return n

def stamp_spr(dst, x, y, src):
    dst.stamp(x, y, src.rows())


def gauge(s, cx, cy, r, on, ang=0):
    """a brass-rimmed pressure gauge with a needle."""
    circle(s, cx, cy, r + 1, 'u'); circle(s, cx, cy, r, 'H' if on else 'M'); circle(s, cx, cy, max(1, r - 1), 'L' if on else 'S')
    for (dx, dy) in ((0, -1), (1, -1), (1, 0), (-1, -1))[ang % 4:ang % 4 + 1]: s.put(int(cx + dx * (r - 1)), int(cy + dy * (r - 1)), 'r' if on else 'W')
    s.put(int(cx), int(cy), 'E')
