"""Race wave 4 preview sheets (3x): WARDEN_FRAME, MURROW (large), SILTBORN (floating), CORVIN, BRINE (large), ECHO, FERRO.
  python3 art/_src/sheet_races4.py [out.png [lineup.png]] [--only name,name]
out.png    each of the seven at 4 rotations x 3 hand weapons, every animation (stand, walk / float 0-5, every arm pose) at 3x and at 1x, the head variants, the glow layers
           (hard pixels, then with the additive light), and the large and floating rigs next to a human for scale.
lineup.png the 1x line-up of ALL 30 species (stand / pistol / walk / walk 2), the flat silhouettes of the same, then 2x with names."""
import sys
from px import *
import pal_races1     # noqa: F401
import crew_v2 as cv2
from sheet_v2 import text
from sp_compose import SKit, render
from sp_items import kit_items
from sheet_species import draw_fig, silhouette
from sheet_races3 import ALL as OLD, TINTS as OLD_TINTS, TEAL
import sp_races4
from sp_races4 import WardenFrame
NEW = [('warden_frame', WardenFrame)]
for _n in ('Murrow', 'Siltborn', 'Corvin', 'Brine', 'Echo', 'Ferro'):
    if hasattr(sp_races4, _n): NEW.append((_n.lower(), getattr(sp_races4, _n)))

K = 3; W = 2760
ALL = OLD + NEW
TINTS = dict(OLD_TINTS)
TINTS.update({'warden_frame': (232, 150, 40), 'murrow': (214, 72, 92), 'siltborn': (70, 164, 118), 'corvin': (196, 60, 74), 'brine': (232, 190, 70), 'echo': (120, 96, 206), 'ferro': (66, 150, 112)})
LOADOUT = {   # three different hand weapons from art/items each: (item id, arm pose)
 'warden_frame': [('gatekeepers_lance', 'heavy'), ('service_pistol', 'pistol'), ('carbine', 'rifle')],
 'murrow':       [('quarry_hammer', 'melee'), ('multi_tool', 'tool'), ('slugthrower', 'heavy')],
 'siltborn':     [(None, 'unarmed'), ('multi_tool', 'tool'), ('flare_gun', 'pistol')],
 'corvin':       [('service_pistol', 'pistol'), ('carbine', 'rifle'), ('multi_tool', 'tool')],
 'brine':        [('rivet_gun', 'tool'), ('doorbuster', 'rifle'), ('quarry_hammer', 'melee')],
 'echo':         [('spark_pistol', 'pistol'), ('service_pistol', 'pistol'), ('carbine', 'rifle')],
 'ferro':        [('multi_tool', 'tool'), ('spark_pistol', 'pistol'), ('torchgun', 'heavy')],
}
POSE_ITEM = [('unarmed', None), ('pistol', 'service_pistol'), ('rifle', 'carbine'), ('tool', 'multi_tool'), ('heavy', 'slugthrower'), ('melee', 'quarry_hammer')]
ROTS = [(6, 0), (0, 90), (2, 180), (4, 270)]        # (legs frame, aim and move direction)
KITS = {}
def kit(n):
    if n not in KITS: KITS[n] = SKit(dict(ALL)[n](), kit_items())
    return KITS[n]
def fig(n, lf, deg, pose, item, head=None, tint=None, aim=None):
    return render(kit(n), lf, deg, deg if aim is None else aim, pose, item, head or kit(n).sp.head_names[0], tint=tint or TINTS[n])
TAG = {'murrow': '  (LARGE RIG 49X49, PIVOT 24)', 'brine': '  (LARGE RIG 49X49, PIVOT 24)', 'siltborn': '  (FLOATING RIG 49X49: FLOAT 0-5, NO WALK)'}

