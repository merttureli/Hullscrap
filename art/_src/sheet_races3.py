"""Race wave 3 preview sheets (3x): REVENANT, CHOIR, RATTLER, TESSELLATE (and TESSELLATE_HALF), SABLE, QUILLBACK, KITE.
  python3 art/_src/sheet_races3.py [out.png [lineup.png]]
out.png    each of the new rigs at 4 rotations x 3 hand weapons, every animation (stand, walk 0-5, every arm pose) at 3x and at 1x, the head variants, the glow layers
           (with and without the additive light), the Quillback's quills at rest and flared, the Tessellate swarm and its 1x1 half at 8x, and the small rigs next to a human for scale.
lineup.png the 1x line-up of ALL 23 species (stand / pistol / walk / walk 2) plus the Tessellate half as a 24th cell, the flat silhouettes of the same, then 2x with names."""
import sys
from px import *
import pal_races1     # noqa: F401
import crew_v2 as cv2
from sheet_v2 import text
import sp_compose
from sp_compose import SKit, render
from sp_items import kit_items
from sheet_species import draw_fig, silhouette
from sheet_races2 import ALL as OLD, TINTS as OLD_TINTS, TEAL
import sp_races3
from sp_races3 import Revenant, Choir, Rattler, Tessellate, TessellateHalf, Sable, Quillback, Kite, swarm_outline

K = 3; W = 2760
NEW = [('revenant', Revenant), ('choir', Choir), ('rattler', Rattler), ('tessellate', Tessellate), ('tessellate_half', TessellateHalf),
       ('sable', Sable), ('quillback', Quillback), ('kite', Kite)]
SEVEN = [n for n in NEW if n[0] != 'tessellate_half']                      # the 23 species: the half is a body of the Tessellate, shown as an extra cell
ALL = OLD + SEVEN
EVERY = ALL + [('tessellate_half', TessellateHalf)]
TINTS = dict(OLD_TINTS)
TINTS.update({'revenant': (96, 150, 200), 'choir': (200, 110, 70), 'rattler': (232, 122, 40), 'tessellate': (214, 72, 92), 'tessellate_half': (214, 72, 92),
              'sable': (196, 60, 74), 'quillback': (66, 150, 112), 'kite': (232, 190, 70)})
LOADOUT = {   # three different hand weapons from art/items each: (item id, arm pose)
 'revenant':        [('rivet_gun', 'tool'), ('service_pistol', 'pistol'), ('carbine', 'rifle')],
 'choir':           [(None, 'unarmed'), ('multi_tool', 'tool'), ('flare_gun', 'pistol')],
 'rattler':         [('multi_tool', 'tool'), ('spark_pistol', 'pistol'), ('carbine', 'rifle')],
 'tessellate':      [('spark_pistol', 'pistol'), ('multi_tool', 'tool'), ('service_pistol', 'pistol')],
 'tessellate_half': [('spark_pistol', 'pistol'), ('multi_tool', 'tool'), ('flare_gun', 'pistol')],
 'sable':           [('carbine', 'rifle'), ('service_pistol', 'pistol'), ('doorbuster', 'rifle')],
 'quillback':       [('ember_knife', 'melee'), ('quarry_hammer', 'melee'), ('service_pistol', 'pistol')],
 'kite':            [('flare_gun', 'pistol'), ('carbine', 'rifle'), ('multi_tool', 'tool')],
}
POSE_ITEM = [('unarmed', None), ('pistol', 'service_pistol'), ('rifle', 'carbine'), ('tool', 'multi_tool'), ('heavy', 'slugthrower'), ('melee', 'ember_knife')]
ROTS = [(6, 0), (0, 90), (2, 180), (4, 270)]        # (legs frame, aim and move direction)
KITS = {}
def kit(n):
    if n not in KITS: KITS[n] = SKit(dict(EVERY)[n](), kit_items())
    return KITS[n]
def fig(n, lf, deg, pose, item, head=None, tint=None, aim=None, k=None):
    """a figure + its glow; the swarm species get the swarm outline (open gaps) instead of the usual one."""
    orig = sp_compose.outline_all
    if n.startswith('tessellate'): sp_compose.outline_all = swarm_outline
    try:
        return render(k or kit(n), lf, deg, deg if aim is None else aim, pose, item, head or kit(n).sp.head_names[0], tint=tint or TINTS[n])
    finally:
        sp_compose.outline_all = orig
TAG = {'rattler': '  (SMALL RIG 25X25, PIVOT 12)', 'tessellate_half': '  (SMALL RIG 25X25: THE 1X1 SPLIT BODY)', 'tessellate': '  (NORMAL RIG 33X33: A SWARM, THE GAPS STAY OPEN)'}

