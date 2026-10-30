extends RefCounted
## The balance of a sectored bubble (docs/CONTENT.md section 4): one weight per sector, in steps of 0.5
## from 0 to 2, always adding up to the number of sectors (even = every weight 1). A sector holds
## `layers x weight` layers, so protection is moved, never made. Pure functions on weight lists (Arrays of
## floats) plus the shape of the ship's saved balance; Shields applies them to a bubble in a fight and
## the Shields tab to the ship at rest.

const STEP := 0.5
const MAX_W := 2.0
const COUNTS: Array[int] = [1, 2, 4, 8]  ## the sector counts a generator can give
const PRESETS: Array[String] = ["Even", "Bow", "Stern", "Port", "Starboard"]
const PRESET_DEG := {"Bow": 0.0, "Starboard": 90.0, "Stern": 180.0, "Port": 270.0}  ## clockwise from the bow
const NAMES := {
	1: ["Bubble"],
	2: ["Bow", "Stern"],
	4: ["Bow", "Starboard", "Stern", "Port"],
	8: ["Bow", "Bow-starboard", "Starboard", "Stern-starboard", "Stern", "Stern-port", "Port", "Bow-port"],
}
const SLOTS := 2  ## custom presets a ship keeps


## `n` sectors, all at weight 1.
static func even(n: int) -> Array:
	var w := []
	for i in n:
		w.append(1.0)
	return w


## The largest legal sector count not above `n` (at least 1).
static func legal(n: int) -> int:
	var best := 1
	for c in COUNTS:
		if c <= n:
			best = c
	return best


static func total(w: Array) -> float:
	var sum := 0.0
	for x in w:
		sum += float(x)
	return sum


## Are `w` good weights for `n` sectors: n of them, each 0..2 in steps of 0.5, adding up to n?
static func valid(w, n: int) -> bool:
	if not (w is Array) or w.size() != n:
		return false
	for x in w:
		if not (x is float or x is int):
			return false
		var v := float(x)
		if v < 0.0 or v > MAX_W or not is_equal_approx(v / STEP, roundf(v / STEP)):
			return false
	return is_equal_approx(total(w), float(n))


## `w` if it suits `n` sectors, else even.
static func normalized(w, n: int) -> Array:
	return (w as Array).duplicate() if valid(w, n) else even(n)


static func opposite(n: int, s: int) -> int:
	return (s + n / 2) % n if n > 1 else s


## The name of sector `s` of `n` ("Bow", "Starboard" ...).
static func name_of(n: int, s: int) -> String:
	var list: Array = NAMES.get(n, [])
	return str(list[s]) if s >= 0 and s < list.size() else "Sector %d" % (s + 1)


## The sector an arrow key points at: "up" the bow, "down" the stern, "right" starboard, "left" port. -1
## when there is none (one sector; port and starboard need 4+).
static func dir_sector(n: int, dir: String) -> int:
	if n < 2:
		return -1
	match dir:
		"up":
			return 0
		"down":
			return n / 2
		"right":
			return n / 4 if n >= 4 else -1
		"left":
			return 3 * n / 4 if n >= 4 else -1
	return -1


## The other sectors in the order a step takes from (or gives to) them: the opposite one first, then
## outward on both sides of it.
static func _order(n: int, s: int) -> Array:
	var opp := opposite(n, s)
	var out := [opp]
	for k in range(1, n):
		for sign in [1, -1]:
			var c := posmod(opp + sign * k, n)
			if c != s and not out.has(c):
				out.append(c)
	return out


