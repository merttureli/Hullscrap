"""Race wave 2 preview sheets (3x): VELLUM, OORTH, DRAKKIN, WISP, HULLKIN, LANTERN.
  python3 art/_src/sheet_races2.py [out.png [lineup.png]]
out.png    each of the six at 4 rotations x 3 hand weapons, every animation (walk / glide 6 frames + stand) and every arm pose at 3x and at 1x,
           the head variants, the glow layers (with and without the additive light), and the small and large rigs next to a human for scale.
lineup.png the 1x line-up of ALL 16 species (stand / pistol / walk / walk 2), the flat silhouettes of the same, then 2x with names."""
import sys
from px import *
import pal_races1     # noqa: F401
import crew_v2 as cv2
from sheet_v2 import text
from sp_compose import SKit, render
from sp_items import kit_items
from sheet_species import draw_fig, silhouette
from sheet_races1 import ALL as OLD, TINTS as OLD_TINTS, TEAL
from sp_races2 import Vellum, Oorth, Drakkin, Wisp, Hullkin, Lantern

K = 3; W = 2760
NEW = [('vellum', Vellum), ('oorth', Oorth), ('drakkin', Drakkin), ('wisp', Wisp), ('hullkin', Hullkin), ('lantern', Lantern)]
ALL = OLD + NEW
TINTS = dict(OLD_TINTS)
TINTS.update({'vellum': (214, 72, 92), 'oorth': (120, 96, 206), 'drakkin': (62, 128, 208), 'wisp': (236, 128, 52), 'hullkin': (196, 66, 66), 'lantern': (70, 164, 118)})
LOADOUT = {   # three different hand weapons from art/items each: (item id, arm pose)
 'vellum':  [('spark_pistol', 'pistol'), ('multi_tool', 'tool'), ('carbine', 'rifle')],
 'oorth':   [('service_pistol', 'pistol'), ('carbine', 'rifle'), ('multi_tool', 'tool')],
 'drakkin': [('quarry_hammer', 'melee'), ('slugthrower', 'heavy'), ('doorbuster', 'rifle')],
 'wisp':    [(None, 'unarmed'), ('multi_tool', 'tool'), ('flare_gun', 'pistol')],
 'hullkin': [('multi_tool', 'tool'), ('service_pistol', 'pistol'), ('doorbuster', 'rifle')],
 'lantern': [('carbine', 'rifle'), ('service_pistol', 'pistol'), ('flare_gun', 'pistol')],
}
POSE_ITEM = [('unarmed', None), ('pistol', 'service_pistol'), ('rifle', 'carbine'), ('tool', 'multi_tool'), ('heavy', 'slugthrower'), ('melee', 'quarry_hammer')]
ROTS = [(6, 0), (0, 90), (2, 180), (4, 270)]        # (legs frame, aim and move direction)
KITS = {}
def kit(n):
    if n not in KITS: KITS[n] = SKit(dict(ALL)[n](), kit_items())
    return KITS[n]
def fig(n, lf, deg, pose, item, head=None, tint=None, aim=None):
    return render(kit(n), lf, deg, deg if aim is None else aim, pose, item, head or kit(n).sp.head_names[0], tint=tint or TINTS[n])

def races_block():
    crop = 72; cw = crop * K + 4
    H = 40 + len(NEW) * (cw + 56) + 10
    def draw(img, y0):
        text(img, 20, y0, 'RACE WAVE 2: VELLUM, OORTH, DRAKKIN, WISP, HULLKIN, LANTERN   EACH AT 4 ROTATIONS (0 90 180 270) X 3 WEAPONS', 'H', 4)
        y = y0 + 38
        for n, c in NEW:
            text(img, 20, y, n.upper(), 'a', 3)
            text(img, 20 + 12 * 4 * 3 + 20, y, ' / '.join((i or 'UNARMED').upper() for i, _ in LOADOUT[n]) + '   (HEAD VARIANT CHANGES ACROSS THE ROW)', 'M', 3)
            idx = 0
            for wi, (iid, pose) in enumerate(LOADOUT[n]):
                for ri, (lf, deg) in enumerate(ROTS):
                    heads = kit(n).sp.head_names
                    f, g = fig(n, lf, deg, pose, iid, head=heads[(wi + ri) % len(heads)])
                    draw_fig(img, f, g, 20 + idx * (cw + 2), y + 26, K, crop=crop)
                    idx += 1
            y += cw + 56
    return H, draw

