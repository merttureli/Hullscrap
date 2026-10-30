"""Ammo rack, 2x2 cells, an INSIDE component: a steel frame with four bays that fill one by one (fill_0 empty .. fill_4 full).
Three contents: missiles (fill_N), scrap chunks (scrap_N) and slugs (slug_N). Plus damaged (2), disabled and wrecked (the frame the code shows briefly before it clears the part)."""
from wbase import *

def junk_pile(s, x, y, k):
    from wbase import junk
    for q, (dx, dy) in enumerate(((0, 0), (5, 1), (2, 5), (6, 6))): junk(s, x + dx, y + dy, k + q)

MINI = ["HLLLLLLLor", "MMMMMMMMrr", "SSSSSSSSnn"]
SLUG = art("""
aQ
nq
""")

class AmmoRack(Comp):
    id = 'ammo_rack'; cells = (2, 2)
    glow_pad = (4, 4, 4, 4)
    anims = ([('on', 'm4', 1, 0)] + [('fill_%d' % k, 'm%d' % k, 1, 0) for k in range(5)] + [('scrap_%d' % k, 's%d' % k, 1, 0) for k in range(5)]
             + [('slug_%d' % k, 'u%d' % k, 1, 0) for k in range(5)] + [('damaged', 'damaged', 2, 4), ('disabled', 'disabled', 1, 0), ('wrecked', 'wrecked', 1, 0)])
    notes = ('INSIDE component, 2x2. Four bays fill one by one: fill_0 (empty) .. fill_4 (full) hold MISSILES (red-nosed rounds), scrap_0..scrap_4 hold SCRAP CHUNKS, '
             'slug_0..slug_4 hold brass SLUGS. The four lamps along the bottom light as the bays fill. on = full missile rack. damaged (2 frames): dented frame, a bay cracked, a sparking wire; '
             'disabled: dark, a bay burst open with its contents spilled; wrecked: a collapsed heap of twisted frame and burnt contents (shown briefly before the part is cleared).')
    BAYS = ((3, 3), (17, 3), (3, 17), (17, 17))
    def bay(self, s, x, y, kind, full):
        recess(s, x, y, 12, 12, 'D', 'K')
        if not full: return
        if kind == 'm':
            for r in range(3):
                for j, row in enumerate(MINI):
                    for i, c in enumerate(row): s.put(x + 1 + i, y + 1 + 3 * r + j + (1 if r else 0) - (1 if r == 0 else 0) + 0, c) if False else s.put(x + 1 + i, y + 1 + 3 * r + j, c)
        elif kind == 's':
            junk_pile(s, x + 1, y + 1, x // 7)
        else:
            for r in range(4):
                for c in range(5): s.stamp(x + 1 + 2 * c, y + 1 + 3 * r, SLUG)
    def draw(self, kind, n, dmg=0):
        s = Spr(32, 32)
        bev(s, 1, 1, 30, 30, 'M', 'S', 'W')
        s.rect(15, 3, 2, 26, 'S'); s.rect(3, 15, 26, 2, 'S'); s.vline(15, 3, 26, 'M'); s.hline(3, 15, 26, 'M')     # the cross bars
        bolts(s, [(2, 2), (29, 2), (2, 29), (29, 29)])
        for k, (x, y) in enumerate(self.BAYS): self.bay(s, x, y, kind, k < n)
        for k in range(4):                                                      # fill lamps on the bottom edge
            s.rect(6 + 6 * k, 30, 3, 1, 'g' if k < n else 'E')
        s.hline(10, 1, 2, 'W'); s.hline(20, 1, 2, 'W')                          # registry stencil
        return s
    def frame(self, state, i):
        if state in ('damaged', 'disabled', 'wrecked'):
            s = self.draw('m', 3 if state == 'damaged' else 4)
            if state == 'damaged':
                dent(s, 3, 1, 8, 3); crack(s, [(18, 3), (20, 7), (19, 12), (21, 14)])
                for (x, y) in ((6, 9), (7, 10)): s.put(x, y, 'K')
                wire(s, [(2, 27), (4, 30), (8, 31)]); s.put(15, 9, 'D')
                spark(s, 27, 22, False) if i == 0 else spark(s, 4, 29, False)
            elif state == 'disabled':
                s = s.sub(DARK)
                crack(s, [(18, 3), (20, 7), (19, 12), (21, 14)]); crack(s, [(4, 18), (7, 22), (6, 27)])
                s.rect(3, 17, 12, 12, '.')                                      # the bay burst open ...
                s.rect(3, 17, 12, 12, 'E'); s.hline(3, 17, 12, 'K')
                for (x, y) in ((6, 26), (10, 28), (12, 25), (4, 28)): s.rect(x, y, 3, 1, 'u')       # ... contents spilled
                junk(s, 5, 20, 1); s.put(9, 24, 'n')
            else:
                s = Spr(32, 32)
                for (x, y, w, h, k) in ((2, 20, 26, 8, 'b'), (5, 12, 18, 6, 'a'), (14, 6, 12, 5, 'r')):
                    plate(s, x, y, w, h, k, bolt=False)
                crack(s, [(4, 22), (14, 25), (26, 22)]); s.hline(5, 18, 18, 'K')
                for (x, y) in ((6, 4), (10, 8), (22, 10), (26, 16), (3, 14)): soot(s, x - 3, y - 2, (x + y) % 3)
                for (x, y, w) in ((3, 28, 5), (12, 29, 4), (20, 27, 6), (25, 29, 4)): s.hline(x, y, w, 'K')
                for (x, y) in ((8, 14), (18, 9), (23, 22), (11, 24)): s.put(x, y, 'u')
                wire(s, [(2, 10), (5, 7), (9, 8)]); wire(s, [(24, 26), (28, 22), (29, 17)])
                for (x, y) in ((6, 6), (20, 14), (14, 15), (26, 24)): s.put(x, y, 'n')
                s = s.copy(); outline_all(s); return drop_shadow(s)
            s = s.copy(); outline_all(s); return drop_shadow(s)
        kind, n = state[0], int(state[1])
        s = self.draw(kind, n)
        outline_all(s); return drop_shadow(s)
    def glow(self, state, i, g, ox, oy):
        n = int(state[1]) if state[0] in 'msu' and state[1:].isdigit() else (3 if state == 'damaged' else 0)
        for k in range(n): glow(g, ox + 7.5 + 6 * k, oy + 30.5, 3, (107, 211, 74), 0.5, 2.0)