def races_block():
    crop = 72; cw = crop * K + 4
    H = 40 + len(NEW) * (cw + 56) + 10
    def draw(img, y0):
        text(img, 20, y0, 'RACE WAVE 3: REVENANT, CHOIR, RATTLER, TESSELLATE (+ HALF), SABLE, QUILLBACK, KITE   EACH AT 4 ROTATIONS (0 90 180 270) X 3 WEAPONS', 'H', 4)
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
    """every animation: the stand frame, the 6 walk frames and the arm poses, each at 3x with the same frame at 1x under it."""
    crop = 66; cw = crop * K + 2; per = cw + 4
    H = 40 + len(NEW) * (cw + 36 + crop + 40) + 10
    def draw(img, y0):
        text(img, 20, y0, 'EVERY ANIMATION AT 3X WITH THE SAME FRAME AT 1X UNDER IT: STAND, WALK 0-5, THEN THE ARM POSES (THE QUILLBACK FLARES IN THE MELEE POSE)', 'H', 3)
        y = y0 + 38
        for n, c in NEW:
            text(img, 20, y, n.upper() + TAG.get(n, '  (NORMAL RIG 33X33)'), 'a', 3)
            frames = [(6, 'unarmed', None, 'STAND')] + [(i, 'unarmed', None, 'WALK %d' % i) for i in range(6)] + [(6, p, it, p.upper()) for p, it in POSE_ITEM[1:]]
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
        text(img, 20, y0, 'HEAD VARIANTS AT 4X   REVENANT: BARE, HOOD, HELMET   CHOIR: SINGER, MITRE, HELMET   RATTLER: GOGGLES, PUSHED, HELMET   TESSELLATE: SWARM, VISOR, HELMET   SABLE: BARE, HOOD, HELMET   QUILLBACK: CREST, HELMET, SCARRED   KITE: WIDE, GOGGLES, HELMET', 'H', 2)
        y = y0 + 38
        x = 20
        for n, c in NEW:
            for h in kit(n).sp.head_names:
                f, g = fig(n, 6, 0, 'unarmed', None, head=h)
                crop = 44 if kit(n).sp.N > 25 else 34
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
    H = 40 + 270 + 270
    def draw(img, y0):
        text(img, 20, y0, 'GLOW LAYERS AT 5X: HARD PIXELS ONLY, THEN THE ADDITIVE LIGHT   REVENANT COLD EYES (2 FRAMES)   CHOIR RESONANCE (2 FRAMES)   TESSELLATE STATUS LIGHTS (2 FRAMES)   HALF', 'H', 2)
        y = y0 + 38
        x = 20
        for n, headn, frames in (('revenant', 'bare', (0, 1)), ('choir', 'singer', (0, 1)), ('tessellate', 'visor', (0, 1)), ('tessellate_half', 'swarm', (0, 1))):
            crop = 44 if kit(n).sp.N > 25 else 30
            f, g = fig(n, 6, 0, 'unarmed', None, head=headn)
            draw_fig(img, f, None, x, y, 5 if crop == 44 else 6, crop=crop, gs=0.0)
            x += crop * (5 if crop == 44 else 6) + 6
            for fr in frames:
                f2, g2 = render_glow(n, headn, fr)
                draw_fig(img, f2, g2, x, y, 5 if crop == 44 else 6, crop=crop, gs=1.0)
                x += crop * (5 if crop == 44 else 6) + 6
            x += 14
            if x > W - 700 and n == 'choir': x = 20; y += 44 * 5 + 20
        y += 44 * 5 + 34
        text(img, 20, y, 'SWARMS AT 8X: EVERY BOT IS A 2X2 BLOCK, THE 1 PX GAPS STAY OPEN (FLOOR SHOWS THROUGH); THE OUTLINE IS ROUND THE OUTSIDE ONLY.  TESSELLATE: STAND, WALK 0, WALK 3, PISTOL.  THE HALF: STAND, PISTOL, TOOL', 'M', 2)
        y += 24
        x = 20
        for n, lf, pose, it in (('tessellate', 6, 'unarmed', None), ('tessellate', 0, 'unarmed', None), ('tessellate', 3, 'unarmed', None), ('tessellate', 6, 'pistol', 'service_pistol'),
                                ('tessellate_half', 6, 'unarmed', None), ('tessellate_half', 6, 'pistol', 'service_pistol'), ('tessellate_half', 6, 'tool', 'multi_tool')):
            f, g = fig(n, lf, 0, pose, it)
            crop = 46 if n == 'tessellate' else 34
            draw_fig(img, f, g, x, y, 6, crop=crop)
            x += crop * 6 + 6
    return H, draw

