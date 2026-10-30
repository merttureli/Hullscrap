"""Build every structure / fx / projectile sprite into art/ (PNG + JSON). Run:  python3 art/_src/build.py
Stdlib only. Every hard-pixel PNG uses palette colours only; glow layers (and the heat shimmer) are palette hues with alpha."""
import os, sys, zlib, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import *
import tiles as T, fx as X, projectiles as P

ART = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALPHA_OK = set()          # files allowed to carry partial alpha (glow layers, overlays)


def out_spr(rel, frames, meta):
    st = strip(frames) if isinstance(frames, list) else frames
    save_spr(st, os.path.join(ART, rel + '.png'))
    save_json(os.path.join(ART, rel + '.json'), meta)


def out_glow(rel, frames):
    save_png(os.path.join(ART, rel + '.png'), len(frames) * frames[0].w, frames[0].h, strip_rgba(frames).bytes())
    ALPHA_OK.add(rel + '.png')


def glow_meta(image, w, h, off, anims, **extra):
    d = {'image': image, 'frame': [w, h], 'offset': list(off), 'anims': anims, 'blend': 'add (preferred) or alpha-over'}
    d.update(extra)
    return d


def halo_tile_y(spr, pad, bands, src):
    """glow for a segment that tiles along y: compute on three stacked copies, keep the middle one (seamless)."""
    w, h = spr.w, spr.h
    st = Spr(w, h * 3)
    for k in range(3): st.stamp(0, k * h, spr.rows())
    g = halo(st, w + 2 * pad, h * 3, pad, 0, bands=bands, src=src)
    o = Rgba(w + 2 * pad, h)
    for y in range(h):
        for x in range(w + 2 * pad): o.p[y][x] = list(g.p[h + y][x])
    return o


