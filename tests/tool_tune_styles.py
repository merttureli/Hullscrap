#!/usr/bin/env python3
"""Tunes the `cost_mult` of the race styles in data/ship_styles.json (the price of their guns: never their budget) until their mean Threat.power is
within a few percent of their base faction's, at stages 1, 3 and 5 (weights .2, .4, .4), using tests/tool_enemy_parity.gd. Run from the repo root:
    python3 tests/tool_tune_styles.py <godot binary> [race ...] [--jobs 3] [--seeds 30] [--rounds 4]"""
import json, os, re, subprocess, sys, threading, importlib.util
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
spec = importlib.util.spec_from_file_location('mk', 'tests/tool_make_ship_styles.py')
mk = importlib.util.module_from_spec(spec); spec.loader.exec_module(mk)
LOCK = threading.Lock()


def measure(godot, race, seeds):
    out = subprocess.run([godot, '--headless', '--path', '.', '--script', 'res://tests/tool_enemy_parity.gd', '--', 'factions=' + race, 'seeds=%d' % seeds],
                         capture_output=True, text=True, timeout=900).stdout
    ratios, pend = {}, None
    for l in out.splitlines():
        m = re.search(r'ratio to (\w+): ([\d.]+)', l)
        if m:
            pend = float(m.group(2)); continue
        m = re.match(r'\w+\s+stage (\d)', l)
        if m and pend is not None:
            ratios[int(m.group(1))] = pend; pend = None
    return ratios


def tune(godot, race, seeds, rounds):
    for r in range(rounds):
        ratios = measure(godot, race, seeds)
        if len(ratios) < 3:
            print(race, 'no numbers'); return
        g = 0.2 * ratios[1] + 0.4 * ratios[3] + 0.4 * ratios[5]
        print('%-13s round %d ratios %s weighted %.2f' % (race, r, ' '.join('%.2f' % ratios[k] for k in (1, 3, 5)), g), flush=True)
        if 0.95 <= g <= 1.05 or r == rounds - 1:
            return
        with LOCK:
            d = json.load(open('data/ship_styles.json'))
            st = d['races'][race]
            st['cost_mult'] = round(float(st.get('cost_mult', 1.0)) * g ** 0.9, 3)
            open('data/ship_styles.json', 'w').write(mk.fmt(d) + '\n')


if __name__ == '__main__':
    args = [a for a in sys.argv[1:]]
    godot = args.pop(0)
    jobs, seeds, rounds = 3, 30, 4
    races = []
    while args:
        a = args.pop(0)
        if a == '--jobs': jobs = int(args.pop(0))
        elif a == '--seeds': seeds = int(args.pop(0))
        elif a == '--rounds': rounds = int(args.pop(0))
        else: races.append(a)
    if not races:
        races = [r for r in json.load(open('data/ship_styles.json'))['races'] if r not in ('kett', 'prismatic', 'grundl')]
    with ThreadPoolExecutor(jobs) as ex:
        list(ex.map(lambda r: tune(godot, r, seeds, rounds), races))
