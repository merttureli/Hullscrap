"""Round 2, ambience: the ship's room tone, one space bed per region family, the hazard loops, the machine loops (medbay, smelter,
fabricator), the drone's hover and the missile's flight. Every one is a loop that is seamless by construction (tail 0, no cross-fade
to hide anything): noise is made in the frequency domain over the loop's own length, tones snap to whole cycles of it, slow
modulators have whole cycles, filtering is circular (fft_filter), and events (groans, bleeps, bangs, clicks) are added with wrap_add so
what runs past the end comes in again at the start. Levels (active RMS, dBFS): beds -30, hazards -26, hums -32, machines -29."""
import numpy as np
from dsp import *
from sounds import sound, R, mix


def pan_add(buf, x, start, pan):
    """Add the event x into the stereo loop buffer at `start` (wrapping), panned -1 (left) .. 1 (right): equal-power gains and a hair of delay on the far ear."""
    a = (pan + 1.0) * np.pi / 4.0
    d = int(abs(pan) * 20)
    wrap_add(buf[:, 0], x * np.cos(a), start + (d if pan > 0 else 0))
    wrap_add(buf[:, 1], x * np.sin(a), start + (d if pan < 0 else 0))


def hit(r, freqs, taus, amps, dur, cut):
    """A far-off metal knock: a struck bar, softened by a low-pass so it reads as distance."""
    return lp(modal(freqs, taus, amps, dur, r, 0.01), cut)


# --- the ship ---------------------------------------------------------------------------------------------------------------

@sound("room_tone", "hum", 1, loop=(6.0, 0.0))
def room_tone(k):
    """The ship's room tone. A mains-like hum with plenty of harmonics, ventilation and a faint electrical hiss. It is meant to be heard
    through a low-pass (the Room bus) that opens with the reactor's load: shut it is a dull hum, open it is air and hiss."""
    L = 6.0
    n = n_of(L)
    chans = []
    for c in range(2):
        r = R("room_tone", c)
        hum = np.zeros(n)
        for h in range(1, 13):
            hum += sine(snap(50.0 * h, L), n, 0.11 * h + 0.2 * c) * (0.9 / h ** 0.8)
        hum *= 1.0 + 0.05 * per(n, 2, 0.1 * c)
        vent = band_noise(r, n, 80, 800, 2.0) * (0.6 + 0.4 * per(n, 1, 0.25 * c))
        air = band_noise(r, n, 600, 6000, 1.0)
        hiss = band_noise(r, n, 3500, 11000, 0.0)
        chans.append(hum * 0.55 + vent * 0.5 + air * 0.35 + hiss * 0.12)
    return stereo(*chans)


@sound("drone_hum", "hum", 1, loop=(2.0, 0.0))
def drone_hum(k):
    """The repair drone's hover: a very quiet rotor whir with a fast flutter."""
    L = 2.0
    n = n_of(L)
    r = R("drone_hum", 0)
    whir = sine(snap(210, L), n) + 0.5 * sine(snap(420, L), n, 0.2) + 0.3 * sine(snap(630, L), n, 0.4)
    whir *= 1.0 + 0.25 * per(n, 12)
    air = band_noise(r, n, 900, 3200, 0.0) * 0.25
    return whir * 0.5 + air


@sound("missile_flight", "loop", 1, loop=(2.0, 0.0))
def missile_flight(k):
    """A missile in flight: a rocket motor's rush with a low flutter, heard through the hull, and a thin hiss."""
    L = 2.0
    n = n_of(L)
    r = R("missile_flight", 0)
    rush = band_noise(r, n, 140, 1900, 1.0) * (0.75 + 0.25 * per(n, 9) * per(n, 2, 0.1))
    buzz = fft_filter(saw(snap(80, L), n), None, 480) * (0.7 + 0.3 * per(n, 5, 0.2))
    hiss = band_noise(r, n, 3000, 7000, 0.0)
    return rush * 0.75 + buzz * 0.45 + hiss * 0.07


