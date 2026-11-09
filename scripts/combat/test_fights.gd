extends RefCounted
## The rules of the test-fight page (K in play mode, test_fight_panel.gd draws it): what can be picked, how a pick becomes a ship, what a ship's
## numbers are and how a fight's end becomes a row of the session's results. No nodes. A test fight never changes the run: the player's ship
## fights as a copy (copy_of), the test ships are read fresh from data/ships/test (data/test_ships.json), and combat_view.gd keeps the real ship out
## of the simulation while it lasts.
##
## An enemy choice is {id, label, path, faction, role, stage, seed}: `path` is what Session.load_ship reads (a generated enemy's spec, a flagship's
## design, the test pirate or the rammer). A generated one is built the way the campaign builds a stage enemy (Campaign.gen_spec: the budget of the
## stage's middle jump, the faction's floor, Shipgen.spec); its seed is the one shown, so the same choice is the same ship.

const Arena = preload("res://scripts/combat/arena.gd")
const Flagships = preload("res://scripts/space/flagships.gd")
const Content = preload("res://scripts/data/content.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Threat = preload("res://scripts/space/threat.gd")

const SHIPS_PATH := "res://data/test_ships.json"
const STAGES := 8
const JUMPS_A_STAGE := 12.5  ## the progression bot's stages (tests/tool_standoff.gd): the enemy of a stage is the one met at its middle jump
const SEARCH := 60  ## seeds looked at for one that gives the role asked for
const CURRENT := "current"  ## the id of "your current ship" in the player's column

static var _ships := {}


# --- the player's column -------------------------------------------------------------------------------

## data/test_ships.json: {ships: [{id, name, blurb, design, stage, pool, build}], pools, fielded}.
static func config() -> Dictionary:
	if _ships.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(SHIPS_PATH))
		assert(data is Dictionary and data.get("ships") is Array, "bad test ships: " + SHIPS_PATH)
		_ships = data
	return _ships


## The player's choices: your current ship first, then the test ships. [{id, name, blurb, path}] (`path` "" for the current ship).
static func player_choices() -> Array:
	var out: Array = [{"id": CURRENT, "name": "Your current ship", "blurb": "A copy of the ship you fly now, as it is. The run keeps the real one.", "path": ""}]
	for e in config()["ships"]:
		out.append({"id": str(e["id"]), "name": str(e["name"]), "blurb": str(e["blurb"]), "path": str(e["design"])})
	return out


## A copy of `ship` (its parts, damage, cargo and crew), made through its save format, so nothing of the copy reaches the original.
static func copy_of(ship) -> Ship:
	var d: Dictionary = ship.to_dict()
	var c := Ship.new("Ship", ShipGrid.new(ship.grid.size, ship.grid.defs))
	if c.load_dict(d) != "":
		return null
	return c


## The ship of player choice `c` to fight with: a copy of `current` (the run's ship) or the test ship's design, read afresh. Its crew is aboard.
static func player_ship(c: Dictionary, current) -> Ship:
	var ship: Ship = copy_of(current) if str(c["id"]) == CURRENT and current != null else (Ship.from_design(str(c["path"])) if str(c["path"]) != "" else null)
	if ship != null:
		Jobs.spawn_crew(ship)
	return ship


# --- the enemy's column ----------------------------------------------------------------------------------

## The factions and races an enemy can be, in the order of the tables.
static func factions() -> Array:
	return Shipgen.tables()["factions"].keys()


static func roles_of(faction: String) -> Array:
	return Shipgen.roles_of(faction)


## The races that have a flagship.
static func flagship_races() -> Array:
	return Flagships.races()


## Does a ship of `size` at `stage` ever fly `role` (Shipgen.pick_role's rules: the least size, the first stage, no bay role where a stage has no drones)?
static func role_fits(role: String, size: String, stage: int) -> bool:
	var r: Dictionary = Shipgen.tables()["roles"]["list"][role]
	var order: Array = ["small", "medium", "large"]
	var no_bay := float(Shipgen.tables().get("drones", {}).get("stage_mult", {}).get(str(stage), 1.0)) <= 0.0
	return order.find(size) >= order.find(str(r.get("min_size", "small"))) and not (no_bay and r.has("bay")) and stage >= int(r.get("min_stage", 0))


## The campaign's danger of the first region whose pirates are `faction` (1.0 when no region sends them).
static func danger_for(faction: String) -> float:
	var base := str(Shipgen.tables()["factions"][faction].get("lines_as", faction))
	var best := INF
	for r in Content.regions():
		if str(r.get("enemies", "")) == base:
			best = minf(best, float(r.get("danger", 1.0)))
	return best if best < INF else 1.0


## The budget of a stage enemy of `faction` at `stage` (1 to STAGES): the middle jump of the stage.
static func budget_of(faction: String, stage: int) -> float:
	var j := roundi(JUMPS_A_STAGE * (float(stage) - 0.5))
	var tier := 3 if j >= 25 else (2 if j >= 10 else 1)
	return maxf(Shipgen.budget_for(tier, j, danger_for(faction), "normal", stage), Shipgen.budget_floor(faction, "normal"))


## The spec of the stage enemy (faction, role, stage, seed), or "" when that seed gives a size the role never flies at that stage.
static func spec_of(faction: String, role: String, stage: int, seed_value: int) -> String:
	var budget := budget_of(faction, stage)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var size := Shipgen.at_least(faction, Shipgen.pick_size(budget, rng))
	if not role_fits(role, size, stage):
		return ""
	return Shipgen.spec(faction, size, seed_value, budget, false, stage) + ":role:" + role


