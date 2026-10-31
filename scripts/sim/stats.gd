extends RefCounted
## Effective stats of a component: its base values times its line's multipliers (data/lines.json).
## Static and pure. Systems that read a part's numbers (Power, Flight, the oxygen generators) get
## them through here, via effective() or a View, so a Scrap or Neon part behaves like one.

const LINES_PATH := "res://data/lines.json"
const DEFAULT_LINE := "standard"
const DEFAULT_HP := 4
const DEFAULT_HEAT_LIMIT := 100.0
## Stats scaled by the line's `output` (the family's main output). Positive power is scaled too.
const OUTPUT_STATS: Array[String] = ["thrust", "o2_rate", "smelt_speed"]


## The lines of a lines.json: line id -> {cost, power, output, mass, heat, repair, malfunction_per_min,
## ion_vulnerability}. Empty when the file is missing or unusable (every part then counts as standard).
static func load_lines(path := LINES_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary and data.get("lines") is Dictionary):
		return {}
	var out := {}
	for id in data["lines"]:
		if data["lines"][id] is Dictionary:
			out[str(id)] = data["lines"][id]
	return out


## The line entry of a component def (an empty dictionary for an unknown line: all multipliers 1).
static func line_of(def: Dictionary, lines: Dictionary) -> Dictionary:
	return lines.get(str(def.get("line", DEFAULT_LINE)), {})


## Maximum hp of a component def.
static func max_hp(def: Dictionary) -> int:
	return int(def.get("hp", DEFAULT_HP))


## The numbers a component really has (`power` is an int when it comes out whole): {power, hp, heat_limit, heat_per_s, cooling, mass_mult,
## malfunction_per_min, repair_mult, ion_vulnerability, cost_mult, line, stats}.
## - positive power (a producer) is scaled by the line's output, a draw (negative) by its power factor;
## - `stats` is a copy of the def's stats with thrust and o2_rate scaled by the line's output; a `stats.malfunction_per_min`
##   replaces the line's rate;
## - heat_per_s is scaled by the line's heat; cooling is the def's own (a radiator adds on top).
static func effective(def: Dictionary, lines: Dictionary) -> Dictionary:
	var ln := line_of(def, lines)
	var out_mult := float(ln.get("output", 1.0))
	var stats: Dictionary = def.get("stats", {}).duplicate()
	for k in OUTPUT_STATS:
		if stats.has(k):
			stats[k] = float(stats[k]) * out_mult
	var power = float(def.get("power", 0))  # an int when whole (8), else a float (5.4)
	power *= out_mult if power > 0.0 else float(ln.get("power", 1.0))
	if is_equal_approx(power, roundf(power)):
		power = roundi(power)
	return {
		"line": str(def.get("line", DEFAULT_LINE)),
		"power": power,
		"hp": max_hp(def),
		"heat_limit": float(def.get("heat_limit", DEFAULT_HEAT_LIMIT)),
		"heat_per_s": float(def.get("heat_per_s", 0.0)) * float(ln.get("heat", 1.0)),
		"cooling": float(def.get("cooling", 0.0)),
		"mass_mult": float(ln.get("mass", 1.0)),
		"malfunction_per_min": float(stats.get("malfunction_per_min", ln.get("malfunction_per_min", 0.0))),  # a part's own stat beats its line's
		"repair_mult": float(ln.get("repair", 1.0)),
		"ion_vulnerability": float(ln.get("ion_vulnerability", 1.0)),
		"cost_mult": float(ln.get("cost", 1.0)),
		"stats": stats,
	}


## component id -> mass multiplier, for the ids that differ from 1.0 (Flight.mass_of's `mass_mult`).
static func mass_mults(components, lines: Dictionary) -> Dictionary:
	var out := {}
	for id in components.ids():
		var m: float = effective(components.def(id), lines)["mass_mult"]
		if not is_equal_approx(m, 1.0):
			out[id] = m
	return out


## A stand-in for a components.gd instance whose defs carry the effective `power` and `stats`:
## Power.solve and Flight.thrust_of / can_fly read part numbers from def(), so handing them a View
## makes them use the line-adjusted values without changing them.
class View extends RefCounted:
	var instances: Dictionary  ## shared with the real components
	var _components
	var _lines: Dictionary
	var _effective: Callable  # Stats.effective
	var _cache := {}  # id -> def with effective power and stats

	func _init(components, lines: Dictionary, effective_fn: Callable) -> void:
		_components = components
		instances = components.instances
		_lines = lines
		_effective = effective_fn

	func def(id: String) -> Dictionary:
		if not _cache.has(id):
			var d: Dictionary = _components.def(id).duplicate()
			if not d.is_empty():
				var e: Dictionary = _effective.call(d, _lines)
				d["power"] = e["power"]
				d["stats"] = e["stats"]
			_cache[id] = d
		return _cache[id]


## See View. `components`: a components.gd instance.
static func view(components, lines: Dictionary) -> View:
	return View.new(components, lines, effective)