def anim_block():
    """every animation: the stand frame, the 6 walk (floating rigs: float / glide) frames and the arm poses, each at 3x with the same frame at 1x under it."""
    crop = 66; cw = crop * K + 2; per = cw + 4
    H = 40 + len(NEW) * (cw + 36 + crop + 40) + 10
    def draw(img, y0):
        text(img, 20, y0, 'EVERY ANIMATION AT 3X WITH THE SAME FRAME AT 1X UNDER IT: STAND, WALK 0-5 (FLOATING RIGS: FLOAT 0-5, THE TRAILING LAYER), THEN THE ARM POSES (THE DRAWER BOBS A FLOATING BODY IN CODE)', 'H', 3)
        y = y0 + 38
        for n, c in NEW:
            tag = {'vellum': '  (SMALL RIG 25X25, PIVOT 12)', 'drakkin': '  (LARGE RIG 49X49)', 'wisp': '  (FLOATING RIG 49X49: THE TAIL PLAYS FLOAT BY TIME)', 'lantern': '  (FLOATING RIG 49X49: THE WING TIPS PLAY FLOAT BY TIME)'}.get(n, '  (NORMAL RIG 33X33)')
            text(img, 20, y, n.upper() + tag, 'a', 3)
            wl = 'FLOAT' if n in ('wisp', 'lantern') else 'WALK'
            frames = [(6, 'unarmed', None, 'STAND')] + [(i, 'unarmed', None, '%s %d' % (wl, i)) for i in range(6)] + [(6, p, it, p.upper()) for p, it in POSE_ITEM[1:]]
            x = 20
            for lf, pose, it, lab in frames:
                f, g = fig(n, lf, 0, pose, it)
                text(img, x + 4, y + 26, lab, 'M', 2)
                draw_fig(img, f, g, x, y + 36, K, crop=crop)
                draw_fig(img, f, g, x, y + 36 + cw + 6, 1, crop=crop)
                x += per
            y += cw + 36 + crop + 40
    return H, draw

def heads_block():
    H = 40 + 520
    def draw(img, y0):
        text(img, 20, y0, 'HEAD VARIANTS AT 5X   VELLUM: FOLD, CAP, HELMET   OORTH: HOOD, BARE, HELMET   DRAKKIN: CREST, HELMET, SCARRED   WISP: ORB, FORKED   HULLKIN: STALK, TWIN   LANTERN: ANTENNAE, GOGGLES, HELMET', 'H', 3)
        y = y0 + 38
        x = 20
        for n, c in NEW:
            for h in kit(n).sp.head_names:
                f, g = fig(n, 6, 0, 'unarmed', None, head=h)
                crop = 44 if n != 'drakkin' else 56
                draw_fig(img, f, g, x, y, 4, crop=crop)
                text(img, x + 2, y + crop * 4 + 6, (n + ' ' + h).upper(), 'M', 2)
                x += crop * 4 + 8
                if x > W - 260: x = 20; y += 250
    return H, draw

def render_glow(n, head, fr, lf=6):
    """figure + glow for glow frame `fr` (the compositor uses frame 0, so swap the frame lists for one render)."""
    k = kit(n)
    tg, hg = k.torso_glow, k.head_glow
    try:
        if tg and len(tg) > fr: k.torso_glow = [tg[fr]]
        nh = len(k.sp.head_names)
        if hg and len(hg) >= (fr + 1) * nh: k.head_glow = hg[fr * nh:(fr + 1) * nh]
        return render(k, lf, 0, 0, 'unarmed', None, head, tint=TINTS[n])
    finally:
        k.torso_glow, k.head_glow = tg, hg

def glow_block():
    H = 40 + 300 + 330
    def draw(img, y0):
        text(img, 20, y0, 'GLOW LAYERS AT 5X: HARD PIXELS ONLY, THEN THE ADDITIVE LIGHT (OORTH THIRD EYE 2 FRAMES, WISP BODY AND TAIL, LANTERN ANTENNA AND WING LAMPS)', 'H', 3)
        y = y0 + 38
        x = 20
        for n, headn, frames in (('oorth', 'hood', (0, 1)), ('wisp', 'orb', (0, 1)), ('lantern', 'antennae', (0, 1))):
            f, g = fig(n, 6, 0, 'unarmed', None, head=headn)
            draw_fig(img, f, None, x, y, 5, crop=44, gs=0.0)
            x += 44 * 5 + 10
            for fr in frames:
                f2, g2 = render_glow(n, headn, fr)
                draw_fig(img, f2, g2, x, y, 5, crop=44, gs=1.0)
                x += 44 * 5 + 10
            x += 20
        y += 44 * 5 + 30
        text(img, 20, y, 'WISP TAIL: THE SIX FLOAT FRAMES AND THE IDLE FRAME, WITH LIGHT, AT 4X', 'M', 3)
        y += 26
        x = 20
        for lf in (0, 1, 2, 3, 4, 5, 6):
            f2, g2 = render_glow('wisp', 'orb', 0, lf)
            draw_fig(img, f2, g2, x, y, 4, crop=52, gs=1.0)
            x += 52 * 4 + 6
    return H, draw