def flare_block():
    """the Quillback's quills: at rest (every pose but melee) and flared (the melee pose), turned to four directions, with and without the weapon."""
    crop = 56
    H = 40 + crop * 5 + 14 + crop * 3 + 70
    def draw(img, y0):
        text(img, 20, y0, 'QUILLBACK QUILLS AT 5X: AT REST (THE TORSO LAYER, UNARMED / PISTOL / RIFLE) AND FLARED (THE MELEE POSE: A SUNBURST ROUND THE BACK AND SIDES, THE FRONT STAYS CLEAR)', 'H', 2)
        y = y0 + 38; x = 20
        for pose, it, lab in (('unarmed', None, 'AT REST'), ('pistol', 'service_pistol', 'PISTOL'), ('rifle', 'carbine', 'RIFLE'), ('melee', 'ember_knife', 'FLARED: EMBER KNIFE'), ('melee', 'quarry_hammer', 'FLARED: HAMMER')):
            f, g = fig('quillback', 6, 0, pose, it, head='crest')
            text(img, x + 4, y - 4, lab, 'M', 2)
            draw_fig(img, f, g, x, y + 10, 5, crop=crop)
            x += crop * 5 + 6
        y += crop * 5 + 14
        x = 20
        for lf, deg in ROTS:
            f, g = fig('quillback', lf, deg, 'melee', 'ember_knife', head='scarred')
            draw_fig(img, f, g, x, y, 3, crop=crop)
            x += crop * 3 + 6
        for lf, deg in ROTS:
            f, g = fig('quillback', lf, deg, 'unarmed', None, head='helmet')
            draw_fig(img, f, g, x, y, 3, crop=crop)
            x += crop * 3 + 6
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
        text(img, 20, y0, 'SCALE: HUMAN, THE SMALL RIGS (RATTLER, TESSELLATE HALF, VELLUM) AND THE NEW NORMAL RIGS   DOTTED BOX = THE SHARED 2X2 BODY (32 PX); THE SMALL ONES: THE 1X1 CELL (16 PX)', 'H', 2)
        y = y0 + 38; x = 20
        for n in ('human', 'rattler', 'tessellate_half', 'vellum', 'tessellate', 'sable'):
            small = n in ('rattler', 'tessellate_half', 'vellum')
            if n in ('human', 'vellum'): f, g = render(SKit(dict(ALL)[n](), kit_items()), 6, 0, 0, 'pistol', 'service_pistol', dict(ALL)[n]().head_names[0], tint=TINTS[n])
            else: f, g = fig(n, 6, 0, 'pistol', 'service_pistol')
            draw_fig(img, f, g, x, y + 20, 4, crop=crop)
            box(img, x + (crop // 2) * 4, y + 20 + (crop // 2) * 4, 8 if small else 16, (255, 79, 216, 160), 4)
            text(img, x + 6, y + 2, (n + ' PISTOL').upper(), 'M', 2)
            x += crop * 4 + 12
            if x > W - 260: x = 20; y += cw + 40
    return H, draw

def build(path):
    bl = [races_block(), anim_block(), heads_block(), glow_block(), flare_block(), scale_block()]
    Ht = sum(h for h, _ in bl) + 24 * len(bl) + 20
    img = Rgba(W, Ht, RGB['F'] + (255,))
    y = 20
    for h, d in bl:
        d(img, y); y += h + 24
        for x in range(W): img.p[y - 12][x] = list(RGB['G']) + [255]
    img.save(path)
    return img.w, img.h

def lineup(path):
    """all 23 species at 1x (actual pixels, then flat silhouettes), two poses a row group, then 2x with names (colour left, flat right); the Tessellate half is a 24th cell."""
    crop = 54; cell = crop + 2; n_sp = len(EVERY); gw = n_sp * cell + 24
    Wl = 20 + 2 * gw
    groups = [[('STAND', 6, 'unarmed', None), ('PISTOL', 6, 'pistol', 'service_pistol')], [('WALK', 0, 'unarmed', None), ('WALK 2', 3, 'unarmed', None)]]
    per_row = 12
    Hl = 50 + 2 * (2 * (crop + 40) + 10) + 20 + 4 * (56 * 2 + 40) * 2 + 20
    img = Rgba(Wl, Hl, RGB['F'] + (255,))
    text(img, 20, 12, 'LINE-UP: ALL 23 SPECIES AT 1X (ACTUAL PIXELS) + THE TESSELLATE HALF, THEN FLAT SILHOUETTES, THEN 2X.   NEW: REVENANT CHOIR RATTLER TESSELLATE SABLE QUILLBACK KITE', 'H', 3)
    y = 50
    names = ' '.join(n.upper() for n, _ in EVERY)
    for row in groups:
        for flat in (False, True):
            x = 20
            for lab, lf, pose, it in row:
                for n, c in EVERY:
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
        for i in range(0, n_sp, per_row):
            x = 20
            for n, c in EVERY[i:i + per_row]:
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
    out = sys.argv[1] if len(sys.argv) > 1 else PREVIEW + '/races3_sheet.png'
    print(build(out))
    print(lineup(sys.argv[2] if len(sys.argv) > 2 else out.replace('.png', '_lineup.png')))