@sound("medbay_hum", "machine", 1, loop=(2.0, 0.0))
def medbay_hum(k):
    """The medbay's scanner: a soft two-tone hum that breathes, with a scan ping once a loop."""
    L = 2.0
    n = n_of(L)
    r = R("medbay_hum", 0)
    base = sine(snap(330, L), n) * 0.6 + sine(snap(495, L), n, 0.3) * 0.35 + sine(snap(165, L), n, 0.1) * 0.4
    base *= 0.75 + 0.25 * per(n, 1)
    x = base * 0.7 + band_noise(r, n, 200, 1400, 1.0) * 0.1
    ping = fm(1760.0, 1.0, env(0.5, [(0, 1.5), (0.4, 0.2)]), n_of(0.5)) * ad(0.5, 0.004, 0.12)
    wrap_add(x, ping * 0.25, n_of(0.35))
    return x


@sound("smelter_loop", "machine", 1, loop=(3.0, 0.0))
def smelter_loop(k):
    """The smelter: a furnace's low roar that pulses, with ember crackle and now and then a clank of the crucible."""
    L = 3.0
    n = n_of(L)
    r = R("smelter_loop", 0)
    roar = band_noise(r, n, 40, 420, 1.5) * (0.8 + 0.2 * per(n, 2))
    mid = band_noise(r, n, 300, 1800, 1.0) * (0.55 + 0.45 * per(n, 3, 0.3)) * 0.4
    embers = fft_filter(wcrackle(r, n, 22, 0.003, 1.5, 0.35), None, 3200) * 0.7
    x = roar * 0.8 + mid + embers
    for t in (0.7, 2.1):
        wrap_add(x, hit(r, BAR[:4] * 230, [0.25, 0.16, 0.1, 0.06], [0.6, 0.4, 0.25, 0.12], 0.5, 1800) * 0.3, n_of(t))
    return x


@sound("fabricator_loop", "machine", 1, loop=(2.0, 0.0))
def fabricator_loop(k):
    """The fabricator: servo whirs in a steady four-beat, a tick on each, and a low hum under them."""
    L = 2.0
    n = n_of(L)
    r = R("fabricator_loop", 0)
    x = sine(snap(120, L), n) * 0.35 + sine(snap(240, L), n, 0.2) * 0.15
    for i in range(8):
        d = 0.09
        f0 = 280 + 40 * (i % 3)
        whirr = lp(saw(sweep(f0, f0 * 1.7, d)), 1400) * swell(d, 0.03, 0.05)
        tick = bp(white(r, n_of(0.02)), 2600, 1.2) * ad(0.02, 0.0002, 0.004)
        wrap_add(x, whirr * 0.5, n_of(0.25 * i))
        wrap_add(x, tick * 0.6, n_of(0.25 * i + 0.08))
    return x + band_noise(r, n, 500, 3000, 1.0) * 0.06


# --- the space beds: one per region family -----------------------------------------------------------------------------------

@sound("bed_boneyard", "bed", 1, loop=(6.0, 0.0))
def bed_boneyard(k):
    """The Boneyard: the dark under a field of wrecks. Distant metal groans that glide down and creak, and the odd tick of cooling plate."""
    L = 6.0
    n = n_of(L)
    r = R("bed_boneyard", 0)
    buf = np.zeros((n, 2))
    for c in range(2):
        rc = R("bed_boneyard", 10 + c)
        buf[:, c] += band_noise(rc, n, 25, 140, 2.0) * 0.4
        buf[:, c] += band_noise(rc, n, 250, 900, 2.0) * 0.12 * (0.6 + 0.4 * per(n, 1, 0.3 * c))
    for i in range(3):
        dur = 1.7 + r.random() * 1.1
        m = n_of(dur)
        f0 = 58 + r.random() * 70
        glide = sweep(f0, f0 * (0.74 + 0.12 * r.random()), dur)
        body = lp(saw(glide), 650) * 0.7 + sine(glide * 2.0) * 0.35
        creak = bp(white(r, m), glide * 4.3, 7.0) * (0.35 + 0.65 * np.abs(saw(11 + 3 * r.random(), m)))
        pan_add(buf, (body + creak * 1.1) * swell(dur, dur * 0.4, dur * 0.6) * 0.8, int(r.random() * n), r.random() * 2 - 1)
    for i in range(4):
        base = 700 + r.random() * 900
        pan_add(buf, hit(r, BAR[:4] * base, [0.22, 0.14, 0.08, 0.05], [0.5, 0.3, 0.15, 0.08], 0.6, 2800) * 0.12, int(r.random() * n), r.random() * 2 - 1)
    return fft_filter(buf, 20, 3800)


