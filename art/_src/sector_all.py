"""Everything for sector space ("Raft in space"): drifting debris, salvage intakes, radars, tractor turrets, the tractor beam, HUD icons, the space backdrop, the jump effects.
build_all.py calls export_all(); `python3 art/_src/sector_all.py` rebuilds just this set."""
import comp_base, comp_salvage, comp_radar, comp_tractor
import debris, sector_fx, poi_icons, space_bg
MOUNTS = comp_salvage.ALL + comp_radar.ALL + comp_tractor.ALL

def export_all():
    for C in MOUNTS:
        c = C()
        _, _, J = comp_base.export(c)
        print(c.id, J['frame'], list(J['anims']))
    debris.export()
    sector_fx.export_tractor_beam(); sector_fx.export_jump()
    poi_icons.export()
    space_bg.export()

if __name__ == '__main__':
    export_all()

def validate(art_dir=None):
    """the new component files: hard layers on palette letters, frames, anims and glow anims inside their strips, barrel sheets consistent. Returns the number of problems."""
    import os, json
    import px
    from build import read_png
    from px_structure import PALETTE_RGB
    art_dir = art_dir or px.ART
    ok_rgb = PALETTE_RGB | set(px.RGB.values())
    bad = 0
    def strip_ok(rel, J, label):
        nonlocal bad
        w, h, _ = read_png(os.path.join(art_dir, rel)); fw, fh = J['frame']
        if w % fw or h % fh: print('FRAME MISMATCH', label, (w, h), (fw, fh)); bad += 1; return
        n = (w // fw) * (h // fh)
        for name, (st, cnt, _f) in J['anims'].items():
            if st + cnt > n: print('ANIM OUT OF RANGE', label, name); bad += 1
    for C in MOUNTS:
        c = C()
        for cid in (c.id, c.id + '_out'):
            p = os.path.join(art_dir, 'components', cid + '.png')
            w, h, rows = read_png(p)
            for y, row in enumerate(rows):
                for x in range(w):
                    r, g, b, a = row[x * 4:x * 4 + 4]
                    if a and ((r, g, b) not in ok_rgb or a != 255): print('OFF-PALETTE/ALPHA', cid, x, y); bad += 1; break
            J = json.load(open(os.path.join(art_dir, 'components', cid + '.json')))
            strip_ok('components/%s.png' % cid, J, cid)
            if 'glow' in J: strip_ok('components/' + J['glow']['image'], {'frame': J['glow']['frame'], 'anims': J['glow']['anims']}, cid + ' glow')
            if 'barrel' in J: strip_ok('components/' + J['barrel']['image'], J['barrel'], cid + ' barrel')
    print('sector components:', 'OK' if not bad else '%d problems' % bad)
    return bad
