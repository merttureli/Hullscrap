"""Builds every ending illustration into art/endings/ (and the hall-of-ships frame kit into art/ui/): python3 art/_src/endings_all.py [id ...]
Each ending: <id>.png (N frames of 320x180 side by side, hard pixels, palette_endings.gpl colours only), <id>_glow.png (soft-alpha light layer, same frames), <id>.json."""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ill import *
import pal_endings
from px import ART

OUT = ART + '/endings'
FPS = 3

def registry():
    import end_dome, end_exodus
    R = {
     'haven_settle': (end_dome.render, 4, "Halcyon's gardens under the glass dome: kids at play, a kite, a little ship docked on its pad, the Lantern mast pulsing. Frames: stars twinkle, lamps swap, kids run, the stream ripples, butterflies flap."),
     'haven_exodus': (end_exodus.render, 4, "A convoy of mismatched ships (Clan hauler, Concord frigate, Lumen skiff, a welded liner, a tug, a raft, darts) arrives at Halcyon, its dome glowing warm. Frames: exhaust flicker, the approach beacons walk in, windows and stars twinkle."),
     'haven_lure': (end_dome.render_wrong, 4, "The same garden, subtly wrong: cold light, five identical children in a row, Hollow hulls with eleven lights in the glass, nothing twinkles or moves. Frames: the eleven lights blink all together."),
    }
    try:
        import end_gate
        R.update(end_gate.REG)
    except ImportError: pass
    try:
        import end_hollow, end_retire
        R.update(end_hollow.REG); R.update(end_retire.REG)
    except ImportError: pass
    return R

def export(ids=None):
    os.makedirs(OUT, exist_ok=True)
    pal_endings.write_gpl(OUT + '/palette_endings.gpl')
    pal_endings.check_against_game(ART + '/palette.gpl')
    R = registry()
    for id_, (fn, n, note) in R.items():
        if ids and id_ not in ids: continue
        frames, glows = [], []
        for f in range(n):
            im, gl = fn(f)
            frames.append(im); glows.append(gl)
        save_strip(frames, '%s/%s.png' % (OUT, id_))
        save_glow_strip(glows, '%s/%s_glow.png' % (OUT, id_))
        meta = {'frame': [W, H], 'cells': [20, 11], 'anims': {'on': [0, n, FPS]},
                'glow': {'image': id_ + '_glow.png', 'frame': [W, H], 'offset': [0, 0], 'anims': {'on': [0, n, FPS]}, 'blend': 'add (preferred) or alpha-over'},
                'notes': 'Ending illustration, 320x180 per frame, %d frames looping at %d fps. Draw it at 3x or 4x with nearest filtering; add the glow strip over it (additive). Light comes from the top-left. %s' % (n, FPS, note)}
        with open('%s/%s.json' % (OUT, id_), 'w') as fh: json.dump(meta, fh, indent=1); fh.write('\n')
        print(id_, n, 'frames')

def export_all(ids=None):
    export(ids)
    if not ids:
        import hall_kit
        regs = hall_kit.export(ART)
        print('hall of ships kit: frame, plate, crest x3 lines, bg, score ornaments (%d regions)' % len(regs))

def read_png(path):
    import zlib, struct
    d = open(path, 'rb').read(); pos, idat = 8, b''
    while pos < len(d):
        n = struct.unpack('>I', d[pos:pos + 4])[0]; t = d[pos + 4:pos + 8]; body = d[pos + 8:pos + 8 + n]; pos += 12 + n
        if t == b'IHDR': w, h = struct.unpack('>II', body[:8]); assert body[8] == 8 and body[9] == 6
        elif t == b'IDAT': idat += body
    raw = zlib.decompress(idat)
    return w, h, [raw[y * (w * 4 + 1) + 1:(y + 1) * (w * 4 + 1)] for y in range(h)]

def validate():
    """endings: every pixel opaque and in palette_endings.gpl, frame/glow sizes agree with the json, every anim in range; ui kit: game palette only, hard alpha for the sprites."""
    pal = set(pal_endings.RGB.values())
    game = set()
    for line in open(ART + '/palette.gpl').read().splitlines():
        parts = line.split('\t')
        if len(parts) == 2 and parts[1].startswith('#'): game.add(tuple(int(parts[1][1:7][i:i + 2], 16) for i in (0, 2, 4)))
    bad = 0
    for fn in sorted(os.listdir(OUT)):
        if not fn.endswith('.png'): continue
        w, h, rows = read_png(OUT + '/' + fn)
        glow = fn.endswith('_glow.png')
        js = OUT + '/' + (fn[:-9] if glow else fn[:-4]) + '.json'
        J = json.load(open(js))
        fw, fh = J['frame']
        if w % fw or h != fh: print('FRAME SIZE', fn, (w, h), (fw, fh)); bad += 1
        n = w // fw
        for name, (st, cnt, _f) in J['anims'].items():
            if st + cnt > n: print('ANIM RANGE', fn, name); bad += 1
        for y in range(h):
            for x in range(w):
                r, g, b, a = rows[y][x * 4:x * 4 + 4]
                if glow:
                    if a and (r, g, b) not in pal: print('GLOW OFF-PALETTE', fn, x, y, (r, g, b)); bad += 1; break
                else:
                    if a != 255: print('NOT OPAQUE', fn, x, y); bad += 1; break
                    if (r, g, b) not in pal: print('OFF-PALETTE', fn, x, y, (r, g, b)); bad += 1; break
    for fn in sorted(os.listdir(ART + '/ui')):
        if not (fn.startswith(('hall_', 'score_')) and fn.endswith('.png')): continue
        w, h, rows = read_png(ART + '/ui/' + fn)
        glow = fn.endswith('_glow.png')
        for y in range(h):
            for x in range(w):
                r, g, b, a = rows[y][x * 4:x * 4 + 4]
                if not a: continue
                if (r, g, b) not in game: print('UI OFF-PALETTE', fn, x, y, (r, g, b)); bad += 1; break
                if a != 255 and not glow: print('UI PARTIAL ALPHA', fn, x, y); bad += 1; break
    print('endings validate:', 'OK' if not bad else '%d problems' % bad)
    return bad

if __name__ == '__main__':
    args = sys.argv[1:]
    if args == ['--check']: sys.exit(1 if validate() else 0)
    export_all(args or None)
    if not args: sys.exit(1 if validate() else 0)
