extends RefCounted
## The threat rating of an enemy ship against the player's (docs/CONTENT.md section 14: "Radar Mk2+ shows an enemy's threat
## rating, 1-5 skulls, against your own ship's strength"). Pure logic over two Ship objects, no nodes.
## A ship's combat power is sqrt(damage per second x effective hp) x a speed factor:
##   - damage per second: every powered weapon's damage x shots over its cooldown, times what lands (a fixed gun by the pilot's
##     aim, a turret by its accuracy), with flak and ion discounted and missiles a little up (data/enemy_tables.json "threat");
##   - effective hp: the block hp it takes to wreck the ship (the share of its blocks' hp above the defeat line, structure.gd)
##     plus the shield layers that are powered;
##   - speed: acceleration over a reference, to a small power, kept between 0.7 and 1.4.
## A kinetic gun's hit counts over `kinetic_floor` (data/enemy_tables.json) when it is smaller: the plating eats a light round (the
## Rattle Burst's 1.2 damage a shot landed 0.09 hp/s on the Beta 4 weapon bench against the 0.7 its listed dps promised), and without
## this the pirates' Rattle Bursts made a jump-5 raider read 3 skulls against the Courier once the gun was given damage 2.
## The ratio enemy power / player power is cut into 1-5 skulls at the table's `cuts`.

const Structure = preload("res://scripts/ship/structure.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Stats = preload("res://scripts/sim/stats.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")

const TABLES_PATH := "res://data/enemy_tables.json"

static var _cfg := {}
static var _weapons: Weapons = null


static func config() -> Dictionary:
	if _cfg.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(TABLES_PATH))
		assert(data is Dictionary and data.get("threat") is Dictionary, "bad enemy tables: " + TABLES_PATH)
		_cfg = data["threat"]
		_weapons = Weapons.new()
	return _cfg


## {dps, ehp, accel, speed, power} of `ship` flown by a pilot of `skill` (0..1).
static func power(ship, skill: float) -> Dictionary:
	var cfg := config()
	ship.refresh()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var dps := 0.0
	for uid in ship.components.instances:
		var id := str(ship.components.instances[uid]["id"])
		if not _weapons.has(id) or not powered.get(uid, false) or ship.components.offline_reason(ship.grid, uid) != "":
			continue
		var w: Dictionary = _weapons.def(id)
		var dmg := float(w["damage"]) * float(w["shots"])
		if str(w["kind"]) == "beam":
			dmg *= float(w["duration"])
		dmg *= float(cfg["kind_factor"].get(str(w["kind"]), 1.0))
		if str(w["damage_type"]) == "kinetic":
			dmg *= minf(1.0, float(w["damage"]) / float(cfg["kinetic_floor"]))
		if str(w["damage_type"]) == "ion":
			dmg *= float(cfg["ion_factor"])
		var hit: float = clampf(float(w["accuracy"]) - float(cfg["turret_miss"]), 0.0, 1.0) if bool(w["turret"]) else float(cfg["fixed_hit"]) * (0.55 + 0.45 * skill)
		dps += dmg * hit / maxf(float(w["cooldown"]), 0.1)
	var ehp := (1.0 - Structure.defeat_below()) * Structure.totals(ship).y + Shields.layers_of_ship(ship, powered) * float(Shields.params_of_ship(ship, powered)["layer_hp"]) * float(cfg["shield_hp_value"])
	var f := Flight.new()
	var mass := f.mass_of(ship.grid, ship.components, ship.cables, Stats.mass_mults(ship.components, ship.lines))
	var thrust := float(f.thrusts_of(Stats.view(ship.components, ship.lines), powered)["fwd"])
	var accel := thrust * f.thrust_to_accel / mass
	var speed := clampf(pow(maxf(accel, 0.0) / float(cfg["speed_ref"]), float(cfg["speed_power"])), 0.7, 1.4)
	return {"dps": dps, "ehp": ehp, "accel": accel, "speed": speed, "power": sqrt(dps * ehp) * speed}


## Skulls (1-5) of `enemy` against `player`: {skulls, ratio, enemy (power()), player (power())}. The enemy's pilot skill is
## its design's `ai.aim_skill`, the player's is the table's `player_aim`.
static func rate(enemy, player) -> Dictionary:
	var cfg := config()
	var e := power(enemy, float(enemy.get_meta("ai", {}).get("aim_skill", 0.6)))
	var p := power(player, float(cfg["player_aim"]))
	var ratio: float = float(e["power"]) / maxf(float(p["power"]), 0.001)
	var skulls := 1
	for cut in cfg["cuts"]:
		if ratio >= float(cut):
			skulls += 1
	return {"skulls": skulls, "ratio": ratio, "enemy": e, "player": p}


## "Threat 3/5" for the radar and the HUD.
static func label(skulls: int) -> String:
	return "Threat %d/5" % clampi(skulls, 1, 5)
