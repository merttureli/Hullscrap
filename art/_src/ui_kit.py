"""The pixel UI kit: 9-slice frames (panel, inset, bar, button, tab, card, tooltip, title bar, scrollbar), resource / mode / category icons and the cursors.
Everything is code-drawn pixel by pixel on the shared palette (the letters of base px + pal_lines + pal_sector, like sector_all), light from the top-left, 1 px near-black outline,
amber for selection. build_all.py runs it in its own process (`python3 art/_src/ui_kit.py` rebuilds just this set); `sheet_ui.py` draws the labelled preview.

The 9-slice rule: the four edge strips and the centre are STRETCHED by the game, so only the four corner blocks carry detail (rivets, brackets, studs); every edge is one
uniform line along its axis and the centre is flat. Every frame's JSON has `nine_slice.margins` {left, top, right, bottom} (= Godot's StyleBoxTexture texture_margin_*),
`content_margins` (the padding to keep text and icons inside) and `anims` naming the frames of the strip (one frame wide each)."""
import json, os
from px import *
import pal_sector                       # registers the whole palette (base + neon/workshop + sector) so palette.gpl stays the law
from sector_fx import write_json
import ui_icons

UI = ART + '/ui'


# ------------------------------------------------------------------ box builder
def box(w, h, rings, fill='D', cham=True):
    """a bevelled box: `rings` run from the outside in, each (top-left colour, bottom-right colour), '.' = transparent; the rest is `fill` ('.' = hollow).
    Top-right takes the top-left colour and bottom-left the bottom-right one (the bevel mitre). `cham` cuts the four outer corner pixels."""
    s = Spr(w, h)
    for y in range(h):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)
            if d >= len(rings): s.g[y][x] = fill; continue
            tl, br = rings[d]
            top, left, bot, right = y == d, x == d, y == h - 1 - d, x == w - 1 - d
            if top and left: c = tl
            elif bot and right: c = br
            elif top and right: c = tl
            elif bot and left: c = br
            elif top or left: c = tl
            else: c = br
            s.g[y][x] = c
    if cham:
        for (x, y) in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)): s.g[y][x] = '.'
    return s

def rivet(s, x, y, tones='LMSE'):
    """a 2x2 domed bolt head lit from the top-left."""
    s.put(x, y, tones[0]); s.put(x + 1, y, tones[1]); s.put(x, y + 1, tones[2]); s.put(x + 1, y + 1, tones[3])


# ------------------------------------------------------------------ the frames: each returns {frame name: Spr} plus its margins and content margins
class Slice:
    def __init__(self, id, frames, margins, content, notes, center='stretch'):
        self.id, self.frames, self.margins, self.content, self.notes, self.center = id, frames, margins, content, notes, center

    def json(self):
        names = list(self.frames)
        f0 = self.frames[names[0]]
        d = {'frame': [f0.w, f0.h], 'cells': [1, 1], 'anims': {n: [i, 1, 0] for i, n in enumerate(names)}}
        if self.margins:
            m, c = self.margins, self.content
            d['nine_slice'] = {'margins': {'left': m[0], 'top': m[1], 'right': m[2], 'bottom': m[3]},
                               'content_margins': {'left': c[0], 'top': c[1], 'right': c[2], 'bottom': c[3]}, 'center': self.center}
        d['notes'] = self.notes
        return d


