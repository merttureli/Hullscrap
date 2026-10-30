"""Race wave 1 preview sheet (3x): Kett, Mire, Sporeling, Gauntling, Prismatic, Grundl at 4 rotations x 3 hand weapons, the 1x line-up of all
10 species with flat silhouettes, the Grundl beside a human for scale (and every item class mounted on both), walk frames, head variants
and the glow layers.   python3 art/_src/sheet_races1.py [out.png]"""
import sys
from px import *
import pal_races1     # noqa: F401
import crew_v2 as cv2
from sheet_v2 import text
from sp_compose import SKit, render
from sp_human import Human
from sp_basalt import Basalt
from sp_emberkin import Emberkin
from sp_fenn import Fenn
from sp_kett import Kett
from sp_mire import Mire
from sp_sporeling import Sporeling
from sp_gauntling import Gauntling
from sp_prismatic import Prismatic
from sp_grundl import Grundl
from sp_items import kit_items
from sheet_species import draw_fig, silhouette

K = 3; W = 2760
NEW = [('kett', Kett), ('mire', Mire), ('sporeling', Sporeling), ('gauntling', Gauntling), ('prismatic', Prismatic), ('grundl', Grundl)]
ALL = [('human', Human), ('basalt', Basalt), ('emberkin', Emberkin), ('fenn', Fenn)] + NEW
HEAD0 = {'human': 'hair', 'basalt': 'rock_a', 'emberkin': 'crest', 'fenn': 'ears', 'kett': 'antennae', 'mire': 'bare', 'sporeling': 'spotted',
         'gauntling': 'lamp', 'prismatic': 'gem', 'grundl': 'tusked'}
HEAD1 = {'human': 'helmet', 'basalt': 'rock_b', 'emberkin': 'helmet', 'fenn': 'goggles', 'kett': 'helmet', 'mire': 'helmet', 'sporeling': 'brown',
         'gauntling': 'helmet', 'prismatic': 'crown', 'grundl': 'cap'}
TINTS = {'human': (79, 196, 184), 'basalt': (212, 160, 70), 'emberkin': (120, 130, 210), 'fenn': (200, 90, 130),
         'kett': (196, 72, 62), 'mire': (232, 206, 84), 'sporeling': (96, 124, 206), 'gauntling': (214, 128, 52), 'prismatic': (206, 86, 186), 'grundl': (74, 146, 204)}
TEAL = (79, 196, 184)
LOADOUT = {   # three different hand weapons from art/items each: (item id, arm pose)
 'kett':      [('rivet_gun', 'tool'), ('spark_pistol', 'pistol'), ('doorbuster', 'rifle')],
 'mire':      [('service_pistol', 'pistol'), ('carbine', 'rifle'), ('multi_tool', 'tool')],
 'sporeling': [('flare_gun', 'pistol'), ('ember_knife', 'melee'), ('multi_tool', 'tool')],
 'gauntling': [('multi_tool', 'tool'), ('slugthrower', 'heavy'), ('carbine', 'rifle')],
 'prismatic': [('gatekeepers_lance', 'heavy'), ('spark_pistol', 'pistol'), ('carbine', 'rifle')],
 'grundl':    [('quarry_hammer', 'melee'), ('slugthrower', 'heavy'), ('doorbuster', 'rifle')],
}
ROTS = [(6, 0), (0, 90), (2, 180), (4, 270)]        # (legs frame, aim and move direction)
KITS = {}
def kit(n):
    if n not in KITS: KITS[n] = SKit(dict(ALL)[n](), kit_items())
    return KITS[n]
def fig(n, lf, deg, pose, item, head=None, tint=None, aim=None):
    return render(kit(n), lf, deg, deg if aim is None else aim, pose, item, head or HEAD0[n], tint=tint or TINTS[n])

def races_block():
    crop = 72; cw = crop * K + 4
    H = 40 + len(NEW) * (cw + 56) + 10
    def draw(img, y0):
        text(img, 20, y0, 'RACE WAVE 1: KETT, MIRE, SPORELING, GAUNTLING, PRISMATIC, GRUNDL   EACH AT 4 ROTATIONS (0 90 180 270) X 3 WEAPONS', 'H', 4)
        y = y0 + 38
        for n, c in NEW:
            text(img, 20, y, n.upper(), 'a', 3)
            text(img, 20 + 12 * 4 * 3 + 20, y, ' / '.join(i.upper() for i, _ in LOADOUT[n]) + '   (OUTFIT TINT AND HEAD VARIANT CHANGE ACROSS THE ROW)', 'M', 3)
            idx = 0
            for wi, (iid, pose) in enumerate(LOADOUT[n]):
                for ri, (lf, deg) in enumerate(ROTS):
                    heads = kit(n).sp.head_names
                    f, g = fig(n, lf, deg, pose, iid, head=heads[(wi + ri) % len(heads)])
                    draw_fig(img, f, g, 20 + idx * (cw + 2), y + 26, K, crop=crop)
                    idx += 1
            y += cw + 56
    return H, draw

