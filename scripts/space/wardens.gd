extends RefCounted
## The exit wardens (docs/MECHANICS_REVIEW.md P7, data/wardens.json): every region's exit beacon is held by a warden, a strong
## generated ship (shipgen.gd) that is known when the region is chosen, as Slay the Spire's act boss is. At the beacon you pay
## its toll, are waved through on good terms, or break through; so a region is built towards a known threat.
## - for_region() rolls the warden of a region at a stage: the guarding faction (the region's `faction` when it is one of the
##   entries of data/wardens.json, else its `enemies`), a hull class by stage, and the budget you will meet about `jumps_ahead`
##   jumps in, times a stage factor. It uses no rng of the campaign, so the same seed, stage and region give the same ship, and
##   the region card can show it before you jump.
## - event() is the event dictionary the event panel shows at the beacon (pay, good standing, break through, turn back).
## - A warden is cleared by the flag flag_of(region, stage): set by the toll, a pass, or a fight that ends won, spared, captured
##   or escaped (campaign.gd: fight_done). The region choice stays shut until it is.
## No nodes, no drawing. `c` below is the campaign (campaign.gd; not preloaded here, to avoid a cycle), `ship` the player's Ship.

const Regions = preload("res://scripts/space/regions.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Threat = preload("res://scripts/space/threat.gd")

const PATH := "res://data/wardens.json"
const DRIFT_PATH := "res://data/drift.json"
const ENTRY_KEYS: Array[String] = ["name", "hail", "hint", "toll", "pass_rep", "rep_on_fight"]
const KEYS: Array[String] = ["_doc", "stage_size", "stage_budget_mult", "jumps_ahead", "fight_credits", "wardens"]
const FALLBACK := "rustfangs"  ## the guard of a region whose faction and enemies have no entry

static var _cfg := {}
static var _danger := {}
static var _foes := {}  # spec -> the warden's Ship, built once
static var _rated := {}  # "spec|player fingerprint" -> skulls


## data/wardens.json, read once.
static func config() -> Dictionary:
	if _cfg.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		assert(data is Dictionary and data.get("wardens") is Dictionary, "bad warden data: " + PATH)
		_cfg = data
	return _cfg


## The enemy tier at jump count `jumps` (data/drift.json danger: the same steps as Campaign.tier()).
static func tier_at(jumps: int) -> int:
	if _danger.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(DRIFT_PATH))
		assert(data is Dictionary and data.get("danger") is Dictionary, "bad drift data: " + DRIFT_PATH)
		_danger = data["danger"]
	if jumps >= int(_danger["tier3_from"]):
		return 3
	return 2 if jumps >= int(_danger["tier2_from"]) else 1


## The faction that guards region `region` (its data): its `faction` when that has an entry, else its `enemies`, else the Rustfangs.
static func faction_of(region: Dictionary) -> String:
	var entries: Dictionary = config()["wardens"]
	for key in ["faction", "enemies"]:
		if entries.has(str(region.get(key, ""))):
			return str(region[key])
	return FALLBACK


## The flag that says the warden of region `region_id` at stage `stage` has been dealt with.
static func flag_of(region_id: String, stage: int) -> String:
	return "warden_%s_%d" % [region_id, stage]


