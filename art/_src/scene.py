"""Compose a mini interior from tile sprites (used by the preview sheet and while drawing)."""
from px import *
from tiles import *

def solid_mask(grid, x, y, solid):
    m = 0
    for bit, (dx, dy) in ((N, (0, -1)), (E, (1, 0)), (S_, (0, 1)), (W_, (-1, 0))):
        xx, yy = x + dx, y + dy
        if 0 <= yy < len(grid) and 0 <= xx < len(grid[yy]) and grid[yy][xx] in solid: m |= bit
    return m

def compose(layout, walls, floors, bg=RGB['K'], solid='#dD'):
    gh, gw = len(layout), len(layout[0])
    cv = Rgba(gw * 16, gh * 16, bg + (255,))
    for y, row in enumerate(layout):
        for x, ch in enumerate(row):
            if ch in '.dDbfc<>^v+':                         # floor under floor-ish cells (door and breach cells too)
                fl = floors[(x * 7 + y * 13) % len(floors)]
                cv.blit_spr(fl, x * 16, y * 16)
    for y, row in enumerate(layout):
        for x, ch in enumerate(row):
            if ch == '#':
                cv.blit_spr(walls[solid_mask(layout, x, y, solid)], x * 16, y * 16)
    return cv
