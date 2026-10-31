extends RefCounted
## Balance bands (data/balance.json, docs/CONTENT_PLAN.md section 3): the expected numbers of a part by family and
## tier, for the Standard line: bands[family][tier][stat]. A line multiplies them the way Stats.effective resolves a
## part's numbers (that function is run on the band itself), so a part is compared by its effective numbers. Static
## and pure; tests/test_content.gd fails on a part that is off its band and tests/tool_content_index.gd lists them.

const Stats = preload("res://scripts/sim/stats.gd")

const PATH := "res://data/balance.json"
const DEFAULT_TOLERANCE := 0.2


## data/balance.json as a Dictionary ({} when it is missing or unusable).
static func load_table(path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## Does the part have a quirk, a trade-off that explains numbers off its band? A non-empty `abilities` or
## `side_effects`, or a `quirk` text.
static func has_quirk(def: Dictionary) -> bool:
	if str(def.get("quirk", "")).strip_edges() != "":
		return true
	for k in ["abilities", "side_effects"]:
		if def.get(k) is Array and not def[k].is_empty():
			return true
	return false


## The band of the part's family and tier as the part's line scales it: stat -> value. {} when there is none.
static func expected(table: Dictionary, def: Dictionary, lines: Dictionary) -> Dictionary:
	var band = table.get("bands", {}).get(str(def.get("family", "")), {}).get(str(int(def.get("tier", 1))))
	if not band is Dictionary:
		return {}
	var d := {"line": def.get("line", Stats.DEFAULT_LINE), "power": band.get("power", 0), "hp": band.get("hp", Stats.DEFAULT_HP), "stats": {}}
	for stat in band:
		if stat != "power" and stat != "hp":
			d["stats"][stat] = band[stat]
	var eff := Stats.effective(d, lines)
	var out := {}
	for stat in band:
		out[stat] = _stat(eff, stat)
	return out


## Does `def` state a `cost` (a text or a non-empty object saying what it costs to run)? With a quirk it is what excuses a relic
## (docs/CONTENT.md 18: `"relic": true`); a relic with neither fails check().
static func has_cost(def: Dictionary) -> bool:
	var c = def.get("cost")
	return (c is String and c.strip_edges() != "") or (c is Dictionary and not c.is_empty())


## How `def` stands against its band: {status, problems}. status is
## - "none": its family has no bands; "unique": a unique part is not held to them;
## - "relic": a relic (`"relic": true`) is never held to the bands but must have a quirk or a cost (else "fail");
## - "no_band": its family has bands but not its tier (problems says so);
## - "ok": every stat is within the tolerance; "quirk": off, but it has a quirk;
## - "waived": off, and listed in the table's `waivers`; "fail": off, with nothing to excuse it;
## - "stale_waiver": listed in `waivers` although it is fine (or exempt) now.
## problems has one line per stat that is off (for "ok" and "none" it is empty).
static func check(table: Dictionary, def: Dictionary, lines: Dictionary) -> Dictionary:
	var id := str(def.get("id", ""))
	var waived: bool = table.get("waivers", {}).has(id)
	var problems: Array[String] = []
	var status := "ok"
	if def.get("relic", false) == true:  # above the bands on purpose, if it says what it costs
		if has_quirk(def) or has_cost(def):
			status = "relic"
		else:
			status = "fail"
			problems = ["%s: a relic needs a quirk or a cost" % id]
	elif not table.get("bands", {}).has(str(def.get("family", ""))):
		status = "none"
	elif def.get("unique", false) == true:
		status = "unique"
	else:
		var want := expected(table, def, lines)
		if want.is_empty():
			return {"status": "no_band", "problems": ["%s: %s has no band for tier %d" % [id, def.get("family"), int(def.get("tier", 1))]]}
		problems = _off(def, lines, want, float(table.get("tolerance", DEFAULT_TOLERANCE)))
		if not problems.is_empty():
			status = "quirk" if has_quirk(def) else ("waived" if waived else "fail")
	if waived and status != "waived":
		status = "stale_waiver"
	return {"status": status, "problems": problems}


static func _off(def: Dictionary, lines: Dictionary, want: Dictionary, tolerance: float) -> Array[String]:
	var out: Array[String] = []
	var eff := Stats.effective(def, lines)
	for stat in want:
		var got = _stat(eff, stat)
		if got == null:
			out.append("%s: no %s" % [def.get("id"), stat])
			continue
		var w := float(want[stat])
		var off := absf(float(got) - w) / maxf(absf(w), 0.0001)
		if off > tolerance + 1e-9:
			out.append("%s: %s is %s against a band of %s (%d%% off, the limit is %d%%; line %s)" % [def.get("id"), stat, snappedf(float(got), 0.01), snappedf(w, 0.01), roundi(off * 100.0), roundi(tolerance * 100.0), eff["line"]])
	return out


## A stat of Stats.effective's answer: `power` and `hp` are its own keys, anything else is in `stats` (null when absent).
static func _stat(eff: Dictionary, stat: String):
	if stat == "power" or stat == "hp":
		return eff[stat]
	return eff["stats"].get(stat)
