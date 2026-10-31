"""Preview sheet (3x) for the racial hand weapons (hand_race.py): every weapon as an icon (1x and 3x) and held by its race's rig at 1x and 3x
(4 rotations at 1x; 0 and 90 at 3x, plain and in the act of firing with its muzzle flash), then the flash frames at 3x.
python3 art/_src/sheet_hand.py [out.png]"""
import sys
from px import *
import pal_races1     # noqa: F401
import crew_v2 as cv2
from crew_v2 import C
from compose import G, GC
from sp_common import MOUNT
from sheet_v2 import text
from sp_compose import SKit, render
from sheet_species import draw_fig
from sheet_races1 import HEAD0, HEAD1, TINTS
from sp_kett import Kett
from sp_mire import Mire
from sp_sporeling import Sporeling
from sp_gauntling import Gauntling
from sp_prismatic import Prismatic
from sp_grundl import Grundl
import sp_items
import hand_race as H

K = 3; BG = (110, 118, 131, 255)
RACES = [('kett', Kett, ['sting_pistol', 'hive_prod']), ('mire', Mire, ['bubble_rifle', 'hook_gaff']), ('sporeling', Sporeling, ['spore_puffer', 'thorn_lash']),
         ('gauntling', Gauntling, ['rivet_fist', 'arc_welder']), ('prismatic', Prismatic, ['lens_pistol', 'shard_lance']), ('grundl', Grundl, ['freight_hammer', 'chain_gun'])]
FLASH = {'sting_pistol': 'sting', 'bubble_rifle': 'bubble', 'spore_puffer': 'puff', 'rivet_fist': 'rivet', 'arc_welder': 'weld', 'lens_pistol': 'lens',
         'shard_lance': 'shard', 'chain_gun': 'chain'}          # the melee weapons have no flash
SHEET_W = 2100; BC = 76                                # BC: the big composite canvas is (2*BC+1) square, centred on the rig's pivot pixel

def rot_spr(s, q):
    for _ in range(q % 4):
        n = Spr(s.h, s.w)
        for y in range(s.h):
            for x in range(s.w): n.g[x][s.h - 1 - y] = s.g[y][x]
        s = n
    return s

def rot_rgba(g, q):
    for _ in range(q % 4):
        n = Rgba(g.h, g.w)
        for y in range(g.h):
            for x in range(g.w): n.p[x][g.h - 1 - y] = list(g.p[y][x])
        g = n
    return g

def rot_pt(x, y, q):
    for _ in range(q % 4): x, y = -y, x
    return x, y

def held(kit, item, deg, fire=False):
    """-> (figure Rgba, glow Rgba) on a (2*BC+1)^2 canvas centred on the pivot pixel; with the item's muzzle flash (frame 0) when `fire`."""
    sp = kit.sp; pose = H.HAND[item]['cls']
    f, g = render(kit, 6, deg, deg, pose, item, HEAD0[sp.id], tint=TINTS[sp.id])
    N = 2 * BC + 1
    fig, gl = Rgba(N, N), Rgba(N, N)
    o = BC - GC
    fig.blit_rgba(f, o, o); gl.blit_rgba(g, o, o)
    if fire and item in FLASH:
        fn, mode, fps, rgb, r, chars, _, _ = H.FX[FLASH[item]]
        frames, (ax, ay) = fn()
        it = H.HAND[item]; q = deg // 90
        vx = MOUNT[pose][0] - C + it['muzzle'][0] - it['grip'][0]; vy = MOUNT[pose][1] - C + it['muzzle'][1] - it['grip'][1]
        vx, vy = rot_pt(vx, vy, q)
        spr = rot_spr(frames[0], q)
        a = rot_pt(ax, ay, q)                                  # the anchor's offset from the frame's top-left, turned
        ax2, ay2 = {0: (ax, ay), 1: (frames[0].h - 1 - ay, ax), 2: (frames[0].w - 1 - ax, frames[0].h - 1 - ay), 3: (ay, frames[0].w - 1 - ax)}[q % 4]
        px_, py_ = BC + vx - ax2, BC + vy - ay2
        fig.blit_rgba(spr_to_rgba(spr), px_, py_)
        gf = rot_rgba(H.fx_glow(frames[0], rgb, r, chars), q)
        gl.blit_rgba(gf, px_ - H.PAD if q % 4 in (0,) else px_ - H.PAD, py_ - H.PAD, add=True)
    return fig, gl

