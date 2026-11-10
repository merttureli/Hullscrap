"""Every Hullscrap sound effect as a recipe: punchy retro-industrial, sfxr-like cores layered with inharmonic scrap-metal body,
a little bit-crush grit and nothing harsh above ~6 kHz. A recipe takes the variant number k (0-based) and returns a float
array (mono, or stereo for loops; a loop returns length + tail seconds, build_sfx.py cross-fades the tail onto the start).
Each sound seeds its own noise from its name, so the output never changes."""
import numpy as np
from dsp import *

REG = {}   # name -> {fn, variants, family, loop: (length, tail) or None}

# loudness targets (active RMS, dBFS) per family; the game trims individual ids in data/audio.json
FAMILY_RMS = {"weapon": -17.0, "rapid": -24.0, "hit": -15.0, "boom": -13.0, "ship": -17.0, "loop": -23.0, "raft": -21.0,
              "build": -20.0, "crew": -22.0, "ui": -23.0, "alarm": -15.0,
              # round 2: the ambience sits far under the effects (beds -30, hazards -26, footsteps and hums -32 dBFS RMS)
              "bed": -30.0, "hazard": -26.0, "foot": -32.0, "hum": -32.0, "machine": -29.0}


def sound(name, family, variants=1, loop=None):
    def deco(fn):
        REG[name] = {"fn": fn, "variants": variants, "family": family, "loop": loop}
        return fn
    return deco


def R(name, k):
    return rng_for(name, k)


def mix(*parts):
    """Sum equal-length arrays (a part may be shorter: it is padded)."""
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


# --- weapons ------------------------------------------------------------------------------------------------------------

@sound("laser", "weapon", 3)
def laser(k):
    r, dur = R("laser", k), 0.30
    n = n_of(dur)
    f = sweep([2000, 2400, 1700][k], [260, 330, 220][k], dur)
    core = lp(0.6 * saw(f) + 0.4 * square(f * 0.5), 4200) * ad(dur, 0.002, [0.075, 0.065, 0.09][k])
    base = [380, 430, 350][k]
    clank = modal(BAR[:5] * base, [0.05, 0.04, 0.03, 0.02, 0.012], [0.5, 0.3, 0.2, 0.1, 0.05], dur, r, 0.01) * 0.4
    tick = bp(white(r, n), 3000, 1.0) * ad(dur, 0.0003, 0.006) * 0.5
    return lp(crush(core + clank + tick, 10, 2), 6000)


@sound("bolt", "weapon", 3)
def bolt(k):
    r, dur = R("bolt", k), 0.34
    n = n_of(dur)
    thump = sine(sweep([170, 150, 195][k], 55, dur)) * ad(dur, 0.001, 0.07)
    crack = bp(white(r, n), sweep(2400, 900, dur), 1.2) * ad(dur, 0.0005, 0.035)
    ping = modal(BAR[:4] * [520, 610, 470][k], [0.09, 0.06, 0.04, 0.03], [0.4, 0.25, 0.15, 0.08], dur, r, 0.01)
    return lp(crush(thump * 1.1 + crack * 0.9 + ping * 0.4, 9, 2), 6000)


@sound("flak", "weapon", 2)
def flak(k):
    """Flak: a breech crack, a low boom (60-120 Hz punch), a metal clank of the mount and a scatter of shrapnel."""
    r, dur = R("flak", k), 0.6
    n = n_of(dur)
    click = bp(white(r, n), 3200, 0.8) * ad(dur, 0.0003, 0.006)
    boom = sine(sweep([125, 105][k], 45, dur)) * ad(dur, 0.002, 0.11)
    clank = place((sample("heavy/metal_clink", [0.62, 0.55][k]), 0.012, 1.0), length=dur) * ad(dur, 0.001, 0.2)
    grains = np.zeros(n)
    for off in ([14, 30, 49, 70, 94, 121] if k == 0 else [12, 26, 44, 66, 87, 115]):
        g = lp(white(r, n_of(0.1)), 2600) * ad(0.1, 0.0005, 0.02)
        i = n_of(off / 1000.0)
        grains[i:i + len(g)] += g * (0.6 + 0.4 * r.random())
    rattle = modal(PLATE * [900, 760][k], [0.05] * 7, [0.2, 0.18, 0.15, 0.12, 0.1, 0.08, 0.06], dur, r, 0.02) * decay(dur, 0.06) * 0.4
    return lp(crush(click * 1.0 + boom * 1.1 + clank * 0.55 + grains * 1.3 + rattle, 9, 2), 5500)


