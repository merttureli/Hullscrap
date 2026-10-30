"""Palette additions for race wave 1 (docs/waves/races_1.md): three greens for the Mire's amphibian skin, plus two private
letters that alias existing neon cyans. B and C are the crew OUTFIT symbols (tint mask), so a crew sprite cannot spell the
neon cyan mid / dark with their own letters: Y and z point at the same colours (RGB only, no new palette entry).
Merged into px.PAL/px.RGB in place; build_all writes the new colours to palette.gpl."""
import px
import pal_lines          # the neon cyans (C, B) must exist before they are aliased
NEW = {
 'T': ('3a9a7e', 'mire skin teal-green'),
 't': ('1f5f52', 'mire skin shade'),
 'U': ('7bd0a6', 'mire skin light'),
}
for k, (h, n) in NEW.items():
    assert k not in px.PAL or px.PAL[k][0] == h, k
    px.PAL[k] = (h, n)
    px.RGB[k] = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
ALIAS = {'Y': 'C', 'z': 'B'}          # sprite letter -> the palette letter whose colour it uses (not outfit symbols)
for k, v in ALIAS.items():
    assert k not in px.PAL
    px.RGB[k] = px.RGB[v]
