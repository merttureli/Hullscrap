"""Preview sheet for the UI kit, read back from art/ui (so it proves the files): a mock build screen at 2x (the in-game scale on a 1600x900 window), then every piece labelled at 3x.
Usage: python3 sheet_ui.py [out.png]   (default /home/user/hs/shots/art_ui_sheet.png)"""
import sys, os, json, random
from px import *
import pal_sector
from build import read_png
from px_structure import text as caption     # the 3x5 caption font (its own palette copy: base letters only, which is all the captions use)

BG = (19, 22, 27)
SPACE = (11, 14, 24)
W = 1600


# ------------------------------------------------------------------ a fast opaque canvas (bytearray) and a null one for measuring layouts
class Canvas:
    def __init__(s, w, h, fill=BG):
        s.w, s.h = w, h; s.b = bytearray(bytes(fill + (255,)) * (w * h))
    def over(s, x, y, p):
        if 0 <= x < s.w and 0 <= y < s.h:
            a = p[3]
            if a == 0: return
            i = (y * s.w + x) * 4; b = s.b
            if a == 255: b[i] = p[0]; b[i + 1] = p[1]; b[i + 2] = p[2]
            else:
                t = a / 255.0
                for c in range(3): b[i + c] = int(b[i + c] + (p[c] - b[i + c]) * t)
    def blit_rgba(s, o, x, y, k=1):
        for j, row in enumerate(o.p):
            for i, p in enumerate(row):
                if p[3] == 0: continue
                for dy in range(k):
                    for dx in range(k): s.over(x + i * k + dx, y + j * k + dy, p)
    def rect(s, x, y, w, h, rgb):
        for j in range(h):
            for i in range(w): s.over(x + i, y + j, rgb + (255,))
    def save(s, path): save_rgba(path, s.w, s.h, bytes(s.b))

class Null:
    w = h = 0
    def over(s, *a): pass
    def blit_rgba(s, *a, **k): pass
    def rect(s, *a): pass


def load(rel):
    w, h, rows = read_png(os.path.join(ART, rel))
    o = Rgba(w, h)
    for y in range(h):
        for x in range(w): o.p[y][x] = list(rows[y][x * 4:x * 4 + 4])
    return o

def crop(o, x, y, w, h):
    f = Rgba(w, h)
    for j in range(h):
        for i in range(w): f.p[j][i] = list(o.p[y + j][x + i])
    return f