@sound("missile_launch", "weapon", 2)
def missile_launch(k):
    """Missile launch: an ignition pop and a rail clack, then a rocket hiss that rushes up and away."""
    r, dur = R("missile_launch", k), 1.0
    n = n_of(dur)
    pop = bp(white(r, n), 900, 0.9) * ad(dur, 0.0005, 0.03)
    thump = sine(sweep([150, 128][k], 48, dur)) * ad(dur, 0.002, 0.07)
    clack = place((sample("heavy/metal_clink", [1.0, 0.85][k]), 0.03, 1.0), length=dur) * ad(dur, 0.001, 0.12)
    fc = env(dur, [(0, 300), (0.12, 900), (0.3, [2600, 2200][k]), (1.0, 600)])
    whoosh = bp(white(r, n), fc, 1.4) * env(dur, [(0, 0), (0.05, 0.25), (0.3, 1), (0.6, 0.6), (1.0, 0)])
    whoosh = np.concatenate([np.zeros(n_of(0.03)), whoosh])[:n]
    hiss = hp(white(r, n), 2200) * ad(dur, 0.04, 0.3) * 0.1
    return lp(crush(pop * 1.0 + thump * 1.0 + clack * 0.45 + whoosh * 1.4 + hiss, 10, 2), 5800)


@sound("beam_loop", "loop", 1, loop=(2.0, 0.25))
def beam_loop(k):
    tot = 2.25
    n, t = n_of(tot), tt(tot)
    chans = []
    for c in range(2):
        r = R("beam_loop", c)
        hum = 0.5 * saw(110, n, 0.25 * c) + 0.25 * saw(165, n) + 0.4 * sine(220, n, 0.1 * c)
        hum = lp(hum, 1400)
        shim = fm(660, 2.0, 2.0 + 1.5 * np.sin(TAU * 3 * t), n) * 0.18
        sizz = bp(white(r, n), 3200, 1.0) * (0.55 + 0.45 * np.sin(TAU * 6 * t + c)) * 0.22
        chans.append((hum + shim + sizz) * (1.0 + 0.15 * np.sin(TAU * 4 * t)))
    return stereo(*chans)


@sound("ion", "weapon", 2)
def ion(k):
    r, dur = R("ion", k), 0.5
    n = n_of(dur)
    f = sweep([1900, 1500][k], 190, dur)
    zap = fm(f, 1.41, env(dur, [(0, 6.0), (0.4, 1.0), (0.5, 0.5)]), n) * ad(dur, 0.002, 0.13)
    trem = 0.65 + 0.35 * square(55, n)
    zap = lp(zap * trem, 5200)
    spit = lp(crackle(r, n, 70, 0.0012), 5000) * decay(dur, 0.18) * 0.7
    low = sine(sweep(180, 70, dur)) * ad(dur, 0.002, 0.08) * 0.6
    return lp(crush(zap + spit + low, 10, 2), 5200)


@sound("rapid_tick", "rapid", 3)
def rapid_tick(k):
    r, dur = R("rapid_tick", k), 0.08
    n = n_of(dur)
    click = bp(white(r, n), 2800 + 300 * k, 1.5) * ad(dur, 0.0003, 0.009)
    tone = sine(sweep(1100 - 100 * k, 600, dur)) * ad(dur, 0.0005, 0.014) * 0.5
    ting = modal([1900 + 200 * k, 3100], [0.007, 0.005], [0.3, 0.2], dur) * 0.4
    return lp(crush(click + tone + ting, 8, 2), 5500)


# --- impacts ------------------------------------------------------------------------------------------------------------

@sound("hit_hull", "hit", 3)
def hit_hull(k):
    r, dur = R("hit_hull", k), 0.7
    n = n_of(dur)
    base = [300, 255, 350][k]
    ring = modal(BAR * base, [0.26, 0.18, 0.12, 0.08, 0.05, 0.03], [1.0, 0.7, 0.5, 0.35, 0.2, 0.12], dur, r, 0.01)
    thud = place((sine(sweep(130, 55, 0.14)) * ad(0.14, 0.001, 0.045), 0.0, 1.0), length=dur)
    strike = bp(white(r, n), 2200, 0.9) * ad(dur, 0.0003, 0.012)
    return lp(crush(ring * 0.55 + thud * 1.1 + strike * 0.7, 10, 1), 6000)


