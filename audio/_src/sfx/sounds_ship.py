"""Round 2, ship, crew and combat extras: footsteps, doors, the comms chirps, crafting and ammo, the hull's creak, and in a fight the
missile's pop, the shield shifting, abilities, the ion lock, a ram and a fire taking hold. Same house style as sounds.py: a sfxr-like core
under a little scrap-metal body, a touch of bit-crush, nothing harsh above ~6 kHz."""
import numpy as np
from dsp import *
from sounds import sound, R, mix


# --- crew and ship ----------------------------------------------------------------------------------------------------------

@sound("footstep", "foot", 4)
def footstep(k):
    """A boot on a metal deck: a short thud, a dull plate tick and a faint ring of the plate."""
    r, dur = R("footstep", k), 0.2
    n = n_of(dur)
    thud = sine(sweep([185, 165, 200, 175][k], 85, dur)) * ad(dur, 0.001, 0.03)
    tick = bp(white(r, n), [1500, 1300, 1700, 1400][k], 1.2) * ad(dur, 0.0003, 0.012) * 1.1
    ring = modal(PLATE * [380, 420, 350, 400][k], [0.05] * 7, [0.3, 0.25, 0.2, 0.15, 0.12, 0.1, 0.08], dur, r, 0.03) * decay(dur, 0.05) * 0.22
    return lp(crush(thud + tick + ring, 10, 1), 3200)


@sound("door_open", "build", 2)
def door_open(k):
    """A door opening: a pneumatic release, the leaves sliding back and a soft stop at the end of the track."""
    r, dur = R("door_open", k), 0.6
    n = n_of(dur)
    hiss = bp(white(r, n), sweep(1800, 3200, 0.2), 0.8) * env(dur, [(0, 0), (0.015, 1), (0.2, 0), (0.6, 0)]) * 0.9
    slide = place((lp(white(r, n_of(0.32)), 650 + 120 * k) * swell(0.32, 0.08, 0.14), 0.1, 0.55), length=dur)
    stop = place((sine(sweep(120 + 10 * k, 60, 0.12)) * ad(0.12, 0.001, 0.035), 0.4, 0.9), (modal(BAR[:3] * 700, [0.04, 0.025, 0.015], [0.4, 0.25, 0.12], 0.15, r, 0.01), 0.4, 0.4), length=dur)
    return lp(crush(hiss + slide + stop, 10, 1), 5500)


@sound("door_close", "build", 2)
def door_close(k):
    """A door closing: the leaves slide in, meet with a clunk, the latch drops and a short seal hiss follows."""
    r, dur = R("door_close", k), 0.6
    n = n_of(dur)
    slide = place((lp(white(r, n_of(0.3)), 750 - 120 * k) * swell(0.3, 0.1, 0.08), 0.0, 0.55), length=dur)
    clunk = place((sine(sweep(150 - 10 * k, 55, 0.14)) * ad(0.14, 0.001, 0.04), 0.28, 1.1), length=dur)
    latch = place((modal(BAR[:3] * (880 + 60 * k), [0.04, 0.025, 0.015], [0.5, 0.3, 0.15], 0.15, r, 0.01), 0.36, 0.6), length=dur)
    seal = bp(white(r, n), 2600, 0.8) * env(dur, [(0, 0), (0.4, 0), (0.42, 0.6), (0.6, 0)]) * 0.35
    return lp(crush(slide + clunk + latch + seal, 10, 1), 5500)


def _chirp(notes, step, r, dur, tail=True, f_lo=380.0, soft=1.0):
    """A radio chirp: short triangle-and-square notes through a narrow speaker, a squelch at the end."""
    layers = []
    for i, f in enumerate(notes):
        m = n_of(step * 0.9)
        b = (0.65 * tri(f, m) + 0.25 * square(f, m)) * env(step * 0.9, [(0, 0), (0.006, 1), (step * 0.65, 0.8), (step * 0.9, 0)])
        layers.append((b, step * i, 0.8 * soft))
    if tail:
        layers.append((bp(white(r, n_of(0.07)), 2200, 0.8) * ad(0.07, 0.002, 0.022), step * len(notes), 0.3 * soft))
    return hp(lp(crush(place(*layers, length=dur), 9, 2), 3200), f_lo)


@sound("comms_chirp", "crew", 2)
def comms_chirp(k):
    """A crewmate acknowledges a post: two quick rising notes and the squelch."""
    r = R("comms_chirp", k)
    notes = [(1100.0, 1650.0), (990.0, 1480.0)][k]
    return _chirp(notes, 0.075, r, 0.28)