static func _fnv(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	return h


## The warden of region `region` (its data) at stage `stage` of the run of seed `run_seed`, built for the budget of the exit,
## about `jumps_ahead` jumps after `jumps`: {faction, name, hint, toll (credits per stage), pass_rep (left out: never waves
## you through), rep_on_fight, spec (a shipgen spec string), region, stage, flag}. {} past the last stage (the ending region has
## no exit). Deterministic, and it does not touch the campaign's rng.
static func for_region(run_seed: int, stage: int, region: Dictionary, jumps: int, difficulty := "normal") -> Dictionary:
	var cfg := config()
	var sizes: Array = cfg["stage_size"]
	if region.is_empty() or stage < 1 or stage > sizes.size():
		return {}
	var id := str(region.get("id", ""))
	var faction := faction_of(region)
	var entry: Dictionary = cfg["wardens"][faction]
	var ahead := jumps + int(cfg["jumps_ahead"])
	var budget := Shipgen.budget_for(tier_at(ahead), ahead, Shipgen.danger_of(region), difficulty) * float(cfg["stage_budget_mult"][stage - 1])
	var w := {"faction": faction, "name": str(entry["name"]), "hint": str(entry["hint"]), "toll": int(entry.get("toll", 0)),
		"rep_on_fight": int(entry.get("rep_on_fight", 0)), "region": id, "stage": stage, "flag": flag_of(id, stage),
		"spec": Shipgen.spec(faction, str(sizes[stage - 1]), Regions.seed_for(run_seed, stage, id) ^ _fnv("warden"), budget)}
	if entry.has("pass_rep"):
		w["pass_rep"] = int(entry["pass_rep"])
	return w


## A saved warden `d` made sound for region `region_id` at `stage` (numbers whole again after the JSON round trip), {} when it is
## not one (then the caller rolls it again).
static func clean(d, region_id: String, stage: int) -> Dictionary:
	if not d is Dictionary:
		return {}
	for k in ["faction", "name", "hint", "spec", "region", "flag"]:
		if not d.get(k) is String:
			return {}
	for k in ["toll", "rep_on_fight", "stage"]:
		if not (d.get(k) is float or d.get(k) is int):
			return {}
	if d["region"] != region_id or int(d["stage"]) != stage or d["flag"] != flag_of(region_id, stage) or not Shipgen.is_spec(d["spec"]):
		return {}
	if d.has("pass_rep") and not (d["pass_rep"] is float or d["pass_rep"] is int):
		return {}
	var out := {}
	for k in ["faction", "name", "hint", "spec", "region", "flag"]:
		out[k] = str(d[k])
	for k in ["toll", "rep_on_fight", "stage"]:
		out[k] = int(d[k])
	if d.has("pass_rep"):
		out["pass_rep"] = int(d["pass_rep"])
	return out


# --- the threat, rated against the player's ship ---------------------------------------------------------------

static func _fingerprint(ship) -> int:
	return hash([ship.get_instance_id(), ship.grid.tiles.hash(), ship.components.instances.hash()])


## The warden's threat to `ship`, 1 to 5 skulls (Threat.rate); 0 when it cannot be rated (no ship, a spec that does not
## build). Worked out once per warden and ship design, so the map can ask every frame.
static func skulls(w: Dictionary, ship) -> int:
	if w.is_empty() or ship == null:
		return 0
	var key := "%s|%d" % [w["spec"], _fingerprint(ship)]
	if not _rated.has(key):
		if _rated.size() > 64:
			_rated.clear()
		if not _foes.has(w["spec"]):
			if _foes.size() > 16:
				_foes.clear()
			_foes[w["spec"]] = Shipgen.from_spec(str(w["spec"]))
		var foe = _foes[w["spec"]]
		_rated[key] = int(Threat.rate(foe, ship)["skulls"]) if foe != null else 0
	return _rated[key]


## "Threat 4/5" for the warden against `ship`, "" when it cannot be rated.
static func threat_label(w: Dictionary, ship) -> String:
	var n := skulls(w, ship)
	return Threat.label(n) if n > 0 else ""


## "Exit warden: Concord Bulwark (Threat 4/5)" for the region card and the map tip.
static func line(w: Dictionary, ship) -> String:
	var t := threat_label(w, ship)
	return "Exit warden: %s%s" % [w["name"], " (%s)" % t if t != "" else ""]


# --- the event at the beacon -----------------------------------------------------------------------------------

## Has the warden been dealt with in campaign `c`?
static func cleared(w: Dictionary, c) -> bool:
	return w.is_empty() or c.flags.has(str(w["flag"]))


## The credits the toll asks at the warden's stage.
static func toll_of(w: Dictionary) -> int:
	return int(w.get("toll", 0)) * int(w.get("stage", 1))


## The event panel's page for warden `w` at the beacon ({} for no warden): its name for a title, the lane held, the toll and
## the threat for the text, and the choices pay the toll, good standing (only with the reputation, blue), break through (a fight
## against the warden's ship, whose `after_win` clears the lane, pays credits and changes the reputation) and turn back
## (nothing changes; come again). `ship` rates the threat.
static func event(w: Dictionary, c, ship) -> Dictionary:
	if w.is_empty():
		return {}
	var cfg := config()
	var entry: Dictionary = cfg["wardens"].get(str(w["faction"]), {})
	var name := str(w["name"])
	var flag := str(w["flag"])
	var fac := str(w["faction"])
	var stage := int(w["stage"])
	var toll := toll_of(w)
	var rating := threat_label(w, ship)
	var text := str(entry.get("hail", "The %s holds the exit lane." % name))
	text += " It wants %d credits for the lane." % toll if toll > 0 else " It asks for nothing. It only holds the lane."
	if rating != "":
		text += " Your scanners rate it %s." % rating
	var clear := {"flag": [flag]}
	var choices := []
	if toll > 0:
		choices.append({"text": "Pay the toll (%d credits)." % toll, "requires": {"credits": toll, "pay": true},
			"outcomes": [{"weight": 1, "text": "The credits change hands. The %s turns its guns away and the lane opens." % name, "effects": clear.duplicate(true)}]})
	if w.has("pass_rep") and c.rep.has(fac):
		choices.append({"text": "[Good standing] They know your registry and wave you through.", "blue": true, "requires": {"rep_min": {fac: int(w["pass_rep"])}},
			"outcomes": [{"weight": 1, "text": "A signal goes out and a reply comes back. The %s lets you through without a word." % name, "effects": clear.duplicate(true)}]})
	var win := {"flag": [flag], "items": {"credits": int(cfg.get("fight_credits", 50)) * stage}}
	var rep_change := int(w.get("rep_on_fight", 0))
	if rep_change != 0 and c.rep.has(fac):
		win["rep"] = {fac: rep_change}
	choices.append({"text": "Break through.", "outcomes": [{"weight": 1, "text": "You raise shields and run at the lane.", "effects": {"fight": str(w["spec"])},
		"after_win": {"text": "The %s is gone from the lane. The beacon is yours." % name, "effects": win, "clears": flag}}]})
	choices.append({"text": "Turn back.", "outcomes": [{"weight": 1, "text": "You back away from the beacon. The %s holds the lane, and will still be here." % name, "effects": {}}]})
	return {"id": "warden", "type": "warden", "once": false, "title": name, "text": text, "choices": choices}


# --- the validator ---------------------------------------------------------------------------------------------

## Every problem with data/wardens.json: unknown keys, bad lists, an entry for a faction with no enemy table, bad numbers.
static func problems() -> Array[String]:
	var out: Array[String] = []
	var cfg := config()
	for k in cfg:
		if not KEYS.has(k):
			out.append("wardens.json: unknown key '%s'" % k)
	var sizes = cfg.get("stage_size")
	var mults = cfg.get("stage_budget_mult")
	if not (sizes is Array and mults is Array and sizes.size() == mults.size() and not sizes.is_empty()):
		out.append("wardens.json: stage_size and stage_budget_mult must be lists of the same length (one per stage)")
	else:
		for s in sizes:
			if not Shipgen.tables()["sizes"].has(s):
				out.append("wardens.json: stage_size '%s' is not a hull class of enemy_tables.json" % str(s))
		for m in mults:
			if not ((m is float or m is int) and m > 0):
				out.append("wardens.json: stage_budget_mult must be numbers above 0")
	if not (cfg.get("jumps_ahead") is float or cfg.get("jumps_ahead") is int) or int(cfg.get("jumps_ahead", -1)) < 0:
		out.append("wardens.json: jumps_ahead must be a whole number of jumps, 0 or more")
	for id in cfg["wardens"]:
		var e = cfg["wardens"][id]
		if not Shipgen.tables()["factions"].has(id):
			out.append("wardens.json: '%s' has no enemy table in enemy_tables.json" % id)
		if not e is Dictionary:
			out.append("wardens.json: '%s' must be an object" % id)
			continue
		for k in e:
			if not ENTRY_KEYS.has(k):
				out.append("wardens.json: '%s': unknown key '%s' (known: %s)" % [id, k, ", ".join(ENTRY_KEYS)])
		for k in ["name", "hail", "hint"]:
			if not (e.get(k) is String and e[k] != ""):
				out.append("wardens.json: '%s': %s must be a non-empty text" % [id, k])
		for k in ["toll", "pass_rep", "rep_on_fight"]:
			if e.has(k) and not (e[k] is float or e[k] is int):
				out.append("wardens.json: '%s': %s must be a number" % [id, k])
		if int(e.get("toll", 0)) < 0:
			out.append("wardens.json: '%s': toll cannot be negative" % id)
	return out