@sound("hit_shield", "hit", 3)
def hit_shield(k):
    r, dur = R("hit_shield", k), 0.55
    n = n_of(dur)
    f0 = [1200, 1500, 1000][k]
    a = fm(f0, 1.5, env(dur, [(0, 5.0), (0.25, 1.5), (0.55, 0.5)]), n) * ad(dur, 0.004, 0.13)
    b = fm(f0 * 1.5, 2.0, 2.0, n) * ad(dur, 0.004, 0.09) * 0.5
    up = place((sine(sweep(500, 2200, 0.12)) * ad(0.12, 0.002, 0.04), 0.0, 0.6), length=dur)
    x = chorus(a + b + up, 0.004, 5.0, 0.6)
    return reverb(lp(lp(x, 5000), 5000), 0.3, 0.2, 11 + k)


@sound("shield_down", "hit", 1)
def shield_down(k):
    r, dur = R("shield_down", k), 1.1
    n = n_of(dur)
    f = sweep(700, 45, dur)
    s = (0.5 * saw(f) + 0.3 * square(f * 0.5)) * env(dur, [(0, 0), (0.02, 1), (0.7, 0.6), (1.1, 0)])
    s = lp(s, sweep(4000, 150, dur), 1.0)
    sparks = lp(crackle(r, n, 120, 0.001), 5000) * decay(dur, 0.2) * 0.8
    boom = place((sine(sweep(80, 35, 0.5)) * ad(0.5, 0.004, 0.14), 0.45, 0.9), length=dur)
    return crush(s * 0.9 + sparks + boom, 10, 2)


@sound("shield_up", "hit", 1)
def shield_up(k):
    notes = [523.25, 659.25, 783.99, 1046.5]
    layers = []
    for i, f in enumerate(notes):
        layers.append((fm(f, 3.5, env(0.6, [(0, 2.0), (0.4, 0.2)]), n_of(0.6)) * ad(0.6, 0.002, 0.16 + 0.04 * i), 0.07 * i, 0.7))
    x = place(*layers, length=0.9)
    return reverb(lp(x, 6000), 0.6, 0.3, 21)


@sound("explosion_s", "boom", 2)
def explosion_s(k):
    r, dur = R("explosion_s", k), 0.85
    n = n_of(dur)
    body = lp(white(r, n), sweep([2400, 2000][k], 160, dur), 0.9) * ad(dur, 0.002, 0.2)
    thump = sine(sweep(90 - 15 * k, 28, dur)) * ad(dur, 0.002, 0.24)
    crunch = lp(crackle(r, n, 45, 0.003), 3500) * decay(dur, 0.25) * 0.5
    return lp(crush(body * 2.0 + thump * 1.0 + crunch * 1.2, 9, 2), 5000)


@sound("explosion_l", "boom", 1)
def explosion_l(k):
    r, dur = R("explosion_l", k), 2.0
    n = n_of(dur)
    body = lp(white(r, n), sweep(3200, 90, dur), 0.9) * ad(dur, 0.003, 0.55)
    sub = sine(sweep(62, 22, dur)) * ad(dur, 0.003, 0.7)
    debris = lp(crackle(r, n, 60, 0.004, 1.5), 3000) * env(dur, [(0, 0), (0.3, 1), (1.5, 0.3), (2.0, 0)])
    boom2 = place((lp(white(r, n_of(0.5)), 600) * ad(0.5, 0.002, 0.12), 0.18, 0.6), length=dur)
    x = lp(crush(body * 1.7 + sub * 1.1 + debris * 0.9 + boom2 * 1.3, 9, 2), 4800)
    return reverb(x, 1.0, 0.22, 31)


@sound("part_destroyed", "boom", 1)
def part_destroyed(k):
    r, dur = R("part_destroyed", k), 1.2
    n = n_of(dur)
    body = lp(white(r, n), sweep(2200, 200, dur), 0.9) * ad(dur, 0.002, 0.2)
    thump = sine(sweep(100, 32, dur)) * ad(dur, 0.002, 0.2)
    hits = []
    for i in range(5):
        base = 200 + r.random() * 400
        hits.append((modal(BAR[:5] * base, [0.12, 0.08, 0.05, 0.03, 0.02], [0.6, 0.4, 0.25, 0.15, 0.08], 0.4, r, 0.01), 0.04 + i * 0.09 + r.random() * 0.04, 0.35))
    clanks = place(*hits, length=dur)
    fizz = hp(white(r, n), 3000) * env(dur, [(0, 0), (0.1, 1), (0.9, 0)]) * decay(dur, 0.4) * 0.15
    return lp(crush(body * 1.7 + thump * 0.9 + clanks * 1.3 + fizz, 9, 2), 5500)