@sound("hail_chirp", "crew", 1)
def hail_chirp(k):
    """The enemy hails you: three notes climbing, a pause and the squelch, with a bit of static in front."""
    r, dur = R("hail_chirp", k), 0.7
    static = place((bp(white(r, n_of(0.08)), 2000, 0.7) * ad(0.08, 0.004, 0.03), 0.0, 0.25), length=dur)
    return mix(static, np.pad(_chirp((880.0, 1175.0, 1480.0), 0.1, r, 0.5), (n_of(0.08), 0)))


@sound("surrender_chirp", "crew", 1)
def surrender_chirp(k):
    """The enemy gives up: three notes sinking, slow and soft, and the carrier fading into static."""
    r, dur = R("surrender_chirp", k), 0.9
    notes = _chirp((1175.0, 880.0, 660.0), 0.14, r, 0.62, soft=0.9)
    fade = place((bp(white(r, n_of(0.3)), 1800, 0.7) * ad(0.3, 0.01, 0.1), 0.42, 0.18), length=dur)
    return mix(notes, fade)


@sound("craft_done", "ui", 1)
def craft_done(k):
    """The fabricator or smelter has finished: a clear two-note ding (not the shop's coin and not the toast), with a short room."""
    layers = []
    for i, (f, g) in enumerate(((1568.0, 0.8), (2093.0, 0.7))):
        layers.append((fm(f, 3.5, env(0.7, [(0, 1.4), (0.4, 0.15)]), n_of(0.7)) * ad(0.7, 0.002, 0.2), 0.11 * i, g))
    return reverb(lp(place(*layers, length=0.9), 6200), 0.4, 0.18, 541)


@sound("ammo_restock", "build", 1)
def ammo_restock(k):
    """A rack takes its last shell: a scrape of the crate on the rails, a heavy clunk home and the latch."""
    r, dur = R("ammo_restock", k), 0.55
    n = n_of(dur)
    scrape = bp(white(r, n_of(0.22)), sweep(1100, 320, 0.22), 1.6) * swell(0.22, 0.04, 0.12)
    clunk = sine(sweep(130, 52, 0.2)) * ad(0.2, 0.001, 0.05)
    latch = modal(BAR[:4] * 540, [0.06, 0.04, 0.025, 0.015], [0.5, 0.35, 0.2, 0.1], 0.2, r, 0.01)
    return lp(crush(place((scrape, 0.0, 0.8), (clunk, 0.2, 1.2), (latch, 0.3, 0.55), length=dur), 10, 1), 5200)


@sound("hull_creak", "ship", 2)
def hull_creak(k):
    """The hull complains: a long groan of plate under strain, in stick-slip jerks, with a low glide beneath it and a couple of pings."""
    r, dur = R("hull_creak", k), 2.2
    n = n_of(dur)
    f0 = [74.0, 62.0][k]
    glide = sweep(f0, f0 * 0.78, dur)
    body = lp(saw(glide), 420) * 0.5 + sine(glide) * 0.5
    jerk = 0.35 + 0.65 * np.abs(saw(sweep(13.0, 9.0, dur)))
    creak = bp(white(r, n), sweep(520 + 80 * k, 330, dur), 6.0) * jerk * 0.8
    pings = place((modal(BAR[:4] * (480 + 120 * k), [0.2, 0.12, 0.07, 0.04], [0.5, 0.3, 0.15, 0.08], 0.5, r, 0.01), 0.7, 0.18),
                  (modal(BAR[:4] * (390 + 90 * k), [0.2, 0.12, 0.07, 0.04], [0.5, 0.3, 0.15, 0.08], 0.5, r, 0.01), 1.4, 0.13), length=dur)
    return lp(crush((body + creak) * swell(dur, 0.7, 1.0) + pings, 10, 2), 3600)


# --- combat -----------------------------------------------------------------------------------------------------------------

@sound("missile_pop", "hit", 1)
def missile_pop(k):
    """A missile shot down: a hard pop, a puff of fragments and a tick of sparkle."""
    r, dur = R("missile_pop", k), 0.4
    n = n_of(dur)
    pop = sine(sweep(700, 150, dur)) * ad(dur, 0.0008, 0.03)
    puff = bp(white(r, n), sweep(3200, 900, dur), 0.9) * ad(dur, 0.0004, 0.05)
    frags = lp(crackle(r, n, 90, 0.0012, 1.0, 0.7), 5000) * decay(dur, 0.07) * 0.7
    thump = sine(sweep(110, 50, dur)) * ad(dur, 0.001, 0.05) * 0.8
    return lp(crush(pop * 0.9 + puff * 1.1 + frags + thump, 10, 2), 5800)


