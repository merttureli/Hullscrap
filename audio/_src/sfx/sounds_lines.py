"""Round 2, weapons: the sound of each equipment line (scrap: low, rattly, crushed; neon: bright, glassy, shimmering; standard keeps the
round-1 sounds) and the ten races' signature guns. A line variant is its kind's round-1 recipe put through scrap() or neon(), so the
two lines stay recognisably the same weapon. A weapon picks its sound by its `sound` key, else <kind sound>_<line>, else the kind
(scripts/audio/audio.gd weapon_sound)."""
import numpy as np
from dsp import *
from sounds import sound, R, mix, laser, bolt, flak, missile_launch, rapid_tick, ion


def fit(x, n):
    """x cut or zero-padded to n samples."""
    return np.pad(x, (0, max(n - len(x), 0)))[:n]


def scrap(x, r):
    """The scrap line: pitched down, rattly and crunchy. A loose-plate rattle and a spit of crackle under a much harder bit-crush."""
    x = resample(x, 0.9)
    x = x * db(-12.0 - active_rms_db(x))      # the base at a known level, so the rattle and grit sit the same against every kind
    n = len(x)
    dur = n / SR
    rattle = fit(modal(PLATE * 560, [0.03] * 7, [0.3, 0.26, 0.22, 0.18, 0.14, 0.1, 0.08], dur, r, 0.04), n) * fit(decay(dur, 0.07), n)
    grit = lp(crackle(r, n, 110, 0.001, 1.0, 0.8), 4500) * fit(decay(dur, 0.12), n)
    y = crush(x * 1.1 + rattle * 0.55 + grit * 0.5, 6, 3)
    return lp(y, 5200)


def neon(x, r, seed, room=0.3):
    """The neon line: brighter and glassy. Bell-like FM partials high up, a chorus for the shimmer and a short bright room."""
    x = resample(x, 1.1)
    x = x * db(-12.0 - active_rms_db(x))
    n = len(x)
    dur = n / SR
    f0 = 2600.0 + 300.0 * r.random()
    glass = fm(f0, 3.01, fit(env(dur, [(0, 3.2), (dur, 0.3)]), n), n) * fit(ad(dur, 0.002, dur * 0.3), n) * 0.32
    glass += fm(f0 * 1.5, 2.0, 1.4, n) * fit(ad(dur, 0.003, dur * 0.4), n) * 0.2
    y = chorus(hp(x * 0.8 + glass, 220), 0.004, 5.0, 0.6)
    return reverb(lp(y, 6500), room, 0.2, seed)


# the kind sounds of round 1 and how many variants a line version has (the first two of the base's)
_BASES = {"laser": (laser, 2), "bolt": (bolt, 2), "flak": (flak, 2), "missile_launch": (missile_launch, 2), "rapid_tick": (rapid_tick, 2)}


def _scrap_version(base, fn, nvar):
    name = base + "_scrap"

    @sound(name, "weapon", nvar)
    def f(k):
        return scrap(fn(k), R(name, k))
    return f


def _neon_version(base, fn, nvar, seed):
    name = base + "_neon"

    @sound(name, "weapon", nvar)
    def f(k):
        return neon(fn(k), R(name, k), seed + k, 0.1 if base == "rapid_tick" else 0.3)   # (a fast tick keeps a short room)
    return f


for _i, (_base, (_fn, _nv)) in enumerate(_BASES.items()):
    _scrap_version(_base, _fn, _nv)
    _neon_version(_base, _fn, _nv, 300 + 10 * _i)


@sound("ion_scrap", "weapon", 1)
def ion_scrap(k):
    return scrap(ion(0), R("ion_scrap", 0))


@sound("ion_neon", "weapon", 1)
def ion_neon(k):
    return neon(ion(1), R("ion_neon", 0), 350)


