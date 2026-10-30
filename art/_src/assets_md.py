"""(Re)writes the art rows of ASSETS.md at the repo root: one row per art file under art/ (not _src)."""
import os
from px import ART
ROOT = os.path.dirname(ART)
HEAD = '# Assets\n\nSource and licence of every art and audio file in the repo.\n\n| File | Source | Licence |\n|---|---|---|\n'
def rows():
    out = []
    for dp, dn, fn in os.walk(ART):
        dn[:] = sorted(d for d in dn if not d.startswith('_'))
        for f in sorted(fn):
            if f.endswith(('.png', '.json', '.gpl')):
                rel = os.path.relpath(os.path.join(dp, f), ROOT)
                out.append('| `%s` | original, made for Hullscrap (generator: `art/_src/`) | project-owned |' % rel)
    return sorted(out)
if __name__ == '__main__':
    p = os.path.join(ROOT, 'ASSETS.md')
    keep = []
    if os.path.exists(p):   # keep rows other agents added
        for line in open(p).read().splitlines():
            if line.startswith('| `') and 'art/_src/' not in line: keep.append(line)
    allrows = sorted(set(keep) | set(rows()))
    open(p, 'w').write(HEAD + '\n'.join(allrows) + '\n')
    print(len(allrows), 'rows')