## One step at sector `s`: `delta` +1 gives it 0.5 more, taken from the opposite sector first and, when
## that has none, from the other sector that has the most (so a run of steps takes evenly); -1 takes 0.5
## away and gives it to the opposite sector, else to the one with the least. Returns {weights, why}:
## the new list and "", or the old list and why the step is refused (past 0 or 2, or nothing to move).
static func step(w: Array, s: int, delta: int) -> Dictionary:
	var n := w.size()
	var out := {"weights": w.duplicate(), "why": ""}
	if n < 2 or s < 0 or s >= n:
		out["why"] = "one piece: no balance to set"
		return out
	var gain := delta > 0
	var cur := float(w[s])
	if gain and cur + STEP > MAX_W + 1e-9:
		out["why"] = "%s is at the most (2)" % name_of(n, s)
		return out
	if not gain and cur - STEP < -1e-9:
		out["why"] = "%s is already at 0" % name_of(n, s)
		return out
	var other := _partner(w, s, gain)
	if other < 0:
		out["why"] = "nothing left to take" if gain else "every other sector is full"
		return out
	var res: Array = w.duplicate()
	res[s] = cur + (STEP if gain else -STEP)
	res[other] = float(w[other]) + (-STEP if gain else STEP)
	out["weights"] = res
	return out


## The sector a step at `s` trades with: the opposite one when it can (has 0.5 to give, or room for
## 0.5), else of the others the one with the most to give (or the least held, when giving). -1 for none.
static func _partner(w: Array, s: int, gain: bool) -> int:
	var n := w.size()
	var best := -1
	for c in _order(n, s):
		var x := float(w[c])
		var ok := x >= STEP - 1e-9 if gain else x + STEP <= MAX_W + 1e-9
		if not ok:
			continue
		if c == opposite(n, s):
			return c
		if best < 0 or (x > float(w[best]) + 1e-9 if gain else x < float(w[best]) - 1e-9):
			best = c
	return best


## The weights of preset `name` for `n` sectors: Even, or the bubble leaning toward Bow, Stern, Port or
## Starboard (weight 1 + cos of the angle off that side, in steps of 0.5, still adding up to n). [] when the
## preset does not exist for `n` (one sector; port and starboard with 2).
static func preset(n: int, name: String) -> Array:
	if n < 2:
		return []
	if name == "Even":
		return even(n)
	if not PRESET_DEG.has(name) or (n < 4 and name in ["Port", "Starboard"]):
		return []
	var raw := []
	var w := []
	for i in n:
		var r := clampf(1.0 + cos(TAU * i / n - deg_to_rad(PRESET_DEG[name])), 0.0, MAX_W)
		raw.append(r)
		w.append(clampf(roundf(r / STEP) * STEP, 0.0, MAX_W))
	var guard := 0
	while not is_equal_approx(total(w), float(n)) and guard < 64:
		guard += 1
		var up := total(w) < n
		var best := -1
		var best_err := -INF
		for i in n:
			if (up and float(w[i]) + STEP > MAX_W + 1e-9) or (not up and float(w[i]) - STEP < -1e-9):
				continue
			var err: float = (float(raw[i]) - float(w[i])) * (1.0 if up else -1.0)
			if err > best_err + 1e-9:
				best_err = err
				best = i
		if best < 0:
			break
		w[best] = float(w[best]) + (STEP if up else -STEP)
	return w


# --- what a ship keeps ------------------------------------------------------------------------------

## A new ship's saved balance: no chosen weights (even), both custom slots empty.
static func fresh() -> Dictionary:
	var presets := []
	for i in SLOTS:
		presets.append([])
	return {"weights": [], "presets": presets}


## A saved balance read back from JSON: the lists that are numbers, anything else dropped. Weights are
## checked against the sector count when a fight starts, so a list for another count is kept as it is.
static func sanitize(d) -> Dictionary:
	var out := fresh()
	if not (d is Dictionary):
		return out
	var w = d.get("weights")
	if w is Array and _all_numbers(w):
		out["weights"] = _floats(w)
	var p = d.get("presets")
	if p is Array:
		for i in mini(p.size(), SLOTS):
			if p[i] is Array and _all_numbers(p[i]):
				out["presets"][i] = _floats(p[i])
	return out


## Is `d` the untouched fresh() balance (nothing to save)?
static func is_fresh(d: Dictionary) -> bool:
	if not (d.get("weights", []) as Array).is_empty():
		return false
	for p in d.get("presets", []):
		if not (p as Array).is_empty():
			return false
	return true


static func _all_numbers(list: Array) -> bool:
	for x in list:
		if not (x is float or x is int):
			return false
	return true


static func _floats(list: Array) -> Array:
	var out := []
	for x in list:
		out.append(float(x))
	return out