def draw_big(img, fig, gl, x, y, k, crop=96, gs=0.55):
    N = fig.w; off = N // 2 - crop // 2
    for j in range(crop):
        for i in range(crop):
            p = fig.p[j + off][i + off] if 0 <= j + off < N and 0 <= i + off < N else (0, 0, 0, 0)
            if p[3]:
                for dy in range(k):
                    for dx in range(k): img.over(x + i * k + dx, y + j * k + dy, tuple(p))
    for j in range(crop):
        for i in range(crop):
            p = gl.p[j + off][i + off] if 0 <= j + off < N and 0 <= i + off < N else (0, 0, 0, 0)
            if p[3]:
                for dy in range(k):
                    for dx in range(k): img.add(x + i * k + dx, y + j * k + dy, (p[0], p[1], p[2], int(p[3] * gs)))

def draw_icon(img, id, x, y, k):
    it = H.HAND[id]; s = sp_items.outlined_item(it)
    img.blit_spr(s, x, y, k)
    if it['glow']:
        gl = H.item_glow(it, margin=1)
        for j in range(gl.h):
            for i in range(gl.w):
                p = gl.p[j][i]
                if p[3]:
                    for dy in range(k):
                        for dx in range(k): img.add(x + (i - sp_items.GLOW_PAD) * k + dx, y + (j - sp_items.GLOW_PAD) * k + dy, (p[0], p[1], p[2], int(p[3] * .6)))
    return s.w, s.h

def draw_flash(img, name, x, y, k):
    fn, mode, fps, rgb, r, chars, _, _ = H.FX[name]
    frames, org = fn(); w = 0
    for f in frames:
        img.blit_spr(f, x + w, y, k)
        g = H.fx_glow(f, rgb, r, chars)
        for j in range(g.h):
            for i in range(g.w):
                p = g.p[j][i]
                if p[3]:
                    for dy in range(k):
                        for dx in range(k): img.add(x + w + (i - H.PAD) * k + dx, y + (j - H.PAD) * k + dy, (p[0], p[1], p[2], int(p[3] * .6)))
        w += f.w * k + 14
    return w

def crop_of(id):
    """a square crop (source px) that holds the rig, the item and its flash at every quarter turn."""
    it = H.HAND[id]; pose = it['cls']
    vx = MOUNT[pose][0] - C + it['muzzle'][0] - it['grip'][0]; vy = MOUNT[pose][1] - C + it['muzzle'][1] - it['grip'][1]
    ext = max(abs(vx), abs(vy)) + (H.FX[FLASH[id]][0]()[0][0].h if id in FLASH else 0) + 5
    return max(60, 2 * max(ext, 22))

def main(out):
    items_kit = H.kit_items()
    H_ = 90 + sum(crop_of(i) * K + 52 for _, _, ids in RACES for i in ids) + 20
    img = Rgba(SHEET_W, H_, BG)
    text(img, 20, 14, 'RACIAL HAND WEAPONS (BETA 2): KETT, MIRE, SPORELING, GAUNTLING, PRISMATIC, GRUNDL   ICON 1X AND 3X, HELD BY ITS RACE RIG AT 3X (0 AND 90 DEGREES, PLAIN AND FIRING) AND 1X (4 ROTATIONS), THEN THE FLASH', 'H', 3)
    text(img, 20, 50, 'THE SAME PNG IS THE ITEM ICON AND THE HELD SPRITE. MELEE WEAPONS HAVE NO FLASH (LIKE THE EXISTING QUARRY HAMMER AND EMBER KNIFE).', 'M', 3)
    y = 90
    for race, cls, ids in RACES:
        kit = SKit(cls(), items_kit)
        for id in ids:
            it = H.HAND[id]
            text(img, 20, y, '%s: %s  (%s, %s)' % (race.upper(), id.upper(), it['cls'].upper(), it['culture'].upper()), 'a', 3)
            yy = y + 30; cr = crop_of(id); cw = cr * K + 6
            iw, ih = draw_icon(img, id, 30, yy + 8, 3)
            draw_icon(img, id, 30, yy + 8 + ih * 3 + 14, 1)
            x = 160
            for deg, fire in ((0, False), (90, False), (0, True), (90, True)):
                if fire and id not in FLASH: continue
                fig, gl = held(kit, id, deg, fire)
                draw_big(img, fig, gl, x, yy, K, crop=cr)
                text(img, x + 6, yy + 2, ('%d DEG' % deg) + (' FIRING' if fire else ''), 'M', 2)
                x += cw
            x = 160 + 4 * cw
            for deg in (0, 90, 180, 270):
                fig, gl = held(kit, id, deg)
                draw_big(img, fig, gl, x, yy + 8, 1, crop=64)
                x += 68
            if id in FLASH:
                text(img, x + 20, yy + 4, 'FLASH, 3 FRAMES', 'M', 2)
                draw_flash(img, FLASH[id], x + 20, yy + 30, 3)
            y += cr * K + 52
    img.save(out)
    print(out, img.w, img.h)

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else PREVIEW + '/hand_art.png')
