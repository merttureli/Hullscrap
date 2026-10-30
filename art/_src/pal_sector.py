"""Palette additions for sector space (debris material cues, the tractor/magnet mint). Merged into px.PAL/px.RGB in place, after pal_lines,
so palette.gpl only ever grows at the end. 37 + 8 = 45 colours (budget: stay under 48)."""
import pal_lines                       # registers the neon/workshop letters first, so the order of palette.gpl is stable
import px
NEW = {
 'T': ('d4793a', 'copper light (debris: copper orange)'),
 'Y': ('f2ab6a', 'copper highlight'),
 'i': ('8fdcec', 'ice mid (debris: pale cyan)'),
 'z': ('dff9ff', 'ice pale / frost highlight'),
 'k': ('8ea8e8', 'polymer pale blue (debris: white-blue)'),
 'x': ('6f8ba3', 'titanium cool mid (debris: cool grey)'),
 't': ('b4d0e2', 'titanium cool light / sheen'),
 'h': ('8cf0c4', 'tractor mint (pale green-cyan: tractor beam, magnet pull)'),
}
for k, (h, n) in NEW.items():
    assert k not in px.PAL or px.PAL[k][0] == h, k
    px.PAL[k] = (h, n)
    px.RGB[k] = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