def lineup_block():
    crop = 54; cell = crop + 2
    H = 40 + 3 * (crop + 40) + 150
    def draw(img, y0):
        text(img, 20, y0, 'LINE-UP: ALL 10 SPECIES AT 1X (ACTUAL PIXELS): STAND / PISTOL / WALK / WALK 2, THEN FLAT SILHOUETTES, THEN 2X', 'H', 4)
        y = y0 + 40
        row = [('STAND', 6, 'unarmed', None), ('PISTOL', 6, 'pistol', 'service_pistol'), ('WALK', 0, 'unarmed', None), ('WALK 2', 3, 'unarmed', None)]
        for flat in (False, True):
            x = 20
            for lab, lf, pose, it in row:
                for n, c in ALL:
                    f, g = fig(n, lf, 0, pose, it, tint=TEAL)
                    draw_fig(img, silhouette(f) if flat else f, None if flat else g, x, y, 1, crop=crop)
                    x += cell
                x += 24
            if not flat:
                text(img, 20, y + crop + 2, 'HUMAN BASALT EMBERKIN FENN KETT MIRE SPORELING GAUNTLING PRISMATIC GRUNDL, REPEATED PER POSE', 'M', 2)
            y += crop + 40
        # 2x reading, standing, with names
        x = 20
        for n, c in ALL:
            f, g = fig(n, 6, 0, 'unarmed', None, tint=TEAL)
            draw_fig(img, f, g, x, y, 2, crop=56)
            text(img, x + 2, y + 114, n.upper(), 'M', 2)
            x += 56 * 2 + 14
        y += 140
        # flat 2x
        x = 20
        for n, c in ALL:
            f, g = fig(n, 6, 0, 'unarmed', None, tint=TEAL)
            draw_fig(img, silhouette(f), None, x, y, 2, crop=56)
            x += 56 * 2 + 14
    return H, draw

