"""Two palette additions for the gun rework (docs/GUNS.md 4): a true crimson for beams, and a pale straw that tells a slug's light from a flak burst's amber.
The letters exist in px.RGB at once (so sprites can be drawn); register() adds them to px.PAL, called by build_all after the sector colours so
palette.gpl only ever grows at its end. 48 + 2 = 50 colours."""
import px
NEW = {
 '(': ('d4143c', 'beam crimson (guns: the beam family light)'),
 ')': ('fff0a8', 'pale straw (guns: the slug family light)'),
}
for k, (h, n) in NEW.items():
    px.RGB[k] = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def register():
    for k, (h, n) in NEW.items():
        assert k not in px.PAL or px.PAL[k][0] == h, k
        px.PAL[k] = (h, n)
