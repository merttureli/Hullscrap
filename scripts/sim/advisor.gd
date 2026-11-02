extends RefCounted
## The Ledger's brain: the guidance program Ma Gantry Loans installs on every ship it finances (docs/LORE.md), because a ship that grows
## pays its debt. Read-only: it measures the ship and the campaign and decides what to say; it never touches an rng or the game's state.
## Three kinds of line, all from data/advisor.json (the words) and data/progression.json (the numbers, written by the balance track):
##   goals     the stage's checklist (the milestone ladder of docs/audit/progression.md section 7): each has a `check` over the vocabulary below;
##             the first one not met is the card's line, with its progress ("Guns 2/3"). A value is a number or "p:<key>" (that stage's
##             progression.json value; a clause whose number is missing is left out, a goal with nothing left is dropped).
##   warnings  section 8's triggers: one amber line, at most once a stage unless it gets worse by a wide margin (rules.worse).
##   tips      the first time something happens (the first fight, the first station ...): once per profile, listed in the journal.
## The setting (profile.ledger) decides what shows: full = card, tips and warnings; warn = warnings only; off = nothing.
## measure() is the check vocabulary; tick() re-evaluates at most once a second. Pure logic, no nodes: tests/test_advisor.gd checks it.

const Threat = preload("res://scripts/space/threat.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Wardens = preload("res://scripts/space/wardens.gd")
const Mods = preload("res://scripts/board/mods.gd")

const WORDS_PATH := "res://data/advisor.json"
const NUMBERS_PATH := "res://data/progression.json"  ## written by the balance track; missing until it lands (the `p:` clauses are then left out)
## The checks a goal may use (docs/audit/progression.md section 7): what measure() computes.
const VOCAB: Array[String] = ["intakes", "guns", "layers", "fab", "power", "margin", "accel_ratio", "plates", "medbays", "known",
	"fuel_margin", "credits_over_toll", "damaged_blocks"]
const MAX_KEYS: Array[String] = ["damaged_blocks"]  ## met when the value is AT MOST the number (the rest: at least)
## The keys of a stage's row and of `warn` in progression.json (the format the balance track writes).
const STAGE_KEYS: Array[String] = ["power_floor", "power_median", "warden", "enemy", "guns", "layers", "intakes", "fab", "plates", "accel_ratio",
	"known", "fuel_margin", "credits_over_toll"]
const WARN_KEYS: Array[String] = ["outgunned_ratio", "skulls_ratio", "cliff_stage", "cliff_power", "hull_left", "scrap_surplus", "accel_min", "known_stall"]
## The warnings, most urgent first (the card shows one at a time).
const WARNINGS: Array[String] = ["outgunned", "fuel", "skulls", "toll", "hull", "cliff", "power", "mass", "scrap", "blueprints"]
## The first-time tips: what each waits for (the tick's `ctx` and the ship / campaign, see watch()).
const TIPS: Array[String] = ["first_build", "first_fight", "first_breach", "first_station", "first_fabricator", "first_blueprint", "first_shields",
	"first_warden", "first_drift_jump", "low_fuel", "first_boarding", "first_mod", "first_rig_bonus", "first_crew", "first_wreck"]
const MODES: Array[String] = ["full", "warn", "off"]
const MODE_NAMES := {"full": "Full", "warn": "Warnings only", "off": "Off"}
const EPS := 1e-6

static var _words := {}
static var _numbers := {}

var words: Dictionary  ## data/advisor.json
var numbers: Dictionary  ## data/progression.json ({} when it is missing)
var profile = null  ## the Profile (setting, tips seen, the run it follows); null in a test that has none
var mode_now := "full"  ## the setting when there is no profile

var values := {}  ## what the last evaluation measured: the checks of VOCAB and the facts around them (fuel, credits, scrap, hops ...)
var stage := 0  ## the stage it was measured at
var base := {}  ## the run's start: {accel, plates} (accel_ratio and plates are against it)
var warned := {}  ## warning id -> {stage, level}: the last time it fired
var announced := {}  ## "<stage>:<goal id>" -> true: the goals whose tick has been given
var warning := {}  ## the warning on show: {id, text, left (seconds)}; {} when none
var tip_queue: Array[String] = []  ## the tips waiting to be shown, in order
var events: Array = []  ## what happened since take_events(): {type: "goal", id, title} | {type: "warning", id, text} | {type: "tip", id}
var dirty := false  ## the run state changed: the caller keeps state() in the profile
var _run := -1  # the seed of the run being followed
var _clock := 0.0  # seconds since the last evaluation
var _prev := {}  # what the last look saw, for the tips that wait for a change ({} before the first look, and after the ship was swapped)
var _jumps := 0  # the campaign's jump counter at the last look (state())
var _met := {}  # "<stage>:<goal id>" -> was it met at the last look: a goal is news when it goes from false to true
var _hops_key := ""  # the cache key of the jump counts below
var _hops := {"exit": -1, "station": -1}


func _init(p_words := {}, p_numbers = null) -> void:
	words = p_words if not p_words.is_empty() else load_words()
	numbers = p_numbers if p_numbers != null else load_numbers()


## data/advisor.json (read once).
static func load_words() -> Dictionary:
	if _words.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(WORDS_PATH))
		if d is Dictionary:
			_words = d
	return _words


