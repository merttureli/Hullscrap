"""Builds the soundtrack: python audio/_src/music/build_music.py [names...] [--force]
Renders each track (deterministic, numpy only), encodes Ogg Vorbis (ffmpeg libvorbis, q5, 44.1 kHz stereo, bitexact so a re-run gives the same bytes) into
assets/audio/music/, measures the decoded file, and writes data/music.json, the ASSETS.md rows and report.json.
The round-2 demos (d_*.py) render EXPLORE, BATTLE and a transition file each into assets/audio/music/demos/; they are
not in data/music.json. Their report adds the sync check: equal sample counts and the onset lag between the two.
A track whose source hash (engine + its own file) is unchanged is skipped. Godot's .import files for the loops
are patched to loop=true (run `godot --headless --import` once first so they exist)."""
import hashlib
import importlib
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "music")
sys.path.insert(0, HERE)
import numpy as np
import synth as S

ENGINE = ["synth.py", "voices.py", "theme.py", "common.py"]
DEMO_ENGINE = ["synth2.py", "voices2.py", "demo.py"]
DEMOS = {"signal": "d_signal", "long_haul": "d_longhaul", "black_box": "d_blackbox"}
DEMO_OUT = os.path.join(OUT, "demos")
LOOPS = {"menu": "t_menu", "explore_a": "t_explore_a", "explore_b": "t_explore_b", "combat": "t_combat",
         "hollow": "t_hollow", "build": "t_build"}
STINGS = ["victory", "defeat", "jump", "region_cross", "ada_found", "unlock", "ending"]
STATES = {"menu": ["menu.ogg"], "explore": ["explore_a.ogg", "explore_b.ogg"], "combat": ["combat.ogg"],
          "hollow": ["hollow.ogg"], "build": ["build.ogg"]}
VOLUMES = {"combat.ogg": 0.0}   # dB per file; the loops are mastered to their own loudness, stings sit 3 dB under
STING_DB = -3.0


def src_hash(*files):
    h = hashlib.sha256()
    for f in ENGINE + list(files):
        h.update(open(os.path.join(HERE, f), "rb").read())
    return h.hexdigest()[:16]


def encode(y, path):
    p = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "f32le", "-ar", "44100", "-ac", "2", "-i", "-",
                        "-fflags", "+bitexact", "-flags:a", "+bitexact", "-c:a", "libvorbis", "-q:a", "5", "-ar", "44100", path], input=np.ascontiguousarray(y.T, "<f4").tobytes(), capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode())


def decode(path):
    p = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ar", "44100", "-ac", "2", "-"], capture_output=True)
    return np.frombuffer(p.stdout, "<f4").reshape(-1, 2).T.copy()


def measure(path, loop, n_src):
    y = decode(path)
    r = {"seconds": round(y.shape[1] / S.SR, 2), "samples_off_vs_render": int(y.shape[1] - n_src),
         "rms_db": round(S.rms_db(y), 2), "peak_db": round(float(20 * np.log10(np.abs(y).max())), 2),
         "true_peak_db": round(float(20 * np.log10(S.true_peak(y))), 2), "bands_pct": S.bands_share(y),
         "bytes": os.path.getsize(path)}
    if loop:
        r["seam"] = {k: float(v) for k, v in S.seam_check(y).items()}
    return r


def patch_import(name, loop, out=OUT):
    p = os.path.join(out, name + ".ogg.import")
    if not os.path.exists(p):
        return False
    t = open(p).read()
    t2 = re.sub(r"^loop=.*$", "loop=%s" % ("true" if loop else "false"), t, flags=re.M)
    if t2 != t:
        open(p, "w").write(t2)
    return True