@sound("bed_lumen", "bed", 1, loop=(6.0, 0.0))
def bed_lumen(k):
    """Lumen space: shimmering tones. A pentatonic cluster of slow swells with a detuned partner each (beating), a soft pad and rare glints."""
    L = 6.0
    n = n_of(L)
    r = R("bed_lumen", 0)
    notes = [392.0, 523.25, 587.33, 783.99, 1174.66, 1567.98]
    buf = np.zeros((n, 2))
    for c in range(2):
        rc = R("bed_lumen", 10 + c)
        for i, f in enumerate(notes):
            fs = snap(f, L)
            amp = (0.5 + 0.5 * per(n, 1 + i % 3, 0.17 * i + 0.5 * c)) ** 2 / (1.0 + 0.35 * i)
            buf[:, c] += (sine(fs, n, 0.13 * i) + 0.6 * sine(fs + 0.5, n, 0.31 * i)) * amp
        buf[:, c] += band_noise(rc, n, 500, 2400, 2.0) * 0.12 * (0.5 + 0.5 * per(n, 2, 0.1 * c))
        buf[:, c] += band_noise(rc, n, 4000, 10000, 0.0) * 0.03
    for i in range(5):
        f = [2093.0, 2637.0, 3136.0, 3951.0][int(r.random() * 4)]
        glint = fm(f, 3.14, env(0.6, [(0, 2.0), (0.4, 0.2)]), n_of(0.6)) * ad(0.6, 0.004, 0.16)
        pan_add(buf, glint * 0.1, int(r.random() * n), r.random() * 2 - 1)
    return fft_filter(buf, 60, 9000)


@sound("bed_concord", "bed", 1, loop=(6.0, 0.0))
def bed_concord(k):
    """Concord space: faint radio. Band-limited static that breathes and a few distant bleeps: single beeps, dit-dit-dit and a rising chirp."""
    L = 6.0
    n = n_of(L)
    r = R("bed_concord", 0)
    buf = np.zeros((n, 2))
    for c in range(2):
        rc = R("bed_concord", 10 + c)
        buf[:, c] += band_noise(rc, n, 500, 3800, 1.0) * 0.3 * (0.4 + 0.6 * smooth_noise(rc, n, 2.0))
    for i in range(7):
        start = int(r.random() * n)
        pan = r.random() * 2 - 1
        f = [900.0, 1100.0, 1250.0, 1500.0, 1800.0][int(r.random() * 5)]
        kind = i % 3
        if kind == 0:
            d = 0.05 + 0.04 * r.random()
            beeps = [(sine(f, n_of(d)) * env(d, [(0, 0), (0.005, 1), (d - 0.008, 1), (d, 0)]), 0.0)]
        elif kind == 1:
            beeps = [(sine(f, n_of(0.04)) * env(0.04, [(0, 0), (0.004, 1), (0.034, 1), (0.04, 0)]), 0.075 * j) for j in range(3)]
        else:
            beeps = [(sine(sweep(f * 0.7, f * 1.3, 0.09)) * env(0.09, [(0, 0), (0.006, 1), (0.08, 1), (0.09, 0)]), 0.0)]
        for b, off in beeps:
            pan_add(buf, b * 0.22, start + n_of(off), pan)
            pan_add(buf, b * 0.07, start + n_of(off + 0.13), pan)
    buf = fft_filter(buf, 350, 3400)
    for c in range(2):
        buf[:, c] += band_noise(R("bed_concord", 20 + c), n, 30, 90, 2.0) * 0.12
    return buf


