"""Preview sheet for the ending art: reads the delivered PNG/JSON back (so it proves the files), lays out every illustration at 2x, every frame at 1x,
the glow layers alone, the hall of ships frame kit assembled around a ship silhouette (three lines) and a mock score panel with the ornaments.
Run: python3 art/_src/endings_sheet.py <out.png>"""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ill import F35, png_bytes, save_rgba
from endings_all import read_png, ART, OUT
import pal_endings

BG = (30, 36, 46)
TXT = (210, 216, 224)
AMB = (225, 161, 54)

class Sheet:
    def __init__(s, w, h, fill=BG):
        s.w, s.h = w, h
        s.p = [[fill] * w for _ in range(h)]
    def put(s, x, y, c):
        if 0 <= x < s.w and 0 <= y < s.h: s.p[y][x] = c
    def blit(s, rows, w, h, x, y, k=1, add=None, alpha=True):
        """rows: raw RGBA rows from read_png."""
        for j in range(h):
            row = rows[j]
            for i in range(w):
                r, g, b, a = row[i * 4:i * 4 + 4]
                if a == 0: continue
                if add is not None: continue
                for dy in range(k):
                    for dx in range(k): s.put(x + i * k + dx, y + j * k + dy, (r, g, b))
    def blit_glow(s, base_rows, glow_rows, w, h, x, y, k=1):
        for j in range(h):
            for i in range(w):
                r, g, b, a = base_rows[j][i * 4:i * 4 + 4]
                gr, gg, gb, ga = glow_rows[j][i * 4:i * 4 + 4]
                t = ga / 255.0
                c = (min(255, int(r + gr * t)), min(255, int(g + gg * t)), min(255, int(b + gb * t)))
                for dy in range(k):
                    for dx in range(k): s.put(x + i * k + dx, y + j * k + dy, c)
    def rect(s, x, y, w, h, c):
        for j in range(h):
            for i in range(w): s.put(x + i, y + j, c)
    def text(s, x, y, t, c=TXT, k=2):
        for ch in t.upper():
            g = F35.get(ch, F35[' '])
            for i, b in enumerate(g):
                if b == '1':
                    for dy in range(k):
                        for dx in range(k): s.put(x + (i % 3) * k + dx, y + (i // 3) * k + dy, c)
            x += 4 * k
        return x
    def save(s, path):
        out = bytearray()
        for row in s.p:
            for c in row: out += bytes(c + (255,))
        save_rgba(path, s.w, s.h, bytes(out))

def load(path):
    w, h, rows = read_png(path)
    return w, h, rows

def frame_rows(rows, w, h, f, fw):
    return [row[f * fw * 4:(f + 1) * fw * 4] for row in rows]

def nine_slice(frame_rows_, fs, m, tw, th, fill):
    """assemble a frame of tw x th from a fs x fs 9-slice with margins m: corners as they are, edges tiled, centre flat."""
    out = [[None] * tw for _ in range(th)]
    def px(x, y):
        r, g, b, a = frame_rows_[y][x * 4:x * 4 + 4]
        return (r, g, b) if a else None
    for y in range(th):
        for x in range(tw):
            sx = x if x < m else (fs - (tw - x)) if x >= tw - m else m + (x - m) % (fs - 2 * m)
            sy = y if y < m else (fs - (th - y)) if y >= th - m else m + (y - m) % (fs - 2 * m)
            out[y][x] = px(sx, sy)
    return out

FILL = {'standard': (42, 47, 55), 'scrap': (19, 22, 27), 'neon': (22, 27, 46)}

def mock_hall(sh, ox, oy, var, name, k=3):
    suf = '' if var == 'standard' else '_' + var
    fw_, fh_, fr = load(ART + '/ui/hall_frame%s.png' % suf)
    gw, gh, gr = load(ART + '/ui/hall_frame%s_glow.png' % suf)
    cw, ch, cr = load(ART + '/ui/hall_crest%s.png' % suf)
    pw, ph, pr = load(ART + '/ui/hall_plate%s.png' % suf)
    bw, bh, br = load(ART + '/ui/hall_bg.png')
    TW, TH = 112, 80
    ns = nine_slice(fr, 96, 24, TW, TH, None)
    gl = nine_slice(gr, 96, 24, TW, TH, None)
    # the display: backdrop tile inside the opening, a ship silhouette on it
    canvas = [[None] * TW for _ in range(TH)]
    for y in range(TH):
        for x in range(TW):
            canvas[y][x] = ns[y][x]
    for y in range(12, TH - 12):
        for x in range(12, TW - 12):
            if ns[y][x] == FILL[var]:
                r, g, b, a = br[(y - 12) % bh][((x - 12) % bw) * 4:((x - 12) % bw) * 4 + 4]
                canvas[y][x] = (r, g, b)
    # a ship silhouette (plan view, a scrap hull): a flat light shape with a rim, drawn into the opening
    import ships_td
    from ill import Ill, Glow, poly_cells
    sil = Ill(TW, TH, '.'); g0 = Glow(TW, TH)
    if var == 'scrap': ships_td.scrap(sil, g0, TW // 2 + 4, TH // 2, 0, 66, 0, seed=3)
    elif var == 'neon': ships_td.lumen_td(sil, g0, TW // 2 + 4, TH // 2, 0, 66, 0)
    else: ships_td.concord(sil, g0, TW // 2 + 4, TH // 2, 0, 66, 0)
    for y in range(TH):
        for x in range(TW):
            c = sil.g[y][x]
            if c != '.' and 12 <= x < TW - 12 and 12 <= y < TH - 12: canvas[y][x] = pal_endings.RGB[c]
    # the glow on top (additive)
    for y in range(TH):
        for x in range(TW):
            r, g, b, a = gl[y][x] if isinstance(gl[y][x], tuple) and len(gl[y][x]) == 4 else (0, 0, 0, 0)
    for y in range(TH):
        for x in range(TW):
            pass
    for y in range(TH):
        for x in range(TW):
            c = canvas[y][x]
            if c is not None:
                for dy in range(k):
                    for dx in range(k): sh.put(ox + x * k + dx, oy + y * k + dy, c)
    # frame glow: read the glow rows through the same 9-slice (alpha lives in the 4th channel; nine_slice returns rgb only), so add the corner glows directly
    for (cx_, cy_) in ((12, 12), (TW - 12, 12), (12, TH - 12), (TW - 12, TH - 12)):
        add_glow(sh, ox + cx_ * k, oy + cy_ * k, 13 * k, {'standard': (255, 210, 58), 'scrap': (255, 138, 30), 'neon': (60, 242, 255)}[var], 0.5)
    # the crest on the top edge (bottom centre 2 px into the border) and the plate under the frame
    sh_blit_rgba(sh, cr, cw, ch, ox + (TW * k - cw * k) // 2, oy - (ch - 2) * k, k)
    PWT = 84
    # plate: caps 12 + tiled middle (it is a flat strip) of width PWT
    plate_rows = []
    for y in range(ph):
        row = []
        for x in range(PWT):
            sx = x if x < 12 else (pw - (PWT - x)) if x >= PWT - 12 else 12 + (x - 12) % (pw - 24)
            row.append(pr[y][sx * 4:sx * 4 + 4])
        plate_rows.append(b''.join(row))
    sh_blit_rgba(sh, plate_rows, PWT, ph, ox + (TW * k - PWT * k) // 2, oy + TH * k + 2 * k, k)
    sh.text(ox + (TW * k - len(name) * 8) // 2, oy + TH * k + 2 * k + 8 * k - 4, name, TXT, 2)

def sh_blit_rgba(sh, rows, w, h, x, y, k):
    for j in range(h):
        for i in range(w):
            r, g, b, a = rows[j][i * 4:i * 4 + 4]
            if a == 0: continue
            for dy in range(k):
                for dx in range(k): sh.put(x + i * k + dx, y + j * k + dy, (r, g, b))

def add_glow(sh, cx, cy, rad, col, a):
    for y in range(cy - rad, cy + rad + 1):
        for x in range(cx - rad, cx + rad + 1):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / rad
            if d >= 1 or not (0 <= x < sh.w and 0 <= y < sh.h): continue
            t = (1 - d) ** 1.8 * a
            r, g, b = sh.p[y][x]
            sh.p[y][x] = (min(255, int(r + col[0] * t)), min(255, int(g + col[1] * t)), min(255, int(b + col[2] * t)))

def mock_score(sh, ox, oy, k=3):
    """a score panel with the ornaments: banner, divider, corner brackets, laurels round a number, pips, a seal."""
    aw, ah, ar = load(ART + '/ui/score_ornaments.png')
    regs = json.load(open(ART + '/ui/score_ornaments.json'))['regions']
    PW_, PH_ = 140, 88
    # panel: dark slate with a light border (like the UI kit)
    for y in range(PH_ * k):
        for x in range(PW_ * k):
            edge = x < 2 * k or y < 2 * k or x >= (PW_ - 2) * k or y >= (PH_ - 2) * k
            sh.put(ox + x, oy + y, (207, 214, 223) if edge else (31, 38, 48))
    def piece(name, x, y, flip=False):
        r = regs[name]
        for j in range(r[3]):
            for i in range(r[2]):
                cr_, cg, cb, ca = ar[r[1] + j][(r[0] + i) * 4:(r[0] + i) * 4 + 4]
                if ca == 0: continue
                for dy in range(k):
                    for dx in range(k): sh.put(ox + (x + i) * k + dx, oy + (y + j) * k + dy, (cr_, cg, cb))
    # corner brackets
    piece('corner_tl', 4, 4); piece('corner_tr', PW_ - 20, 4); piece('corner_bl', 4, PH_ - 20); piece('corner_br', PW_ - 20, PH_ - 20)
    # banner with the title
    bx, by = 14, 8
    piece('banner_l', bx, by)
    for t in range(0, 12): piece('banner_mid', bx + 16 + t * 8, by) if t < 8 else None
    piece('banner_r', bx + 16 + 8 * 8, by)
    sh.text(ox + (bx + 24) * k, oy + (by + 7) * k, 'THE HAVEN', (19, 22, 27), 2)
    # divider
    dy_ = 32
    piece('divider_l', 10, dy_)
    for t in range(0, 4): piece('divider_mid', 26 + t * 8, dy_)
    piece('divider_c', 10 + 16 + 32, dy_)
    for t in range(0, 4): piece('divider_mid', 10 + 16 + 32 + 24 + t * 8, dy_) if t < 2 else None
    piece('divider_r', PW_ - 26, dy_)
    # score with laurels
    piece('laurel_l', 34, 40); piece('laurel_r', PW_ - 54, 40)
    sh.text(ox + 52 * k, oy + 54 * k, '4820', (255, 210, 58), 3)
    sh.text(ox + 54 * k, oy + 70 * k, 'SCORE', (163, 172, 184), 2)
    for i in range(5): piece('pip_on' if i < 4 else 'pip_off', 50 + i * 12, 78)
    piece('seal', 8, 44)

def main(out):
    ids = ['haven_settle', 'haven_exodus', 'haven_lure', 'wayout_concord', 'wayout_clans', 'wayout_lumen', 'hollow_truth', 'retire']
    names = {'haven_settle': 'HAVEN: SETTLE', 'haven_exodus': 'HAVEN: EXODUS', 'haven_lure': 'HAVEN: THE LURE', 'wayout_concord': 'WAY OUT: CONCORD',
             'wayout_clans': 'WAY OUT: CLANS', 'wayout_lumen': 'WAY OUT: LUMEN', 'hollow_truth': 'THE HOLLOW', 'retire': 'RETIRE'}
    SW = 1320
    sh_h = 40 + 4 * (360 + 24) + 40 + 8 * (180 + 22) + 40 + 2 * (180 + 22) + 60 + 400 + 380 + 80
    sh = Sheet(SW, sh_h)
    y = 8
    sh.text(10, y, 'HULLSCRAP ENDING ART: 320X180 AT 2X (SHOWN WITH THE GLOW LAYER ADDED), 8 ILLUSTRATIONS', AMB, 2)
    y += 28
    meta = {}
    data = {}
    for id_ in ids:
        w, h, rows = load('%s/%s.png' % (OUT, id_))
        gw, gh, grows = load('%s/%s_glow.png' % (OUT, id_))
        J = json.load(open('%s/%s.json' % (OUT, id_)))
        data[id_] = (w, h, rows, gw, gh, grows, J)
    for n, id_ in enumerate(ids):
        w, h, rows, gw, gh, grows, J = data[id_]
        x = 10 + (n % 2) * 650
        yy = y + (n // 2) * 384
        sh.blit_glow(frame_rows(rows, w, h, 0, 320), frame_rows(grows, gw, gh, 0, 320), 320, 180, x, yy, 2)
        sh.text(x, yy + 364 - 2, names[id_], TXT, 2)
    y += 4 * 384 + 12
    sh.text(10, y, 'ALL 4 FRAMES OF EACH (1X, GLOW ADDED): LIGHTS BLINK, STARS TWINKLE, THINGS MOVE', AMB, 2)
    y += 22
    for id_ in ids:
        w, h, rows, gw, gh, grows, J = data[id_]
        n = w // 320
        for f in range(n):
            sh.blit_glow(frame_rows(rows, w, h, f, 320), frame_rows(grows, gw, gh, f, 320), 320, 180, 10 + f * 325, y, 1)
        sh.text(1306 - len(names[id_]) * 8, y + 2, '', TXT, 2)
        y += 180 + 4
        sh.text(10, y, names[id_] + '  ' + str(n) + ' FRAMES AT ' + str(J['anims']['on'][2]) + ' FPS', (163, 172, 184), 1)
        y += 14
    y += 8
    sh.text(10, y, 'THE GLOW LAYERS ALONE (FRAME 0, SOFT ALPHA, SHOWN OVER BLACK)', AMB, 2)
    y += 22
    for n, id_ in enumerate(ids):
        w, h, rows, gw, gh, grows, J = data[id_]
        x = 10 + (n % 4) * 325
        yy = y + (n // 4) * 184
        for j in range(180):
            for i in range(320):
                r, g, b, a = grows[j][i * 4:i * 4 + 4]
                t = a / 255.0
                sh.put(x + i, yy + j, (int(r * t), int(g * t), int(b * t)))
    y += 2 * 184 + 10
    sh.text(10, y, 'THE HALL OF SHIPS FRAME (9-SLICE, 3 LINES), CREST AND NAMEPLATE, AND A SCORE PANEL WITH THE ORNAMENTS (3X)', AMB, 2)
    y += 96
    for n, (var, name) in enumerate((('standard', 'CS-114 DILIGENCE'), ('scrap', 'SECOND MORTGAGE'), ('neon', 'AFTERIMAGE'))):
        mock_hall(sh, 10 + n * 360, y, var, name, 3)
    y += 80 * 3 + 80
    mock_score(sh, 10, y, 3)
    # the kit pieces at 4x next to the score panel
    kx = 10 + 140 * 3 + 30
    sh.text(kx, y, 'THE FRAME KIT, 4X: FRAME (3 LINES)', TXT, 2)
    for n, suf in enumerate(('', '_scrap', '_neon')):
        w, h, rows = load(ART + '/ui/hall_frame%s.png' % suf)
        sh.blit(rows, w, h, kx + n * 210, y + 22, 2)
    sh.text(kx, y + 22 + 96 * 2 + 12, 'CRESTS, NAMEPLATES AND THE BLUEPRINT TILE (4X)', TXT, 2)
    for n, suf in enumerate(('', '_scrap', '_neon')):
        w, h, rows = load(ART + '/ui/hall_crest%s.png' % suf)
        sh.blit(rows, w, h, kx + n * 112, y + 22 + 96 * 2 + 32, 2)
        w, h, rows = load(ART + '/ui/hall_plate%s.png' % suf)
        sh.blit(rows, w, h, kx + 346 + n * 106, y + 22 + 96 * 2 + 36, 2)
    w, h, rows = load(ART + '/ui/hall_bg.png')
    sh.blit(rows, w, h, kx + 346 + 3 * 106, y + 22 + 96 * 2 + 32, 2)
    sh.text(kx, y + 22 + 96 * 2 + 32 + 70, 'ORNAMENT ATLAS (DIVIDERS, CORNERS, PIPS, LAURELS, SEAL, BANNER), 3X', TXT, 2)
    w, h, rows = load(ART + '/ui/score_ornaments.png')
    sh.blit(rows, w, h, kx, y + 22 + 96 * 2 + 32 + 92, 3)
    sh.h = min(sh.h, y + 22 + 96 * 2 + 32 + 92 + 96 * 3 + 20)
    sh.p = sh.p[:sh.h]
    sh.save(out)
    print('sheet', sh.w, sh.h)

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '/home/user/hs/shots/art_endings_sheet.png')