@sound("breach", "hit", 1)
def breach(k):
    r, dur = R("breach", k), 1.7
    n = n_of(dur)
    hiss = bp(white(r, n), env(dur, [(0, 3400), (1.7, 1100)]), 0.7) * env(dur, [(0, 0), (0.03, 1), (0.5, 0.8), (1.7, 0)])
    whump = place((sine(sweep(80, 38, 0.3)) * ad(0.3, 0.003, 0.09), 0.0, 1.2), length=dur)
    rumble = lp(coloured(r, n, 2.0), 220) * env(dur, [(0, 0), (0.1, 1), (1.7, 0)]) * 0.5
    creak = modal([140, 211, 337, 508], [0.5, 0.35, 0.3, 0.2], [0.5, 0.3, 0.2, 0.1], dur, r, 0.02) * env(dur, [(0, 0), (0.15, 1), (0.8, 0)]) * 0.25
    return lp(crush(hiss * 0.55 + whump + rumble + creak, 10, 2), 5500)


@sound("collision", "boom", 1)
def collision(k):
    """A glancing collision: a hull thud, a short crunch, a clang of struck plate and a scrape that dies away."""
    r, dur = R("collision", k), 0.8
    n = n_of(dur)
    thud = sine(sweep(105, 38, dur)) * ad(dur, 0.002, 0.13)
    crunch = lp(white(r, n), 900) * ad(dur, 0.001, 0.07)
    clang = place((sample("heavy/metal_bong", 0.85), 0.0, 1.0), length=dur) * ad(dur, 0.001, 0.2)
    clunks = modal(BAR * 175, [0.2, 0.14, 0.1, 0.07, 0.05, 0.03], [0.9, 0.6, 0.45, 0.3, 0.2, 0.1], dur, r, 0.02)
    scrape = bp(white(r, n), sweep(900, 350, dur), 2.0) * env(dur, [(0, 0), (0.05, 1), (0.5, 0.2), (0.8, 0)]) * 0.5
    return lp(crush(thud * 1.0 + crunch * 1.2 + clang * 0.5 + clunks * 0.4 + scrape * 1.1, 9, 2), 5200)


# --- ship ---------------------------------------------------------------------------------------------------------------

@sound("engine_loop", "loop", 1, loop=(3.0, 0.3))
def engine_loop(k):
    tot = 3.3
    n, t = n_of(tot), tt(tot)
    chans = []
    for c in range(2):
        r = R("engine_loop", c)
        rumble = tile_to(band_noise(r, n_of(3.0), 28, 170, 2.0), n)
        tone = sine(48, n, 0.07 * c) + 0.7 * sine(96, n) + 0.5 * sine(144, n, 0.2 * c) + 0.4 * sine(192, n) + 0.3 * sine(240, n, 0.1 * c) + 0.5 * lp(saw(48, n), 500)
        tone = tone * (1.0 + 0.18 * np.sin(TAU * 8 * t + c))
        mid = tile_to(band_noise(r, n_of(3.0), 150, 600, 0.0), n) * 0.25
        wind = bp(white(r, n), 800, 0.7) * 0.05
        chans.append(rumble * 0.7 + tone * 0.7 + mid + wind)
    return stereo(*chans)


@sound("jump_spool", "ship", 1)
def jump_spool(k):
    r, dur = R("jump_spool", k), 3.0
    n = n_of(dur)
    f = sweep(110, 2600, dur)
    amp = env(dur, [(0, 0.05), (2.6, 1.0), (3.0, 0.0)], power=2.0)
    whine = 0.35 * saw(f) + 0.2 * sine(f * 2) + 0.25 * sine(f * 1.01)
    whine = lp(whine, sweep(500, 4800, dur), 1.2)
    trem = 1.0 - 0.3 * (0.5 + 0.5 * sine(env(dur, [(0, 2), (3, 26)]), n))
    noise = bp(white(r, n), sweep(300, 3500, dur), 1.5) * 0.3
    sub = sine(sweep(40, 90, dur)) * 0.22
    return (whine * trem + noise + sub) * amp


