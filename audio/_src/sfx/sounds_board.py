"""Round 3, boarding on foot (docs/BOARDING.md, stage B2): the hand weapons (pistol, rifle, heavy), a melee swing, the reload and the empty click, a foe
hit and a foe down, the crawler's screech and skitter, a sentry's servo whir, the motion tracker's ping (three pitches, by distance) and the flashlight
click. Same house style as sounds.py: a sfxr-like core under a little scrap-metal body, a touch of bit-crush, nothing harsh above ~6 kHz."""
import numpy as np
from dsp import *
from sounds import sound, R, mix


# --- the hand weapons ---------------------------------------------------------------------------------------------------------

@sound("shot_pistol", "weapon", 2)
def shot_pistol(k):
    """A pistol: a sharp crack over a short thump and a small room tail."""
    r, dur = R("shot_pistol", k), 0.3
    n = n_of(dur)
    crack = bp(white(r, n), [2700, 2300][k], 0.9) * ad(dur, 0.0004, 0.016)
    thump = sine(sweep([230, 195][k], 70, dur)) * ad(dur, 0.001, 0.05)
    tail = lp(white(r, n), 1300) * ad(dur, 0.002, 0.09) * 0.3
    return lp(crush(crack * 1.1 + thump * 0.9 + tail, 10, 1), 6000)


@sound("shot_rifle", "weapon", 2)
def shot_rifle(k):
    """A rifle: a harder crack, a deeper thump and a ring of the barrel."""
    r, dur = R("shot_rifle", k), 0.42
    n = n_of(dur)
    crack = bp(white(r, n), [2100, 1800][k], 0.8) * ad(dur, 0.0004, 0.022)
    thump = sine(sweep([170, 150][k], 52, dur)) * ad(dur, 0.001, 0.07)
    ring = modal(BAR[:4] * [640, 560][k], [0.06, 0.04, 0.03, 0.02], [0.3, 0.2, 0.12, 0.08], dur, r, 0.01) * 0.5
    tail = lp(white(r, n), 1000) * ad(dur, 0.003, 0.12) * 0.35
    return lp(crush(crack * 1.0 + thump * 1.1 + ring + tail, 9, 1), 5800)


@sound("shot_heavy", "weapon", 2)
def shot_heavy(k):
    """A heavy slug gun: a flat boom with a long dark tail and a rattle of loose plates."""
    r, dur = R("shot_heavy", k), 0.7
    n = n_of(dur)
    boom = sine(sweep([130, 110][k], 36, dur)) * ad(dur, 0.002, 0.14)
    crack = bp(white(r, n), 1500, 0.7) * ad(dur, 0.0006, 0.03)
    rattle = modal(PLATE * [520, 460][k], [0.06] * 7, [0.3, 0.25, 0.2, 0.15, 0.12, 0.1, 0.08], dur, r, 0.02) * decay(dur, 0.08) * 0.35
    tail = lp(white(r, n), 700) * ad(dur, 0.004, 0.2) * 0.4
    return lp(crush(boom * 1.2 + crack * 0.9 + rattle + tail, 9, 2), 5200)


@sound("melee_swing", "crew", 2)
def melee_swing(k):
    """A swing: air rushing past, a short whoosh that rises and falls, with a dull knock at its end."""
    r, dur = R("melee_swing", k), 0.32
    n = n_of(dur)
    air = bp(white(r, n), sweep([900, 1100][k], 2600, dur), 0.9) * swell(dur, 0.12, 0.16)
    knock = place((sine(sweep(140, 70, 0.1)) * ad(0.1, 0.001, 0.03), 0.22, 0.4), length=dur)
    return lp(air * 0.8 + knock, 5000)


@sound("reload", "crew", 1)
def reload(k):
    """A reload: the magazine drops out, a beat, the new one slides in and seats, the slide snaps."""
    r, dur = R("reload", k), 0.9
    n = n_of(dur)
    out = place((modal(BAR[:3] * 760, [0.03, 0.02, 0.012], [0.5, 0.3, 0.15], 0.12, r, 0.01), 0.0, 0.7), (bp(white(r, n_of(0.04)), 2400, 1.0) * ad(0.04, 0.0003, 0.01), 0.0, 0.5), length=dur)
    slide = place((lp(white(r, n_of(0.18)), 900) * swell(0.18, 0.08, 0.08), 0.32, 0.4), length=dur)
    seat = place((sine(sweep(210, 90, 0.08)) * ad(0.08, 0.001, 0.025), 0.5, 0.9), (modal(BAR[:3] * 980, [0.03, 0.02, 0.012], [0.5, 0.3, 0.15], 0.12, r, 0.01), 0.5, 0.6), length=dur)
    snap = place((modal(BAR[:4] * 1250, [0.025, 0.018, 0.01, 0.008], [0.5, 0.35, 0.2, 0.1], 0.1, r, 0.01), 0.74, 0.8), (bp(white(r, n_of(0.03)), 3000, 1.0) * ad(0.03, 0.0003, 0.008), 0.74, 0.6), length=dur)
    return lp(crush(out + slide + seat + snap, 10, 1), 5600)


@sound("empty_click", "crew", 1)
def empty_click(k):
    """A dry click: the hammer falls on nothing."""
    r, dur = R("empty_click", k), 0.09
    n = n_of(dur)
    return lp(crush(bp(white(r, n), 2000, 1.4) * ad(dur, 0.0003, 0.008) + modal(BAR[:3] * 900, [0.02, 0.012, 0.008], [0.5, 0.3, 0.15], dur, r, 0.01) * 0.6, 9, 1), 5000)


# --- foes -----------------------------------------------------------------------------------------------------------------------