@sound("beam_loop_neon", "loop", 1, loop=(2.0, 0.25))
def beam_loop_neon(k):
    """A neon beam: the beam's hum an octave up, with a glassy FM shimmer that wanders and a bright fizz."""
    tot = 2.25
    n, t = n_of(tot), tt(tot)
    chans = []
    for c in range(2):
        r = R("beam_loop_neon", c)
        hum = 0.4 * saw(220, n, 0.25 * c) + 0.25 * saw(330, n) + 0.4 * sine(440, n, 0.1 * c)
        hum = lp(hum, 2600)
        glass = fm(1320, 3.01, 2.6 + 1.8 * np.sin(TAU * 2 * t + c), n) * 0.2 + fm(1980, 2.0, 1.4 + np.sin(TAU * 3 * t), n) * 0.12
        fizz = bp(white(r, n), 5200, 1.0) * (0.55 + 0.45 * np.sin(TAU * 9 * t + c)) * 0.2
        chans.append(chorus((hum + glass + fizz) * (1.0 + 0.12 * np.sin(TAU * 5 * t)), 0.003, 1.0, 0.4))
    return stereo(*chans)


# --- the ten races' signature guns ---------------------------------------------------------------------------------------

@sound("sig_magma", "weapon", 2)
def sig_magma(k):
    """Basalt magma spitter: a thick lava gloop. A low FM body, three bubbles bursting upward, a wet slap and hot pops."""
    r, dur = R("sig_magma", k), 0.7
    n = n_of(dur)
    body = fm(sweep([185, 160][k], 55, dur), 0.5, env(dur, [(0, 4.0), (0.3, 2.0), (0.7, 0.5)]), n) * ad(dur, 0.004, 0.2)
    bubbles = place((sine(sweep(140, 420, 0.12)) * ad(0.12, 0.002, 0.04), 0.06, 1.8), (sine(sweep(110, 320, 0.1)) * ad(0.1, 0.002, 0.035), 0.2, 1.3),
                    (sine(sweep(90, 260, 0.09)) * ad(0.09, 0.002, 0.03), 0.33, 1.0), length=dur)
    slap = lp(white(r, n), 1100) * ad(dur, 0.002, 0.07) * 1.3
    pops = lp(crackle(r, n, 40, 0.004), 2200) * decay(dur, 0.25) * 1.2
    return lp(crush(np.tanh(1.5 * body) * 0.7 + bubbles + slap + pops, 9, 2), 3800)


@sound("sig_swarm", "weapon", 2)
def sig_swarm(k):
    """Kett hive swarm launcher: buzzing. Six saw-wing pulses, each chopped at a hornet's rate, one after another, over a thin whoosh."""
    r, dur = R("sig_swarm", k), 1.0
    n = n_of(dur)
    layers = []
    for i in range(6):
        d = 0.24
        m = n_of(d)
        f = 200 + 24 * i + 12 * k
        b = (0.6 * saw(f, m) + 0.4 * square(f * 1.5, m)) * (0.55 + 0.45 * square(135 + 7 * i, m))
        b = lp(b, 2400) * env(d, [(0, 0), (0.02, 1), (0.16, 0.7), (0.24, 0)])
        layers.append((b, 0.075 * i + 0.02 * r.random(), 0.55))
    wing = bp(white(r, n), env(dur, [(0, 900), (0.5, 2400), (1.0, 1300)]), 2.0) * swell(dur, 0.2, 0.5) * 0.35
    thump = place((sine(sweep(110, 50, 0.25)) * ad(0.25, 0.002, 0.07), 0.0, 0.9), length=dur)
    return lp(crush(place(*layers, length=dur) + wing + thump, 9, 2), 5200)