def shrink(o, k):
    """nearest-neighbour 1/k (the in-game cards scale big parts down)."""
    f = Rgba(o.w // k, o.h // k)
    for j in range(f.h):
        for i in range(f.w): f.p[j][i] = list(o.p[j * k + k // 2][i * k + k // 2])
    return f

def with_alpha(f, a):
    o = Rgba(f.w, f.h)
    for j in range(f.h):
        for i in range(f.w):
            p = f.p[j][i]; o.p[j][i] = [p[0], p[1], p[2], int(p[3] * a)]
    return o

def tint(f, rgb, t):
    o = Rgba(f.w, f.h)
    for j in range(f.h):
        for i in range(f.w):
            p = f.p[j][i]; o.p[j][i] = [int(p[k] + (rgb[k] - p[k]) * t) for k in range(3)] + [p[3]]
    return o


class Sheet:
    """a sprite file read back from art/: frames by anim name, and the 9-slice margins if it has them."""
    def __init__(s, rel):
        s.J = json.load(open(os.path.join(ART, rel + '.json'))); s.img = load(rel + '.png')
        s.fw, s.fh = s.J['frame']; s.m = s.J.get('nine_slice', {}).get('margins')
        s.names = list(s.J['anims'])
    def frame(s, anim, i=0):
        st = s.J['anims'][anim][0] + i
        cols = max(1, s.img.w // s.fw)
        return crop(s.img, (st % cols) * s.fw, (st // cols) * s.fh, s.fw, s.fh)
    def nine(s, anim, cv, x, y, w, h, k=1):
        """frame `anim` stretched to w x h source px (what StyleBoxTexture does), its top-left at canvas px (x, y), each source px drawn k x k."""
        f = s.frame(anim); L, T, R, B = s.m['left'], s.m['top'], s.m['right'], s.m['bottom']
        xs = [(0, L, 0, L), (L, s.fw - R, L, w - R), (s.fw - R, s.fw, w - R, w)]
        ys = [(0, T, 0, T), (T, s.fh - B, T, h - B), (s.fh - B, s.fh, h - B, h)]
        for (sy0, sy1, dy0, dy1) in ys:
            for (sx0, sx1, dx0, dx1) in xs:
                sw, sh, dw, dh = sx1 - sx0, sy1 - sy0, dx1 - dx0, dy1 - dy0
                if sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0: continue
                for j in range(dh):
                    row = f.p[sy0 + j * sh // dh]
                    for i in range(dw):
                        p = row[sx0 + i * sw // dw]
                        if p[3] == 0: continue
                        for a in range(k):
                            for b in range(k): cv.over(x + (dx0 + i) * k + b, y + (dy0 + j) * k + a, p)


def comp_frame(cid):
    """the first 'on' frame of a component sprite, or None."""
    try: return Sheet('components/' + cid).frame('on')
    except Exception: return None


def text(cv, x, y, s, col='M', k=2): caption(cv, x, y, s, col, k)


# ------------------------------------------------------------------ the mock build screen, 800x450 source px drawn at 2x
class Mock:
    K = 2
    def __init__(s):
        s.cv = Canvas(800 * s.K, 450 * s.K, SPACE)
        for n in ('panel', 'inset', 'bar', 'button', 'tab', 'card', 'highlight', 'tooltip', 'titlebar', 'scrollbar', 'scrollbar_grip', 'icons_res', 'icons_mode', 'icons_cat', 'cursors_x2'):
            setattr(s, n.upper(), Sheet('ui/' + n))

    def t(s, x, y, txt, col='H'): caption(s.cv, int(x * s.K), int(y * s.K), txt, col, s.K)      # one source px per font pixel
    def blit(s, f, x, y): s.cv.blit_rgba(f, int(x * s.K), int(y * s.K), s.K)
    def rect(s, x, y, w, h, rgb): s.cv.rect(int(x * s.K), int(y * s.K), int(w * s.K), int(h * s.K), rgb)
    def tag(s, x, y, txt, col):
        s.rect(x - 2, y - 2, 4 * len(txt) + 3, 9, (19, 22, 27)); s.t(x, y, txt, col)
    def outline(s, x, y, w, h, rgb):
        K = s.K
        for i in range(w * K): s.cv.over(x * K + i, y * K, rgb + (255,)); s.cv.over(x * K + i, (y + h) * K - 1, rgb + (255,))
        for j in range(h * K): s.cv.over(x * K, y * K + j, rgb + (255,)); s.cv.over((x + w) * K - 1, y * K + j, rgb + (255,))
    def nine(s, sh, anim, x, y, w, h): sh.nine(anim, s.cv, int(x * s.K), int(y * s.K), w, h, s.K)

    def ship(s):
        """a ship interior under the UI, from the real floor, wall and component art."""
        fl = Sheet('tiles/floor'); wl = load('tiles/walls.png')
        ox, oy = 236, 54                      # cells are 16 src px
        Wc, Hc = 20, 16
        solid = {(x, 0) for x in range(Wc)} | {(x, Hc - 1) for x in range(Wc)} | {(0, y) for y in range(Hc)} | {(Wc - 1, y) for y in range(Hc)}
        solid |= {(9, y) for y in range(1, Hc - 1) if y not in (4, 5, 9, 10)} | {(x, 8) for x in range(1, Wc - 1) if x not in (4, 5, 14, 15)}
        for y in range(Hc):
            for x in range(Wc):
                if (x, y) in solid:
                    m = sum(1 << b for b, (dx, dy) in enumerate(((0, -1), (1, 0), (0, 1), (-1, 0))) if (x + dx, y + dy) in solid)
                    s.blit(crop(wl, m * 16, 0, 16, 16), ox + x * 16, oy + y * 16)
                else:
                    s.blit(fl.frame('v0' if (x * 7 + y * 13) % 10 < 7 else 'v1' if (x + y) % 2 else 'v2'), ox + x * 16, oy + y * 16)
        for cid, cx, cy in (('reactor_mk1', 2, 1), ('helm', 6, 5), ('oxygen_gen', 11, 1), ('bed', 16, 1), ('shield_mk1', 11, 10), ('fabricator', 2, 11), ('engine_mk1', 15, 11)):
            f = comp_frame(cid)
            if f is not None: s.blit(f, ox + cx * 16, oy + cy * 16)
        return ox, oy

    def topbar(s):
        s.nine(s.BAR, 'normal', 2, 2, 796, 26)
        res = [('scrap', '128'), ('copper', '46'), ('polymer', '12'), ('titanium', '8'), ('silicon', '21'), ('crystal', '3'), ('credits', '460'), ('fuel', '14')]
        x = 9
        for name, val in res:
            s.blit(s.ICONS_RES.frame(name), x, 7); s.t(x + 18, 13, val, 'H'); x += 18 + 4 * len(val) + 9
        x += 10
        for name, val, col in (('power', '9/11', 'g'), ('o2', '98%', 'H'), ('hull', '100%', 'H'), ('heat', '34%', 'o')):
            s.blit(s.ICONS_RES.frame(name), x, 7); s.t(x + 18, 13, val, col); x += 18 + 4 * len(val) + 9
        s.t(606, 13, 'PAUSED: BUILD MODE', 'a')

    def modebar(s):
        modes = [('build', 'B'), ('play', 'SPC'), ('map', 'M'), ('shields', 'H'), ('crafting', 'C'), ('help', 'F1'), ('pause', 'P')]
        bw, bh, gap = 38, 32, 3
        Wb = len(modes) * bw + (len(modes) - 1) * gap + 24
        x0 = (800 - Wb) // 2
        s.nine(s.BAR, 'normal', x0, 450 - 48, Wb, 44)
        for i, (m, key) in enumerate(modes):
            x = x0 + 12 + i * (bw + gap); y = 450 - 42
            s.nine(s.BUTTON, 'hover' if m == 'build' else 'normal', x, y, bw, bh)
            s.blit(s.ICONS_MODE.frame(m), x + 7, y + 4)
            s.t(x + bw - 4 * len(key) - 4, y + bh - 8, key, 'a' if m == 'build' else 'M')

    def palette(s):
        x0, y0, w, h = 4, 32, 212, 372
        s.nine(s.PANEL, 'normal', x0, y0, w, h)
        s.nine(s.TITLEBAR, 'normal', x0 + 8, y0 + 8, w - 16, 14)
        s.t(x0 + 22, y0 + 13, 'BUILD PALETTE', 'H')
        cats = ['structure', 'shapes', 'systems', 'weapons', 'engines', 'utility', 'cargo']
        tw, th = 27, 24
        for i, c in enumerate(cats):
            x = x0 + 8 + i * tw; on = c == 'systems'
            s.nine(s.TAB, 'on' if on else 'off', x, y0 + 25 + (0 if on else 2), tw, th if on else th - 2)
            s.blit(s.ICONS_CAT.frame(c), x + 5, y0 + 30 + (0 if on else 2))
        ix, iy, iw, ih = x0 + 8, y0 + 25 + th - 1, w - 28, h - (25 + th + 7)
        s.nine(s.INSET, 'normal', ix, iy, iw, ih)
        s.nine(s.SCROLLBAR, 'track', ix + iw + 3, iy, 8, ih)
        s.nine(s.SCROLLBAR, 'thumb', ix + iw + 3, iy + 2, 8, 120)
        s.blit(s.SCROLLBAR_GRIP.frame('grip'), ix + iw + 3 + 2, iy + 2 + 57)
        by = {c['id']: c for c in json.load(open(os.path.join(ART, '..', 'data', 'components.json')))['components']}
        cards = [('reactor_mk1', 'steel', '8 POWER', [('scrap', '24'), ('copper', '10')]), ('reactor_scrap_mk1', 'scrap', '6 POWER', [('scrap', '30')]),
                 ('reactor_neon_mk1', 'neon', '16 POWER', [('crystal', '4'), ('silicon', '6')]), ('shield_mk1', 'steel', '-3 POWER', [('titanium', '6'), ('silicon', '4')]),
                 ('helm', 'steel', '-1 POWER', [('scrap', '12')]), ('oxygen_scrap_mk1', 'scrap', '-2 POWER', [('scrap', '14')]),
                 ('mirror_veil', 'gold', '-3 POWER', [('crystal', '6')]), ('nanoforge', 'locked', '-4 POWER', [('military_circuit', '2'), ('gate_alloy', '1')])]
        cw, ch = 82, 76
        s.cards = {}
        for i, (cid, line, pw, cost) in enumerate(cards):
            cx = ix + 4 + (i % 2) * (cw + 4); cy = iy + 4 + (i // 2) * (ch + 4)
            s.nine(s.CARD, line, cx, cy, cw, ch)
            f = comp_frame(cid)
            if f is not None:
                f = shrink(f, 2) if max(f.w, f.h) > 40 else f
                if line == 'locked': f = tint(f, (42, 47, 55), 0.55)
                s.blit(f, cx + (cw - f.w) // 2, cy + 7 + (34 - f.h) // 2)
            c = by.get(cid, {}); name = c.get('name', cid).upper()
            s.t(cx + (cw - 4 * len(name)) // 2, cy + 43, name, 'M' if line == 'locked' else 'H')
            s.t(cx + 8, cy + 50, '%dX%d' % tuple(c.get('size', (1, 1))), 'M')
            s.t(cx + cw - 8 - 4 * len(pw), cy + 50, pw, 'g' if not pw.startswith('-') else 'p')
            xx = cx + 7
            for (rn, rv) in cost:
                s.blit(s.ICONS_RES.frame(rn), xx, cy + 56); s.t(xx + 17, cy + 62, rv, 'M' if line == 'locked' else 'H'); xx += 19 + 4 * len(rv) + 3
            s.cards[i] = (cx, cy, cw, ch)
        for (i, anim) in ((0, 'selected'), (3, 'hover')):             # the overlays, drawn 2 px outside the card
            cx, cy, cw, ch = s.cards[i]; s.nine(s.HIGHLIGHT, anim, cx - 2, cy - 2, cw + 4, ch + 4)

    def hovercard(s):
        x0, y0, w, h = 590, 54, 206, 196
        s.nine(s.TOOLTIP, 'normal', x0, y0, w, h)
        s.blit(shrink(comp_frame('shield_mk1'), 2), x0 + w - 40, y0 + 8)
        s.t(x0 + 8, y0 + 8, 'SHIELD MK1', 'H'); s.t(x0 + 8, y0 + 16, 'STANDARD LINE  TIER 1', 'M')
        s.t(x0 + 8, y0 + 24, 'SHIELD  4X4', 'M')
        s.rect(x0 + 8, y0 + 44, w - 16, 1, (86, 94, 106))
        for i, (ic, txt, col) in enumerate((('power', 'POWER USE  -3', 'p'), ('hull', 'HP  40', 'H'), ('heat', 'HEAT  LOW', 'H'))):
            s.blit(s.ICONS_RES.frame(ic), x0 + 6, y0 + 48 + i * 17); s.t(x0 + 26, y0 + 55 + i * 17, txt, col)
        s.t(x0 + 8, y0 + 102, 'A SINGLE BUBBLE OF CERTIFIED', 'M'); s.t(x0 + 8, y0 + 109, 'SAFETY. NOT VALID IN THE DRIFT.', 'M')
        s.rect(x0 + 8, y0 + 120, w - 16, 1, (86, 94, 106))
        s.t(x0 + 8, y0 + 125, 'RECIPE', 'a')
        xx = x0 + 6
        for rn, rv in (('titanium', '6'), ('silicon', '4'), ('crystal', '1')):
            s.blit(s.ICONS_RES.frame(rn), xx, y0 + 133); s.t(xx + 17, y0 + 139, rv, 'H'); xx += 31
        s.t(x0 + 8, y0 + 154, 'ANYWHERE INSIDE: 4X4 FLOOR', 'M'); s.t(x0 + 8, y0 + 161, 'NEEDS A POWERED CABLE', 'M')
        s.t(x0 + 8, y0 + 173, 'IN CARGO  X1', 'g'); s.t(x0 + 100, y0 + 173, 'R ROTATE   X REMOVE', 'M')

    def ghosts(s, ox, oy):
        f = comp_frame('laser_mk1')
        gx, gy = ox + 12 * 16, oy + 6 * 16 + 2
        s.blit(tint(with_alpha(f, 0.6), (107, 211, 74), 0.35), gx, gy)
        s.outline(gx, gy + 4, 64, 32, (107, 211, 74)); s.tag(gx + 4, gy + 42, 'OK  -2 POWER', 'g')
        gx2, gy2 = ox + 3 * 16, oy + 8 * 16 - 8
        s.blit(tint(with_alpha(f, 0.55), (224, 65, 59), 0.5), gx2, gy2)
        s.outline(gx2, gy2 + 4, 64, 32, (224, 65, 59)); s.tag(gx2 + 2, gy2 - 10, 'NEEDS A WALL FACE', 'r')
        s.cv.blit_rgba(s.CURSORS_X2.frame('place'), (gx + 30) * s.K - 16, (gy + 18) * s.K - 16)
        s.cv.blit_rgba(s.CURSORS_X2.frame('invalid'), (gx2 + 30) * s.K - 16, (gy2 + 22) * s.K - 16)
        s.cv.blit_rgba(s.CURSORS_X2.frame('pointer'), 590 * s.K + 6, 300 * s.K)

    def render(s):
        rnd = random.Random(7)
        for _ in range(140): s.cv.over(rnd.randrange(800 * s.K), rnd.randrange(450 * s.K), (200, 210, 230, rnd.choice((60, 110, 170))))
        ox, oy = s.ship()
        s.palette(); s.hovercard(); s.ghosts(ox, oy); s.topbar(); s.modebar()
        return s.cv


# ------------------------------------------------------------------ the labelled pieces at 3x
K = 3

def checker(cv, x, y, w, h, a=(42, 47, 55), b=(52, 58, 67), n=6):
    for j in range(h):
        for i in range(w): cv.over(x + i, y + j, (a if ((i // n) + (j // n)) % 2 == 0 else b) + (255,))

def raw(cv, sh, anim, x, y):
    """a frame raw at 3x on a checker with its 9-slice margins in magenta; returns its width."""
    L, T, R, B = (sh.m['left'], sh.m['top'], sh.m['right'], sh.m['bottom']) if sh.m else (0, 0, 0, 0)
    checker(cv, x, y, sh.fw * K, sh.fh * K)
    cv.blit_rgba(sh.frame(anim), x, y, K)
    if sh.m:
        for gx in (L, sh.fw - R):
            for j in range(sh.fh * K): cv.over(x + gx * K, y + j, (255, 79, 216, 170))
        for gy in (T, sh.fh - B):
            for i in range(sh.fw * K): cv.over(x + i, y + gy * K, (255, 79, 216, 170))
    text(cv, x, y + sh.fh * K + 3, anim.upper(), 'M', 2)
    return max(sh.fw * K, 8 * len(anim))

def stretched(cv, sh, anim, x, y, w, h, bg=(110, 118, 131)):
    """the frame stretched to w x h source px at 3x on a light backdrop; returns the width drawn."""
    checker(cv, x, y, (w + 4) * K, (h + 4) * K, bg, (116, 124, 137), 9)
    sh.nine(anim, cv, x + 2 * K, y + 2 * K, w, h, K)
    return (w + 4) * K

def kit_block(cv, y0):
    text(cv, 20, y0, '9-SLICE KIT   EVERY FRAME RAW AT 3X (MARGINS IN MAGENTA), THEN STRETCHED AT 3X', 'H', 3)
    y = y0 + 34
    def head(sh, title):
        m = sh.m
        text(cv, 20, y, '%s   FRAME %dX%d   MARGINS L%d T%d R%d B%d   CONTENT %s' % (title, sh.fw, sh.fh, m['left'], m['top'], m['right'], m['bottom'],
             '/'.join(str(v) for v in sh.J['nine_slice']['content_margins'].values())), 'a', 2)
    def row(title, sh, sizes, anims=None, over=None):
        nonlocal y
        head(sh, title)
        yy = y + 16; x = 20; hmax = 0
        for n in (anims or sh.names): x += raw(cv, sh, n, x, yy) + 12
        x += 20
        for (w, h, an) in sizes:
            for n in (an or [sh.names[0]]):
                x += stretched(cv, sh, n, x, yy, w, h) + 10
                hmax = max(hmax, (h + 4) * K)
        y = yy + max(hmax, sh.fh * K) + 26
    S = lambda n: Sheet('ui/' + n)
    p = S('panel'); row('PANEL', p, [(40, 34, None), (96, 46, None)])
    row('INSET', S('inset'), [(34, 24, None), (80, 14, None)])
    row('BAR', S('bar'), [(44, 26, None), (110, 26, None)])
    row('BUTTON', S('button'), [(36, 20, ['normal', 'hover', 'pressed', 'disabled'])])
    row('TAB', S('tab'), [(30, 24, ['on', 'off'])])
    c = S('card'); row('CARD', c, [(44, 56, c.names)])
    # highlight: shown over a steel card (drawn 2 px outside)
    h = S('highlight'); head(h, 'HIGHLIGHT')
    yy = y + 16; x = 20
    for n in h.names: x += raw(cv, h, n, x, yy) + 12
    x += 20
    for n in h.names:
        checker(cv, x, yy, 64 * K, 64 * K, (42, 47, 55), (52, 58, 67), 9)
        c.nine('steel', cv, x + 8 * K, yy + 8 * K, 44, 48, K)
        h.nine(n, cv, x + 6 * K, yy + 6 * K, 48, 52, K)
        x += 64 * K + 10
    y = yy + 64 * K + 26
    row('TOOLTIP', S('tooltip'), [(50, 28, None), (110, 18, None)])
    row('TITLE BAR', S('titlebar'), [(70, 14, None), (120, 14, None)])
    # scrollbars: a track with each thumb state, vertical and horizontal
    for fid, title, vert in (('scrollbar', 'SCROLLBAR (VERTICAL)', True), ('scrollbar_h', 'SCROLLBAR H', False)):
        sh = S(fid); head(sh, title)
        yy = y + 16; x = 20
        for n in sh.names: x += raw(cv, sh, n, x, yy) + 14
        x += 30
        for n in sh.names[1:]:
            if vert:
                checker(cv, x, yy, 14 * K, 70 * K, (42, 47, 55), (52, 58, 67), 9)
                sh.nine('track', cv, x + 3 * K, yy + 2 * K, 8, 66, K); sh.nine(n, cv, x + 3 * K, yy + 6 * K, 8, 26, K)
                g = Sheet('ui/scrollbar_grip'); cv.blit_rgba(g.frame('grip'), x + 5 * K, yy + (6 + 10) * K, K)
                x += 14 * K + 8
            else:
                checker(cv, x, yy, 70 * K, 14 * K, (42, 47, 55), (52, 58, 67), 9)
                sh.nine('track', cv, x + 2 * K, yy + 3 * K, 66, 8, K); sh.nine(n, cv, x + 6 * K, yy + 3 * K, 26, 8, K)
                x += 70 * K + 8
        y = yy + (70 if vert else 14) * K + 26
    return y

def icons_block(fid, title, per, cellw):
    def fn(cv, y0):
        sh = Sheet('ui/' + fid)
        text(cv, 20, y0, title, 'H', 3)
        y = y0 + 32; rowh = sh.fh * K + 34
        for i, n in enumerate(sh.names):
            cx = 20 + (i % per) * cellw; cy = y + (i // per) * rowh
            checker(cv, cx, cy, sh.fw * K, sh.fh * K)
            cv.blit_rgba(sh.frame(n), cx, cy, K)
            text(cv, cx, cy + sh.fh * K + 4, n.upper(), 'M', 2)
        return y + ((len(sh.names) + per - 1) // per) * rowh + 10
    return fn

def cursors_block(cv, y0):
    sh = Sheet('ui/cursors_x2'); s1 = Sheet('ui/cursors')
    text(cv, 20, y0, 'CURSORS 16X16 (X2 SET 32X32 SHOWN AT 2X), HOTSPOT = MAGENTA CROSS', 'H', 3)
    y = y0 + 32
    for i, n in enumerate(sh.names):
        cx = 20 + i * 190
        for bi, bg in enumerate(((110, 118, 131), (42, 47, 55))):
            checker(cv, cx + bi * 84, y, 80, 80, bg, tuple(c + 7 for c in bg), 8)
            cv.blit_rgba(sh.frame(n), cx + bi * 84 + 8, y + 8, 2)
            hx, hy = sh.J['anchors'][n]
            for d in range(-4, 5): cv.over(cx + bi * 84 + 8 + hx * 2 + d, y + 8 + hy * 2, (255, 79, 216, 255)); cv.over(cx + bi * 84 + 8 + hx * 2, y + 8 + hy * 2 + d, (255, 79, 216, 255))
        text(cv, cx, y + 86, '%s  HOT %d,%d' % (n.upper(), s1.J['anchors'][n][0], s1.J['anchors'][n][1]), 'M', 2)
    return y + 108

def small_block(cv, y0):
    text(cv, 20, y0, 'ICONS AT THEIR REAL SIZE (SHOWN AT 2X) ON THE KIT COLOURS', 'H', 3)
    y = y0 + 34
    res = Sheet('ui/icons_res'); cat = Sheet('ui/icons_cat'); mode = Sheet('ui/icons_mode')
    for (cap, col) in (('ON PANEL', (42, 47, 55)), ('ON INSET', (19, 22, 27)), ('ON FLOOR', (110, 118, 131)), ('ON NAVY', (34, 42, 69))):
        text(cv, 20, y, cap, 'M', 2)
        cv.rect(20, y + 14, 1560, 112, col)
        for i, n in enumerate(res.names): cv.blit_rgba(res.frame(n), 28 + i * 36, y + 20, 2)
        for i, n in enumerate(cat.names): cv.blit_rgba(cat.frame(n), 28 + i * 36, y + 60, 2)
        for i, n in enumerate(mode.names): cv.blit_rgba(mode.frame(n), 28 + 18 * 36 + 20 + i * 54, y + 20, 2)
        y += 134
    return y

BLOCKS = [kit_block, icons_block('icons_res', 'RESOURCE ICONS 16X16 AT 3X', 12, 132), icons_block('icons_cat', 'CATEGORY ICONS 16X16 AT 3X', 12, 132),
          icons_block('icons_mode', 'MODE ICONS 24X24 AT 3X', 12, 132), cursors_block, small_block]


def main(out):
    mock = Mock().render()
    heights = [fn(Null(), 0) + 16 for fn in BLOCKS]            # a dry run with a null canvas measures each block
    gal = Canvas(W, sum(heights))
    y = 0
    for fn, h in zip(BLOCKS, heights):
        fn(gal, y); y += h
    top = Canvas(W, 34)
    text(top, 20, 10, 'HULLSCRAP UI KIT   MOCK BUILD SCREEN AT 2X (1600X900), THEN EVERY PIECE LABELLED', 'H', 3)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    save_rgba(out, W, top.h + mock.h + 14 + gal.h, bytes(top.b) + bytes(mock.b) + bytes(Canvas(W, 14).b) + bytes(gal.b))
    print('sheet', W, 'x', top.h + mock.h + 14 + gal.h, '->', out)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '/home/user/hs/shots/art_ui_sheet.png')