def build(names, force):
    os.makedirs(OUT, exist_ok=True)
    hp = os.path.join(HERE, "hashes.json")
    rp = os.path.join(HERE, "report.json")
    hashes = json.load(open(hp)) if os.path.exists(hp) else {}
    report = json.load(open(rp)) if os.path.exists(rp) else {}
    jobs = [(n, LOOPS[n], True) for n in LOOPS] + [(n, "stings", False) for n in STINGS]
    for name, modname, loop in jobs:
        if names and name not in names:
            continue
        path = os.path.join(OUT, name + ".ogg")
        h = src_hash(modname + ".py")
        if not force and hashes.get(name) == h and os.path.exists(path):
            print("skip", name)
            continue
        t0 = time.time()
        mod = importlib.import_module(modname)
        if loop:
            y = mod.render()
            info = {"title": mod.TITLE, "target_rms_db": mod.RMS, "bpm": round(mod.render.bpm, 2)}
        else:
            y = mod.render(name)
            info = {"title": name}
        encode(y, path)
        info.update(measure(path, loop, y.shape[1]))
        report[name] = info
        hashes[name] = h
        json.dump(hashes, open(hp, "w"), indent=1, sort_keys=True)
        json.dump(report, open(rp, "w"), indent=1, sort_keys=True)
        print("built %-13s %5.1fs  %6.1fs audio  rms %s  peak %s  tp %s  bands %s  %d KB" % (
            name, time.time() - t0, info["seconds"], info["rms_db"], info["peak_db"], info["true_peak_db"], info["bands_pct"], info["bytes"] // 1024))
    for name, modname in DEMOS.items():
        if not names or name in names:
            build_demo(name, modname, force, hashes, report, hp, rp)
    for n in list(LOOPS) + STINGS:
        patch_import(n, n in LOOPS)
    for n in DEMOS:
        for v in ("explore", "battle", "transition"):
            patch_import("%s_%s" % (n, v), v != "transition", DEMO_OUT)
    write_data()


def build_demo(name, modname, force, hashes, report, hp, rp):
    """EXPLORE and BATTLE (loops of identical length) and the transition demo for one direction."""
    os.makedirs(DEMO_OUT, exist_ok=True)
    paths = {v: os.path.join(DEMO_OUT, "%s_%s.ogg" % (name, v)) for v in ("explore", "battle", "transition")}
    h = src_hash(*(DEMO_ENGINE + [modname + ".py"]))
    if not force and hashes.get(name) == h and all(map(os.path.exists, paths.values())):
        print("skip", name)
        return
    import synth2 as S2
    t0 = time.time()
    mod = importlib.import_module(modname)
    r = mod.render()
    info = {"title": mod.TITLE, "bpm": round(mod.render.bpm, 2), "sections_s": r["sections"], "crossfades_start_s": list(r["xfade_s"])}
    for v, p in paths.items():
        encode(r[v], p)
        info[v] = measure(p, v != "transition", r[v].shape[1])
        if v != "transition":
            info[v]["target_rms_db"] = mod.RMS[v]
    x, b = decode(paths["explore"]), decode(paths["battle"])
    lag, corr = S2.onset_lag(x, b)
    info["sync"] = {"samples_explore": int(x.shape[1]), "samples_battle": int(b.shape[1]), "same_length": x.shape[1] == b.shape[1],
                    "onset_lag_ms": lag, "onset_corr": corr}
    report.setdefault("demos", {})[name] = info
    hashes[name] = h
    json.dump(hashes, open(hp, "w"), indent=1, sort_keys=True)
    json.dump(report, open(rp, "w"), indent=1, sort_keys=True)
    print("built %-10s %5.1fs  %s  sync %s" % (name, time.time() - t0, "  ".join("%s %.1fs rms %s tp %s" % (
        v, info[v]["seconds"], info[v]["rms_db"], info[v]["true_peak_db"]) for v in paths), info["sync"]))


def write_data():
    have = lambda f: os.path.exists(os.path.join(OUT, f))   # while tracks are still being added, list only what exists
    vol = {**{f + ".ogg": 0.0 for f in LOOPS}, **{n + ".ogg": STING_DB for n in STINGS}, **VOLUMES}
    files = {"dir": "res://assets/audio/music/", "states": {k: [f for f in v if have(f)] for k, v in STATES.items()},
             "stings": {n: n + ".ogg" for n in STINGS if have(n + ".ogg")}, "volumes": {f: d for f, d in vol.items() if have(f)}}
    json.dump(files, open(os.path.join(ROOT, "data", "music.json"), "w"), indent=1)
    open(os.path.join(ROOT, "data", "music.json"), "a").write("\n")
    # ASSETS.md rows
    p = os.path.join(ROOT, "ASSETS.md")
    lines = [l for l in open(p).read().splitlines() if "assets/audio/music/" not in l]
    rows = ["| `assets/audio/music/%s.ogg` | original, composed and synthesised for Hullscrap (generator: `audio/_src/music/`) | project-owned |" % n
            for n in sorted(list(LOOPS) + STINGS)]
    rows += ["| `assets/audio/music/demos/%s_%s.ogg` | original, composed and synthesised for Hullscrap (round-2 demo, generator: `audio/_src/music/%s.py`) | project-owned |" % (n, v, m)
             for n, m in sorted(DEMOS.items()) for v in ("explore", "battle", "transition") if os.path.exists(os.path.join(DEMO_OUT, "%s_%s.ogg" % (n, v)))]
    open(p, "w").write("\n".join(lines + rows) + "\n")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    build(args, "--force" in sys.argv)
