"""The ending-art palette (art/endings/palette_endings.gpl): 46 colours, used by the eight 320x180 ending illustrations.
40 of them are the game palette (art/palette.gpl, same hex); 6 are new and exist only here: a plum and a rose for dusk skies, and four leaf greens for Halcyon's gardens.
It is a SEPARATE set from px.PAL on purpose (the letters differ from the other pal_* modules, which clash with each other), so nothing here touches palette.gpl."""
import os
PAL = {
 # steel ramp and the white
 'K': ('13161b', 'near-black outline'), 'D': ('2a2f37', 'dark slate'), 'E': ('3d444e', 'steel dark'), 'W': ('565e6a', 'steel mid-dark'),
 'S': ('7a8491', 'steel mid'), 'M': ('a3acb8', 'steel light'), 'L': ('d2d8e0', 'steel highlight'), 'H': ('f4f6f8', 'white'),
 # navy (neon panels, night skies)
 'N': ('161b2e', 'navy deepest'), 'I': ('222a45', 'navy dark'), 'J': ('323e63', 'navy mid'), 'j': ('4a5a88', 'navy light'),
 # violet, then the dusk run plum - magenta - rose
 'Z': ('4e3590', 'workshop violet dark'), 'V': ('8a5fd0', 'workshop violet'), 'X': ('c4a0f0', 'workshop violet light'),
 'd': ('6b2f66', 'plum (dusk sky, NEW)'), 'P': ('b0309a', 'neon magenta dark'), 'w': ('d9647a', 'rose (dusk sky, NEW)'), 'm': ('ff4fd8', 'neon magenta'),
 # warm: browns, rust, copper, amber, fire
 'n': ('3a2e28', 'brown dark'), 'q': ('6d5646', 'brown mid'), 'Q': ('93775f', 'brown light'), 'u': ('9c5a33', 'scrap rust'),
 'T': ('d4793a', 'copper light'), 'Y': ('f2ab6a', 'copper highlight'), 'a': ('e1a136', 'hull / door amber'),
 'o': ('ff8a1e', 'fire orange'), 'y': ('ffd23a', 'fire yellow'), 'r': ('e0413b', 'damage red'),
 # cyan
 'c': ('3cf2ff', 'neon cyan'), 'C': ('1fa9c2', 'neon cyan mid'), 'B': ('146f8c', 'neon cyan dark'), 'i': ('8fdcec', 'ice mid'), 'z': ('dff9ff', 'ice pale'),
 # leaves
 'A': ('15301f', 'leaf deepest (NEW)'), 'O': ('25512f', 'leaf dark (NEW)'), 'R': ('3d8238', 'leaf mid (NEW)'), 'U': ('74b948', 'leaf light (NEW)'), 'g': ('6bd34a', 'power green'),
 # skin, pink, cool blues
 's': ('e3ad82', 'skin'), 'v': ('b87a54', 'skin shade'), 'p': ('e88aa0', 'low-o2 pink'),
 'b': ('4fa3ff', 'shield blue'), 'k': ('8ea8e8', 'polymer pale blue'), 'x': ('6f8ba3', 'titanium cool mid'), 't': ('b4d0e2', 'titanium cool light'),
}
NEW = set('dwAORU')
RGB = {c: tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for c, (h, _) in PAL.items()}
HEX2CH = {h: c for c, (h, _) in PAL.items()}

def write_gpl(path):
    lines = ['GIMP Palette', 'Name: Hullscrap endings', 'Columns: 5', '#']
    for c, (h, name) in PAL.items():
        r, g, b = RGB[c]
        lines.append('%3d %3d %3d\t#%s %s' % (r, g, b, h, name))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write('\n'.join(lines) + '\n')

def check_against_game(gpl):
    """every non-NEW colour must be in the game's art/palette.gpl."""
    game = set()
    for line in open(gpl).read().splitlines():
        parts = line.split('\t')
        if len(parts) == 2 and parts[1].startswith('#'): game.add(parts[1][1:7])
    bad = [c for c, (h, _) in PAL.items() if c not in NEW and h not in game]
    assert not bad, 'not in the game palette: %s' % bad
