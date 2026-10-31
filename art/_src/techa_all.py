"""Racial tech art, group a (human, basalt, emberkin, fenn, kett): export + preview.
  python3 techa_all.py            export every part and projectile into art/ (build_all.py calls export_all())
  python3 techa_all.py preview [out.png]   draw the preview sheet (every part mounted through a wall or placed in a room, then every projectile and impact)
15 ship weapons (inside half `<id>`, `_out` half, `_barrel`), 15 components (2 engines as two halves, 5 reactors, 2 shields, 6 utilities), 15 projectile + impact sets."""
import os, sys, json
import techa_human, techa_basalt, techa_emberkin, techa_fenn, techa_kett
import comp_base
from px import *

RACES = [('human', techa_human), ('basalt', techa_basalt), ('emberkin', techa_emberkin), ('fenn', techa_fenn), ('kett', techa_kett)]
WEAPONS = [C for _, m in RACES for C in m.WEAPONS]
COMPONENTS = [C for _, m in RACES for C in m.COMPONENTS]
PROJECTILES = [p for _, m in RACES for p in m.PROJECTILES]

def ids():
    """(weapons, components, projectiles) ids in order; an engine is listed once (its `_out` half is `<id>_out`)."""
    w = [C.id for C in WEAPONS]
    c = []
    for C in COMPONENTS:
        i = (C() if isinstance(C, type) else C).id
        if i.endswith('_out'): continue
        c.append(i)
    return w, c, [p.id for p in PROJECTILES]

def export_all(verbose=True):
    for C in WEAPONS + COMPONENTS:
        c = C() if isinstance(C, type) else C
        _, _, J = comp_base.export(c)
        if verbose: print(c.id, J['frame'], list(J['anims']))
    for p in PROJECTILES:
        p.export()
        if verbose: print(p.id, 'projectile', len(p.frames), 'frames,', len(p.impact), 'impact frames')