def build():
    # ---------------------------------------------------------------- tiles
    fl = T.floor_variants()
    out_spr('tiles/floor', fl, {
        'frame': [16, 16], 'cells': [1, 1], 'variants': 3, 'anims': {'v0': [0, 1, 0], 'v1': [1, 1, 0], 'v2': [2, 1, 0]},
        'notes': 'Three seamless floor variants. Each has the 1px tile seam on its top and left edge, so any mix tiles cleanly. Pick one per cell by a position hash; v0 is the plain one, so use it most.'})
    mask_note = 'Autotile by 4-neighbour mask: frame index = N*1 + E*2 + S*4 + W*8, each bit set when that neighbour is also solid. Walls fill their whole cell; open sides get the near-black outline, convex corners are chamfered (transparent corner pixels).'
    out_spr('tiles/walls', T.autotile(T.wall_standard), {
        'frame': [16, 16], 'cells': [1, 1], 'autotile': 'mask4', 'mask': {'N': 1, 'E': 2, 'S': 4, 'W': 8}, 'frames': 16, 'notes': mask_note})
    out_spr('tiles/walls_armor', T.autotile(T.wall_armor), {
        'frame': [16, 16], 'cells': [1, 1], 'autotile': 'mask4', 'mask': {'N': 1, 'E': 2, 'S': 4, 'W': 8}, 'frames': 16, 'tint': 'multiply',
        'notes': mask_note + ' Heavier armour plate in neutral greys: multiply the material colour over it.'})
    df = T.door_frames()
    door_lights = []
    for i, f in enumerate(df):
        m = Spr(32, 16)
        for y in range(16):
            for x in range(32):
                c = f.get(x, y)
                if c == 'r' or (c == 'a' and 5 <= x <= 26): m.put(x, y, c)
        door_lights.append(halo(m, 36, 20, 2, 2, bands=((1.3, 95), (2.6, 45)), src='ar'))
    out_glow('tiles/door_glow', door_lights)
    out_spr('tiles/door', df, {
        'frame': [32, 16], 'cells': [2, 1], 'orientation': 'horizontal: the long axis runs along the wall; the game rotates the piece for a vertical wall',
        'anims': {'open': [0, 5, 10], 'closed': [0, 1, 0], 'opened': [4, 1, 0], 'locked': [5, 1, 0], 'broken': [6, 1, 0]},
        'glow': glow_meta('door_glow.png', 36, 20, (-2, -2), {'on': [0, 7, 0]}, note='frame i of the glow goes with frame i of the door; amber leaf lights, red lamp when locked'),
        'anchors': {'opening_left': [5, 0], 'opening_right': [27, 0]},
        'notes': 'Frames 0-4 play closed -> open (play backwards to close). 5 = locked (red lamp), 6 = broken (bent leaf, jammed half open). Open frames leave the passage transparent so the floor shows. Same band profile as the wall tiles (row 0 near-black, row 1 lit lip, rows 14-15 shadow).'})
    out_spr('tiles/breach', T.breach_frames(), {
        'frame': [16, 16], 'cells': [1, 1], 'variants': 3, 'anims': {'a': [0, 1, 0], 'b': [1, 1, 0], 'c': [2, 1, 0]},
        'notes': 'Hull hole: jagged near-black hole, torn rim, bent flaps, soot and debris specks. Drawn over a wall or floor cell; pick a variant per cell by a position hash.'})
    cab_off, cab_on = T.cable_frames(False), T.cable_frames(True)
    out_spr('tiles/cable', cab_off, {
        'frame': [16, 16], 'cells': [1, 1], 'autotile': 'mask4', 'mask': {'N': 1, 'E': 2, 'S': 4, 'W': 8}, 'frames': 16,
        'powered': 'cable_on.png',
        'glow': glow_meta('cable_glow.png', 16, 16, (0, 0), {'on': [0, 16, 0]}, autotile='mask4'),
        'notes': 'Unpowered (dull) cable. cable_on.png is the powered version (green light strip), same 16-frame mask layout; draw cable_glow.png over it for the soft green glow. Ends and tees get a small junction plate.'})
    out_spr('tiles/cable_on', cab_on, {
        'frame': [16, 16], 'cells': [1, 1], 'autotile': 'mask4', 'mask': {'N': 1, 'E': 2, 'S': 4, 'W': 8}, 'frames': 16, 'notes': 'Powered cable, see cable.json.'})
    out_glow('tiles/cable_glow', [halo(f, 16, 16, 0, 0, bands=((1.1, 85), (2.3, 42), (3.6, 18)), src='g') for f in cab_on])

    # ---------------------------------------------------------------- fx
    fire = X.fire_frames()
    out_glow('fx/fire_glow', [halo(f, 24, 24, 4, 4, bands=((1.5, 75), (3.0, 40), (4.5, 18)), src='oy') for f in fire])
    out_spr('fx/fire', fire, {
        'frame': [16, 16], 'cells': [1, 1], 'mode': 'loop', 'anims': {'loop': [0, 4, 8]}, 'anchors': {'base': [8, 15]},
        'glow': glow_meta('fire_glow.png', 24, 24, (-4, -4), {'loop': [0, 4, 8]}),
        'notes': 'One burning cell: flat bold flames (yellow core, orange body, red tips), base on the bottom edge. Several fires in a row look right if each starts on a random frame.'})
    smoke = X.smoke_frames()
    out_spr('fx/smoke', smoke, {
        'frame': [16, 16], 'cells': [1, 1], 'mode': 'once', 'anims': {'play': [0, 4, 5]}, 'anchors': {'base': [8, 15]},
        'notes': 'Grey puff rising and thinning over 4 frames. Hard pixels; fade it with modulate alpha as it rises. Spawn staggered puffs for a smoke column.'})
    out_spr('fx/sparks', X.sparks_frames(), {
        'frame': [16, 16], 'cells': [1, 1], 'mode': 'once', 'anims': {'play': [0, 3, 12]}, 'anchors': {'center': [8, 8]},
        'notes': 'Electrical sparks bursting from the centre (white-yellow rays, then orange specks).'})
    ex = X.explosion_frames()
    out_glow('fx/explosion_glow', [halo(f, 48, 48, 8, 8, bands=((2.0, 110), (4.0, 62), (6.5, 28)), src='oyH') for f in ex[:6]] + [Rgba(48, 48) for _ in ex[6:]])
    out_spr('fx/explosion', ex, {
        'frame': [32, 32], 'cells': [2, 2], 'mode': 'once', 'anims': {'play': [0, 10, 14]}, 'anchors': {'center': [16, 16]},
        'glow': glow_meta('explosion_glow.png', 48, 48, (-8, -8), {'play': [0, 10, 14]}, note='the last four glow frames are empty'),
        'notes': 'Flat white core -> yellow -> orange -> lobes that open -> shards flying out -> embers. Scale up for bigger blasts; fragments are transparent-backed.'})
    mz = X.muzzle_frames()
    out_glow('fx/muzzle_glow', [halo(f, 26, 26, 5, 5, bands=((1.6, 90), (3.2, 46), (5.0, 20)), src='oyH') for f in mz])
    out_spr('fx/muzzle', mz, {
        'frame': [16, 16], 'cells': [1, 1], 'mode': 'once', 'anims': {'play': [0, 3, 24]}, 'anchors': {'muzzle': [8, 15]},
        'glow': glow_meta('muzzle_glow.png', 26, 26, (-5, -5), {'play': [0, 3, 24]}),
        'notes': 'Muzzle flash, faces UP (rotation 0): place the muzzle anchor on the weapon muzzle and rotate with the weapon.'})
    sh = X.shield_frames()
    sg = []
    for i, f in enumerate(sh):
        g = Rgba(32, 32)
        r = (5, 10, 15, 20)[i]
        def band(cells, col, a):                      # strongest band wins; colours never blend, so every pixel stays a palette hue
            for (x, y) in cells:
                if a > g.p[y][x][3]: g.p[y][x] = list(RGB[col]) + [a]
        band(X.skin(5.5, 1.5) & X.near(*X.IMPACT, 0, r - 1), 'b', 38)
        band(X.skin(3.6, 1.0) & X.near(*X.IMPACT, 0, r - 3), 'b', 56)
        band(X.skin(2.0, 0.6) & X.near(*X.IMPACT, r - 5, r + 1), 'c', 64)
        sg.append(g)
    out_glow('fx/shield_ripple_glow', sg)
    out_spr('fx/shield_ripple', sh, {
        'frame': [32, 32], 'cells': [2, 2], 'mode': 'once', 'anims': {'play': [0, 4, 12]}, 'anchors': {'impact': [16, 6]},
        'glow': glow_meta('shield_ripple_glow.png', 32, 32, (0, 0), {'play': [0, 4, 12]}, note='soft blue fill of the shield skin behind the ripple'),
        'notes': 'Arc of the shield skin rippling outward from the hit, 4 frames. Faces UP: the impact anchor is the apex of the arc; rotate so the apex points at the hit, with the arc bulging away from the ship.'})
    hs = X.shimmer_frames()
    save_png(os.path.join(ART, 'fx/heat_shimmer.png'), 48, 16, strip_rgba(hs).bytes()); ALPHA_OK.add('fx/heat_shimmer.png')
    save_json(os.path.join(ART, 'fx/heat_shimmer.json'), {
        'frame': [16, 16], 'cells': [1, 1], 'mode': 'loop', 'anims': {'loop': [0, 3, 6]}, 'alpha': True,
        'notes': 'Optional overlay for overheated parts: translucent dashes of pale heat climbing and wobbling. Alpha layer (palette hues, alpha 40-80). Tile it over the part, one frame step per tick.'})

    # ---------------------------------------------------------------- projectiles
    ls = P.laser_segment()
    out_glow('projectiles/laser_glow', [halo_tile_y(ls, 4, ((1.2, 100), (2.4, 55), (3.8, 24)), 'r')])
    li = P.laser_impact()
    out_glow('projectiles/laser_impact_glow', [halo(f, 24, 24, 4, 4, bands=((1.8, 95), (3.4, 48), (4.8, 20)), src='oyH') for f in li])
    out_spr('projectiles/laser', [ls], {
        'frame': [4, 16], 'length': 16, 'width': 4, 'orientation': 'up: travels towards the top of the image at rotation 0', 'tile': 'y', 'cells': [1, 1],
        'anims': {'loop': [0, 1, 0]}, 'anchors': {'head': [2, 0], 'tail': [2, 15]},
        'glow': glow_meta('laser_glow.png', 12, 16, (-4, 0), {'loop': [0, 1, 0]}, tile='y'),
        'impact': {'image': 'laser_impact.png', 'frame': [16, 16], 'anims': {'play': [0, 3, 18]}, 'anchor': [8, 8],
                   'glow': glow_meta('laser_impact_glow.png', 24, 24, (-4, -4), {'play': [0, 3, 18]})},
        'notes': 'Red beam with a white core, 16 long x 4 wide. Repeat the frame along y to any length (it joins seamlessly, glow too). Draw the impact flare at the hit point.'})
    out_spr('projectiles/laser_impact', li, {'frame': [16, 16], 'anims': {'play': [0, 3, 18]}, 'mode': 'once', 'anchors': {'center': [8, 8]}, 'notes': 'Hit flare for the laser; see laser.json.'})
    bf = P.bolt_frames()
    out_glow('projectiles/bolt_glow', [halo(f, 14, 20, 4, 4, bands=((1.5, 100), (3.0, 52), (4.6, 22)), src='yoH') for f in bf])
    out_spr('projectiles/bolt', bf, {
        'frame': [6, 12], 'orientation': 'up', 'anims': {'fly': [0, 4, 16]}, 'anchors': {'head': [3, 2], 'tail': [3, 11]},
        'glow': glow_meta('bolt_glow.png', 14, 20, (-4, -4), {'fly': [0, 4, 16]}),
        'notes': 'Glowing 6px pellet with a flickering tail (4 frames). Head anchor is the pellet centre.'})
    fk = P.flak_frames()
    out_glow('projectiles/flak_glow', [halo(f, 14, 16, 4, 4, bands=((1.4, 90), (2.8, 42)), src='oy') for f in fk])
    out_spr('projectiles/flak', fk, {
        'frame': [6, 8], 'orientation': 'up', 'anims': {'fly': [0, 2, 12]}, 'anchors': {'head': [3, 2], 'tail': [3, 7]},
        'glow': glow_meta('flak_glow.png', 14, 16, (-4, -4), {'fly': [0, 2, 12]}),
        'notes': 'Dark steel flak shell with a hot spark behind it (2 frames).'})
    ms = P.missile_frames()
    out_glow('projectiles/missile_glow', [halo(f, 18, 32, 6, 6, bands=((1.8, 105), (3.5, 55), (5.5, 22)), src='oyH') for f in ms])
    out_spr('projectiles/missile', ms, {
        'frame': [6, 20], 'orientation': 'up', 'body': [6, 12], 'anims': {'fly': [0, 3, 14]}, 'anchors': {'nose': [3, 0], 'center': [3, 6], 'tail': [3, 12]},
        'glow': glow_meta('missile_glow.png', 18, 32, (-6, -6), {'fly': [0, 3, 14]}),
        'notes': 'Missile body 12 long x 6 wide, with a 3-frame exhaust drawn below it inside the frame. Tail anchor is where the exhaust starts.'})
    bm = P.beam_frames()
    out_glow('projectiles/beam_glow', [halo_tile_y(f, 5, ((1.6, 95), (3.2, 50), (5.0, 22)), 'c') for f in bm])
    bi = P.beam_impact()
    out_glow('projectiles/beam_impact_glow', [halo(f, 24, 24, 4, 4, bands=((1.8, 95), (3.4, 48), (4.8, 20)), src='cbH') for f in bi])
    out_spr('projectiles/beam', bm, {
        'frame': [6, 16], 'length': 16, 'width': 6, 'orientation': 'up', 'tile': 'y', 'anims': {'flicker': [0, 3, 12]}, 'anchors': {'head': [3, 0], 'tail': [3, 15]},
        'glow': glow_meta('beam_glow.png', 16, 16, (-5, 0), {'flicker': [0, 3, 12]}, tile='y'),
        'impact': {'image': 'beam_impact.png', 'frame': [16, 16], 'anims': {'play': [0, 3, 14]}, 'anchor': [8, 8],
                   'glow': glow_meta('beam_impact_glow.png', 24, 24, (-4, -4), {'play': [0, 3, 14]})},
        'notes': 'Cyan beam with a white core, tileable along y, 3 flicker frames (step one per tick; use the same frame on every repeat or offset them for a crawling look).'})
    out_spr('projectiles/beam_impact', bi, {'frame': [16, 16], 'anims': {'play': [0, 3, 14]}, 'mode': 'once', 'anchors': {'center': [8, 8]}, 'notes': 'End flare for the beam; see beam.json.'})