def gusset(s, corner, n, hi='M', mid='S', lo='W', bolt='LMSE'):
    """a raised n x n corner plate flush with the box: its outer sides are the box outline, its two inner sides get a 1 px outline plus a light (left/top)
    or dark (right/bottom) lip, and a bolt sits in the middle. corner: 'tl', 'tr', 'bl' or 'br'."""
    x0 = 0 if corner[1] == 'l' else s.w - n
    y0 = 0 if corner[0] == 't' else s.h - n
    x1, y1 = x0 + n - 1, y0 + n - 1
    inner_x = x1 if corner[1] == 'l' else x0          # the plate's inner vertical edge
    inner_y = y1 if corner[0] == 't' else y0
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            d = min(x, y, s.w - 1 - x, s.h - 1 - y)
            if d < 2: continue                         # keep the box's own outline and first lip ring
            if x == inner_x or y == inner_y: c = 'K'
            else:
                c = mid
                dx = abs(x - inner_x); dy = abs(y - inner_y)
                if dx == 1: c = lo if corner[1] == 'l' else hi
                if dy == 1: c = lo if corner[0] == 't' else hi
            s.g[y][x] = c
    cx = x0 + (n - 2) // 2 + (0 if corner[1] == 'l' else 1)
    cy = y0 + (n - 2) // 2 + (0 if corner[0] == 't' else 1)
    rivet(s, cx, cy, bolt)


def panel():
    """the main window frame: riveted steel, 4 px thick, a recessed lip, a flat dark-slate fill, a bolted plate in every corner. 28x28, margins 10."""
    w = h = 28
    s = box(w, h, [('K', 'K'), ('M', 'S'), ('S', 'W'), ('W', 'E'), ('K', 'W')], 'D')
    for c in ('tl', 'tr', 'bl', 'br'): gusset(s, c, 10)
    return Slice('panel', {'normal': s}, (10, 10, 10, 10), (7, 7, 7, 7),
                 'The main window frame (palette, info card, dialogs): riveted steel with a recessed lip and a flat dark-slate (#2a2f37) fill. Corners carry the bolts, so stretch it freely.')


def inset():
    w = h = 12
    s = box(w, h, [('K', 'E'), ('K', 'W')], 'K', cham=False)
    return Slice('inset', {'normal': s}, (3, 3, 3, 3), (3, 3, 3, 3),
                 'A sunken field (lists, slots, bar backgrounds): near-black fill, dark top/left lip, light bottom/right lip.')


def bar():
    """the thin HUD frame (top resource bar, bottom mode bar, small floating panels): 3 px of steel with a bolt in each corner. 18x18, margins 6."""
    w = h = 18
    s = box(w, h, [('K', 'K'), ('M', 'S'), ('S', 'W'), ('K', 'E')], 'D')
    for (x, y) in ((2, 2), (w - 4, 2), (2, h - 4), (w - 4, h - 4)): rivet(s, x, y)
    return Slice('bar', {'normal': s}, (6, 6, 6, 6), (4, 4, 4, 4),
                 'The thin HUD frame for the top resource bar, the bottom mode bar and small floating panels: a 3 px steel rim, a bolt in each corner, dark-slate fill.')


def button():
    """4 states in one strip, 16x16 each, margins 4. Amber is the focus colour: hover gets an amber inner rim, pressed a dim one."""
    n = box(16, 16, [('K', 'K'), ('M', 'W'), ('S', 'E')], 'W')
    h = box(16, 16, [('K', 'K'), ('y', 'a'), ('L', 'S')], 'W')
    p = box(16, 16, [('K', 'K'), ('u', 'a'), ('K', 'W')], 'E')
    d = box(16, 16, [('K', 'K'), ('E', 'D'), ('D', 'D')], 'D')
    return Slice('button', {'normal': n, 'hover': h, 'pressed': p, 'disabled': d}, (4, 4, 4, 4), (5, 4, 5, 4),
                 'Push button, 4 frames: normal (steel, light top/left), hover (same face, amber inner rim and a lit lip), pressed (sunk face, dim amber rim; shift the label 1 px down-right) and disabled (flat dark slate; use a #565e6a label). White labels read on the first three.')