def races_block():
    crop = 72; cw = crop * K + 4
    H = 40 + len(NEW) * (cw + 56) + 10
    def draw(img, y0):
        text(img, 20, y0, 'RACE WAVE 4: ' + ' '.join(n.upper() for n, _ in NEW) + '   EACH AT 4 ROTATIONS (0 90 180 270) X 3 WEAPONS', 'H', 4)
        y = y0 + 38
        for n, c in NEW:
            text(img, 20, y, n.upper(), 'a', 3)
            text(img, 20 + 16 * 4 * 3 + 20, y, ' / '.join((i or 'UNARMED').upper() for i, _ in LOADOUT[n]) + '   (HEAD VARIANT CHANGES ACROSS THE ROW)', 'M', 3)
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
    """every animation: the stand frame, the 6 walk (or float) frames and the arm poses, each at 3x with the same frame at 1x under it."""
    crop = 66; cw = crop * K + 2; per = cw + 4
    H = 40 + len(NEW) * (cw + 36 + crop + 40) + 10
    def draw(img, y0):
        text(img, 20, y0, 'EVERY ANIMATION AT 3X WITH THE SAME FRAME AT 1X UNDER IT: STAND, WALK (SILTBORN: FLOAT) 0-5, THEN THE ARM POSES', 'H', 3)
        y = y0 + 38
        for n, c in NEW:
            text(img, 20, y, n.upper() + TAG.get(n, '  (NORMAL RIG 33X33)'), 'a', 3)
            frames = [(6, 'unarmed', None, 'STAND')] + [(i, 'unarmed', None, ('FLOAT %d' if n == 'siltborn' else 'WALK %d') % i) for i in range(6)] + [(6, p, it, p.upper()) for p, it in POSE_ITEM[1:]]
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
        text(img, 20, y0, 'HEAD VARIANTS AT 4X   ' + '   '.join(n.upper() + ': ' + ', '.join(h.upper() for h in kit(n).sp.head_names) for n, _ in NEW), 'H', 2)
        y = y0 + 38
        x = 20
        for n, c in NEW:
            for h in kit(n).sp.head_names:
                f, g = fig(n, 6, 0, 'unarmed', None, head=h)
                crop = 44
                draw_fig(img, f, g, x, y, 4, crop=crop)
                text(img, x + 2, y + crop * 4 + 6, (n + ' ' + h).upper(), 'M', 2)
                x += max(crop * 4 + 8, 200)
                if x > W - 260: x = 20; y += 230
    return H, draw

def render_glow(n, head, fr, lf=6, pose='unarmed', item=None):
    """figure + glow for glow frame `fr` (the compositor uses frame 0, so swap the frame lists for one render)."""
    k = kit(n)
    tg, hg = k.torso_glow, k.head_glow
    try:
        if tg and len(tg) > fr: k.torso_glow = [tg[fr]]
        nh = len(k.sp.head_names)
        if hg and len(hg) >= (fr + 1) * nh: k.head_glow = hg[fr * nh:(fr + 1) * nh]
        return fig(n, lf, 0, pose, item, head=head)
    finally:
        k.torso_glow, k.head_glow = tg, hg

def glow_block():
    names = [n for n, _ in NEW]
    H = 40 + 270 * 2
    def draw(img, y0):
        text(img, 20, y0, 'GLOW LAYERS AT 4X: HARD PIXELS ONLY, THEN THE ADDITIVE LIGHT FRAME 0 AND 1   ' + ' '.join(n.upper() for n in names), 'H', 2)
        y = y0 + 38
        x = 20
        for n in names:
            f, g = fig(n, 6, 0, 'unarmed', None)
            draw_fig(img, f, None, x, y, 4, crop=44, gs=0.0)
            x += 44 * 4 + 6
            for fr in (0, 1):
                f2, g2 = render_glow(n, kit(n).sp.head_names[0], fr)
                draw_fig(img, f2, g2, x, y, 4, crop=44, gs=1.0)
                x += 44 * 4 + 6
            x += 14
            if x > W - 700: x = 20; y += 44 * 4 + 20
    return H, draw