@sound("shield_shift", "ship", 1)
def shield_shift(k):
    """The shield's weight moves round the hull: a tone that slides up and settles, with a soft shimmer and a short room."""
    dur = 0.6
    n = n_of(dur)
    f = env(dur, [(0, 520), (0.25, 1250), (0.6, 930)])
    tone = fm(f, 2.0, env(dur, [(0, 2.5), (0.3, 0.7), (0.6, 0.3)]), n) * swell(dur, 0.06, 0.4)
    shim = fm(f * 1.5, 3.0, 1.0, n) * swell(dur, 0.1, 0.4) * 0.35
    return reverb(lp(chorus(tone + shim, 0.004, 4.0, 0.5), 5800), 0.35, 0.2, 551)


@sound("ability", "ship", 3)
def ability(k):
    """A system's ability switching on (and the overcharge): a whoosh that rises and a tone riding it, three flavours:
    0 charged (bright), 1 heavy (low), 2 shimmering (high)."""
    r, dur = R("ability", k), 0.75
    n = n_of(dur)
    lo, hi = [(380, 3200), (200, 1500), (700, 4600)][k]
    whoosh = bp(white(r, n), env(dur, [(0, lo), (0.35, hi), (0.75, lo * 1.5)]), 1.3) * swell(dur, 0.3, 0.4)
    tone = sine(sweep([220, 110, 440][k], [880, 330, 1760][k], 0.4)) * swell(0.4, 0.2, 0.2)
    tone = place((tone, 0.05, 0.5), length=dur)
    thump = place((sine(sweep(100, 45, 0.25)) * ad(0.25, 0.002, 0.07), 0.0, 0.8 if k == 1 else 0.5), length=dur)
    spark = fm(sweep([1800, 900, 2800][k], 400, dur), 1.5, 2.0, n) * ad(dur, 0.004, 0.12) * [0.15, 0.1, 0.3][k]
    return lp(crush(whoosh * 1.3 + tone + thump + spark, 10, 2), 5800)


@sound("ion_lock", "ship", 1)
def ion_lock(k):
    """A system locked by an ion hit: a fizz that sags, electric crackle and a downward whine."""
    r, dur = R("ion_lock", k), 0.75
    n = n_of(dur)
    fizz = hp(white(r, n), 1800) * ad(dur, 0.002, 0.2) * (0.6 + 0.4 * square(48, n))
    sag = fm(sweep(1400, 200, dur), 1.41, env(dur, [(0, 5.0), (0.6, 1.0)]), n) * ad(dur, 0.002, 0.2) * 0.5
    sparks = lp(crackle(r, n, 110, 0.001, 1.2), 5200) * decay(dur, 0.25) * 0.9
    return lp(crush(fizz * 0.35 + sag + sparks, 9, 2), 5600)


@sound("ram_impact", "boom", 1)
def ram_impact(k):
    """Two hulls drive into each other: a deep boom, a grinding crunch, a long ring of buckled plate and a rain of debris."""
    r, dur = R("ram_impact", k), 1.5
    n = n_of(dur)
    boom = sine(sweep(80, 26, dur)) * ad(dur, 0.002, 0.35)
    crunch = lp(white(r, n), sweep(1500, 200, dur), 0.9) * ad(dur, 0.001, 0.2)
    ring = modal(BAR * 95, [0.7, 0.5, 0.35, 0.25, 0.15, 0.1], [0.8, 0.6, 0.45, 0.3, 0.2, 0.1], dur, r, 0.02)
    scrape = bp(white(r, n), sweep(1200, 300, dur), 2.0) * env(dur, [(0, 0), (0.08, 1), (0.8, 0.3), (1.5, 0)]) * 0.5
    debris = lp(crackle(r, n, 55, 0.003, 1.4), 3200) * env(dur, [(0, 0), (0.2, 1), (1.1, 0.2), (1.5, 0)])
    return lp(crush(boom * 1.2 + crunch * 1.2 + ring * 0.6 + scrape + debris * 0.8, 9, 2), 4800)


@sound("fire_whoomph", "boom", 1)
def fire_whoomph(k):
    """A fire takes hold of a new cell: a soft rush of igniting air, a low whoomph and a crackle that dies away."""
    r, dur = R("fire_whoomph", k), 0.9
    n = n_of(dur)
    rush = lp(white(r, n), env(dur, [(0, 300), (0.12, 1500), (0.9, 350)])) * swell(dur, 0.06, 0.7)
    whoomph = sine(sweep(75, 32, dur)) * ad(dur, 0.01, 0.2)
    crackle_ = lp(crackle(r, n, 40, 0.003, 1.3), 3500) * env(dur, [(0, 0), (0.15, 1), (0.9, 0)]) * 0.7
    return lp(crush(rush * 1.4 + whoomph * 1.1 + crackle_, 10, 2), 3800)