def tab():
    """a tab sits on top of its page: both frames are 16x14, margins l5 t5 r5 b3. `on` is lit with an amber cap, `off` is sunk."""
    on = box(16, 14, [('K', 'K'), ('M', 'S')], 'E', cham=False)
    off = box(16, 14, [('K', 'K'), ('E', 'D')], 'D', cham=False)
    for x in range(2, 14):                      # the amber cap of the active tab
        on.g[1][x] = 'y'; on.g[2][x] = 'a'
    on.g[1][1] = 'M'; on.g[2][1] = 'M'; on.g[1][14] = 'S'; on.g[2][14] = 'S'
    for x in range(1, 15): off.g[1][x] = 'W' if 1 < x < 14 else off.g[1][x]
    for t in (on, off):                          # 2 px chamfer on the top corners
        t.g[0][1] = '.'; t.g[0][14] = '.'; t.g[1][0] = 'K'; t.g[1][15] = 'K'
    for x in (2, 13): on.g[0][x] = 'K'; off.g[0][x] = 'K'
    return Slice('tab', {'on': on, 'off': off}, (5, 5, 5, 3), (4, 5, 4, 2),
                 'Tab: `on` is lit steel with an amber cap, `off` is sunk dark slate. Put it on top of its page; the bottom rim is plain so it can overlap the page by 1 px. Icon (16x16) + label go inside the content margins.')


LINES = {'scrap': ('T', 'u', 'q'), 'steel': ('L', 'S', 'W'), 'neon': ('c', 'C', 'B'), 'gold': ('y', 'a', 'u')}


def card():
    """5 frames, 24x24, margins 7: the four line colours (scrap rust, standard steel, neon cyan, unique gold) and a `locked` one for what you can't afford or don't hold."""
    out = {}
    for name, (hi, mid, lo) in LINES.items():
        fill = 'I' if name == 'neon' else 'D'
        s = box(24, 24, [('K', 'K'), (hi, lo), (mid, mid), ('K', 'E') if name != 'neon' else ('N', 'J')], fill)
        out[name] = s
    def one(s, corner, dx, dy, rows):
        cx, cy = corner
        for j, r in enumerate(rows):
            for i, c in enumerate(r):
                x = dx + i if cx == 0 else s.w - 1 - dx - i
                y = dy + j if cy == 0 else s.h - 1 - dy - j
                s.put(x, y, c)
    TL, TR, BL, BR = (0, 0), (1, 0), (0, 1), (1, 1)
    BOLT = ['LM', 'SE']
    s = out['scrap']                                       # bolt heads, a hazard checker at the top-left, a weld bead, rust patches: asymmetric on purpose
    one(s, TL, 4, 4, ['aKa', 'KaK', 'aKa'])
    one(s, TR, 4, 4, ['QT', 'uq']); one(s, BL, 4, 4, ['QT', 'uq'])
    one(s, BR, 4, 4, ['.LM', 'MLS', 'KSE'])
    for (x, y) in ((8, 1), (9, 2), (1, 9), (2, 10), (22, 12), (21, 13), (12, 22), (13, 21)): s.put(x, y, 'q')
    for (x, y) in ((7, 1), (1, 8), (22, 14), (14, 22)): s.put(x, y, 'n')
    s = out['steel']                                       # clean: four identical bolts
    for c in (TL, TR, BL, BR): one(s, c, 4, 4, BOLT)
    s = out['neon']                                        # crystal facets in the corners, magenta ticks
    for c in (TL, TR, BL, BR): one(s, c, 4, 4, ['cC', 'CB'])
    for c in (TR, BL): one(s, c, 3, 3, ['m'])
    s = out['gold']                                        # gold studs, a glint on the top-left one
    for c in (TL, TR, BL, BR): one(s, c, 4, 4, ['.y.', 'yHa', '.a.'] if c == TL else ['.y.', 'yya', '.a.'])
    out['locked'] = box(24, 24, [('K', 'K'), ('E', 'D'), ('E', 'E'), ('K', 'D')], 'D')
    return Slice('card', out, (7, 7, 7, 7), (6, 6, 6, 6),
                 'Palette / info card frame, 5 frames by line colour: scrap (rust, bolt heads, hazard lip), steel (standard, clean rivets), neon (cyan on navy, magenta ticks), gold (unique), locked (greyed out). Fill is flat, so put icon and text straight on it.')


