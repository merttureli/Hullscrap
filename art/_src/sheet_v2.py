"""v2 preview sheet: everything at 3x on the floor colour."""
from px import *
import comp_base
from build_all import COMPS
from compose import Kit, compose, floor_shadow
import crew_v2 as cv2

K = 3; W = 2400
F35 = {
 'A':'010101111101101','B':'110101110101110','C':'011100100100011','D':'110101101101110','E':'111100110100111',
 'F':'111100110100100','G':'011100101101011','H':'101101111101101','I':'111010010010111','J':'001001001101010',
 'K':'101101110101101','L':'100100100100111','M':'101111111101101','N':'110101101101101','O':'010101101101010',
 'P':'110101110100100','Q':'010101101111011','R':'110101110101101','S':'011100010001110','T':'111010010010010',
 'U':'101101101101111','V':'101101101101010','W':'101101111111101','X':'101101010101101','Y':'101101010010010',
 'Z':'111001010100111','0':'111101101101111','1':'010110010010111','2':'110001010100111','3':'110001010001110',
 '4':'101101111001001','5':'111100110001110','6':'011100111101111','7':'111001010010010','8':'111101111101111',
 '9':'111101111001110','+':'000010111010000','-':'000000111000000','/':'001001010100100','.':'000000000000010',
 ' ':'000000000000000','_':'000000000000111',':':'000010000010000',
}
blocks = []          # (height, draw(img, y))
def text(img, x, y, s, col='L', k=3):
    for ch in s.upper():
        g = F35.get(ch, F35[' '])
        for i, b in enumerate(g):
            if b == '1':
                for dy in range(k):
                    for dx in range(k): img.over(x + (i % 3) * k + dx, y + (i // 3) * k + dy, RGB[col] + (255,))
        x += 4 * k

def comp_block(C):
    c = C(); frames, gframes, J = comp_base.export(c, PREVIEW + '/comp_tmp')
    l, t, r, b = c.glow_pad
    cw, ch = (c.w + l + r) * K, (c.h + t + b) * K
    per = max(1, (W - 40) // cw)
    names = {}
    for nm, (st, cnt, fps) in J['anims'].items():
        for q in range(cnt): names.setdefault(st + q, '%s %d' % (nm, q) if cnt > 1 else nm)
    gmap = {}
    for nm, (st, cnt, fps) in J['anims'].items():
        g = J.get('glow', {}).get('anims', {}).get(nm)
        for q in range(cnt):
            if g: gmap[st + q] = g[0] + q
    rows = (len(frames) + per - 1) // per
    H = 40 + rows * (ch + 26)
    def draw(img, y0):
        text(img, 20, y0, '%s  %dX%d CELLS' % (c.id, c.cells[0], c.cells[1]), 'H', 4)
        for i, f in enumerate(frames):
            x, y = 20 + (i % per) * cw, y0 + 32 + (i // per) * (ch + 26)
            img.blit_spr(f, x + l * K, y + t * K, K)
            if i in gmap: img.blit_rgba(gframes[gmap[i]].scaled(K), x, y, 1)
            text(img, x + l * K, y + ch + 2, names.get(i, ''), 'M', 3)
    return H, draw

def crew_block():
    kit = Kit(); G = 97; cw = 66 * K
    items = [('pistol', 'pistol', 'helmet'), ('rifle', 'rifle', 'hair'), ('tool', 'wrench', 'helmet'), ('tool', 'extinguisher', 'hair')]
    rots = [0, 45, 135, 270]
    def cell(f): 
        crop = Spr(66, 66)
        for y in range(66):
            for x in range(66): crop.g[y][x] = f.g[y + 15][x + 15]
        return crop
    H = 40 + 2 * (cw + 20) + 40 + cw + 20 + 40 + 33 * K * 2 + 60
    def draw(img, y0):
        text(img, 20, y0, 'CREW: HUMAN TEAL, 4 ITEMS X 4 AIM ROTATIONS 0 45 135 270', 'H', 4)
        n = 0
        for (pose, it, hd) in items:
            for rdeg in rots:
                f = floor_shadow(compose(kit, 6, rdeg, rdeg, pose, it, hd))
                x, y = 20 + (n % 8) * (cw + 10), y0 + 32 + (n // 8) * (cw + 20)
                img.blit_rgba(cv2.tinted_rgba(cell(f)), x, y, K)
                text(img, x + 6, y + cw - 6, '%s %d' % (it, rdeg), 'M', 3)
                n += 1
        y1 = y0 + 32 + 2 * (cw + 20) + 10
        text(img, 20, y1, 'WALK CYCLE: LEGS MOVE RIGHT 90, TORSO AIMS UP 0  /  LEGS 30, AIM 300', 'H', 4)
        for i in range(6):
            f = floor_shadow(compose(kit, i, 90, 0, 'rifle', 'rifle', 'hair'))
            img.blit_rgba(cv2.tinted_rgba(cell(f)), 20 + i * (cw + 10), y1 + 32, K)
        for i in range(2):
            f = floor_shadow(compose(kit, (0, 3)[i], 30, 300, 'pistol', 'pistol', 'helmet'))
            img.blit_rgba(cv2.tinted_rgba(cell(f)), 20 + (6 + i) * (cw + 10), y1 + 32, K)
        y2 = y1 + 32 + cw + 20
        text(img, 20, y2, 'PARTS: LEGS 6+STAND, TORSO, ARMS UNARMED PISTOL RIFLE TOOL, HEADS HAIR HELMET, ITEMS', 'H', 4)
        cv2.OUTLINE = True
        parts = cv2.legs() + [cv2.torso()] + [cv2.arms(p) for p in cv2.POSES] + [cv2.head(h) for h in cv2.HEADS]
        for i, p in enumerate(parts):
            img.blit_rgba(cv2.tinted_rgba(p), 20 + i * (33 * K * 2 // 2 + 12), y2 + 32, K)
        x = 20 + len(parts) * (33 * K + 12) + 20
        for nme in cv2.ITEM_ART:
            sp = cv2.item(nme); img.blit_spr(sp, x, y2 + 32, K); x += sp.w * K + 24
    return H, draw

def build(path):
    bl = [crew_block()] + [comp_block(C) for C in COMPS]
    Ht = sum(h for h, _ in bl) + 20 * len(bl) + 20
    img = Rgba(W, Ht, RGB['F'] + (255,))
    y = 20
    for h, d in bl:
        d(img, y); y += h + 20
        for x in range(W): img.p[y - 10][x] = list(RGB['G']) + [255]
    img.save(path)
    return img.w, img.h

if __name__ == '__main__':
    print(build(PREVIEW + '/v2_sheet.png'))