@sound("jump", "ship", 1)
def jump(k):
    r, dur = R("jump", k), 1.5
    n = n_of(dur)
    whoosh = bp(white(r, n), env(dur, [(0, 200), (0.35, 5000), (0.5, 3000), (1.5, 250)]), 1.2) * swell(dur, 0.3, 1.0)
    zip_ = place((sine(sweep(2200, 60, 0.7)) * ad(0.7, 0.003, 0.2), 0.0, 0.5), length=dur)
    boom = place((sine(sweep(120, 35, 0.6)) * ad(0.6, 0.002, 0.2), 0.0, 1.0), length=dur)
    return reverb(lp(whoosh * 1.3 + zip_ + boom, 6000), 0.7, 0.2, 41)


@sound("arrive", "ship", 1)
def arrive(k):
    r, dur = R("arrive", k), 1.3
    n = n_of(dur)
    rev = bp(white(r, n), env(dur, [(0, 3500), (0.5, 500), (1.3, 300)]), 1.0) * swell(dur, 0.12, 1.0)
    thud = place((sine(sweep(100, 40, 0.5)) * ad(0.5, 0.002, 0.15), 0.0, 1.0), length=dur)
    chime = place((fm(392.0, 3.5, 1.2, n_of(0.6)) * ad(0.6, 0.003, 0.16), 0.1, 0.25), (fm(587.33, 3.5, 1.0, n_of(0.6)) * ad(0.6, 0.003, 0.18), 0.2, 0.2), length=dur)
    return reverb(lp(rev * 0.9 + thud * 1.1 + chime, 5500), 0.7, 0.22, 43)


# --- raft loop ----------------------------------------------------------------------------------------------------------

@sound("collect", "raft", 3)
def collect(k):
    # a short dry metal clunk: no tonal blip (it fought the music); inharmonic bar partials with very fast decay + a noise tick
    r, dur = R("collect", k), 0.14
    n = n_of(dur)
    f0 = [520, 610, 450][k]
    clunk = modal(BAR[:5] * f0, [0.018, 0.014, 0.01, 0.007, 0.005], [0.5, 0.4, 0.3, 0.2, 0.12], dur, r, 0.06)
    tick = bp(white(r, n), 3200, 0.8) * ad(dur, 0.0004, 0.006) * 0.5
    thud = lp(white(r, n), 700) * ad(dur, 0.0006, 0.02) * 0.5
    return lp(crush(clunk * 0.9 + tick + thud, 10, 2), 5200) * ad(dur, 0.0005, 0.05)


@sound("tractor_loop", "loop", 1, loop=(2.0, 0.25))
def tractor_loop(k):
    tot = 2.25
    n, t = n_of(tot), tt(tot)
    chans = []
    for c in range(2):
        r = R("tractor_loop", c)
        hum = 0.5 * sine(140, n, 0.1 * c) + 0.3 * sine(280, n) + 0.3 * tri(70, n)
        hum = hum * (0.75 + 0.25 * np.sin(TAU * 6 * t))
        shim = bp(white(r, n), 1200 + 500 * np.sin(TAU * 1 * t + c), 2.5) * 0.3
        vib = fm(420, 1.0, 1.2 + np.sin(TAU * 2 * t), n) * 0.12
        chans.append(hum + shim + vib)
    return stereo(*chans)


@sound("intake_pull", "raft", 1)
def intake_pull(k):
    r, dur = R("intake_pull", k), 0.6
    n = n_of(dur)
    pull = bp(white(r, n), sweep(250, 1400, 0.45), 1.5) * swell(dur, 0.3, 0.25)
    thunk = place((sine(sweep(160, 80, 0.14)) * ad(0.14, 0.002, 0.04), 0.4, 1.0), length=dur)
    return lp(crush(pull * 1.2 + thunk, 10, 2), 5000)


# --- build --------------------------------------------------------------------------------------------------------------

@sound("place_tile", "build", 2)
def place_tile(k):
    r, dur = R("place_tile", k), 0.16
    n = n_of(dur)
    thunk = sine(sweep(240 - 25 * k, 120, dur)) * ad(dur, 0.001, 0.025)
    click = bp(white(r, n), 1600 + 400 * k, 1.0) * ad(dur, 0.0004, 0.012) * 0.6
    tink = modal([1800 + 300 * k, 2900], [0.03, 0.02], [0.2, 0.12], dur) * 0.5
    return lp(crush(thunk * 1.1 + click + tink, 10, 1), 5500)