@sound("sig_crystal", "weapon", 2)
def sig_crystal(k):
    """Prismatic refractor: crystalline. A run of glass bells in inharmonic ratios, a bright upward glint and a clear room."""
    r, dur = R("sig_crystal", k), 0.9
    notes = [[1568.0, 2093.0, 2637.0, 3136.0, 3951.0], [1760.0, 2349.0, 2794.0, 3520.0, 4186.0]][k]
    layers = []
    for i, f in enumerate(notes):
        m = n_of(0.5)
        bell = fm(f, 3.14, env(0.5, [(0, 2.4), (0.35, 0.3)]), m) * ad(0.5, 0.001, 0.14 + 0.02 * i)
        layers.append((bell, 0.045 * i, 0.55))
    glint = place((sine(sweep(1200, 5200, 0.1)) * ad(0.1, 0.001, 0.03), 0.0, 0.4), length=dur)
    tick = place((bp(white(r, n_of(0.04)), 5200, 1.2) * ad(0.04, 0.0002, 0.006), 0.0, 0.5), length=dur)
    return reverb(lp(place(*layers, length=dur) + glint + tick, 7000), 0.55, 0.3, 400 + k)


@sound("sig_spore", "weapon", 2)
def sig_spore(k):
    """Sporeling spore cannon: a wet puff. A soft throaty slosh, a cough of damp air and a drip."""
    r, dur = R("sig_spore", k), 0.5
    n = n_of(dur)
    puff = lp(white(r, n), env(dur, [(0, 2200), (0.15, 700), (0.5, 300)])) * ad(dur, 0.004, 0.08)
    slosh = bp(white(r, n), sweep(500 + 80 * k, 1400, dur), 4.0) * ad(dur, 0.003, 0.07) * 1.2
    pop = place((sine(sweep(260, 90, 0.1)) * ad(0.1, 0.001, 0.03), 0.0, 0.9), length=dur)
    drip = place((sine(sweep(900, 300, 0.06)) * ad(0.06, 0.001, 0.02), 0.26 + 0.03 * k, 0.4), length=dur)
    return lp(crush(puff * 1.2 + slosh + pop + drip, 10, 2), 3800)


@sound("sig_pyre", "loop", 1, loop=(2.0, 0.25))
def sig_pyre(k):
    """Emberkin pyre lance: a roar (a beam, so a loop). A deep furnace rumble, a ragged mid roar, a growl at 41 Hz and flame crackle."""
    tot = 2.25
    n, t = n_of(tot), tt(tot)
    chans = []
    for c in range(2):
        r = R("sig_pyre", c)
        rumble = tile_to(band_noise(r, n_of(2.0), 35, 320, 1.5), n)
        roar = tile_to(band_noise(r, n_of(2.0), 250, 2400, 1.0), n) * (0.7 + 0.3 * np.sin(TAU * 3 * t + c))
        growl = lp(saw(41, n, 0.3 * c), 320) * (0.6 + 0.4 * np.sin(TAU * 7 * t))
        flames = lp(crackle(r, n, 30, 0.003, 1.5), 4000) * 0.6
        chans.append(rumble * 0.6 + roar * 0.9 + growl * 0.4 + flames)
    return stereo(*chans)


@sound("sig_pop", "weapon", 3)
def sig_pop(k):
    """Fenn twitch cannon: a sly clicky pop. A click, a small round pop, and a second click a beat later, as if it winked."""
    r, dur = R("sig_pop", k), 0.24
    n = n_of(dur)
    click = bp(white(r, n), 3500 + 200 * k, 1.5) * ad(dur, 0.0003, 0.004)
    pop = sine(sweep(900 - 60 * k, 380, 0.09)) * ad(0.09, 0.001, 0.025)
    wink = place((bp(white(r, n_of(0.05)), 4200, 1.5) * ad(0.05, 0.0002, 0.004), 0.06 + 0.01 * k, 0.6), length=dur)
    tink = place((modal([2400, 3700], [0.02, 0.014], [0.25, 0.15], 0.1), 0.06, 0.5), length=dur)
    return lp(crush(click * 1.7 + place((pop, 0.0, 0.8), length=dur) + wink * 1.4 + tink, 9, 1), 6500)