def highlight():
    """hover and selected overlays for a card: draw them 2 px outside the card's rect (their transparent middle lets the card show). 24x24, margins 7."""
    hv = box(24, 24, [('K', 'K'), ('L', 'M')], '.')
    sel = box(24, 24, [('K', 'K'), ('y', 'a')], '.')
    for (x, y) in ((2, 2), (21, 2), (2, 21), (21, 21)): sel.put(x, y, 'a')
    for (x, y) in ((2, 2),): sel.put(x, y, 'H')
    return Slice('highlight', {'hover': hv, 'selected': sel}, (7, 7, 7, 7), (0, 0, 0, 0),
                 'Overlays for a hovered / selected card or slot. They are a 2 px frame (outer near-black, inner light steel for hover, amber for selected) with a transparent middle: draw them 2 px OUTSIDE the target rect (rect grown by 2 on every side) so the target keeps its own outline.')


def tooltip():
    s = box(16, 16, [('K', 'K'), ('M', 'S'), ('K', 'K')], 'D')
    return Slice('tooltip', {'normal': s}, (4, 4, 4, 4), (5, 4, 5, 4),
                 'Floating tooltip / hover-card body: near-black outer line, light steel rim, dark fill. Sits over the world as well as over panels.')


def titlebar():
    """a header strip for panels: steel bar, hazard tape on the left cap, a bolt on the right cap. 28x14, margins l12 t4 r8 b4."""
    w, h = 28, 14
    s = box(w, h, [('K', 'K'), ('M', 'S')], 'W')
    for y in range(2, h - 2):                    # hazard tape in the left cap
        for x in range(2, 9): s.put(x, y, 'a' if ((x + y) // 2) % 2 == 0 else 'K')
    s.vline(9, 1, h - 2, 'K')
    rivet(s, w - 6, 5)
    return Slice('titlebar', {'normal': s}, (12, 4, 8, 4), (14, 2, 10, 2),
                 'Panel header strip: steel bar with a hazard-tape cap on the left and a bolt on the right. Title text goes in the content margins (left 14 to clear the tape).')


def scrollbar_v():
    track = box(8, 16, [('K', 'W')], 'K', cham=False)
    def th(rim, face, rimlo):
        return box(8, 16, [('K', 'K'), (rim, rimlo)], face, cham=False)
    return Slice('scrollbar', {'track': track, 'thumb': th('M', 'W', 'S'), 'thumb_hover': th('y', 'S', 'a'), 'thumb_pressed': th('u', 'E', 'u')}, (3, 3, 3, 3), (1, 1, 1, 1),
                 'Vertical scrollbar, 8x16 frames: `track` (sunk) and `thumb` in normal / hover (amber rim) / pressed. Stretch the thumb to the visible fraction; `scrollbar_grip` is the 3-ridge grip to centre on it when it is 14 px or longer. `scrollbar_h` is the same rotated for a horizontal bar.')


def scrollbar_h():
    v = scrollbar_v()
    fr = {k: f.transpose() for k, f in v.frames.items()}
    sl = Slice('scrollbar_h', fr, (3, 3, 3, 3), (1, 1, 1, 1), 'Horizontal scrollbar, 16x8 frames: the same frames as `scrollbar`, turned (light stays top-left).')
    return sl


def scrollbar_grip():
    g = from_art("""
    KKKK
    MMMM
    KKKK
    MMMM
    KKKK
    MMMM
    """)
    return Slice('scrollbar_grip', {'grip': g}, None, None, 'The 4x6 grip ridges for a scrollbar thumb (it fits the thumb face): centre it on the thumb when the thumb is 14 px or longer. Not a 9-slice.')


SLICES = [panel, inset, bar, button, tab, card, highlight, tooltip, titlebar, scrollbar_v, scrollbar_h, scrollbar_grip]


def all_slices():
    return [f() for f in SLICES]


def export_slices(art_dir=None):
    art_dir = art_dir or ART
    for sl in all_slices():
        fr = list(sl.frames.values())
        save(sheet(fr, len(fr), fr[0].w, fr[0].h), '%s/ui/%s.png' % (art_dir, sl.id))
        write_json('%s/ui/%s.json' % (art_dir, sl.id), sl.json())


ICON_SETS = [
    ('icons_res', ui_icons.RES, 16, 'Resource and gauge icons, 16x16 (anim name = the resource id, in the order of the top bar): scrap, copper, polymer, titanium, silicon, crystal, plasma_cell, nanite_paste, '
     'military_circuit, gate_alloy, void_crystal, credits, fuel, power, o2, hull, heat, crew. Each is its own hue (scrap grey and rust, copper orange, polymer pale blue, titanium cool grey, silicon navy, '
     'crystal cyan, plasma cell orange, nanite mint, circuit amber and red, gate alloy violet, void crystal dark violet and magenta, credits gold, fuel amber, power green, O2 pale cyan, hull steel and amber, heat red and orange, crew cyan). '
     'Bold at 1x; draw at 2x.'),
    ('icons_mode', ui_icons.MODE, 24, 'Mode-bar icons, 24x24 (anim name = the mode): build (wrench and hammer), play, map (star chart), shields, crafting (anvil), help, pause. Steel bodies with one accent each; '
     'for the active mode use the button `hover` or `pressed` frame behind it, and tint the icon with modulate if you want it lit.'),
    ('icons_cat', ui_icons.CAT, 16, 'Build-palette category icons, 16x16 (anim name = the tab): structure, shapes, systems, weapons, engines, utility, cargo. Steel with one accent each; they sit inside the 16x16 tab content area.'),
]


def export_icons(art_dir=None):
    art_dir = art_dir or ART
    for fid, lst, sz, notes in ICON_SETS:
        frames = [f() for _, f in lst]
        for (n, _), f in zip(lst, frames): assert f.w == sz and f.h == sz, (n, f.w, f.h)
        save(sheet(frames, len(frames), sz, sz), '%s/ui/%s.png' % (art_dir, fid))
        write_json('%s/ui/%s.json' % (art_dir, fid), {'frame': [sz, sz], 'cells': [1, 1], 'anims': {n: [i, 1, 0] for i, (n, _) in enumerate(lst)},
                                                      'anchors': {'center': [sz // 2, sz // 2]}, 'notes': notes})
    # cursors: the frames at 16x16, and the same at 32x32 (pre-scaled with nearest neighbour, ready for Input.set_custom_mouse_cursor, which does not scale)
    cur = ui_icons.CURSORS
    frames = [f() for _, f, _ in cur]
    for k, name in ((1, 'cursors'), (2, 'cursors_x2')):
        sz = 16 * k
        save(sheet(frames, len(frames), 16, 16), '%s/ui/%s.png' % (art_dir, name), scale=k)
        write_json('%s/ui/%s.json' % (art_dir, name), {
            'frame': [sz, sz], 'cells': [1, 1], 'anims': {n: [i, 1, 0] for i, (n, _, _) in enumerate(cur)},
            'anchors': {n: [h[0] * k, h[1] * k] for (n, _, h) in cur},
            'notes': 'Mouse cursors, %dx%d: pointer, place (amber reticle), remove (red X), invalid (no-entry sign). `anchors` holds each cursor\'s hotspot in px from the frame top-left (pointer: its tip; the others: the middle). '
                     'Cut a frame out and pass it to Input.set_custom_mouse_cursor(texture, shape, hotspot).%s' % (sz, sz, '' if k == 2 else ' This is the 1x set; `cursors_x2` is the same pre-scaled to 32x32, which is the size to use on a 1600x900 window.')})


def export_all(art_dir=None):
    export_slices(art_dir)
    export_icons(art_dir)
    print('ui kit:', ', '.join(sl.id for sl in all_slices()), '| icons', sum(len(l) for _, l, _, _ in ICON_SETS), '| cursors', len(ui_icons.CURSORS))


if __name__ == '__main__':
    export_all()
