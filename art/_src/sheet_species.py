"""art-species preview sheet: species at 4 rotations x 3 weapons, the 1x silhouette line-up, every hand weapon at 3x, muzzle flashes, gear."""
import sys
from px import *
import crew_v2 as cv2
from sheet_v2 import text
from sp_compose import SKit, render
from sp_human import Human
from sp_basalt import Basalt
from sp_emberkin import Emberkin
from sp_fenn import Fenn
import sp_items, sp_gear, sp_fx
from sp_items import ITEMS, ORDER, outlined_item, kit_items, item_glow
from sp_gear import gear_kit, GEAR

K = 3; W = 2760
CROP = 72; OFF = 48 - CROP // 2
TEAL = (79, 196, 184)
TINTS = {'human': (79, 196, 184), 'basalt': (212, 160, 70), 'emberkin': (120, 130, 210), 'fenn': (200, 90, 130)}   # outfit colour per example

def draw_fig(img, fig, gl, x, y, k, crop=CROP, gs=0.55, shadow=True):
    off = 48 - crop // 2
    for j in range(crop):
        for i in range(crop):
            p = fig.p[j + off][i + off]
            if p[3]:
                for dy in range(k):
                    for dx in range(k): img.over(x + i * k + dx, y + j * k + dy, tuple(p))
    if gl is not None:
        for j in range(crop):
            for i in range(crop):
                p = gl.p[j + off][i + off]
                if p[3]:
                    for dy in range(k):
                        for dx in range(k): img.add(x + i * k + dx, y + j * k + dy, (p[0], p[1], p[2], int(p[3] * gs)))

def silhouette(fig):
    o = Rgba(fig.w, fig.h)
    for j in range(fig.h):
        for i in range(fig.w):
            if fig.p[j][i][3]: o.p[j][i] = [19, 22, 27, 255]
    return o

SPECIES = [('human', Human), ('basalt', Basalt), ('emberkin', Emberkin), ('fenn', Fenn)]
LOADOUT = {   # three different weapons each: (item id, pose, head variant)
 'human':    [('service_pistol', 'pistol'), ('rivet_gun', 'tool'), ('gatekeepers_lance', 'heavy')],
 'basalt':   [('quarry_hammer', 'melee'), ('slugthrower', 'heavy'), ('doorbuster', 'rifle')],
 'emberkin': [('torchgun', 'heavy'), ('ember_knife', 'melee'), ('flare_gun', 'pistol')],
 'fenn':     [('spark_pistol', 'pistol'), ('multi_tool', 'tool'), ('carbine', 'rifle')],
}
HEADS = {'human': ('hair', 'helmet'), 'basalt': ('rock_a', 'rock_b'), 'emberkin': ('crest', 'helmet'), 'fenn': ('ears', 'goggles')}
ROTS = [(6, 0), (0, 90), (2, 180), (4, 270)]        # (legs frame, aim and move direction)

def species_block():
    items = kit_items()
    kits = {n: SKit(c(), items) for n, c in SPECIES}
    cw = CROP * K + 4
    H = 40 + len(SPECIES) * (cw + 52) + 10
    def draw(img, y0):
        text(img, 20, y0, 'SPECIES: HUMAN, BASALT, EMBERKIN, FENN   EACH AT 4 ROTATIONS (0 90 180 270) X 3 WEAPONS', 'H', 4)
        y = y0 + 38
        for n, c in SPECIES:
            kit = kits[n]
            text(img, 20, y, n.upper(), 'a', 3)
            names = ' / '.join(i.upper() for i, _ in LOADOUT[n])
            text(img, 20 + 4 * 4 * 3 * 3 + 20, y, names, 'M', 3)
            idx = 0
            for wi, (iid, pose) in enumerate(LOADOUT[n]):
                for ri, (lf, deg) in enumerate(ROTS):
                    head = HEADS[n][(wi + ri) % 2] if n != 'fenn' else HEADS[n][(wi + ri) % 2]
                    fig, gl = render(kit, lf, deg, deg, pose, iid, head, tint=TINTS[n])
                    x = 20 + idx * (cw + 2)
                    draw_fig(img, fig, gl, x, y + 26, K)
                    idx += 1
            y += cw + 52
    return H, draw

