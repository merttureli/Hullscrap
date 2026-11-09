extends RefCounted
## The Hollow tide (docs/MECHANICS_REVIEW.md P1, tuning in data/tide.json): FTL's rebel fleet. A front sweeps over a
## region's map from its entry node along +x, one step per jump (a wait and a tow count as jumps too). Places behind
## the front are Hollow: ghost ships, no rewards, no trade. Stations and the region's exit hold. Lingering in one
## place also pushes it: linger_s seconds of play (the campaign's linger()) are one step, with warnings before.
## Pure logic, no nodes and no randomness. Built from a map: Tide.make(drift, entry_id, cfg, exit_id, stage). The
## campaign owns it (campaign.gd: `tide`), the map view draws it (map_view.gd) and tide_hud.gd shows the clock.
##
## The front is at max(steps - grace, 0) * axis_len / jumps_to_cross px along the axis. The axis starts at the entry
## node and points to +x; axis_len is the farthest node's projection on it. A node is Hollow once the front has
## reached its projection (so the farthest one falls when the front has crossed the whole map).

const CONFIG_PATH := "res://data/tide.json"
const EPS := 0.001  ## px: tolerance for the float maths of the front
const RISES_TEXT := "The Hollow tide rises."
const NEAR_TEXT := "The Hollow is near. Jump soon."  ## told with the first linger warning when the ship's own place falls at the next step

static var _cfg := {}

var steps := 0  ## how far the tide has come: jumps, waits, tows and lingering
var grace := 3  ## steps before the front starts to move
var jumps_to_cross := 16  ## steps the front takes to cross the whole axis
var linger_s := 240.0  ## seconds of play in one place that make one step
var warns: Array = [60, 15]  ## seconds left at which a warning is told, once each (largest first)
var pressure_from := 0.3  ## the pressure on a place one step from falling, as its linger step begins (pressure())
var axis_len := 0.0  ## px: the farthest node's projection on the axis
var entry_id := ""
var far_id := ""  ## the node farthest along the axis (the map view fits the front between the entry and this one)
var exit_id := ""  ## the region's exit beacon: it holds (optional)
var linger_t := 0.0  ## seconds lingered towards the next step
var _proj := {}  # node id -> px along the axis (negative behind the entry)
var _holds := {}  # node id -> true for the nodes the tide never takes
var _warned := {}  # warning seconds already told in this linger period -> true


## data/tide.json, read once.
static func config() -> Dictionary:
	if _cfg.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		assert(data is Dictionary, "bad tide data: " + CONFIG_PATH)
		_cfg = data
	return _cfg


## The tide of map `drift` (drift.gd) entered at node `entry_id`. `cfg` is data/tide.json (the shipped one when empty),
## `exit_id` the exit beacon that holds ("" for none), `stage` the region's place in the run (1 first): it picks
## stage_jumps_to_cross. The tide starts at step 0.
static func make(drift, entry_id: String, cfg := {}, exit_id := "", stage := 1):
	var t = new()
	var c: Dictionary = cfg if not cfg.is_empty() else config()
	t.grace = maxi(int(c.get("grace", 3)), 0)
	t.linger_s = maxf(float(c.get("linger_s", 240.0)), 1.0)
	t.jumps_to_cross = maxi(int(c.get("jumps_to_cross", 16)), 1)
	var per_stage = c.get("stage_jumps_to_cross")
	if per_stage is Array and stage >= 1 and stage <= per_stage.size():
		t.jumps_to_cross = maxi(int(per_stage[stage - 1]), 1)
	var w: Array = []
	for s in c.get("linger_warn", [60, 15]):
		w.append(int(s))
	w.sort()
	w.reverse()
	t.warns = w
	t.pressure_from = clampf(float(c.get("pressure_from", 0.3)), 0.0, 1.0)
	t.entry_id = entry_id
	t.exit_id = exit_id
	if not drift.has(entry_id):
		return t
	var origin: Vector2 = drift.node(entry_id)["pos"]
	t.far_id = entry_id
	for n in drift.nodes:
		var id := str(n["id"])
		var x: float = n["pos"].x - origin.x
		t._proj[id] = x
		if x > t.axis_len:
			t.axis_len = x
			t.far_id = id
		if str(n["type"]) == "station" or id == exit_id:
			t._holds[id] = true
	return t