@sound("sig_thunk", "weapon", 2)
def sig_thunk(k):
    """Grundl slug mortar: a deep thunk. Sub-bass, a dull knock and almost nothing above 1 kHz."""
    r, dur = R("sig_thunk", k), 0.5
    n = n_of(dur)
    sub = sine(sweep([95, 85][k], 34, dur)) * ad(dur, 0.003, 0.12)
    body = sine(sweep(190, 70, dur)) * ad(dur, 0.002, 0.05) * 0.6
    knock = lp(white(r, n), 520) * ad(dur, 0.001, 0.045) * 0.9
    return lp(crush(np.tanh(2.2 * sub) * 0.8 + body * 1.2 + knock * 1.4, 10, 2), 1600)


@sound("sig_hiss", "weapon", 2)
def sig_hiss(k):
    """Mire steam lance: a hiss. A valve thump, then a long rush of steam with a thin whistle riding on it."""
    r, dur = R("sig_hiss", k), 0.95
    n = n_of(dur)
    rush = hp(white(r, n), [2800, 2400][k]) * env(dur, [(0, 0), (0.03, 1), (0.5, 0.8), (0.95, 0)])
    whistle = bp(white(r, n), sweep(4200, 3000, dur), 8.0) * env(dur, [(0, 0), (0.08, 1), (0.6, 0.6), (0.95, 0)]) * 0.6
    valve = place((sine(sweep(200, 80, 0.1)) * ad(0.1, 0.001, 0.03), 0.0, 1.0), length=dur)
    return lp(crush(rush * 0.45 + whistle + valve, 10, 2), 6800)


@sound("sig_arc", "weapon", 2)
def sig_arc(k):
    """Gauntling arc hammer: an electric crack. A broadband snap, a falling FM arc, a mains-hum buzz, sparks and a thump."""
    r, dur = R("sig_arc", k), 0.6
    n = n_of(dur)
    crack = white(r, n) * ad(dur, 0.0002, 0.004) * 1.6
    arc = fm(sweep(1800 - 200 * k, 300, dur), 1.0, env(dur, [(0, 8.0), (0.5, 3.0)]), n) * ad(dur, 0.001, 0.09) * 0.5
    buzz = lp(square(60, n) + 0.5 * square(120, n), 900) * ad(dur, 0.002, 0.16) * 0.5
    sparks = lp(crackle(r, n, 160, 0.0008, 1.2), 6500) * decay(dur, 0.15)
    thump = sine(sweep(130, 45, dur)) * ad(dur, 0.002, 0.06) * 0.9
    return lp(crush(crack * 2.4 + arc * 1.2 + buzz * 0.3 + sparks * 1.2 + thump * 0.5, 9, 1), 6500)


@sound("sig_volley", "weapon", 2)
def sig_volley(k):
    """Human volley rack: a rippled multi-shot. Three launches in quick order, each a little higher, so it ripples."""
    r, dur = R("sig_volley", k), 1.35
    layers = []
    for i in range(3):
        m = n_of(0.8)
        fc = env(0.8, [(0, 380 + 80 * i), (0.25, 2400 + 300 * i + 100 * k), (0.8, 650)])
        w = bp(white(r, m), fc, 1.4) * swell(0.8, 0.2, 0.55)
        th = place((sine(sweep(95 + 10 * i, 42, 0.25)) * ad(0.25, 0.002, 0.07), 0.0, 1.1), length=0.8)
        latch = place((modal(BAR[:4] * (290 + 25 * i), [0.06, 0.04, 0.025, 0.015], [0.5, 0.35, 0.2, 0.1], 0.15, r, 0.01), 0.0, 0.4), length=0.8)
        layers.append((mix(w * 1.2, th, latch), 0.15 * i, 0.75))
    return lp(crush(place(*layers, length=dur), 10, 2), 5800)
