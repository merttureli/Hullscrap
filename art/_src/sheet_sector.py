"""Preview sheet for the sector art, at 3x: a mock "Raft in space" scene (hull edge, bow intake pulling debris, tractor beam, radar dish, drifting debris on the backdrop, HUD icons at the edge),
then every sprite with all its frames labelled, then all the debris at 1x on dark space.  Usage: python3 sheet_sector.py [out.png]"""
import sys, os, json, math
from px import *
import pal_sector
from build import read_png
from sheet_v2 import text
import space_bg, debris, sector_fx, poi_icons, mview
from sheet_weapons import wall_rows, floor_bg, rot_barrel
from wbase import FLANGE
import sector_all

SPACE = (11, 14, 24)
K = 3
def hexrgb(h): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))

def load(rel):
    w, h, rows = read_png(os.path.join(ART, rel))
    o = Rgba(w, h)
    for y in range(h):
        for x in range(w): o.p[y][x] = list(rows[y][x * 4:x * 4 + 4])
    return o
def meta(rel): return json.load(open(os.path.join(ART, rel[:-4] + '.json')))
def split(o, fw, fh):
    out = []
    for r in range(o.h // fh):
        for c in range(o.w // fw):
            f = Rgba(fw, fh)
            for y in range(fh):
                for x in range(fw): f.p[y][x] = list(o.p[r * fh + y][c * fw + x])
            out.append(f)
    return out
class Sheet:
    """a sprite file read back from art/: frames, glow frames and the animation table."""
    def __init__(s, rel):
        s.rel = rel; s.J = meta(rel); s.fr = split(load(rel), *s.J['frame']); s.dir = os.path.dirname(rel)
        g = s.J.get('glow'); s.gl = split(load(s.dir + '/' + g['image']), *g['frame']) if g else None
    def get(s, anim, i=0):
        st, cnt, _ = s.J['anims'][anim]
        g = s.J.get('glow', {}).get('anims', {}).get(anim)
        return s.fr[st + i % cnt], (s.gl[g[0] + i % g[1]] if g else None)
    @property
    def goff(s): return s.J['glow']['offset'] if s.gl else (0, 0)

def blit(dst, f, x, y, add=False): dst.blit_rgba(f, x, y, 1, add=add)
def blit_glow(dst, sh, anim, i, x, y):
    f, g = sh.get(anim, i)
    if g is not None: blit(dst, g, x + sh.goff[0], y + sh.goff[1], add=True)

def tiled_layer(dst, layer, ox, oy, tint=None):
    w, h = dst.w, dst.h
    for y0 in range(-(oy % 256), h, 256):
        for x0 in range(-(ox % 256), w, 256):
            for j in range(256):
                yy = y0 + j
                if not (0 <= yy < h): continue
                for i in range(256):
                    p = layer.p[j][i]
                    if p[3] and 0 <= x0 + i < w: dst.over(x0 + i, yy, tuple(p))

def nebula_over(dst, key, x, y, scale=1):
    neb = space_bg.nebula(key); t = hexrgb(space_bg.NEB[key][4])
    for j in range(0, 512):
        for i in range(0, 512):
            p = neb.p[j][i]
            if p[3] == 0: continue
            c = (p[0] * t[0] // 255, p[1] * t[1] // 255, p[2] * t[2] // 255, p[3])
            xx, yy = x + i // scale, y + j // scale
            if 0 <= xx < dst.w and 0 <= yy < dst.h: dst.over(xx, yy, c)

# ------------------------------------------------------------------ the mock scene (built at 1x, shown at 3x)
def mock_scene(nebulas):
    W, H = 800, 300
    img = Rgba(W, H, SPACE + (255,))
    wy = 196                                                                     # top of the 2-row hull wall
    nebula_over(img, 'concord', 40, -120, 1)
    nebula_over(img, 'lumen', 380, -170, 1)
    tiled_layer(img, space_bg.stars_far(), 0, 0); tiled_layer(img, space_bg.stars_mid(), 70, 30); tiled_layer(img, space_bg.stars_near(), 30, 90)
    deb = {n: Sheet('debris/%s.png' % n) for n in ('scrap_chunk_s', 'scrap_chunk_m', 'copper_coil', 'polymer_barrel', 'ice_chunk_s', 'ice_chunk_m', 'titanium_plate', 'silicon_rock', 'crystal_shard',
                                                    'plasma_canister', 'sealed_crate', 'ore_rock_s', 'ore_rock_l', 'dead_drone', 'fuel_canister', 'fragment')}
    def put(n, cx, cy, frame=0, anim='tumble'):
        sh = deb[n]; f, g = sh.get(anim, frame); x, y = cx - f.w // 2, cy - f.h // 2
        blit(img, f, x, y)
        if g is not None: blit(img, g, x + sh.goff[0], y + sh.goff[1], add=True)
    # drifting debris, back to front
    for (n, cx, cy, fr) in (('ore_rock_l', 90, 44, 1), ('silicon_rock', 210, 62, 2), ('sealed_crate', 318, 30, 0), ('ice_chunk_m', 548, 40, 2), ('dead_drone', 650, 86, 1), ('titanium_plate', 726, 30, 1),
                            ('plasma_canister', 592, 118, 2), ('crystal_shard', 40, 124, 1), ('ore_rock_s', 700, 148, 3), ('fuel_canister', 150, 150, 0), ('scrap_chunk_m', 336, 52, 2), ('ice_chunk_s', 760, 120, 0),
                            ('polymer_barrel', 520, 94, 3), ('scrap_chunk_s', 60, 70, 3), ('titanium_plate', 440, 24, 3),
                            ('ice_chunk_s', 262, 128, 1), ('scrap_chunk_s', 296, 104, 2), ('polymer_barrel', 232, 108, 1), ('crystal_shard', 372, 120, 2), ('ice_chunk_s', 346, 96, 3), ('scrap_chunk_m', 62, 150, 1), ('ice_chunk_s', 428, 150, 1)):
        put(n, cx, cy, fr)
    for (cx, cy, v) in ((300, 96, 0), (322, 80, 1), (360, 118, 2), (30, 170, 3), (748, 176, 1)):
        f = split(load('debris/fragment.png'), 8, 8)[v]; blit(img, f, cx, cy)
    # the hull: a wall band, the interior floor and the mounts
    floor_bg(img, wy + 32, H)
    img.blit_spr(wall_rows(W, 2), 0, wy)
    mounts = {}
    def mount(cid, x_in, out_w, x_out=None, ostate='on', oi=0, istate='on', ii=0, deg=None, bstate='idle', bi=0):
        c = [C for C in sector_all.MOUNTS if C().id == cid][0]()
        oc, ic = Sheet('components/%s_out.png' % cid), Sheet('components/%s.png' % cid)
        x_out = x_in + (c.w - out_w) // 2 if x_out is None else x_out
        oy = wy - 32
        fo, _ = oc.get(ostate, oi); blit(img, fo, x_out, oy)
        fi, _ = ic.get(istate, ii); iy = wy + 32 - FLANGE; blit(img, fi, x_in, iy)
        if deg is not None and c.has_barrel:
            b = c.barrel_frame(bstate, bi); r, h = rot_barrel(c, b, deg)
            img.blit_spr(r, x_out + c.pivot[0] - h, oy + c.pivot[1] - h)
            if bstate != 'disabled':
                gg = c.barrel_glow_frame(bstate, bi); px_, py_ = c.bpivot_final(); pd = c.bpad
                if deg == 0: blit(img, gg, x_out + c.pivot[0] - px_ - pd, oy + c.pivot[1] - py_ - pd, add=True)
        blit_glow(img, oc, ostate, oi, x_out, oy); blit_glow(img, ic, istate, ii, x_in, iy)
        return c, x_out, oy
    mount('net_mouth_scrap', 40, 32, ostate='pulling', oi=3, istate='pulling', ii=3)
    c3, xo, yo = mount('intake_mk2', 246, 64, ostate='pulling', oi=2, istate='pulling', ii=2)
    ct, xt, yt = mount('tractor_mk1', 120, 64, istate='fire', ii=0, deg=0, bstate='fire', bi=2, ostate='on')
    mount('lumen_siphon_neon', 340, 64, ostate='pulling', oi=4, istate='pulling', ii=4)
    mount('radar_mk2', 470, 32, ostate='on', oi=0, istate='on', ii=2, deg=38)
    mount('listening_horn_scrap', 600, 32, ostate='on', oi=1, istate='on', ii=5, deg=-25)
    mount('lumen_eye_neon', 690, 32, ostate='on', oi=0, istate='on', ii=6, deg=62)
    # the tractor beam: tiled up from the turret head to a copper coil
    tb = Sheet('projectiles/tractor_beam.png'); fb, gb = tb.get('pull', 1)
    mx, my = xt + 32, yt + 15 - 24
    for k in range(7):
        y = my - 16 * (k + 1)
        if y < 70: break
        blit(img, fb, mx - 6, y); blit(img, gb, mx - 6 + tb.goff[0], y, add=True)
    cc = deb['copper_coil']; f, g = cc.get('tumble', 2); blit(img, f, mx - 8, 58)
    # HUD: edge markers (icon, distance) round the top and sides
    pi = Sheet('ui/poi_icons.png')
    marks = (('distress', 118, 4, '2.4K'), ('quest', 250, 4, '5.1K'), ('station', 384, 4, '3.0K'), ('mining_field', 530, 4, '6.8K'), ('pirate_nest', 770, 22, '7.7K'),
             ('wreck', 4, 60, '1.9K'), ('anomaly', 4, 110, '9.2K'), ('concord_checkpoint', 780, 90, '4.4K'), ('contact', 4, 150, '??'), ('course', 780, 140, '3.3K'), ('store', 650, 4, '4.0K'),
             ('trader', 200, 4, '2.8K'), ('unknown', 460, 4, '--'), ('abandoned_station', 4, 28, '8.0K'))
    for (n, x, y, dist) in marks:
        f, g = pi.get(n); blit(img, f, x, y); blit(img, g, x - 4, y - 4, add=True)
        text(img, x + (18 if x < 700 else -18 - 4 * len(dist) + 1), y + 5, dist, 'M', 1)
    return img

# ------------------------------------------------------------------ the sheet
def label(img, x, y, s, col='H', k=3): text(img, x, y, s, col, k)

def grid_frames(img, items, x0, y0, W, K=3, gap=10, lab=True):
    """items: [(label, Rgba frame, Rgba glow or None, glow offset)] laid out in rows; returns the y after the last row."""
    pad = max([max(0, -it[3][1]) for it in items if it[2] is not None] + [0]) * K          # headroom for glows that spill above the frame
    y = y0 + pad
    x, rh = x0, 0
    for (lbl, f, g, goff) in items:
        w, h = f.w * K, f.h * K + (14 if lab else 0)
        if x + w + 12 > W: x = x0; y += rh + gap + pad; rh = 0
        # a dark space patch behind, so glows read
        for j in range(f.h * K):
            for i in range(f.w * K): img.p[y + j][x + i] = list(SPACE) + [255]
        img.blit_rgba(f.scaled(K), x, y, 1)
        if g is not None: img.blit_rgba(g.scaled(K), x + goff[0] * K, y + goff[1] * K, 1, add=True)
        if lab: text(img, x, y + f.h * K + 2, lbl, 'M', 2)
        x += w + gap; rh = max(rh, h)
    return y + rh + gap

def sheet_items(rel, names=None):
    sh = Sheet(rel); items = []
    for nm, (st, cnt, fps) in sh.J['anims'].items():
        if names and nm not in names: continue
        g = sh.J.get('glow', {}).get('anims', {}).get(nm)
        for q in range(cnt):
            items.append(('%s %d' % (nm, q) if cnt > 1 else nm, sh.fr[st + q], sh.gl[g[0] + q] if g and sh.gl else None, sh.goff))
    return items

class Page:
    """the sheet is long: draw into a moderate canvas and flush finished rows to bytes, so memory stays small."""
    HMAX = 1500
    def __init__(s, W): s.W = W; s.rows = []; s.new()
    def new(s): s.img = Rgba(s.W, s.HMAX, RGB['F'] + (255,))
    def fit(s, y, need):
        if y + need > s.HMAX:
            for r in s.img.p[:y]: s.rows.append(b''.join(bytes(v for v in p) for p in r))
            s.new(); y = 0
        return s.img, y
    def finish(s, y, path):
        for r in s.img.p[:y]: s.rows.append(b''.join(bytes(v for v in p) for p in r))
        h = len(s.rows)
        save_rgba(path, s.W, h, b''.join(s.rows))
        return s.W, h

def build(path, W=2400):
    pg = Page(W)
    img, y = pg.fit(0, 1200)
    scene = mock_scene(None)
    y = 14
    label(img, 20, y, 'SECTOR SPACE: RAFT IN SPACE (MOCK SCENE, 3X): BOW INTAKES PULL DRIFTING DEBRIS, TRACTOR BEAM, RADAR DISHES TURNING, HUD EDGE MARKERS', 'H', 4); y += 36
    img.blit_rgba(scene.scaled(3), 20, y, 1); y += scene.h * 3 + 30
    # ---- debris
    img, y = pg.fit(y, 300)
    label(img, 20, y, 'DEBRIS: 4 TUMBLE FRAMES EACH (+ GLOW WHERE IT EMITS), BROKEN / CRACKED FRAMES AT THE END', 'H', 4); y += 34
    for O in debris.OBJS:
        img, y = pg.fit(y, 300)
        rel = 'debris/%s.png' % O.id
        label(img, 20, y, '%s  %dX%d' % (O.id, O.W, O.H), 'L', 3); y += 22
        y = grid_frames(img, sheet_items(rel), 20, y, W - 20, K) + 6
    img, y = pg.fit(y, 120)
    label(img, 20, y, 'fragment 8X8 x 4 VARIANTS (NEUTRAL GREYS, TINT THEM)', 'L', 3); y += 22
    y = grid_frames(img, sheet_items('debris/fragment.png'), 20, y, W - 20, 6) + 12
    # ---- mounts
    for C in sector_all.MOUNTS:
        c = C()
        img, y = pg.fit(y, 1300)
        label(img, 20, y, '%s  INSIDE %dX%d  OUTSIDE %dX%d%s' % (c.id, c.cells[0], c.cells[1], c.out_cells[0], c.out_cells[1], '  + BARREL' if c.has_barrel else ''), 'H', 4); y += 34
        y = grid_frames(img, sheet_items('components/%s.png' % c.id), 20, y, W - 20, K) + 4
        y = grid_frames(img, sheet_items('components/%s_out.png' % c.id), 20, y, W - 20, K) + 4
        if c.has_barrel:
            bsh = Sheet('components/%s_out.png' % c.id)
            B = bsh.J['barrel']; bs = split(load('components/' + B['image']), *B['frame'])
            bg = split(load('components/' + B['glow']['image']), *B['glow']['frame']) if 'glow' in B else None
            items = []
            for nm, (st, cnt, fps) in B['anims'].items():
                ga = B.get('glow', {}).get('anims', {}).get(nm)
                for q in range(cnt): items.append((nm + (' %d' % q if cnt > 1 else ''), bs[st + q], bg[ga[0] + q] if ga and bg else None, B['glow']['offset'] if bg else (0, 0)))
            y = grid_frames(img, items, 20, y, W - 20, K) + 4
        # the mount through a wall in five states (barrel turned)
        d = mview.data(C)
        x = 20; sh = 0
        for (os_, oi, is_, ii, deg) in (('on', 0, 'on', 0, 0), ('pulling' if 'pulling' in d[3][2]['anims'] else 'on', 2, 'pulling' if 'pulling' in d[2][2]['anims'] else ('fire' if 'fire' in d[2][2]['anims'] else 'on'), 2, 40),
                                        ('damaged', 0, 'damaged', 0, -30), ('disabled', 0, 'disabled', 0, 0), ('off', 0, 'off', 0, 0)):
            a = mview.scene(d[0], d[1], d[2], d[3], os_, oi, is_, ii, bstate=('idle' if c.has_barrel and os_ not in ('damaged', 'disabled') else os_ if c.has_barrel else None), deg=deg, top=max(30, d[1].glow_pad[1] + 6))
            img.blit_rgba(a.scaled(K), x, y, 1); x += a.w * K + 12; sh = max(sh, a.h * K)
        y += sh + 26
    # ---- tractor beam, jump fx, icons, space
    img, y = pg.fit(y, 1000)
    label(img, 20, y, 'TRACTOR BEAM STRIP (TILED ALONG Y, 4 FRAMES) / JUMP SPOOL (8) / JUMP FLASH (6)', 'H', 4); y += 34
    tb = Sheet('projectiles/tractor_beam.png'); x = 20; yy = y
    for fi in range(4):
        f, g = tb.get('pull', fi)
        for r in range(6):
            img.blit_rgba(f.scaled(K), x + 4 * K, y + r * 16 * K, 1); img.blit_rgba(g.scaled(K), x + (4 + tb.goff[0]) * K, y + r * 16 * K, 1, add=True)
        text(img, x, y + 6 * 16 * K + 2, 'pull %d' % fi, 'M', 2); x += 100
    sp = Sheet('fx/jump_spool.png'); x0 = 480
    for i in range(8):
        f, g = sp.get('spool', i); bx, by = x0 + (i % 4) * 230, y + (i // 4) * 230
        for j in range(f.h * 2 + 32):
            for q in range(210): img.p[by + j][bx + q] = list(SPACE) + [255]
        img.blit_rgba(f.scaled(2), bx + 16, by + 16, 1); img.blit_rgba(g.scaled(2), bx + 16 + sp.goff[0] * 2, by + 16 + sp.goff[1] * 2, 1, add=True)
        text(img, bx + 4, by + 4, 'spool %d' % i, 'M', 2)
    fl = Sheet('fx/jump_flash.png')
    for i in range(6):
        f, g = fl.get('flash', i); bx, by = 1420 + (i % 3) * 320, y + (i // 3) * 320
        for j in range(f.h * 3 + 16):
            for q in range(300): img.p[by + j][bx + q] = list(SPACE) + [255]
        img.blit_rgba(f.scaled(3), bx + 6, by + 14, 1); img.blit_rgba(g.scaled(3), bx + 6 + fl.goff[0] * 3, by + 14 + fl.goff[1] * 3, 1, add=True)
        text(img, bx + 4, by + 2, 'flash %d' % i, 'M', 2)
    y += max(6 * 16 * K + 36 + 100, 2 * 320 + 40)
    img, y = pg.fit(y, 700)
    label(img, 20, y, 'POI ICONS 16X16 + GLOW (6X), THEN AT 1X', 'H', 4); y += 34
    pi = Sheet('ui/poi_icons.png'); x = 20
    for i, n in enumerate(pi.J['anims']):
        f, g = pi.get(n)
        for j in range(24 * 5):
            for q in range(150): img.p[y + j][x + q] = list(SPACE) + [255]
        img.blit_rgba(f.scaled(5), x + 20, y + 20, 1); img.blit_rgba(g.scaled(5), x, y, 1, add=True)
        text(img, x + 2, y + 24 * 5 - 14, n, 'M', 2)
        x += 154
        if x > W - 160: x = 20; y += 24 * 5 + 6
    y += 24 * 5 + 20
    x = 20
    for i, n in enumerate(pi.J['anims']):
        f, g = pi.get(n)
        for j in range(24):
            for q in range(24): img.p[y + j][x + q] = list(SPACE) + [255]
        img.blit_rgba(f, x + 4, y + 4, 1); img.blit_rgba(g, x, y, 1, add=True); x += 28
    y += 40
    img, y = pg.fit(y, 800)
    label(img, 20, y, 'SPACE LAYERS: STARS FAR / MID / NEAR DUST (256X256 TILES, 2X) AND THE FIVE NEBULAE (512X512 AT 1/2, TINTED)', 'H', 4); y += 34
    x = 20
    for n, fn in (('far', space_bg.stars_far), ('mid', space_bg.stars_mid), ('near', space_bg.stars_near)):
        L = fn()
        for j in range(256 * 2):
            for q in range(256 * 2): img.p[y + j][x + q] = list(SPACE) + [255]
        for j in range(256):
            for i in range(256):
                p = L.p[j][i]
                if p[3]:
                    for dy in range(2):
                        for dx in range(2): img.over(x + i * 2 + dx, y + j * 2 + dy, tuple(p))
        text(img, x + 4, y + 4, 'stars_' + n, 'M', 2); x += 530
    y += 256 * 2 + 20; x = 20
    for key in space_bg.NEB:
        for j in range(256):
            for q in range(256): img.p[y + j][x + q] = list(SPACE) + [255]
        neb = Sheet.__new__(Sheet)
        N = space_bg.nebula(key); t = hexrgb(space_bg.NEB[key][4])
        for j in range(0, 512, 2):
            for i in range(0, 512, 2):
                p = N.p[j][i]
                if p[3]: img.over(x + i // 2, y + j // 2, (p[0] * t[0] // 255, p[1] * t[1] // 255, p[2] * t[2] // 255, p[3]))
        text(img, x + 4, y + 4, 'nebula_' + key, 'M', 2); x += 270
    y += 256 + 20
    # ---- all debris at 1x on dark space
    img, y = pg.fit(y, 400)
    label(img, 20, y, 'ACTUAL SIZE 1X: ALL DEBRIS ON DARK SPACE (EVERY TUMBLE FRAME, GLOW ON), THEN WITH THE BACKDROP', 'H', 4); y += 34
    H1 = 150
    for j in range(H1):
        for q in range(W - 40): img.p[y + j][20 + q] = list(SPACE) + [255]
    x = 30
    for O in debris.OBJS:
        sh = Sheet('debris/%s.png' % O.id)
        names = ['tumble'] + [n for n in sh.J['anims'] if n not in ('tumble', 'cracked')]
        for nm in names:
            cnt = sh.J['anims'][nm][1]
            for q in range(cnt):
                f, g = sh.get(nm, q)
                if x + f.w > W - 30: break
                yy = y + 10 + (48 - f.h) // 2 if False else y + 10
                blit(img, f, x, y + 10)
                if g is not None: blit(img, g, x + sh.goff[0], y + 10 + sh.goff[1], add=True)
                x += f.w + 4
        x += 12
    fr = split(load('debris/fragment.png'), 8, 8)
    for f in fr: blit(img, f, x, y + 10); x += 10
    y += H1 + 10
    # the same debris over the backdrop layers
    for j in range(H1):
        for q in range(W - 40): img.p[y + j][20 + q] = list(SPACE) + [255]
    bgs = Rgba(W - 40, H1, SPACE + (255,))
    tiled_layer(bgs, space_bg.stars_far(), 0, 0); tiled_layer(bgs, space_bg.stars_mid(), 60, 20); tiled_layer(bgs, space_bg.stars_near(), 10, 70)
    img.blit_rgba(bgs, 20, y, 1)
    x = 30
    for O in debris.OBJS:
        sh = Sheet('debris/%s.png' % O.id); f, g = sh.get('tumble', 1)
        if x + f.w > W - 30: break
        blit(img, f, x, y + 10)
        if g is not None: blit(img, g, x + sh.goff[0], y + 10 + sh.goff[1], add=True)
        x += f.w + 12
    y += H1 + 24
    return pg.finish(y, path)

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else PREVIEW + '/sector_sheet.png'
    print(build(out))