def box(img, cx, cy, half, col, k):
    """a square of side 2*half px round the pivot, dotted, at scale k."""
    for t in range(-half * k, half * k + 1):
        if (t // 2) % 2 == 0:
            for (x, y) in ((cx + t, cy - half * k), (cx + t, cy + half * k), (cx - half * k, cy + t), (cx + half * k, cy + t)):
                img.over(x, y, col)
def scale_block():
    crop = 60; cw = crop * 4 + 12
    H = 40 + 2 * (cw + 40) + 40
    def draw(img, y0):
        text(img, 20, y0, 'SCALE: HUMAN, GRUNDL AND DRAKKIN (LARGE), THE NEW LARGE AND FLOATING RIGS AND THE NEW NORMAL RIGS   DOTTED BOX = THE SHARED 2X2 BODY (32 PX)', 'H', 2)
        y = y0 + 38; x = 20
        for n in ['human', 'grundl', 'drakkin'] + [n for n, _ in NEW]:
            f, g = render(SKit(dict(ALL)[n](), kit_items()), 6, 0, 0, 'pistol', 'service_pistol', dict(ALL)[n]().head_names[0], tint=TINTS[n])
            draw_fig(img, f, g, x, y + 20, 4, crop=crop)
            box(img, x + (crop // 2) * 4, y + 20 + (crop // 2) * 4, 16, (255, 79, 216, 160), 4)
            text(img, x + 6, y + 2, (n + ' PISTOL').upper(), 'M', 2)
            x += crop * 4 + 12
            if x > W - 260: x = 20; y += cw + 40
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
    """all 30 species at 1x (actual pixels, then flat silhouettes), stand / pistol / walk / walk 2, then 2x with names (colour, then flat)."""
    crop = 54; cell = crop + 2; n_sp = len(ALL)
    Wl = 20 + n_sp * cell + 20
    rows = [('STAND', 6, 'unarmed', None), ('PISTOL', 6, 'pistol', 'service_pistol'), ('WALK', 0, 'unarmed', None), ('WALK 2', 3, 'unarmed', None)]
    per_row = 12
    Hl = 50 + len(rows) * 2 * (crop + 30) + 20 + 2 * 3 * (56 * 2 + 40) + 20
    img = Rgba(Wl, Hl, RGB['F'] + (255,))
    text(img, 20, 12, 'LINE-UP: ALL %d SPECIES AT 1X (ACTUAL PIXELS), THEN FLAT SILHOUETTES, THEN 2X.   NEW: %s' % (n_sp, ' '.join(n.upper() for n, _ in NEW)), 'H', 3)
    y = 50
    for lab, lf, pose, it in rows:
        for flat in (False, True):
            x = 20
            for n, c in ALL:
                f, g = fig(n, lf, 0, pose, it, tint=TEAL)
                draw_fig(img, silhouette(f) if flat else f, None if flat else g, x, y, 1, crop=crop)
                x += cell
            if not flat: text(img, 20, y + crop + 2, lab + ':  ' + ' '.join(n.upper() for n, _ in ALL), 'M', 1)
            y += crop + 30
    y += 10
    for flat in (False, True):                                   # 2x with names (colour), then the same flat
        for i in range(0, n_sp, per_row):
            x = 20
            for n, c in ALL[i:i + per_row]:
                f, g = fig(n, 6, 0, 'unarmed', None, tint=TEAL)
                draw_fig(img, silhouette(f) if flat else f, None if flat else g, x, y, 2, crop=56)
                if not flat: text(img, x + 2, y + 114, n.upper(), 'M', 2)
                x += 56 * 2 + 14
            y += 56 * 2 + (20 if flat else 40)
    out = Rgba(Wl, min(Hl, y + 10), RGB['F'] + (255,))
    out.p = img.p[:out.h]
    out.save(path)
    return out.w, out.h

if __name__ == '__main__':
    argv = [a for a in sys.argv[1:] if not a.startswith('--')]
    only = None
    for a in sys.argv[1:]:
        if a.startswith('--only='): only = a.split('=', 1)[1].split(',')
    if only: NEW = [n for n in NEW if n[0] in only]
    out = argv[0] if argv else PREVIEW + '/races4_sheet.png'
    print(build(out))
    if not only: print(lineup(argv[1] if len(argv) > 1 else out.replace('.png', '_lineup.png')))