@sound("bed_clans", "bed", 1, loop=(6.0, 0.0))
def bed_clans(k):
    """Clan space: distant rowdiness with no voices in it. Bangs on metal in pairs and threes, a rattle of chain, a far engine revving."""
    L = 6.0
    n = n_of(L)
    r = R("bed_clans", 0)
    buf = np.zeros((n, 2))
    for c in range(2):
        rc = R("bed_clans", 10 + c)
        buf[:, c] += band_noise(rc, n, 30, 220, 2.0) * 0.25 * (0.7 + 0.3 * per(n, 1, 0.2 * c))
    d = 2.1
    rev = lp(saw(sweep(70, 108, d / 2)), 280)
    rev = np.concatenate([rev, lp(saw(sweep(108, 70, d / 2)), 280)]) * swell(d, 0.5, 0.8)
    pan_add(buf, rev * 0.3, int(r.random() * n), r.random() * 2 - 1)
    for group in range(3):
        start = int(r.random() * n)
        pan = r.random() * 2 - 1
        for j in range(2 + group % 2):
            t = n_of(0.17 * j + 0.03 * r.random())
            thump = sine(sweep(125, 48, 0.4)) * ad(0.4, 0.002, 0.12)
            base = 220 + r.random() * 260
            clang = hit(r, BAR * base, [0.35, 0.25, 0.18, 0.12, 0.08, 0.05], [0.6, 0.45, 0.3, 0.2, 0.12, 0.07], 0.9, 2000)
            pan_add(buf, mix(thump * 0.8, clang * 1.0) * (0.5 + 0.5 * r.random()), start + t, pan)
    for i in range(2):
        m = n_of(0.5)
        chain = bp(wcrackle(r, m, 70, 0.0012, 1.0, 0.9), 1800, 1.0) * swell(0.5, 0.05, 0.35)
        pan_add(buf, chain * 0.4, int(r.random() * n), r.random() * 2 - 1)
    return fft_filter(buf, 25, 3000)


@sound("bed_hollow", "bed", 1, loop=(6.0, 0.0))
def bed_hollow(k):
    """The Hollow: airy whispers. Breathy noise through three drifting bands, each rising and falling like syllables, with no voiced sound
    in it and no words, over a hollow sub-bass and a faint high air."""
    L = 6.0
    n = n_of(L)
    buf = np.zeros((n, 2))
    for c in range(2):
        rc = R("bed_hollow", 10 + c)
        w = np.zeros(n)
        for lo, hi, g, rate in ((350, 750, 1.0, 3.0), (1300, 2300, 0.8, 4.0), (2800, 4800, 0.5, 5.0)):
            w += band_noise(rc, n, lo, hi, 0.0) * smooth_noise(rc, n, rate) * g
        w *= 0.35 + 0.65 * smooth_noise(rc, n, 0.7)
        buf[:, c] = w * 1.7 + band_noise(rc, n, 28, 90, 2.0) * 0.12 + sine(snap(41.0 + 0.5 * c, L), n) * 0.05 + band_noise(rc, n, 5000, 11000, 0.0) * 0.05
    return fft_filter(buf, 25, 9000)


# --- the hazard loops (the fight's hazard, data/hazards.json `sound`) -------------------------------------------------------------

@sound("haz_ion_storm", "hazard", 1, loop=(4.0, 0.0))
def haz_ion_storm(k):
    """Ion storm: electric crackle. Dry snaps, a mains buzz, falling zaps now and then and a bed of static."""
    L = 4.0
    n = n_of(L)
    r = R("haz_ion_storm", 0)
    buf = np.zeros((n, 2))
    for c in range(2):
        rc = R("haz_ion_storm", 10 + c)
        stat = band_noise(rc, n, 2500, 9000, 0.0) * 0.12 * (0.4 + 0.6 * smooth_noise(rc, n, 3.0))
        snaps = fft_filter(wcrackle(rc, n, 24, 0.0008, 1.4, 0.9), 1200, None) * 0.9
        buzz = fft_filter(saw(snap(60, L), n, 0.2 * c), None, 700) * 0.25 * (0.5 + 0.5 * smooth_noise(rc, n, 2.0))
        buf[:, c] = stat + snaps + buzz + band_noise(rc, n, 40, 220, 2.0) * 0.15
    for i in range(4):
        zap = fm(sweep(1500 + 500 * r.random(), 220, 0.14), 1.41, env(0.14, [(0, 5.0), (0.14, 0.8)]), n_of(0.14)) * ad(0.14, 0.001, 0.05)
        pan_add(buf, zap * 0.3, int(r.random() * n), r.random() * 2 - 1)
    return buf


