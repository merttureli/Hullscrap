"""Palette additions for the Neon line (navy panels, cyan/magenta ramps) and the workshop (violet).
Merged into px.PAL/px.RGB in place, so everything that imports px sees them, and build_all writes them to palette.gpl."""
import px
NEW = {
 'N': ('161b2e', 'navy deepest (neon seams)'),
 'I': ('222a45', 'navy dark (neon panel shade)'),
 'J': ('323e63', 'navy mid (neon panel)'),
 'j': ('4a5a88', 'navy light (neon panel highlight)'),
 'C': ('1fa9c2', 'neon cyan mid (crystal facet)'),
 'B': ('146f8c', 'neon cyan dark (crystal shade)'),
 'P': ('b0309a', 'neon magenta dark'),
 'V': ('8a5fd0', 'workshop violet'),
 'X': ('c4a0f0', 'workshop violet light'),
 'Z': ('4e3590', 'workshop violet dark'),
}
for k, (h, n) in NEW.items():
    assert k not in px.PAL or px.PAL[k][0] == h, k
    px.PAL[k] = (h, n)
    px.RGB[k] = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
