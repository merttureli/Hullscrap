"""Round 2, interface: tabs, the slider's tick, the error, the map's node hover, the jump chime, confirm and cancel, a journal page. Same
quiet UI voice as round 1: soft, short, nothing above ~5 kHz, FM bells and triangle blips at -23 dBFS RMS."""
import numpy as np
from dsp import *
from sounds import sound, R, mix


@sound("tab_switch", "ui", 1)
def tab_switch(k):
    """A tab changes: two soft rising blips, close together."""
    dur = 0.12
    layers = []
    for i, f in enumerate((1200.0, 1560.0)):
        layers.append((tri(f, n_of(0.05)) * env(0.05, [(0, 0), (0.003, 1), (0.05, 0)]), 0.045 * i, 0.8))
    return lp(crush(place(*layers, length=dur), 10, 1), 4200)


@sound("slider_tick", "ui", 1)
def slider_tick(k):
    """A slider notch: a very small tick."""
    r, dur = R("slider_tick", k), 0.035
    n = n_of(dur)
    return crush(sine(2300, n) * ad(dur, 0.0004, 0.005) * 0.6 + bp(white(r, n), 3500, 1.0) * ad(dur, 0.0002, 0.003) * 0.3, 9, 1)


@sound("error", "ui", 1)
def error(k):
    """Something was refused: two falling notes in a low, flat voice (the build's `invalid` is a buzz, this is a 'no')."""
    layers = []
    for i, f in enumerate((392.0, 294.0)):
        m = n_of(0.14)
        layers.append((lp(0.7 * tri(f, m) + 0.3 * square(f, m), 1800) * env(0.14, [(0, 0), (0.01, 1), (0.11, 0.9), (0.14, 0)]), 0.13 * i, 0.9))
    return crush(place(*layers, length=0.4), 9, 2)


@sound("node_hover", "ui", 1)
def node_hover(k):
    """The pointer rests on a place on the map: one soft round blip."""
    r, dur = R("node_hover", k), 0.1
    n = n_of(dur)
    return sine(sweep(780, 940, dur)) * ad(dur, 0.002, 0.02) * 0.5 + bp(white(r, n), 3000, 1.0) * ad(dur, 0.0003, 0.004) * 0.12


@sound("jump_ready", "ui", 1)
def jump_ready(k):
    """The jump drive is charged: three bell notes climbing, unhurried, with a clear room round them."""
    layers = []
    for i, f in enumerate((659.25, 880.0, 1318.5)):
        layers.append((fm(f, 3.5, env(0.8, [(0, 1.5), (0.5, 0.2)]), n_of(0.8)) * ad(0.8, 0.002, 0.22), 0.12 * i, 0.75))
    return reverb(lp(place(*layers, length=1.2), 6000), 0.7, 0.28, 561)


@sound("confirm", "ui", 1)
def confirm(k):
    """A choice made: a short rising two-note, bright and firm."""
    layers = []
    for i, f in enumerate((660.0, 990.0)):
        layers.append((fm(f, 2.0, env(0.25, [(0, 1.2), (0.15, 0.2)]), n_of(0.25)) * ad(0.25, 0.002, 0.09), 0.07 * i, 0.8))
    return lp(crush(place(*layers, length=0.35), 10, 1), 5200)


@sound("cancel", "ui", 1)
def cancel(k):
    """A step back: a short falling two-note, softer than confirm."""
    layers = []
    for i, f in enumerate((660.0, 440.0)):
        layers.append((fm(f, 2.0, env(0.22, [(0, 1.0), (0.14, 0.15)]), n_of(0.22)) * ad(0.22, 0.002, 0.08), 0.07 * i, 0.7))
    return lp(crush(place(*layers, length=0.3), 10, 1), 4600)


@sound("page_turn", "ui", 1)
def page_turn(k):
    """A journal page turns: a dry paper swish that rises and falls, a flick at its start and a soft settle at the end."""
    r, dur = R("page_turn", k), 0.4
    n = n_of(dur)
    swish = bp(white(r, n), env(dur, [(0, 2200), (0.16, 5200), (0.4, 2400)]), 0.7) * swell(dur, 0.12, 0.2)
    flick = bp(white(r, n), 3800, 1.0) * ad(dur, 0.0003, 0.012) * 0.8
    settle = place((lp(white(r, n_of(0.08)), 900) * ad(0.08, 0.002, 0.02), 0.31, 0.35), length=dur)
    return lp(swish * 0.7 + flick + settle, 6000)