def read_png(path):
    d = open(path, 'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n'
    pos, idat, w, h = 8, b'', 0, 0
    while pos < len(d):
        n = struct.unpack('>I', d[pos:pos + 4])[0]; t = d[pos + 4:pos + 8]; body = d[pos + 8:pos + 8 + n]; pos += 12 + n
        if t == b'IHDR': w, h = struct.unpack('>II', body[:8]); assert body[8] == 8 and body[9] == 6
        elif t == b'IDAT': idat += body
    raw = zlib.decompress(idat)
    rows = []
    for y in range(h):
        row = raw[y * (w * 4 + 1):(y + 1) * (w * 4 + 1)]
        assert row[0] == 0
        rows.append(row[1:])
    return w, h, rows


def validate():
    import json
    bad = 0
    for sub in ('tiles', 'fx', 'projectiles'):
        for fn in sorted(os.listdir(os.path.join(ART, sub))):
            if not fn.endswith('.png'): continue
            rel = sub + '/' + fn
            w, h, rows = read_png(os.path.join(ART, rel))
            js = os.path.join(ART, rel[:-4] + '.json')
            is_glow = rel in ALPHA_OK
            if not is_glow and not os.path.exists(js):
                print('MISSING JSON', rel); bad += 1
            for y, row in enumerate(rows):
                for x in range(w):
                    r, g, b, a = row[x * 4:x * 4 + 4]
                    if a == 0: continue
                    if (r, g, b) not in PALETTE_RGB:
                        print('OFF-PALETTE', rel, x, y, (r, g, b)); bad += 1
                    if a != 255 and not is_glow:
                        print('PARTIAL ALPHA in hard-pixel file', rel, x, y, a); bad += 1
            if os.path.exists(js):
                fw, fh = json.load(open(js))['frame']
                if w % fw or h % fh: print('FRAME MISMATCH', rel, (w, h), (fw, fh)); bad += 1
    print('validate:', 'OK' if not bad else '%d problems' % bad)
    return bad


def check_masks():
    """the autotile index rule N*1 + E*2 + S*4 + W*8 really is what each frame draws."""
    bad = 0
    for name, fn in (('walls', T.wall_standard), ('walls_armor', T.wall_armor)):
        for m in range(16):
            t = fn(m)
            for bit, (x, y) in ((1, (8, 0)), (2, (14, 8)), (4, (8, 14)), (8, (0, 8))):
                outline = t.get(x, y) == 'K'
                solid = bool(m & bit)
                if outline == solid:
                    print('MASK MISMATCH', name, m, bit, (x, y), t.get(x, y)); bad += 1
    for m in range(16):
        t = T.cable_tile(m, True)
        for bit, (x, y) in ((1, (7, 0)), (2, (15, 7)), (4, (7, 15)), (8, (0, 7))):
            arm = t.get(x, y) != '.'
            if arm != bool(m & bit):
                print('MASK MISMATCH cable', m, bit, (x, y), t.get(x, y)); bad += 1
    print('masks:', 'OK' if not bad else '%d problems' % bad)
    return bad


if __name__ == '__main__':
    build()
    sys.exit(1 if (validate() or check_masks()) else 0)