@sound("place_part", "build", 1)
def place_part(k):
    r, dur = R("place_part", k), 0.45
    n = n_of(dur)
    clunk = sine(sweep(160, 70, dur)) * ad(dur, 0.001, 0.05)
    latch = place((modal(BAR[:4] * 520, [0.06, 0.04, 0.025, 0.015], [0.5, 0.35, 0.2, 0.1], 0.25, r, 0.01), 0.08, 0.6), length=dur)
    servo = place((lp(saw(sweep(180, 380, 0.15)), 1000) * swell(0.15, 0.05, 0.08), 0.13, 0.25), length=dur)
    click = bp(white(r, n), 1800, 1.0) * ad(dur, 0.0004, 0.01) * 0.5
    return lp(crush(clunk * 1.2 + latch + servo + click, 10, 1), 5500)


@sound("remove", "build", 1)
def remove(k):
    r, dur = R("remove", k), 0.32
    n = n_of(dur)
    scrape = bp(white(r, n), sweep(2400, 500, 0.25), 1.5) * ad(dur, 0.003, 0.09)
    thud = sine(sweep(110, 55, dur)) * ad(dur, 0.001, 0.04)
    return lp(crush(scrape * 1.2 + thud * 0.6, 10, 2), 5000)


@sound("invalid", "build", 1)
def invalid(k):
    dur = 0.3
    n = n_of(dur)
    buzz = lp(0.5 * square(150, n) + 0.5 * square(158.5, n), 1300)
    pulses = np.zeros(n)
    for a, b in ((0.0, 0.1), (0.14, 0.26)):
        pulses += env(dur, [(a, 0), (a + 0.008, 1), (b - 0.015, 1), (b, 0)])
    return crush(buzz * pulses, 9, 2)


@sound("rotate", "build", 1)
def rotate(k):
    r, dur = R("rotate", k), 0.18
    layers = []
    for i, f in enumerate([900, 1100, 1350]):
        tk = tri(f, n_of(0.05)) * ad(0.05, 0.0004, 0.008) + bp(white(r, n_of(0.05)), 2500, 1.0) * ad(0.05, 0.0002, 0.004) * 0.5
        layers.append((tk, 0.05 * i, 0.8))
    return lp(crush(place(*layers, length=dur), 9, 1), 5500)


@sound("door", "build", 1)
def door(k):
    r, dur = R("door", k), 0.6
    n = n_of(dur)
    hiss = bp(white(r, n), 2500, 0.8) * env(dur, [(0, 0), (0.02, 1), (0.24, 0.0)]) * 0.9
    chunk = sine(sweep(140, 60, dur)) * ad(dur, 0.001, 0.04)
    slide = place((lp(white(r, n_of(0.3)), 700) * swell(0.3, 0.08, 0.15), 0.16, 0.5), length=dur)
    latch = place((modal(BAR[:3] * 800, [0.04, 0.025, 0.015], [0.4, 0.25, 0.12], 0.15, r, 0.01), 0.45, 0.6), length=dur)
    return lp(crush(hiss + chunk * 1.1 + slide + latch, 10, 1), 5500)


# --- crew and drone -----------------------------------------------------------------------------------------------------

@sound("repair_loop", "loop", 1, loop=(2.0, 0.25))
def repair_loop(k):
    tot = 2.25
    n, t = n_of(tot), tt(tot)
    chans = []
    for c in range(2):
        r = R("repair_loop", c)
        flare = 0.6 + 0.4 * np.clip(lp1(white(r, n), 9.0) * 6.0, -1, 1)
        sizzle = bp(white(r, n), 3500, 0.6) * 0.3 * flare
        pops = crackle(r, n, 180, 0.0015, 0.8, 0.3)
        buzz = lp(saw(100, n, 0.2 * c), 1500) * 0.12 * (0.7 + 0.3 * np.sin(TAU * 3 * t))
        chans.append(lp(lp(sizzle + pops * 0.6 + buzz, 4800), 4800))
    return stereo(*chans)


@sound("extinguish", "crew", 1)
def extinguish(k):
    r, dur = R("extinguish", k), 0.95
    n = n_of(dur)
    hiss = bp(white(r, n), env(dur, [(0, 2500), (0.8, 1800)]), 0.8) * env(dur, [(0, 0), (0.03, 1), (0.3, 0.8), (0.95, 0)])
    foomp = sine(sweep(120, 50, dur)) * ad(dur, 0.002, 0.07) * 0.9
    return lp(crush(hiss * 0.8 + foomp, 10, 2), 5200)