def box(img, cx, cy, half, col, k):
    """a square of side 2*half px round the pivot, dotted, at scale k."""
    for t in range(-half * k, half * k + 1):
        if (t // 2) % 2 == 0:
            for (x, y) in ((cx + t, cy - half * k), (cx + t, cy + half * k), (cx - half * k, cy + t), (cx + half * k, cy + t)):
                img.over(x, y, col)
def scale_block():
    crop = 72; cw = crop * K + 4
    H = 40 + 2 * (cw + 40) + 90
    def draw(img, y0):
        text(img, 20, y0, 'SCALE: HUMAN, VELLUM (SMALL RIG), DRAKKIN AND GRUNDL (LARGE RIG), WISP AND LANTERN (FLOATING)   DOTTED BOX = THE SHARED 2X2 BODY (32 PX); VELLUM: THE 1X1 CELL (16 PX)', 'H', 3)
        y = y0 + 38
        poses = [('pistol', 'service_pistol'), ('tool', 'multi_tool'), ('rifle', 'carbine'), ('heavy', 'slugthrower'), ('melee', 'quarry_hammer')]
        x = 20
        for n in ('human', 'vellum'):
            for pose, iid in poses:
                f, g = fig(n, 6, 0, pose, iid)
                draw_fig(img, f, g, x, y + 24, K, crop=crop)
                box(img, x + (crop // 2) * K, y + 24 + (crop // 2) * K, 8 if n == 'vellum' else 16, (255, 79, 216, 160), K)
                text(img, x + 6, y + 4, (n + ' ' + pose).upper(), 'M', 2)
                x += cw
            if n == 'human': x = 20 + 5 * cw + 30
        y += cw + 40
        x = 20
        for n, lf, deg in (('human', 6, 0), ('vellum', 6, 0), ('drakkin', 6, 0), ('grundl', 6, 0), ('drakkin', 1, 135), ('wisp', 1, 135), ('lantern', 3, 90)):
            f, g = fig(n, lf, deg, 'unarmed', None, tint=TINTS[n])
            draw_fig(img, f, g, x, y, K + 1, crop=60)
            box(img, x + 30 * (K + 1), y + 30 * (K + 1), 8 if n == 'vellum' else 16, (255, 79, 216, 160), K + 1)
            text(img, x + 6, y + 60 * (K + 1) + 4, n.upper(), 'M', 2)
            x += 60 * (K + 1) + 12
    return H, draw

def build(path):
    bl = [races_block(), anim_block(), heads_block(), glow_block(), scale_block()]
    Ht = sum(h for h, _ in bl) + 24 * len(bl) + 20
    img = Rgba(W, Ht, RGB['F'] + (255,))
    y = 20
    for h, d in bl:
        d(img, y); y += h + 24
        for x in range(W): img.p[y - 12][x] = list(RGB['G']) + [255]
    img.save(path)
    return img.w, img.h

def lineup(path):
    """all 16 species at 1x (actual pixels, then flat silhouettes), two poses a row group, then 2x with names (colour left, flat right)."""
    crop = 54; cell = crop + 2; n_sp = len(ALL); gw = n_sp * cell + 24
    Wl = 20 + 2 * gw
    groups = [[('STAND', 6, 'unarmed', None), ('PISTOL', 6, 'pistol', 'service_pistol')], [('WALK', 0, 'unarmed', None), ('WALK 2', 3, 'unarmed', None)]]
    Hl = 50 + 2 * (2 * (crop + 40) + 10) + 20 + 4 * (56 * 2 + 40) + 20
    img = Rgba(Wl, Hl, RGB['F'] + (255,))
    text(img, 20, 12, 'LINE-UP: ALL 16 SPECIES AT 1X (ACTUAL PIXELS), THEN FLAT SILHOUETTES, THEN 2X', 'H', 3)
    y = 50
    names = ' '.join(n.upper() for n, _ in ALL)
    for row in groups:
        for flat in (False, True):
            x = 20
            for lab, lf, pose, it in row:
                for n, c in ALL:
                    f, g = fig(n, lf, 0, pose, it, tint=TEAL)
                    draw_fig(img, silhouette(f) if flat else f, None if flat else g, x, y, 1, crop=crop)
                    x += cell
                x += 24
            if not flat:
                text(img, 20, y + crop + 4, names + '   (' + ' / '.join(lab for lab, *_ in row) + ')', 'M', 2)
            y += crop + 40
        y += 10
    y += 20
    for flat in (False, True):                                   # 2x with names (colour), then the same flat
        for half in (ALL[:8], ALL[8:]):
            x = 20
            for n, c in half:
                f, g = fig(n, 6, 0, 'unarmed', None, tint=TEAL)
                draw_fig(img, silhouette(f) if flat else f, None if flat else g, x, y, 2, crop=56)
                if not flat: text(img, x + 2, y + 114, n.upper(), 'M', 2)
                x += 56 * 2 + 14
            y += 56 * 2 + (20 if flat else 40)
    img.save(path)
    return img.w, img.h

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else PREVIEW + '/races2_sheet.png'
    print(build(out))
    print(lineup(sys.argv[2] if len(sys.argv) > 2 else out.replace('.png', '_lineup.png')))