@sound("haz_star_heat", "hazard", 1, loop=(4.0, 0.0))
def haz_star_heat(k):
    """Star heat: a roar. A deep rumble, a ragged mid roar that swells and a hiss of heat shimmer over it."""
    L = 4.0
    n = n_of(L)
    buf = np.zeros((n, 2))
    for c in range(2):
        rc = R("haz_star_heat", 10 + c)
        rumble = band_noise(rc, n, 30, 300, 2.0) * (0.75 + 0.25 * per(n, 1, 0.2 * c))
        roar = band_noise(rc, n, 150, 1200, 1.0) * (0.7 + 0.3 * per(n, 2, 0.3 * c)) * 1.0
        shim = band_noise(rc, n, 1500, 6000, 0.5) * (0.6 + 0.4 * per(n, 3, 0.1 * c)) * 0.2
        ticks = fft_filter(wcrackle(rc, n, 14, 0.003, 1.0, 0.4), None, 3000) * 0.3
        buf[:, c] = rumble + roar + shim + ticks
    return buf


@sound("haz_gas_cloud", "hazard", 1, loop=(4.0, 0.0))
def haz_gas_cloud(k):
    """Gas cloud: a hiss. A wide airy hiss that swells slowly, a swirl underneath and small bubbles coming up through it."""
    L = 4.0
    n = n_of(L)
    r = R("haz_gas_cloud", 0)
    buf = np.zeros((n, 2))
    for c in range(2):
        rc = R("haz_gas_cloud", 10 + c)
        hiss = band_noise(rc, n, 1800, 7500, 0.0) * (0.65 + 0.35 * per(n, 1, 0.25 * c))
        swirl = band_noise(rc, n, 200, 650, 1.0) * (0.6 + 0.4 * per(n, 2, 0.4 * c)) * 0.3
        buf[:, c] = hiss * 0.8 + swirl
    for i in range(6):
        f0 = 380 + 520 * r.random()
        bub = sine(sweep(f0, f0 * 1.9, 0.05)) * ad(0.05, 0.002, 0.014)
        pan_add(buf, bub * 0.18, int(r.random() * n), r.random() * 2 - 1)
    return buf


@sound("haz_radiation", "hazard", 1, loop=(4.0, 0.0))
def haz_radiation(k):
    """Radiation: Geiger clicks. Sharp random ticks, some in a small cluster, over a faint low hiss."""
    L = 4.0
    n = n_of(L)
    buf = np.zeros((n, 2))
    for c in range(2):
        rc = R("haz_radiation", 10 + c)
        clicks = wcrackle(rc, n, 12, 0.0004, 1.0, 1.0, power=0.7)
        wrap_add(clicks, wcrackle(rc, n_of(0.3), 20, 0.0004, 1.0, 1.0, power=0.7) * 0.8, int(rc.random() * n))  # a little cluster
        buf[:, c] = clicks * 0.9 + band_noise(rc, n, 2500, 8000, 0.0) * 0.03 + band_noise(rc, n, 40, 160, 2.0) * 0.05
    return buf


@sound("haz_debris_surge", "hazard", 1, loop=(4.0, 0.0))
def haz_debris_surge(k):
    """Debris surge: a rumble. A rolling sub rumble, a grinding mid band and the rattle of small fragments on the hull, with a dull ping or two."""
    L = 4.0
    n = n_of(L)
    r = R("haz_debris_surge", 0)
    buf = np.zeros((n, 2))
    for c in range(2):
        rc = R("haz_debris_surge", 10 + c)
        sub = band_noise(rc, n, 25, 180, 2.0) * (0.7 + 0.3 * per(n, 1, 0.2 * c))
        grind = band_noise(rc, n, 200, 1500, 1.5) * (0.6 + 0.4 * per(n, 3, 0.3 * c)) * 0.8
        rattle = fft_filter(wcrackle(rc, n, 38, 0.003, 1.0, 0.25), None, 2600) * 0.7
        buf[:, c] = sub + grind + rattle
    for i in range(2):
        pan_add(buf, hit(r, BAR[:4] * (300 + 200 * r.random()), [0.2, 0.12, 0.07, 0.04], [0.5, 0.3, 0.15, 0.08], 0.5, 2200) * 0.25, int(r.random() * n), r.random() * 2 - 1)
    return buf
