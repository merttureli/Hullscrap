#!/usr/bin/env python3
"""One-off (docs/GUNS.md 13): scale every ship gun's range x1.4 and its shot speed x1.2 (point defence: range and intercept range x1.15, speed as is),
and the limpets' and pods' launch and cap speeds x1.2. Text edits, so the one-entry-per-line layout of the files stays.
  python3 tests/tool_scale_ranges.py [--dry]"""
import glob, json, re, sys

R, V, PD_R = 1.4, 1.2, 1.15
files = ["data/weapons.json"] + sorted(glob.glob("data/packs/*/weapons.json"))
n = 0
r10 = lambda x: round(x / 10) * 10
for f in files + ["data/packs/drones_2/items.json"]:
    text = open(f).read()
    d = json.loads(text)
    if json.dumps(d, indent=2 if "weapons" in d else 1, ensure_ascii=False) in (text, text.rstrip("\n")):  # the file is plain json.dumps: edit the structure
        if "weapons" in d:
            for w in d["weapons"].values():
                pd = w.get("family") == "pd" or "intercept" in w.get("effects", {})
                w["range"] = r10(w["range"] * (PD_R if pd else R))
                if pd and "intercept" in w.get("effects", {}):
                    w["effects"]["intercept"]["range"] = r10(w["effects"]["intercept"]["range"] * PD_R)
                if "speed" in w and not pd:
                    w["speed"] = r10(w["speed"] * V)
                n += 1
        else:
            for i in d["items"]:
                m = i.get("drone", {}).get("magnet")
                if m:
                    m["launch"] = float(r10(m["launch"] * V))
                    m["cap"] = float(r10(m["cap"] * V))
                    n += 1
        if "--dry" not in sys.argv:
            open(f, "w").write(json.dumps(d, indent=2 if "weapons" in d else 1, ensure_ascii=False) + ("\n" if text.endswith("\n") else ""))
        continue
    if "weapons" not in d:
        continue
    out = []
    for line in text.split("\n"):
        if re.match(r'\s+"[a-z0-9_]+": \{"kind": ', line) or re.match(r'\s+"[a-z0-9_]+": \{\s*$', line) and False:
            pd = '"intercept"' in line or '"family": "pd"' in line
            k = PD_R if pd else R
            line = re.sub(r'("range": )(\d+(?:\.\d+)?)', lambda m: m.group(1) + str(round(float(m.group(2)) * k / 10) * 10), line, count=1)
            if pd:  # the intercept reach, nested
                line = re.sub(r'("intercept": \{"range": )(\d+)', lambda m: m.group(1) + str(round(int(m.group(2)) * PD_R / 10) * 10), line)
            else:
                line = re.sub(r'("speed": )(\d+(?:\.\d+)?)', lambda m: m.group(1) + str(round(float(m.group(2)) * V / 10) * 10), line, count=1)
            n += 1
        out.append(line)
    if "--dry" not in sys.argv:
        open(f, "w").write("\n".join(out))
print(n, "entries")