## data/progression.json (read once); {} while the file is not in the game.
static func load_numbers() -> Dictionary:
	if _numbers.is_empty() and FileAccess.file_exists(NUMBERS_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(NUMBERS_PATH))
		if d is Dictionary:
			_numbers = d
	return _numbers


func rule(key: String) -> float:
	return float(words.get("rules", {}).get(key, 0.0))


# --- the setting ---------------------------------------------------------------------------------------------------

func mode() -> String:
	return str(profile.ledger) if profile != null else mode_now


## What the setting lets show: "card" (the goal), "tips" or "warnings".
func shows(what: String) -> bool:
	match mode():
		"full":
			return true
		"warn":
			return what == "warnings"
	return false


# --- the numbers ---------------------------------------------------------------------------------------------------

## The number behind `key` at `at_stage`: progression.json's stage row, or NAN when it is not there.
func stage_value(at_stage: int, key: String) -> float:
	var row = numbers.get("stages", {}).get(str(at_stage), {})
	return float(row[key]) if row is Dictionary and row.has(key) else NAN


func warn_value(key: String) -> float:
	var w = numbers.get("warn", {})
	return float(w[key]) if w is Dictionary and w.has(key) else NAN


## A check's number: a literal, or "p:<key>" read from the stage's row (NAN when it is missing).
func resolve(v, at_stage: int) -> float:
	if v is String and v.begins_with("p:"):
		return stage_value(at_stage, v.substr(2))
	return float(v)


