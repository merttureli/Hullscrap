"""Recorded layers of the impact sounds (CC0 / CC-BY samples from OpenGameArt, credited in ASSETS.md), read with the stdlib `wave`.
They are trimmed once and committed under samples/impacts/; the recipes mix them with the synthesis, so the build stays byte-identical."""
import os
import wave
import numpy as np

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples", "impacts")


def samp(name, ratio=1.0):
    """A sample as a float array (mono, 44.1 kHz) normalised to a peak of 1; ratio > 1 plays it faster and higher."""
    with wave.open(os.path.join(DIR, name + ".wav")) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32768.0
    x = x / (np.max(np.abs(x)) + 1e-9)
    if ratio != 1.0:
        idx = np.arange(0.0, len(x) - 1.0, ratio)
        lo = idx.astype(int)
        x = x[lo] * (1.0 - (idx - lo)) + x[lo + 1] * (idx - lo)
    return x