@sound("foe_hit", "hit", 3)
def foe_hit(k):
    """A round into a body: a dull wet thud and a short scrape of noise."""
    r, dur = R("foe_hit", k), 0.2
    n = n_of(dur)
    thud = sine(sweep([150, 135, 165][k], 60, dur)) * ad(dur, 0.001, 0.035)
    flesh = lp(white(r, n), [900, 750, 1000][k]) * ad(dur, 0.001, 0.04)
    return lp(crush(thud * 1.1 + flesh * 0.9, 10, 1), 3600)


@sound("foe_down", "hit", 2)
def foe_down(k):
    """A foe goes down: a long falling grunt of air, then the weight hits the deck."""
    r, dur = R("foe_down", k), 0.6
    n = n_of(dur)
    breath = bp(white(r, n), sweep([700, 600][k], 220, dur), 1.2) * env(dur, [(0, 0), (0.03, 1), (0.3, 0.4), (0.6, 0)])
    fall = place((sine(sweep(120 - 15 * k, 45, 0.22)) * ad(0.22, 0.002, 0.07), 0.3, 1.0), (lp(white(r, n_of(0.12)), 600) * ad(0.12, 0.001, 0.04), 0.3, 0.5), length=dur)
    return lp(crush(breath * 0.8 + fall, 9, 1), 3800)


@sound("crawler_screech", "crew", 2)
def crawler_screech(k):
    """The thing in the vents: a thin rising shriek, broken up by a fast tremor, with a rasp under it."""
    r, dur = R("crawler_screech", k), 0.8
    n = n_of(dur)
    f = sweep([820, 700][k], [2100, 2500][k], dur, "lin")
    shriek = fm(f, 1.41, env(dur, [(0, 2.0), (0.4, 5.0), (0.8, 1.0)]), n)
    tremor = 0.55 + 0.45 * sine(31.0 + 6.0 * k, n)
    rasp = bp(white(r, n), sweep(1600, 3000, dur), 1.5) * 0.35
    amp = env(dur, [(0, 0), (0.05, 1), (0.55, 0.9), (0.8, 0)])
    return lp(crush((shriek * tremor + rasp) * amp, 9, 2), 5600)


@sound("crawler_skitter", "foot", 3)
def crawler_skitter(k):
    """Many small claws on a metal deck: a quick run of dry ticks that speeds up and fades."""
    r, dur = R("crawler_skitter", k), 0.42
    out = []
    t = 0.0
    gap = [0.05, 0.045, 0.055][k]
    i = 0
    while t < dur - 0.05:
        tick = bp(white(r, n_of(0.03)), 2200 + 700 * r.random(), 1.4) * ad(0.03, 0.0002, 0.006)
        out.append((tick, t, 0.55 + 0.45 * r.random()))
        t += gap * (0.8 + 0.5 * r.random()) * (1.0 - 0.015 * i)
        i += 1
    return lp(crush(place(*out, length=dur) * decay(dur, 0.28), 9, 1), 5200)


@sound("sentry_whir", "machine", 2)
def sentry_whir(k):
    """A turret's servo finding its mark: a thin motor whine that climbs and settles, with a click of a lock at the end."""
    r, dur = R("sentry_whir", k), 0.7
    n = n_of(dur)
    f = env(dur, [(0, 320), (0.35, [980, 880][k]), (0.55, [760, 700][k]), (0.7, [760, 700][k])])
    whine = lp(0.7 * saw(f, n) + 0.3 * square(f * 2.0, n), 2400) * swell(dur, 0.12, 0.25)
    click = place((modal(BAR[:3] * 1100, [0.02, 0.012, 0.008], [0.5, 0.3, 0.15], 0.08, r, 0.01), 0.58, 0.6), length=dur)
    return lp(crush(whine * 0.8 + click, 10, 1), 4800)


# --- the motion tracker and the light -------------------------------------------------------------------------------------------

def _beep(f0, f1, dur):
    """A rising beep: a pure tone with the faintest harmonic, a soft attack and a clean cut."""
    n = n_of(dur)
    f = sweep(f0, f1, dur)
    return (sine(f, n) * 0.85 + sine(f * 2.0, n) * 0.12) * env(dur, [(0, 0), (0.012, 1), (dur - 0.03, 0.9), (dur, 0)])


@sound("tracker_ping_far", "ui", 1)
def tracker_ping_far(k):
    """A contact far out: one low, slow rising beep."""
    return lp(_beep(520, 760, 0.28), 4000)


@sound("tracker_ping_mid", "ui", 1)
def tracker_ping_mid(k):
    """A contact at middle distance: a higher, shorter rising beep."""
    return lp(_beep(780, 1150, 0.18), 4600)


@sound("tracker_ping_near", "ui", 1)
def tracker_ping_near(k):
    """A contact close: two quick high beeps, rising. The nearer it is, the more it sounds like trouble."""
    layers = [(_beep(1150, 1700, 0.09), 0.0, 1.0), (_beep(1350, 1950, 0.09), 0.13, 1.0)]
    return lp(place(*layers, length=0.26), 5200)


@sound("flashlight_click", "ui", 1)
def flashlight_click(k):
    """A flashlight switch: a firm double click, plastic on metal."""
    r, dur = R("flashlight_click", k), 0.12
    n = n_of(dur)
    a = bp(white(r, n_of(0.03)), 2600, 1.6) * ad(0.03, 0.0002, 0.006) + modal(BAR[:3] * 1400, [0.012, 0.008, 0.005], [0.5, 0.3, 0.12], 0.03, r, 0.01) * 0.4
    return lp(crush(place((a, 0.0, 1.0), (a, 0.055, 0.7), length=dur), 9, 1), 5200)