def lineup_block():
    items = kit_items()
    kits = {n: SKit(c(), items) for n, c in SPECIES}
    H = 40 + 130 + 190
    def draw(img, y0):
        text(img, 20, y0, 'SILHOUETTES: ALL 4 SPECIES SIDE BY SIDE AT 1X (ACTUAL PIXELS), THEN FLAT, THEN 2X AND 4X FOR READING', 'H', 4)
        y = y0 + 40
        # 1x colour, 1x flat shadow, standing unarmed, then with pistol, then walking
        row = [('STAND', 6, 'unarmed', None), ('PISTOL', 6, 'pistol', 'service_pistol'), ('WALK', 0, 'unarmed', None), ('WALK 2', 3, 'unarmed', None)]
        x = 20
        for lab, lf, pose, it in row:
            for n, c in SPECIES:
                fig, gl = render(kits[n], lf, 0, 0, pose, it, HEADS[n][0], tint=TEAL)
                draw_fig(img, fig, gl, x, y, 1, crop=44)
                x += 46
            x += 20
        text(img, 20, y + 48, 'HUMAN BASALT EMBERKIN FENN, EACH IN STAND / PISTOL / WALK / WALK 2 (1X)', 'M', 2)
        # flat silhouettes at 1x
        x = 20; y2 = y + 70
        for lab, lf, pose, it in row:
            for n, c in SPECIES:
                fig, gl = render(kits[n], lf, 0, 0, pose, it, HEADS[n][0], tint=TEAL)
                draw_fig(img, silhouette(fig), None, x, y2, 1, crop=44)
                x += 46
            x += 20
        # 2x and 4x readings
        x = 20; y3 = y + 130
        for n, c in SPECIES:
            fig, gl = render(kits[n], 6, 0, 0, 'unarmed', None, HEADS[n][0], tint=TEAL)
            draw_fig(img, fig, gl, x, y3, 4, crop=40)
            text(img, x, y3 + 164, n.upper(), 'M', 3)
            x += 40 * 4 + 20
        x += 40
        for n, c in SPECIES:
            fig, gl = render(kits[n], 6, 0, 0, 'unarmed', None, HEADS[n][1] if n != 'basalt' else 'rock_b', tint=TEAL)
            draw_fig(img, fig, gl, x, y3, 2, crop=40)
            x += 40 * 2 + 12
    return H, draw

def items_block():
    ids = ORDER
    colw = (W - 40) // len(ids)
    sprs = {i: outlined_item(ITEMS[i]) for i in ids}
    top = max(s.h for s in sprs.values()) * K
    H = 40 + top + 80
    def draw(img, y0):
        text(img, 20, y0, 'HAND WEAPONS AT 3X (MAGENTA DOT = GRIP ANCHOR, GREEN DOT = MUZZLE ANCHOR)', 'H', 4)
        y = y0 + 36
        for c, i in enumerate(ids):
            sp = sprs[i]; it = ITEMS[i]
            x = 20 + c * colw + (colw - sp.w * K) // 2
            yy = y + top - sp.h * K                      # bottoms line up, so lengths compare
            img.blit_spr(sp, x, yy, K)
            if it['glow']:
                g = item_glow(it, margin=1)
                for j in range(g.h):
                    for k2 in range(g.w):
                        p = g.p[j][k2]
                        if p[3]:
                            for dy in range(K):
                                for dx in range(K): img.add(x + (k2 - sp_items.GLOW_PAD) * K + dx, yy + (j - sp_items.GLOW_PAD) * K + dy, (p[0], p[1], p[2], int(p[3] * 0.6)))
            a = sp_items.anchors(it)
            for key, col in (('grip', (255, 79, 216, 255)), ('muzzle', (107, 211, 74, 255))):
                ax, ay = a[key]
                for dy in range(K):
                    for dx in range(K): img.over(x + ax * K + dx, yy + ay * K + dy, col)
            text(img, 20 + c * colw + 4, y + top + 10, i.upper().replace('_', ' ')[:18], 'H', 2)
            text(img, 20 + c * colw + 4, y + top + 28, it['cls'].upper(), 'M', 2)
            text(img, 20 + c * colw + 4, y + top + 44, it['culture'].upper(), 'a', 2)
    return H, draw