## Every problem with the numbers' format (the stages 1 to 8 with every key, `warn` with every key): [] when it is sound.
static func numbers_problems(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not d.get("stages") is Dictionary:
		return ["no stages"]
	for s in range(1, 9):
		var row = d["stages"].get(str(s))
		if not row is Dictionary:
			out.append("stage %d is missing" % s)
			continue
		for k in STAGE_KEYS:
			if not (row.get(k) is float or row.get(k) is int):
				out.append("stage %d has no number for %s" % [s, k])
	if not d.get("warn") is Dictionary:
		out.append("no warn")
		return out
	for k in WARN_KEYS:
		if not (d["warn"].get(k) is float or d["warn"].get(k) is int):
			out.append("warn has no number for %s" % k)
	return out


# --- goals ---------------------------------------------------------------------------------------------------------

## A check as alternatives (any one will do), each a list of clauses {key, need}: a dictionary is one alternative, an array of
## dictionaries several. A clause whose number is missing is left out; [] when some alternative has none left (the goal cannot be judged).
func alternatives(check, at_stage: int) -> Array:
	var raw: Array = check if check is Array else [check]
	var out := []
	for alt in raw:
		var clauses := []
		for k in alt:
			var need := resolve(alt[k], at_stage)
			if not is_nan(need):
				clauses.append({"key": str(k), "need": need})
		if clauses.is_empty():
			return []
		out.append(clauses)
	return out


## The goals of `at_stage`, in order, ready to judge: {id, title, why, alts}; the ones that cannot be judged are left out. The `{=key}`
## holes of the words are filled with the first alternative's numbers.
func goals(at_stage: int) -> Array:
	var out := []
	for g in words.get("stages", {}).get(str(at_stage), []):
		var alts := alternatives(g["check"], at_stage)
		if alts.is_empty():
			continue
		var nums := {}
		for c in alts[0]:
			nums[c["key"]] = c["need"]
		out.append({"id": str(g["id"]), "title": fill(str(g["title"]), nums), "why": fill(str(g.get("why", "")), nums), "alts": alts})
	return out


## `text` with each {=key} replaced by the number of that check.
static func fill(text: String, nums: Dictionary) -> String:
	var out := text
	for k in nums:
		out = out.replace("{=%s}" % k, num(float(nums[k]), str(k)))
	return out


## A check number as text: a share as a percent, a whole number plain, else up to two decimals.
static func num(v: float, key := "") -> String:
	if key == "accel_ratio":
		return "%d%%" % roundi(v * 100.0)
	if is_equal_approx(v, roundf(v)):
		return "%d" % roundi(v)
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	return s


static func clause_met(c: Dictionary, vals: Dictionary) -> bool:
	var have := float(vals.get(c["key"], 0.0))
	return have <= float(c["need"]) + EPS if MAX_KEYS.has(c["key"]) else have >= float(c["need"]) - EPS


## Is goal `g` met: every clause of at least one alternative.
static func goal_met(g: Dictionary, vals: Dictionary) -> bool:
	for alt in g["alts"]:
		if alt.all(func(c): return clause_met(c, vals)):
			return true
	return false


## How far goal `g` is: the clause to show ({key, label, have, need, text: "Guns 2/3"}), the first unmet one of the alternative that is nearest done.
func progress(g: Dictionary, vals: Dictionary) -> Dictionary:
	var best := {}
	var best_left := INF
	for alt in g["alts"]:
		var unmet: Array = alt.filter(func(c): return not clause_met(c, vals))
		if unmet.is_empty():
			unmet = [alt[0]]
		var c: Dictionary = unmet[0]
		var left := float(unmet.size()) + absf(float(c["need"]) - float(vals.get(c["key"], 0.0))) / maxf(absf(float(c["need"])), 1.0)
		if left < best_left:
			best_left = left
			best = c
	var label := str(words.get("labels", {}).get(best["key"], best["key"]))
	var have := float(vals.get(best["key"], 0.0))
	return {"key": best["key"], "label": label, "have": have, "need": float(best["need"]),
		"text": "%s %s/%s" % [label, num(have, best["key"]) if best["key"] != "margin" else "%+d" % roundi(have), num(float(best["need"]), best["key"])]}


## The stage's checklist: [{id, title, why, met, progress}] in order.
func checklist(vals := {}, at_stage := -1) -> Array:
	var vs: Dictionary = vals if not vals.is_empty() else values
	var out := []
	for g in goals(stage if at_stage < 0 else at_stage):
		out.append({"id": g["id"], "title": g["title"], "why": g["why"], "met": goal_met(g, vs), "progress": progress(g, vs)})
	return out


## The first goal not met, as a checklist row ({} when every one is, or the stage has none).
func next_goal(vals := {}, at_stage := -1) -> Dictionary:
	for row in checklist(vals, at_stage):
		if not row["met"]:
			return row
	return {}


## What the card has to say now: {} for nothing, else {goal (the next goal's row, {} when all are met), done (the stage's goals are all met), warning}.
## The setting decides: Full has the goal, Warnings only has just the warning, Off nothing.
func card() -> Dictionary:
	var out := {}
	var rows := checklist()
	if shows("card") and not rows.is_empty():
		var next := next_goal()
		out["goal"] = next
		out["done"] = next.is_empty()
	if shows("warnings") and not warning.is_empty():
		out["warning"] = warning
	return out


# --- measuring -----------------------------------------------------------------------------------------------------

## The start of a run, which accel_ratio and plates are measured against: {accel, plates}.
static func baseline(ship) -> Dictionary:
	return {"accel": float(Threat.power(ship, float(Threat.config()["player_aim"]))["accel"]), "plates": plates_of(ship)}


## Armour cells: the solid tiles that are not the plain wall, the door or the floor.
static func plates_of(ship) -> int:
	var n := 0
	var defs = ship.grid.defs
	for c in ship.grid.tiles:
		var id := str(ship.grid.tiles[c])
		if id == "wall" or defs == null:
			continue
		var d: Dictionary = defs.get_def(id)
		if bool(d.get("solid", false)) and not bool(d.get("door", false)):
			n += 1
	return n


## The jumps from the ship's node to the nearest node of the region that satisfies `want` (a Callable on the node), or -1.
static func hops_to(campaign, want: Callable) -> int:
	var d = campaign.drift
	if d == null or str(campaign.current) == "":
		return -1
	var dist := {str(campaign.current): 0}
	var queue: Array = [str(campaign.current)]
	var i := 0
	while i < queue.size():
		var id: String = queue[i]
		i += 1
		if want.call(d.node(id)):
			return int(dist[id])
		for n in d.neighbours(id):
			if not dist.has(n):
				dist[n] = int(dist[id]) + 1
				queue.append(n)
	return -1


## The checks of VOCAB, and the facts around them (fuel, credits, scrap, hops, toll, structure, stage), for `ship` in `campaign`.
## `base` is the run's start ({accel, plates}); a ship with none is measured against itself. Reads only.
static func measure(ship, campaign, base_now := {}) -> Dictionary:
	ship.refresh()
	var comps = ship.components
	var powered: Dictionary = ship.power_state.get("powered", {})
	var off: Dictionary = ship.disabled_uids()
	var v := {"intakes": 0, "guns": 0, "medbays": 0}
	for uid in comps.instances:
		var inst: Dictionary = comps.instances[uid]
		var fam := str(comps.def(inst["id"]).get("family", ""))
		if fam == "weapon" and powered.get(uid, false) and comps.offline_reason(ship.grid, uid) == "":
			v["guns"] += 1
		elif fam == "medbay" and not off.has(uid):
			v["medbays"] += 1
		elif fam == "intake" and not inst["out_cells"].is_empty() and not off.has(uid) and (int(comps.def(inst["id"]).get("power", 0)) >= 0 or powered.get(uid, false)):
			v["intakes"] += 1
	v["layers"] = Shields.layers_of_ship(ship, powered)
	v["fab"] = int(Workshop.best(ship)["level"])
	var th := Threat.power(ship, float(Threat.config()["player_aim"]))
	v["power"] = float(th["power"])
	var accel0 := float(base_now.get("accel", th["accel"]))
	v["accel_ratio"] = float(th["accel"]) / accel0 if accel0 > 0.0 else 1.0
	v["plates"] = maxi(plates_of(ship) - int(base_now.get("plates", 0)), 0)
	v["known"] = ship.crafting.known.size()
	var best_net := {}
	for n in ship.power_state.get("networks", []):
		if best_net.is_empty() or float(n["supply"]) > float(best_net["supply"]):
			best_net = n
	v["margin"] = float(best_net["supply"]) - float(best_net["demand"]) if not best_net.is_empty() else 0.0
	v["damaged_blocks"] = Structure.damaged(ship).size()
	v["fuel"] = ship.inventory.count("fuel")
	v["credits"] = ship.inventory.count("credits")
	v["scrap"] = ship.inventory.count("scrap")
	v["structure"] = Structure.structure_fraction(ship)
	v["stage"] = int(campaign.stage) if campaign != null else 0
	v["toll"] = 0
	v["hops"] = -1
	v["station_hops"] = -1
	v["at_exit"] = false
	v["warden_up"] = false
	if campaign != null and campaign.drift != null:
		v["toll"] = Wardens.toll_of(campaign.warden) if not campaign.warden.is_empty() else 0
		v["at_exit"] = campaign.at_exit()
		v["warden_up"] = campaign.warden_up()
		v["hops"] = hops_to(campaign, func(n): return str(n.get("type", "")) == "exit")
		v["station_hops"] = hops_to(campaign, func(n): return str(n.get("type", "")) == "station")
	v["credits_over_toll"] = v["credits"] - v["toll"]
	var per_jump := float(campaign.jump_cost(ship)) / float(campaign.FUEL_PARTS) if campaign != null and campaign.drift != null else 1.0
	v["fuel_margin"] = float(v["fuel"]) - maxf(float(v["hops"]), 0.0) * per_jump
	return v


# --- warnings ------------------------------------------------------------------------------------------------------

## The warnings whose condition holds in `vals` at `at_stage`: [{id, level}], most urgent first. `level` is how bad (1 = just over the line);
## `ctx.foe_ratio` is the enemy/player power ratio of the fight on now (0 for none). A warning whose numbers are missing is not asked.
func conditions(vals: Dictionary, ctx := {}) -> Array:
	var out := []
	var at: int = int(vals.get("stage", stage))
	var power := float(vals.get("power", 0.0))
	var warden := stage_value(at, "warden")
	var outgunned := warn_value("outgunned_ratio")
	var toll_short := float(vals.get("credits_over_toll", 0.0)) < 0.0
	if bool(vals.get("at_exit", false)) and bool(vals.get("warden_up", false)) and toll_short and not is_nan(warden) and not is_nan(outgunned) \
			and power < outgunned * warden:
		out.append({"id": "outgunned", "level": warden / maxf(power, 1.0)})
	var fm := float(vals.get("fuel_margin", 0.0))
	if int(vals.get("hops", -1)) >= 0 and fm < 0.0:
		out.append({"id": "fuel", "level": -fm})
	var skulls := warn_value("skulls_ratio")
	var foe := float(ctx.get("foe_ratio", 0.0))
	if not is_nan(skulls) and foe >= skulls:
		out.append({"id": "skulls", "level": foe / skulls})
	var hops := int(vals.get("hops", -1))
	var want := stage_value(at, "credits_over_toll")  # the cushion over the toll the stage asks for (the toll itself when the numbers are missing)
	var gap := (want if not is_nan(want) else 0.0) - float(vals.get("credits_over_toll", 0.0))
	if hops >= 0 and hops <= int(rule("toll_jumps")) and bool(vals.get("warden_up", false)) and gap > 0.0 and int(vals.get("scrap", 0)) > int(rule("toll_scrap")):
		out.append({"id": "toll", "level": maxf(gap, 1.0)})
	var hull := warn_value("hull_left")
	if not is_nan(hull) and float(vals.get("structure", 1.0)) < hull and int(vals.get("station_hops", -1)) > int(rule("hull_stations")):
		out.append({"id": "hull", "level": hull / maxf(float(vals.get("structure", 1.0)), 0.05)})
	var cliff := warn_value("cliff_stage")
	if not is_nan(cliff) and at == int(cliff) and not is_nan(warn_value("cliff_power")) and power < warn_value("cliff_power"):
		out.append({"id": "cliff", "level": warn_value("cliff_power") / maxf(power, 1.0)})
	if float(vals.get("margin", 0.0)) < 0.0:
		out.append({"id": "power", "level": -float(vals["margin"])})
	var accel_min := warn_value("accel_min")
	if not is_nan(accel_min) and float(vals.get("accel_ratio", 1.0)) < accel_min:
		out.append({"id": "mass", "level": accel_min / maxf(float(vals["accel_ratio"]), 0.05)})
	var surplus := warn_value("scrap_surplus")
	if not is_nan(surplus) and float(vals.get("scrap", 0)) > surplus and float(vals.get("credits", 0)) < rule("scrap_credits"):
		out.append({"id": "scrap", "level": float(vals["scrap"]) / surplus})
	var stall := warn_value("known_stall")
	if not is_nan(stall) and at > 3 and float(vals.get("known", 0)) <= stall:
		out.append({"id": "blueprints", "level": 1.0})
	out.sort_custom(func(a, b): return WARNINGS.find(a["id"]) < WARNINGS.find(b["id"]))
	return out


## May warning `id` fire now, at `at_stage` with `level`: not yet this stage, or worse than it was by rules.worse (a wide margin).
func may_fire(id: String, at_stage: int, level: float) -> bool:
	var w = warned.get(id)
	if not w is Dictionary or int(w["stage"]) != at_stage:
		return true
	return level >= float(w["level"]) * rule("worse") - EPS


## The line of warning `id`.
func warning_text(id: String) -> String:
	return str(words.get("warnings", {}).get(id, {}).get("text", ""))


## Fire the first of `conds` that may: it goes on the card for rules.warn_s seconds (its words, {} when the setting hides warnings),
## and is remembered. Returns its id, "" when none fired.
func fire(conds: Array, at_stage: int) -> String:
	for c in conds:
		if may_fire(c["id"], at_stage, float(c["level"])):
			warned[c["id"]] = {"stage": at_stage, "level": float(c["level"])}
			dirty = true
			if shows("warnings"):
				warning = {"id": c["id"], "text": warning_text(c["id"]), "left": rule("warn_s")}
				events.append({"type": "warning", "id": c["id"], "text": warning["text"]})
			return c["id"]
	return ""


# --- tips ----------------------------------------------------------------------------------------------------------

## The tip ids whose moment came in this look, given the ship, the campaign and `ctx`: {build_on, fighting, boarding, loadout, breach, station,
## craft, shields, rig_bonus} (the screens' state, from the glue), plus what the ship and the campaign say. The tips that wait for a change
## (a blueprint learned, a crewmate hired) need a first look to compare with, so the look that begins a run or a load fires none of them.
func watch(ship, campaign, ctx: Dictionary) -> Array[String]:
	if int(_prev.get("ship", 0)) != ship.get_instance_id():
		_prev = {}  # another ship (a new pick): its blueprints and crew are no change of ours
	var now := {"ship": ship.get_instance_id()}
	now["known"] = ship.crafting.known.size()
	now["crew"] = ship.crew.filter(func(m): return not m.is_player).size()
	var fired: Array[String] = []
	var checks := {
		"first_build": bool(ctx.get("build_on", false)),
		"first_fight": bool(ctx.get("fighting", false)),
		"first_breach": bool(ctx.get("breach", false)),
		"first_station": bool(ctx.get("station", false)),
		"first_fabricator": bool(ctx.get("craft", false)),
		"first_shields": bool(ctx.get("shields", false)),
		"first_boarding": bool(ctx.get("loadout", false)),
		"first_rig_bonus": bool(ctx.get("rig_bonus", false)),
		"first_wreck": not ship.components.wrecks.is_empty(),
		"low_fuel": int(values.get("fuel", ship.inventory.count("fuel"))) <= int(words.get("rules", {}).get("low_fuel", 2)) and campaign != null and campaign.jumps > 0,
	}
	if campaign != null and campaign.drift != null:
		checks["first_warden"] = campaign.at_exit() and campaign.warden_up()
		checks["first_drift_jump"] = bool(campaign.last_jump.get("ok", false)) and bool(campaign.last_jump.get("drift", false))
	checks["first_mod"] = ship.inventory.counts.keys().any(func(k): return Mods.is_item(str(k)))
	if not _prev.is_empty():
		checks["first_blueprint"] = int(now["known"]) > int(_prev.get("known", 0))
		checks["first_crew"] = int(now["crew"]) > int(_prev.get("crew", 0))
	_prev = now
	for id in TIPS:
		if bool(checks.get(id, false)):
			fired.append(id)
	return fired


## Queue the tips of `fired` that this profile has not seen (the setting must allow tips).
func queue_tips(fired: Array) -> void:
	if not shows("tips"):
		return
	for id in fired:
		if not (profile != null and profile.has_tip(id)) and not tip_queue.has(id):
			tip_queue.append(id)


## The next tip to show, or "" (the card shows it and calls tip_shown).
func next_tip() -> String:
	return tip_queue[0] if shows("tips") and not tip_queue.is_empty() else ""


## The tip `id` is on the screen: it is remembered for good, and leaves the queue.
func tip_shown(id: String) -> void:
	tip_queue.erase(id)
	if profile != null:
		profile.mark_tip(id)
	events.append({"type": "tip", "id": id})


## The words of tip `id`: {title, text}, {} for one the words do not have.
func tip_words(id: String) -> Dictionary:
	for t in words.get("tips", []):
		if str(t["id"]) == id:
			return {"title": str(t.get("title", "")), "text": str(t.get("text", ""))}
	return {}


## The tips a profile has been shown, in the order shown, as the journal lists them: [{id, title, text, date}] (a tip the words no longer have is left out).
static func tips_seen(prof) -> Array:
	var out := []
	var all: Array = load_words().get("tips", [])
	for id in prof.tips:
		for t in all:
			if str(t["id"]) == str(id):
				out.append({"id": str(id), "title": str(t.get("title", "")), "text": str(t.get("text", "")), "date": str(prof.tips[id])})
	return out


# --- the run, and the clock ------------------------------------------------------------------------------------------

## What of this run to keep in the profile (profile.ledger_run), so a Continue picks up where the Ledger was.
func state() -> Dictionary:
	return {"seed": _run, "jumps": _jumps, "base": base, "warned": warned, "announced": announced.keys()}


## Follow campaign `c` with `ship`: a new run starts the Ledger afresh (its start measured now); the run the profile remembers goes on.
func follow(ship, c) -> void:
	if c == null or int(c.seed_value) == _run:
		return
	_run = int(c.seed_value)
	_prev = {}
	_met = {}
	_jumps = 0
	warning = {}
	tip_queue.clear()
	var kept = profile.ledger_run if profile != null else {}
	if kept is Dictionary and int(kept.get("seed", -1)) == _run and int(kept.get("jumps", 0)) <= int(c.jumps) and kept.get("base") is Dictionary:
		base = kept["base"]
		warned = kept.get("warned", {}) if kept.get("warned") is Dictionary else {}
		announced = {}
		for k in kept.get("announced", []):
			announced[str(k)] = true
	else:
		base = baseline(ship)
		warned = {}
		announced = {}
		dirty = true


## Look at the ship and the campaign: measure, announce the goals newly met, fire a warning, queue the tips. `ctx` as watch() says. Evaluating the
## checks is skipped in a fight or a boarding (the tips and warnings of the fight are not). Returns nothing; read card(), next_tip(), take_events().
func update(ship, campaign, ctx := {}) -> void:
	if ship == null or campaign == null or campaign.drift == null:
		return
	follow(ship, campaign)
	var busy := bool(ctx.get("fighting", false)) or bool(ctx.get("boarding", false))
	if not busy or values.is_empty():
		values = measure(ship, campaign, base)
		stage = int(values["stage"])
		_jumps = int(campaign.jumps)
		for g in goals(stage):
			var key := "%d:%s" % [stage, g["id"]]
			var met := goal_met(g, values)
			if met and not announced.has(key):
				announced[key] = true
				dirty = true
				if shows("card") and _met.get(key, true) == false:  # a goal already met at the first look (a new run, a new stage) is not news
					events.append({"type": "goal", "id": g["id"], "title": g["title"]})
			_met[key] = met
	var conds := conditions(values, ctx)
	fire(conds, stage)
	if not warning.is_empty() and not conds.any(func(c): return c["id"] == warning["id"]):
		warning = {}
	queue_tips(watch(ship, campaign, ctx))


## Time passes by `dt` real seconds: the warning on show ages, and the checks are measured at most once a second (rules.pace_s).
func tick(dt: float, ship, campaign, ctx := {}) -> void:
	if not warning.is_empty():
		warning["left"] = float(warning["left"]) - dt
		if float(warning["left"]) <= 0.0:
			warning = {}
	_clock += dt
	if _clock < maxf(rule("pace_s"), 1.0):
		return
	_clock = 0.0
	update(ship, campaign, ctx)


## What happened since the last call (see `events`).
func take_events() -> Array:
	var out := events
	events = []
	return out


# --- words with keywords ------------------------------------------------------------------------------------------------

## `text` cut into runs: [{text, kw}] where kw is a keyword id of advisor.json `keywords` ("" for plain words). {id} marks a keyword shown as its own
## word, {id:words} shows `words` instead.
static func segments(text: String) -> Array:
	var out := []
	var rest := text
	while true:
		var a := rest.find("{")
		var b := rest.find("}", a + 1) if a >= 0 else -1
		if a < 0 or b < 0:
			break
		var inner := rest.substr(a + 1, b - a - 1)
		if inner.begins_with("="):
			break
		if a > 0:
			out.append({"text": rest.substr(0, a), "kw": ""})
		var id := inner.get_slice(":", 0)
		out.append({"text": inner.get_slice(":", 1) if inner.contains(":") else id, "kw": id})
		rest = rest.substr(b + 1)
	if rest != "":
		out.append({"text": rest, "kw": ""})
	return out


## The text of `text` with its keyword marks taken out.
static func plain(text: String) -> String:
	return "".join(segments(text).map(func(s): return s["text"]))


## Keyword `id`: {id, color, hover}, {} when advisor.json has none.
func keyword(id: String) -> Dictionary:
	var k: Dictionary = words.get("keywords", {}).get(id, {})
	if k.is_empty():
		return {}
	return {"id": id, "color": Color(str(k["color"])), "hover": str(k["hover"])}