@sound("fire_loop", "loop", 1, loop=(2.0, 0.3))
def fire_loop(k):
    tot = 2.3
    n = n_of(tot)
    chans = []
    for c in range(2):
        r = R("fire_loop", c)
        rumble = tile_to(band_noise(r, n_of(2.0), 40, 350, 2.0), n) * 0.9
        whoosh = bp(white(r, n), 700 + 250 * lp1(white(r, n), 2.0) * 8.0, 1.0) * 0.3
        pops = lp(crackle(r, n, 25, 0.003, 1.5), 3500) * 0.8
        chans.append(rumble * 0.6 + whoosh * 1.6 + pops * 1.2)
    return stereo(*chans)


@sound("drone_beep", "crew", 2)
def drone_beep(k):
    notes = [(880.0, 1175.0), (1175.0, 784.0)][k]
    layers = []
    for i, f in enumerate(notes):
        n = n_of(0.1)
        b = (0.6 * tri(f, n) + 0.25 * square(f, n)) * env(0.1, [(0, 0), (0.008, 1), (0.07, 0.8), (0.1, 0)])
        layers.append((b, 0.11 * i, 0.8))
    return lp(crush(place(*layers, length=0.22), 10, 2), 2800)


@sound("crew_hurt", "crew", 1)
def crew_hurt(k):
    r, dur = R("crew_hurt", k), 0.28
    n = n_of(dur)
    thud = sine(sweep(160, 60, dur)) * ad(dur, 0.002, 0.05)
    body = lp(white(r, n), 500) * ad(dur, 0.001, 0.045) * 0.7
    return lp(thud * 1.1 + body, 900)


# --- UI -----------------------------------------------------------------------------------------------------------------

@sound("click", "ui", 1)
def click(k):
    r, dur = R("click", k), 0.07
    n = n_of(dur)
    return crush(sine(1300, n) * ad(dur, 0.0005, 0.009) * 0.5 + bp(white(r, n), 3000, 1.0) * ad(dur, 0.0002, 0.005) * 0.4, 9, 1)


@sound("hover", "ui", 1)
def hover(k):
    dur = 0.04
    return sine(2000, n_of(dur)) * ad(dur, 0.0005, 0.007) * 0.4


@sound("open", "ui", 1)
def open_(k):
    r, dur = R("open", k), 0.24
    n = n_of(dur)
    t_ = tri(sweep(320, 640, dur), n) * swell(dur, 0.04, 0.12)
    air = bp(white(r, n), sweep(800, 2400, dur), 1.5) * swell(dur, 0.06, 0.12) * 0.3
    return lp(crush(t_ * 0.6 + air, 10, 1), 4500)


@sound("close", "ui", 1)
def close(k):
    r, dur = R("close", k), 0.22
    n = n_of(dur)
    t_ = tri(sweep(640, 300, dur), n) * swell(dur, 0.02, 0.14)
    air = bp(white(r, n), sweep(2400, 700, dur), 1.5) * swell(dur, 0.03, 0.14) * 0.3
    return lp(crush(t_ * 0.6 + air, 10, 1), 4500)


@sound("event_open", "ui", 1)
def event_open(k):
    r, dur = R("event_open", k), 0.75
    n = n_of(dur)
    s1 = bp(white(r, n), 1500, 0.8) * env(dur, [(0, 0), (0.01, 0.6), (0.1, 0.25), (0.11, 0)]) * 0.5
    c1 = place((square(1500, n_of(0.08)) * env(0.08, [(0, 0), (0.005, 1), (0.07, 1), (0.08, 0)]), 0.12, 0.5), length=dur)
    c2 = place((square(1100, n_of(0.08)) * env(0.08, [(0, 0), (0.005, 1), (0.07, 1), (0.08, 0)]), 0.22, 0.5), length=dur)
    tail = bp(white(r, n), 1800, 0.8) * env(dur, [(0, 0), (0.3, 0), (0.32, 0.5), (0.75, 0)]) * 0.4
    x = hp(lp(s1 + c1 + c2 + tail, 3200), 300)
    return crush(x, 8, 2)


@sound("toast", "ui", 1)
def toast(k):
    dur = 0.5
    n = n_of(dur)
    b = fm(988.0, 2.0, env(dur, [(0, 2.0), (0.3, 0.3)]), n) * ad(dur, 0.002, 0.12)
    return reverb(lp(b, 5000), 0.35, 0.15, 51)


