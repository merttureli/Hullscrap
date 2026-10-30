"""preview: every frame of a component on floor, its glow over it, at k x."""
import sys
from px import *
from comp_base import export
def preview(c, k=4, path=None):
    frames, gframes, J = export(c, PREVIEW + '/comp_tmp')
    l, t, r, b = c.glow_pad
    n = len(frames)
    cols = min(n, 6)
    rows = (n + cols - 1) // cols
    cw, ch = (c.w + l + r), (c.h + t + b)
    img = Rgba(cw * k * cols, ch * k * rows, RGB['F'] + (255,))
    # map frame index -> glow frame index
    gmap = {}
    for name, (st, cnt, fps) in J['anims'].items():
        g = J.get('glow', {}).get('anims', {}).get(name)
        for q in range(cnt):
            if g: gmap[st + q] = g[0] + q
    for i, f in enumerate(frames):
        x0, y0 = (i % cols) * cw * k, (i // cols) * ch * k
        img.blit_spr(f, x0 + l * k, y0 + t * k, k)
        if i in gmap: img.blit_rgba(gframes[gmap[i]].scaled(k), x0, y0, 1)
    img.save(path or (PREVIEW + '/preview/comp_%s.png' % c.id))
    return J
if __name__ == '__main__':
    import importlib
    mod, cls = sys.argv[1], sys.argv[2]
    m = importlib.import_module(mod)
    print(preview(getattr(m, cls)(), int(sys.argv[3]) if len(sys.argv) > 3 else 4)['anims'])