def fx_block():
    H = 40 + 150 + 80
    def draw(img, y0):
        text(img, 20, y0, 'MUZZLE FLASHES (3 FRAMES EACH, AT 3X) AND ON THE WEAPONS THEY BELONG TO', 'H', 4)
        y = y0 + 36
        x = 20
        for name, fn in sp_fx.FX.items():
            frames, org = fn()
            text(img, x, y, name.upper(), 'M', 3)
            xx = x
            for f in frames:
                img.blit_spr(f, xx, y + 24, K)
                rgb, r = sp_fx.FX_GLOW[name]
                g = sp_fx.glow_frame(f, rgb, r)
                for j in range(g.h):
                    for k2 in range(g.w):
                        p = g.p[j][k2]
                        if p[3]:
                            for dy in range(K):
                                for dx in range(K): img.add(xx + (k2 - sp_fx.PAD) * K + dx, y + 24 + (j - sp_fx.PAD) * K + dy, (p[0], p[1], p[2], int(p[3] * 0.8)))
                xx += (f.w + 2) * K
            x = xx + 30
        # on the weapons
        y += 24 + 27 * K + 40
        x = 40
        pairs = [('service_pistol', 'pistol'), ('carbine', 'rifle'), ('slugthrower', 'heavy'), ('torchgun', 'flame'), ('spark_pistol', 'spark'), ('flare_gun', 'pistol')]
        for iid, fxn in pairs:
            sp = outlined_item(ITEMS[iid]); frames, org = sp_fx.FX[fxn]()
            a = sp_items.anchors(ITEMS[iid])
            f = frames[0]
            ox = x + 10 * K; oy = y + f.h * K + 10
            img.blit_spr(sp, ox - a['muzzle'][0] * K, oy - a['muzzle'][1] * K, K)
            img.blit_spr(f, ox - org[0] * K, oy - org[1] * K - (f.h - 1 - org[1]) * 0, K)
            text(img, x, y - 14 + 0, iid.upper(), 'M', 2)
            x += 190
    return 430, draw

def gear_block():
    kit = SKit(Human(), kit_items())
    cases = [(None, 'NO GEAR'), ('eva_suit', 'EVA SUIT'), ('combat_vest', 'COMBAT VEST'), ('exosuit', 'EXOSUIT'), ('salamander_suit', 'SALAMANDER SUIT')]
    GK = 5; GC_ = 56
    H = 40 + 2 * (GC_ * GK + 36) + 20
    def draw(img, y0):
        text(img, 20, y0, 'GEAR OVERLAYS ON A HUMAN (5X): STANDING, THEN WALKING AND AIMING 135 WITH THE GATEKEEPER\'S LANCE', 'H', 4)
        y = y0 + 36
        for row, (lf, ld, ad, pose, it) in enumerate([(6, 0, 0, 'unarmed', None), (1, 135, 135, 'heavy', 'gatekeepers_lance')]):
            x = 20
            for gid, lab in cases:
                gear = gear_kit(gid) if gid else None
                hd = 'helmet' if gid == 'combat_vest' else 'hair'
                fig, gl = render(kit, lf, ld, ad, pose, it if row else None, hd, gear=gear)
                draw_fig(img, fig, gl, x, y, GK, crop=GC_)
                if row == 0: text(img, x + 6, y + GC_ * GK - 16, lab, 'M', 3)
                x += GC_ * GK + 10
            y += GC_ * GK + 36
    return H, draw

def build(path):
    bl = [species_block(), lineup_block(), items_block(), fx_block(), gear_block()]
    Ht = sum(h for h, _ in bl) + 24 * len(bl) + 20
    img = Rgba(W, Ht, RGB['F'] + (255,))
    y = 20
    for h, d in bl:
        d(img, y); y += h + 24
        for x in range(W): img.p[y - 12][x] = list(RGB['G']) + [255]
    img.save(path)
    return img.w, img.h

if __name__ == '__main__':
    print(build(PREVIEW + '/species_sheet.png'))