# ------------------------------------------------------------------ preview
def preview(path, K=3, W=1900):
    import sheet_weapons as SW
    from sheet_v2 import text
    SPACE = SW.SPACE
    # ---- weapons: mounted through a wall (barrel straight out), one scene per weapon, five to a row
    scenes = []
    for race, m in RACES:
        for C in m.WEAPONS:
            d = SW.Data(C)
            c = d.c
            top = max(46, c.blen - 1 - c.bpivot[0] - c.pivot[1] + 6)
            sc = SW.scene(d, 0, top=top)
            scenes.append((race, c.id, c.aim, sc))
    # ---- components
    comps = []
    for race, m in RACES:
        for C in m.COMPONENTS:
            c = C() if isinstance(C, type) else C
            comps.append((race, c))
    # layout: weapons 5 per row
    per = 5
    cw = max(s.w for _, _, _, s in scenes) * K + 14
    rows = [scenes[i:i + per] for i in range(0, len(scenes), per)]
    rowh = [max(s.h for _, _, _, s in r) * K + 34 for r in rows]
    H1 = 40 + sum(rowh)
    # components: engines (out + wall + core), then the rest placed in a room
    comp_items = []
    for race, c in comps:
        if c.id.endswith('_out'): continue
        comp_items.append((race, c))
    # build comp scenes
    def room_scene(c, state='on', i=0, pad=14):
        fr, gfr, J = comp_base.export(c, PREVIEW + '/comp_tmp')
        l, t, r, b = c.glow_pad
        w = c.w + 2 * pad; h = c.h + 2 * pad
        img = Rgba(w, h, RGB['F'] + (255,))
        for y in range(h):
            for x in range(w):
                if x % 16 == 0 or y % 16 == 0: img.p[y][x] = list(RGB['G']) + [255]
        st, cnt, fps = J['anims'][state]
        img.blit_spr(fr[st + i], pad, pad, 1)
        g = J.get('glow', {}).get('anims', {}).get(state)
        if g: img.blit_rgba(gfr[g[0] + i], pad - l, pad - t, 1, add=True)
        return img
    def engine_scene(c_in, c_out, state='on', i=0, pad=18, top=30):
        fi, gi, Ji = comp_base.export(c_in, PREVIEW + '/comp_tmp')
        fo, go, Jo = comp_base.export(c_out, PREVIEW + '/comp_tmp')
        oh = c_out.h
        w = 64 + 2 * pad; h = top + oh + 32 + 32 + 4
        img = Rgba(w, h, RGB['F'] + (255,))
        wy = top + oh
        SW.space_bg(img, 0, wy); SW.floor_bg(img, wy + 32, h)
        img.blit_spr(SW.wall_rows(w), 0, wy)
        st, cnt, fps = Jo['anims'][state]
        img.blit_spr(fo[st + i], pad, top)
        g = Jo.get('glow', {}).get('anims', {}).get(state)
        l, t, r, b = c_out.glow_pad
        iy = wy + 32 - 4
        st2, _, _ = Ji['anims'][state]
        img.blit_spr(fi[st2 + i], pad, iy)
        if g: img.blit_rgba(go[g[0] + i], pad - l, top - t, 1, add=True)
        g2 = Ji.get('glow', {}).get('anims', {}).get(state)
        l2, t2, _, _ = c_in.glow_pad
        if g2: img.blit_rgba(gi[g2[0] + i], pad - l2, iy - t2, 1, add=True)
        return img
    engines = {}
    for race, c in comps:
        if c.id.endswith('_out'): engines[c.id[:-4]] = c
    items = []
    for race, c in comp_items:
        if c.id in engines:
            items.append((race, c.id, engine_scene(c, engines[c.id], 'on', 1)))
        else:
            items.append((race, c.id, room_scene(c, 'on', 1)))
    # components: reactors 4x4 and shields get a damaged + disabled companion
    extra = []
    for race, c in comp_items:
        if c.id in engines: continue
        extra.append((c.id, [room_scene(c, 'off', 0), room_scene(c, 'damaged', 0), room_scene(c, 'disabled', 0)]))
    per_c = 5
    cw2 = max(s.w for _, _, s in items) * K + 14
    crow = [items[i:i + per_c] for i in range(0, len(items), per_c)]
    crowh = [max(s.h for _, _, s in r) * K + 34 for r in crow]
    H2 = 40 + sum(crowh)
    # projectiles
    PK = 4
    ph = 0
    prows = []
    for p in PROJECTILES:
        hh = max(p.frames[0].h + 2 * p.pad, p.impact[0].h + 2 * p.ipad) * PK + 36
        prows.append(hh)
    # projectiles two per row
    pper = 2
    H3 = 40 + sum(max(prows[i:i + pper]) for i in range(0, len(prows), pper))
    Ht = H1 + H2 + H3 + 60
    img = Rgba(W, Ht, RGB['F'] + (255,))
    y = 14
    text(img, 20, y, 'RACIAL TECH A: HUMAN BASALT EMBERKIN FENN KETT  15 SHIP WEAPONS MOUNTED THROUGH A 2-ROW WALL (OUTSIDE HALF, WALL, INSIDE HALF, BARREL STRAIGHT OUT)', 'H', 3)
    y += 30
    for r, rh in zip(rows, rowh):
        x = 20
        for (race, wid, aim, sc) in r:
            img.blit_rgba(sc.scaled(K), x, y, 1)
            text(img, x + 6, y + 6, wid.upper() + (' F' if aim == 'fixed' else ' T'), 'H', 2)
            x += cw
        y += rh
    text(img, 20, y, 'COMPONENTS: ENGINES AS HULL MOUNTS (NOZZLES OUTSIDE, WALL, CORE INSIDE), THE REST IN A ROOM. ON FRAME 1 WITH GLOW', 'H', 3)
    y += 30
    for r, rh in zip(crow, crowh):
        x = 20
        for (race, cid, sc) in r:
            img.blit_rgba(sc.scaled(K), x, y, 1)
            text(img, x + 6, y + rh - 26, cid.upper(), 'H', 2)
            x += cw2
        y += rh
    text(img, 20, y, 'PROJECTILES AND IMPACTS AT 4X, WITH GLOW, ON SPACE. LEFT TO RIGHT: THE PROJECTILE FRAMES, THEN THE IMPACT', 'H', 3)
    y += 30
    for i0 in range(0, len(PROJECTILES), pper):
        x0 = 20
        rh = max(prows[i0:i0 + pper])
        for p in PROJECTILES[i0:i0 + pper]:
            import techa_kit as TK
            wd = (p.frames[0].w + 2 * p.pad) * len(p.frames) * PK + (p.impact[0].w + 2 * p.ipad) * len(p.impact) * PK + 60
            bg = Rgba(wd + 10, rh - 10, SPACE + (255,))
            x = 10
            text(bg, 6, 4, p.id.upper(), 'H', 2)
            for f in p.frames:
                g = TK.halo(f, p.pad, p.bands, p.src) if not p.tile else TK.tile_halo_y(f, p.pad, p.bands, p.src)
                bg.blit_rgba(g.scaled(PK), x, 20, 1, add=True)
                bg.blit_spr(f, x + p.pad * PK, 20 + (0 if p.tile else p.pad * PK), PK)
                x += (f.w + 2 * p.pad) * PK
            x += 40
            for f in p.impact:
                g = TK.halo(f, p.ipad, p.ibands, p.isrc)
                bg.blit_rgba(g.scaled(PK), x, 20, 1, add=True)
                bg.blit_spr(f, x + p.ipad * PK, 20 + p.ipad * PK, PK)
                x += (f.w + 2 * p.ipad) * PK
            img.blit_rgba(bg, x0, y, 1)
            x0 += wd + 24
        y += rh
    img = _crop(img, y + 10)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return img.w, img.h

def _crop(img, h):
    n = Rgba(img.w, min(h, img.h)); n.p = img.p[:n.h]; return n

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'preview':
        print(preview(sys.argv[2] if len(sys.argv) > 2 else '/home/user/hs/shots/art_tech_a.png'))
    else:
        export_all()