@sound("buy", "ui", 1)
def buy(k):
    r = R("buy", k)
    n = n_of(0.45)
    a = fm(1319.0, 3.5, env(0.45, [(0, 1.6), (0.3, 0.2)]), n) * ad(0.45, 0.002, 0.1)
    b = fm(1760.0, 3.5, env(0.45, [(0, 1.6), (0.3, 0.2)]), n) * ad(0.45, 0.002, 0.14)
    tk = bp(white(r, n_of(0.05)), 4000, 1.0) * ad(0.05, 0.0003, 0.008)
    return lp(crush(place((tk, 0.0, 0.5), (a, 0.0, 0.7), (b, 0.08, 0.7), length=0.5), 10, 1), 5500)


@sound("unlock", "ui", 1)
def unlock(k):
    notes = [392.0, 523.25, 659.25, 783.99]
    layers = []
    for i, f in enumerate(notes):
        layers.append((fm(f, 3.5, env(0.8, [(0, 1.8), (0.5, 0.2)]), n_of(0.8)) * ad(0.8, 0.002, 0.2), 0.09 * i, 0.7))
    layers.append((fm(1567.98, 3.5, 1.0, n_of(0.8)) * ad(0.8, 0.002, 0.25), 0.4, 0.3))
    return reverb(lp(place(*layers, length=1.2), 6000), 0.8, 0.3, 53)


# --- alarms -------------------------------------------------------------------------------------------------------------

@sound("red_alert", "alarm", 1)
def red_alert(k):
    layers = []
    for off in (0.0, 0.45):
        n = n_of(0.4)
        f = sweep(420, 640, 0.4)
        p = (0.5 * saw(f, n) + 0.3 * square(f, n)) * env(0.4, [(0, 0), (0.02, 1), (0.34, 1), (0.4, 0)])
        layers.append((p, off, 1.0))
    return lp(crush(place(*layers, length=0.9), 10, 2), 2400)


@sound("breach_alert", "alarm", 1)
def breach_alert(k):
    r, dur = R("breach_alert", k), 1.2
    n = n_of(dur)
    p1 = place((0.6 * saw(sweep(440, 330, 0.3), n_of(0.3)) * env(0.3, [(0, 0), (0.01, 1), (0.25, 1), (0.3, 0)]), 0.0, 1.0), length=dur)
    p2 = place((0.6 * saw(sweep(311, 220, 0.4), n_of(0.4)) * env(0.4, [(0, 0), (0.01, 1), (0.33, 1), (0.4, 0)]), 0.34, 1.0), length=dur)
    hiss = bp(white(r, n), 2500, 0.7) * env(dur, [(0, 0), (0.05, 1), (0.7, 0.3), (1.2, 0)]) * 0.3
    sub = sine(sweep(75, 40, dur)) * ad(dur, 0.003, 0.15) * 1.0
    return reverb(lp(crush(lp(p1 + p2, 2600) + hiss + sub, 10, 2), 5000), 0.4, 0.15, 61)


@sound("tide_warning", "alarm", 1)
def tide_warning(k):
    r, dur = R("tide_warning", k), 3.6
    n = n_of(dur)
    amp = swell(dur, 1.8, 1.7)
    drone = sine(sweep(41, 48, dur)) * 0.7 + lp(saw(sweep(61, 66, dur)), 500) * 0.5 + sine(sweep(92, 86, dur)) * 0.4 + sine(sweep(123, 131, dur)) * 0.35 + sine(sweep(184, 170, dur)) * 0.2
    haze = lp(coloured(r, n, 1.0), 700) * 0.5
    toll = place((modal(BAR[:4] * 110, [1.4, 0.9, 0.6, 0.4], [0.6, 0.45, 0.3, 0.15], 2.0, r, 0.01), 1.2, 0.5), length=dur)
    return reverb((drone + haze) * amp + toll, 1.5, 0.35, 71, damp=2500)


# --- round 2: the rest of the library lives in these modules (each registers its sounds in REG on import) ------------------------
import sounds_lines   # noqa: E402,F401  weapon lines and the races' signature guns
import sounds_amb     # noqa: E402,F401  ambience beds, hazard loops, machine loops
import sounds_ship    # noqa: E402,F401  ship, crew and combat extras
import sounds_ui      # noqa: E402,F401  interface
import sounds_board   # noqa: E402,F401  boarding on foot: weapons, foes, the tracker