## The first seed from `from` up (at most SEARCH on) whose enemy really flies `role` (a carrier that found no wall for its bay is a gunboat), else -1.
static func next_seed(faction: String, role: String, stage: int, from: int) -> int:
	for s in range(maxi(from, 1), maxi(from, 1) + SEARCH):
		var spec := spec_of(faction, role, stage, s)
		if spec == "":
			continue
		var ship: Ship = Session.load_ship(spec)
		if ship != null and str(ship.get_meta("shipgen", {}).get("role", "")) == role:
			return s
	return -1


## The enemy choice for a generated ship; {} when the kind has no ship at that stage. `seed_value` is the first seed to try (the choice's own seed is the one found).
static func stage_choice(faction: String, role: String, stage: int, seed_value := 1) -> Dictionary:
	var s := next_seed(faction, role, stage, seed_value)
	if s < 0:
		return {}
	return {"id": "stage:%s:%s:%d:%d" % [faction, role, stage, s], "label": "%s %s, stage %d" % [faction.capitalize(), role, stage], "path": spec_of(faction, role, stage, s),
		"faction": faction, "role": role, "stage": stage, "seed": s}


## The enemy choice of a race's flagship.
static func flagship_choice(race: String) -> Dictionary:
	var e := Flagships.entry(race)
	if e.is_empty():
		return {}
	return {"id": "flagship:" + race, "label": "%s (%s flagship)" % [str(e.get("name", race)), race.capitalize()], "path": Flagships.design_of(race), "faction": race, "role": "flagship", "stage": int(e.get("stage", 0)), "seed": 0}


## The test pirate and the rustfang rammer (what K and Shift+K started before).
static func fixed_choices() -> Array:
	return [{"id": "pirate", "label": "Test pirate", "path": Session.PIRATE_PATH, "faction": "", "role": "", "stage": 0, "seed": 0},
		{"id": "rammer", "label": "Rustfang rammer", "path": Session.RAMMER_PATH, "faction": "", "role": "", "stage": 0, "seed": 0}]


## Every kind of enemy the page can pick, as a list of choices: each flagship, the pirate and the rammer, and every faction x role at `stage`
## (seed 1 up). Roles that never fly at that stage are left out.
static func all_choices(stage: int) -> Array:
	var out: Array = []
	for race in flagship_races():
		out.append(flagship_choice(race))
	out.append_array(fixed_choices())
	for f in factions():
		for role in roles_of(f):
			var c := stage_choice(f, role, stage)
			if not c.is_empty():
				out.append(c)
	return out


## The Random button: one of all the kinds (a flagship, the pirate, the rammer or a generated ship at a random stage), rolled with `rng`.
static func random_choice(rng: RandomNumberGenerator) -> Dictionary:
	var kinds: Array = []
	for race in flagship_races():
		kinds.append(["flagship", race])
	kinds.append(["fixed", "pirate"])
	kinds.append(["fixed", "rammer"])
	for f in factions():
		for role in roles_of(f):
			kinds.append(["stage", f, role])
	for i in 20:
		var k: Array = kinds[rng.randi_range(0, kinds.size() - 1)]
		match k[0]:
			"flagship":
				return flagship_choice(k[1])
			"fixed":
				return fixed_choices()[0 if k[1] == "pirate" else 1]
			_:
				var c := stage_choice(k[1], k[2], rng.randi_range(1, STAGES), rng.randi_range(1, 9999))
				if not c.is_empty():
					return c
	return fixed_choices()[0]


# --- numbers -----------------------------------------------------------------------------------------------

## What a column shows about `ship`: {hull, layers, guns, supply, demand, power (the threat number: Threat.power, the pilot's aim as the game rates it)}.
## Works on a private arena, so the ship is only read.
static func stats_of(ship, skill := -1.0) -> Dictionary:
	var arena := Arena.new(1)
	arena.add_ship(ship)
	var co = arena.ships[0]
	var supply := 0.0
	var demand := 0.0
	for n in ship.power_state.get("networks", []):
		supply += n["supply"]
		demand += n["demand"]
	var aim := skill if skill >= 0.0 else float(ship.get_meta("ai", {}).get("aim_skill", Threat.config()["player_aim"]))
	return {"hull": Structure.totals(ship).y, "layers": co.layers_cap, "guns": co.mounts.size(), "supply": supply, "demand": demand, "power": float(Threat.power(ship, aim)["power"])}


## The arena a preview of `ship` is drawn from (the schematic binds to it).
static func preview_arena(ship) -> Arena:
	var arena := Arena.new(1)
	arena.add_ship(ship)
	return arena


# --- the results -------------------------------------------------------------------------------------------

## How a fight ended, in words, from combat_view's leave(): `state` is the result's state, `offered` whether the enemy's surrender was on the table, `jumped` whether
## the player's drive had spooled.
static func ending_text(state: String, offered: bool, jumped: bool) -> String:
	match state:
		"won", "captured":
			return "won" if state == "won" else "won: crew all down"
		"lost":
			return "lost"
		"spared":
			return "you accepted their surrender"
		"escaped":
			return "they fled"
	if offered:
		return "they surrendered; you left"
	return "you jumped away" if jumped else "you broke away"


## A row of the results list: {ship, enemy, ending, time, hull, foe_hull}.
static func result_row(ship_name: String, enemy_name: String, ending: String, time_s: float, hull: float, foe_hull: float) -> Dictionary:
	return {"ship": ship_name, "enemy": enemy_name, "ending": ending, "time": time_s, "hull": hull, "foe_hull": foe_hull}


static func row_text(r: Dictionary) -> String:
	return "%s vs %s: %s, %d:%02d, hull %d%% / %d%%" % [r["ship"], r["enemy"], r["ending"], int(r["time"]) / 60, int(r["time"]) % 60, roundi(float(r["hull"]) * 100.0), roundi(float(r["foe_hull"]) * 100.0)]