# --- the front ----------------------------------------------------------------------------------------------

## Where the front is after `s` steps, px along the axis (0 until the grace is used up).
func front_at(s: int) -> float:
	return float(maxi(s - grace, 0)) * axis_len / float(jumps_to_cross)


## Where the front is now.
func front() -> float:
	return front_at(steps)


func holds(id: String) -> bool:
	return _holds.has(id)


func _hollow_at(id: String, s: int) -> bool:
	if not _proj.has(id) or _holds.has(id):
		return false
	var f := front_at(s)
	return f > 0.0 and float(_proj[id]) <= f + EPS


## Has the tide taken node `id`? Stations, the exit and unknown nodes never fall.
func is_hollow(id: String) -> bool:
	return _hollow_at(id, steps)


## Steps until node `id` goes Hollow: 0 if it is, -1 if it never does (a station, the exit, an unknown node).
func jumps_until(id: String) -> int:
	if not _proj.has(id) or _holds.has(id):
		return -1
	for n in range(0, grace + jumps_to_cross + 2):
		if _hollow_at(id, steps + n):
			return n
	return -1


## How hard the tide presses on node `id`, 0 to 1 (the campaign hands it to the node's sector, sector.gd set_pressure): 0 while the node is 2 or
## more steps from falling (and for one that never falls), rising from `pressure_from` to 1 over the last step as the linger clock runs out, 1 once
## it is Hollow.
func pressure(id: String) -> float:
	var n := jumps_until(id)
	if n == 0:
		return 1.0
	if n != 1:
		return 0.0
	return lerpf(pressure_from, 1.0, clampf(1.0 - linger_left() / linger_s, 0.0, 1.0))


## How many nodes are Hollow now.
func hollow_count() -> int:
	var n := 0
	for id in _proj:
		if _hollow_at(id, steps):
			n += 1
	return n


## Has the front crossed the whole map (no more nodes to take)?
func spent() -> bool:
	return axis_len <= 0.0 or front() >= axis_len


## The tide comes on by `n` steps (jumps, waits, tows, lingering). Returns how many places it took.
func advance(n := 1) -> int:
	var before := hollow_count()
	steps = maxi(steps + n, 0)
	return hollow_count() - before


# --- lingering ----------------------------------------------------------------------------------------------

## `dt` seconds of play pass in the same place (the map is shut, no build mode, no fight). At linger_s the tide
## advances one step (RISES_TEXT), the count starts again, and the lines for the HUD and the chronicle come back:
## "The tide rises in 60 s" once at each of the warn seconds, then the rise. Never touches the jump counter.
func linger(dt: float) -> Array:
	var lines := []
	if dt <= 0.0 or spent():
		return lines
	linger_t += dt
	while true:
		var left := linger_s - linger_t
		if left <= 0.0:
			linger_t -= linger_s
			_warned.clear()
			advance(1)
			lines.append(RISES_TEXT)
			if spent():
				linger_t = 0.0
				break
			continue
		for w in warns:
			if left <= float(w) and not _warned.has(w):
				_warned[w] = true
				lines.append("The tide rises in %d s" % w)
		break
	return lines


## The ship arrived somewhere new: the count towards the next step starts again.
func reset_linger() -> void:
	linger_t = 0.0
	_warned.clear()


## Seconds of lingering left until the next step.
func linger_left() -> float:
	return maxf(linger_s - linger_t, 0.0)


## Seconds as M:SS, rounded up ("4:00" for 240, "0:01" for a hair over 0).
static func clock(seconds: float) -> String:
	var s := maxi(ceili(seconds - 0.0001), 0)
	return "%d:%02d" % [s / 60, s % 60]


# --- save format --------------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"steps": steps, "linger": linger_t}


## Take a saved state. Returns "" or why not (and nothing changes).
func load_save(d: Dictionary) -> String:
	if not ((d.get("steps") is int or d.get("steps") is float) and (d.get("linger", 0.0) is int or d.get("linger", 0.0) is float)):
		return "bad tide"
	steps = maxi(int(d["steps"]), 0)
	linger_t = clampf(float(d.get("linger", 0.0)), 0.0, linger_s - 0.001)
	_warned.clear()
	for w in warns:  # the warnings already given in this period are not told again
		if linger_s - linger_t <= float(w):
			_warned[w] = true
	return ""