def box(img, cx, cy, half, col, k):
    """the 2x2-cell body (32 px) round the pivot, dotted, at scale k."""
    for t in range(-half * k, half * k + 1):
        if (t // 2) % 2 == 0:
            for (x, y) in ((cx + t, cy - half * k), (cx + t, cy + half * k), (cx - half * k, cy + t), (cx + half * k, cy + t)):
                img.over(x, y, col)
def scale_block():
    crop = 72; cw = crop * K + 4
    H = 40 + 2 * (cw + 40) + 90
    def draw(img, y0):
        text(img, 20, y0, 'THE GRUNDL NEXT TO A HUMAN FOR SCALE (DOTTED BOX = THE SHARED 2X2 BODY, 32 PX, PIVOT AT ITS CENTRE: THE ART OVERHANGS IT)', 'H', 4)
        y = y0 + 38
        # row 1: each item class on the human and on the grundl
        poses = [('pistol', 'service_pistol'), ('tool', 'rivet_gun'), ('rifle', 'carbine'), ('heavy', 'slugthrower'), ('melee', 'quarry_hammer')]
        x = 20
        for n in ('human', 'grundl'):
            for pose, iid in poses:
                f, g = fig(n, 6, 0, pose, iid, tint=TINTS[n])
                draw_fig(img, f, g, x, y + 24, K, crop=crop)
                box(img, x + (crop // 2) * K, y + 24 + (crop // 2) * K, 16, (255, 79, 216, 160), K)
                text(img, x + 6, y + 4, (n + ' ' + pose).upper(), 'M', 2)
                x += cw
            x += 30 if n == 'human' else 0
            if n == 'human': x = 20 + 5 * cw + 30
        y += cw + 40
        # row 2: unarmed standing at 5x, human then grundl, then walking and aiming across
        x = 20
        for n, lf, deg in (('human', 6, 0), ('grundl', 6, 0), ('human', 1, 135), ('grundl', 1, 135), ('human', 3, 90), ('grundl', 3, 90)):
            f, g = fig(n, lf, deg, 'unarmed', None, tint=TINTS[n])
            draw_fig(img, f, g, x, y, K + 1, crop=60)
            box(img, x + 30 * (K + 1), y + 30 * (K + 1), 16, (255, 79, 216, 160), K + 1)
            x += 60 * (K + 1) + 12
    return H, draw

def walk_block():
    crop = 62; step = 190; cw = crop * K + 2
    rows = (len(NEW) + 1) // 2
    H = 40 + rows * (cw + 40) + 10
    def draw(img, y0):
        text(img, 20, y0, 'WALK CYCLES (6 FRAMES, FRAMES 0 AND 3 ARE THE CONTACTS) AT 3X, BODY AND LEGS FACING UP', 'H', 4)
        y = y0 + 36
        for i, (n, c) in enumerate(NEW):
            x0 = 20 + (i % 2) * (W // 2)
            yy = y + (i // 2) * (cw + 40)
            text(img, x0, yy, n.upper(), 'a', 3)
            for k in range(6):
                f, g = fig(n, k, 0, 'unarmed', None, tint=TINTS[n])
                draw_fig(img, f, g, x0 + k * step, yy + 22, K, crop=crop)
    return H, draw

def heads_block():
    H = 40 + 270
    def draw(img, y0):
        text(img, 20, y0, 'HEAD VARIANTS AT 6X (KETT: ANTENNAE, TORN, HELMET   MIRE: BARE, HELMET   SPORELING: SPOTTED, BROWN   GAUNTLING: LAMP, HELMET   PRISMATIC: GEM, CROWN   GRUNDL: TUSKED, CAP)', 'H', 4)
        y = y0 + 38
        x = 20
        for n, c in NEW:
            for h in kit(n).sp.head_names:
                f, g = fig(n, 6, 0, 'unarmed', None, head=h, tint=TINTS[n])
                crop = 46 if n != 'grundl' else 50
                draw_fig(img, f, g, x, y, 4, crop=crop)
                text(img, x + 2, y + crop * 4 + 6, (n + ' ' + h).upper(), 'M', 2)
                x += crop * 4 + 8
                if x > W - 260: x = 20; y += 230
    return H, draw

def glow_block():
    H = 40 + 270
    def draw(img, y0):
        text(img, 20, y0, 'GLOW LAYERS AT 5X: LEFT = HARD PIXELS ONLY, RIGHT = WITH THE ADDITIVE GLOW (SPORELING SPORES 2 FRAMES, GAUNTLING LAMP, PRISMATIC CORE 2 PULSE FRAMES)', 'H', 4)
        y = y0 + 38
        x = 20
        for n, headn, frames in (('sporeling', 'spotted', (0, 1)), ('gauntling', 'lamp', (0,)), ('prismatic', 'gem', (0, 1))):
            f, g = fig(n, 6, 0, 'unarmed', None, head=headn, tint=TINTS[n])
            draw_fig(img, f, None, x, y, 5, crop=44, gs=0.0)
            x += 44 * 5 + 10
            for fr in frames:
                f2, g2 = render_glow(n, headn, fr)
                draw_fig(img, f2, g2, x, y, 5, crop=44, gs=1.0)
                x += 44 * 5 + 10
            x += 30
    return H, draw

def render_glow(n, head, fr):
    """figure + glow for glow frame `fr` (the compositor uses frame 0, so swap the frame lists for one render)."""
    k = kit(n)
    tg, hg = k.torso_glow, k.head_glow
    try:
        if tg and len(tg) > fr: k.torso_glow = [tg[fr]]
        if hg and len(hg) > fr * len(k.sp.head_names): k.head_glow = hg[fr * len(k.sp.head_names):(fr + 1) * len(k.sp.head_names)]
        return render(k, 6, 0, 0, 'unarmed', None, head, tint=TINTS[n])
    finally:
        k.torso_glow, k.head_glow = tg, hg

def build(path):
    bl = [races_block(), lineup_block(), scale_block(), walk_block(), heads_block(), glow_block()]
    Ht = sum(h for h, _ in bl) + 24 * len(bl) + 20
    img = Rgba(W, Ht, RGB['F'] + (255,))
    y = 20
    for h, d in bl:
        d(img, y); y += h + 24
        for x in range(W): img.p[y - 12][x] = list(RGB['G']) + [255]
    img.save(path)
    return img.w, img.h

if __name__ == '__main__':
    print(build(sys.argv[1] if len(sys.argv) > 1 else PREVIEW + '/races1_sheet.png'))
