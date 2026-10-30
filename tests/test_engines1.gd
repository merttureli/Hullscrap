extends "res://tests/base_test.gd"
## Engine wave 1 (docs/waves/engines_1.md): the 19 engines (4 re-tuned in core, 15 in data/packs/engines_1) against
## the spec's table, placed as hull mounts and thrusting by their numbers times the line, the Kickjet and Ion Surge
## abilities, the recipes and key materials, the Drift's fuel (a jump costs the thrust-weighted mean fuel_mult of the
## powered engines, the fraction is kept and saved) and the stock of the three stations.

const Fixture = preload("res://tests/fixture_ship.gd")
const Wall = preload("res://tests/fixture_wall.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Balance = preload("res://scripts/data/balance.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Components = preload("res://scripts/ship/components.gd")
const Content = preload("res://scripts/data/content.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Stats = preload("res://scripts/sim/stats.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const OUTPUT := {"scrap": 0.9, "standard": 1.0, "neon": 1.3}  ## data/lines.json `output`, the line's multiplier on thrust

## The spec's table: id -> [name, line, tier, thrust, power, hp, heat_per_s, outside (w, h), fuel_mult].
const TABLE := {
	"engine_mk1": ["Concord Thruster Mk1", "standard", 1, 10, -2, 6, 3, [4, 2], 1.0],
	"engine_mk2": ["Concord Thruster Mk2", "standard", 2, 18, -3, 8, 4, [4, 2], 1.0],
	"engine_mk3": ["Concord Thruster Mk3", "standard", 3, 26, -4, 10, 5, [4, 2], 1.1],
	"engine_mk4": ["Concord Thruster Mk4", "standard", 4, 36, -5, 12, 6, [4, 3], 1.2],
	"engine_mk5": ["Concord Thruster Mk5", "standard", 5, 48, -6, 14, 7, [4, 3], 1.3],
	"engine_scrap_mk1": ["Kickjet", "scrap", 1, 10, -2, 6, 3, [4, 2], 1.0],
	"engine_scrap_mk2": ["Kickjet Deluxe", "scrap", 2, 18, -3, 8, 4, [4, 2], 1.0],
	"engine_scrap_mk3": ["Double Kick", "scrap", 3, 26, -4, 10, 5, [4, 2], 1.1],
	"engine_scrap_mk4": ["Thunderknuckle", "scrap", 4, 36, -5, 12, 6, [4, 3], 1.2],
	"engine_neon_mk1": ["Ion Drive: Glimmer", "neon", 1, 10, -2, 6, 3, [4, 2], 1.0],
	"engine_neon_mk2": ["Ion Drive: Halo", "neon", 2, 18, -3, 8, 4, [4, 2], 1.0],
	"engine_neon_mk3": ["Ion Drive: Corona", "neon", 3, 26, -4, 10, 5, [4, 2], 1.1],
	"engine_neon_mk4": ["Ion Drive: Zenith", "neon", 4, 36, -5, 12, 6, [4, 3], 1.2],
	"strafe_jets_mk1": ["Strafe Jets Mk1", "standard", 1, 6, -1, 4, 2, [2, 2], 1.0],
	"strafe_jets_mk2": ["Strafe Jets Mk2", "standard", 2, 10, -2, 5, 2, [2, 2], 1.0],
	"strafe_jets_mk3": ["Strafe Jets Mk3", "standard", 3, 14, -2, 6, 3, [2, 2], 1.0],
	"longburn_mk1": ["Long-Burn Drive Mk1", "standard", 1, 6, -2, 6, 2, [4, 2], 0.5],
	"longburn_mk2": ["Long-Burn Drive Mk2", "standard", 2, 11, -3, 8, 3, [4, 2], 0.5],
	"longburn_mk3": ["Long-Burn Drive Mk3", "standard", 3, 16, -4, 10, 4, [4, 2], 0.45],
}
const OLD_IDS: Array[String] = ["engine_mk1", "engine_mk2", "engine_scrap_mk1", "engine_neon_mk1"]
const STRAFE_QUIRK := "small side jets, mount on side walls for A/D strafe"
const LONGBURN_QUIRK := "an explorer's engine: half the fuel, 60% thrust"


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _comps() -> Components:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	return c


func _new_ids() -> Array:
	return TABLE.keys().filter(func(id): return not OLD_IDS.has(id))


# --- the data ----------------------------------------------------------------------------------------

func test_the_table_has_19_engines_4_in_core_and_15_in_the_pack() -> void:
	eq(TABLE.size(), 19, "the spec has 19 engines")
	eq(_new_ids().size(), 15, "15 of them are new")
	for id in OLD_IDS:
		eq(Content.origin("components", id), "core", id + " is re-tuned in core")
	for id in _new_ids():
		eq(Content.origin("components", id), "engines_1", id + " is in the pack")
	check(Content.errors().is_empty(), "the content loads without problems: " + str(Content.errors()))
	var pack := {}
	for p in Content.packs():
		pack[p["id"]] = p
	check(pack.has("engines_1") and pack["engines_1"]["requires"] == [], "the pack engines_1 has no requirements")


func test_every_engine_has_the_numbers_of_the_table() -> void:
	var c := _comps()
	for id in TABLE:
		var row: Array = TABLE[id]
		var d := c.def(id)
		check(not d.is_empty(), id + " exists")
		eq(d["name"], row[0], id + " name")
		eq([d["family"], d["line"], d["tier"]], ["engine", row[1], row[2]], id + " family, line, tier")
		eq(float(d["stats"]["thrust"]), float(row[3]), id + " thrust (a Standard-band value: the line multiplies it in game)")
		eq(d["power"], row[4], id + " power")
		eq(d["hp"], row[5], id + " hp")
		eq(float(d["heat_per_s"]), float(row[6]), id + " heat_per_s")
		eq([float(d["heat_limit"]), float(d["cooling"]), int(d["priority"]), d["manned"]], [100.0, 3.0, 4, false], id + " heat limit, cooling, priority, not manned")
		eq(d["size"], row[7].duplicate() if id.begins_with("strafe") else [4, 2], id + " inside half")
		eq(d["mount"]["outside"], row[7], id + " outside half")
		eq(d["mount"]["outside_hp"], int(floor(row[5] * 0.75 + 0.5)), id + " outside_hp is 75 percent of hp, rounded")
		near(float(d["stats"]["fuel_mult"]), row[8], id + " fuel_mult")
		check(str(d.get("blurb", "")).length() > 20, id + " has a blurb")
		check(Mounts.is_mount(d), id + " is a hull mount")
		check(Content.has_art(id) and Content.has_art(id + "_out"), id + " has its art (core and _out)")


func test_the_old_blurbs_are_kept_and_the_new_ones_are_all_different() -> void:
	var c := _comps()
	eq(c.def("engine_mk1")["blurb"], "Reliable thrust, uncomplicated. Do not mistake that for exciting.", "Mk1's blurb")
	eq(c.def("engine_mk2")["blurb"], "Improved thrust, improved paperwork. Mostly the paperwork.", "Mk2's blurb")
	eq(c.def("engine_scrap_mk1")["blurb"], "Welded together from three other engines. Kicks like a mule.", "the Kickjet's blurb")
	eq(c.def("engine_neon_mk1")["blurb"], "Light and fast, glows when it works.", "the Glimmer's blurb")
	var seen := {}
	for id in TABLE:
		var b: String = c.def(id)["blurb"]
		check(not seen.has(b), id + " has a blurb of its own")
		seen[b] = true


func test_the_unique_afterburner_is_as_it_was() -> void:
	var d := _comps().def("afterburner")
	eq([float(d["stats"]["thrust"]), d["tier"], d.get("unique"), d["mount"]["outside_hp"]], [16.0, 2, true, 5], "the Afterburner")


func test_quirks_and_abilities() -> void:
	var c := _comps()
	for id in ["strafe_jets_mk1", "strafe_jets_mk2", "strafe_jets_mk3"]:
		eq(c.def(id)["quirk"], STRAFE_QUIRK, id + " quirk")
	for id in ["longburn_mk1", "longburn_mk2", "longburn_mk3"]:
		eq(c.def(id)["quirk"], LONGBURN_QUIRK, id + " quirk")
	var sputter := {"engine_scrap_mk1": 1.25, "engine_scrap_mk2": 1.30, "engine_scrap_mk3": 1.35, "engine_scrap_mk4": 1.40}
	for id in sputter:
		var a: Dictionary = c.def(id)["abilities"][0]
		eq([a["id"], a["type"], a["key"], a["duration"], a["cooldown"]], ["sputter_boost", "active", "engine", 4.0, 15.0], id + " Sputter Boost")
		near(float(a["effects"]["stat_mult"]["thrust"]), sputter[id], id + " Sputter Boost multiplier")
		eq(a["side_effects"], [{"type": "self_damage", "rate": 0.3}, {"type": "fire_risk", "rate": 0.05}], id + " side effects (as the Kickjet's)")
	var surge := {"engine_neon_mk3": 1.3, "engine_neon_mk4": 1.35}
	for id in surge:
		var a: Dictionary = c.def(id)["abilities"][0]
		eq([a["id"], a["name"], a["type"], a["key"], a["duration"], a["cooldown"]], ["ion_surge", "Ion Surge", "active", "engine", 5.0, 20.0], id + " Ion Surge")
		near(float(a["effects"]["stat_mult"]["thrust"]), surge[id], id + " Ion Surge multiplier")
		eq(a["side_effects"], [{"type": "heat", "rate": 15.0}], id + " side effect: heat 15 a second")
		check(not a.has("operator_needs"), id + " needs no operator")
	for id in ["engine_mk3", "engine_mk4", "engine_mk5", "engine_neon_mk2", "engine_neon_mk1"]:
		check(not c.def(id).has("abilities") and not c.def(id).has("quirk"), id + " has no ability and no quirk")


func test_the_balance_bands_hold_for_all_19_and_the_waivers_are_gone() -> void:
	var table := Balance.load_table()
	eq(table["waivers"], {}, "no waivers are left")
	var c := _comps()
	var lines := Stats.load_lines()
	for id in TABLE:
		var r := Balance.check(table, c.def(id), lines)
		check(r["status"] in ["ok", "quirk"], "%s is %s: %s" % [id, r["status"], r["problems"]])
		if not Balance.has_quirk(c.def(id)):
			eq(r["status"], "ok", id + " has no quirk, so it is within 20% of its band")
	for id in ["engine_mk1", "engine_mk2", "engine_mk3", "engine_mk4", "engine_mk5", "engine_neon_mk1", "engine_neon_mk2"]:
		eq(Balance.check(table, c.def(id), lines)["status"], "ok", id + " is on its band without an excuse")


func test_recipes_follow_the_spec() -> void:
	var recipes := {}
	for r in Content.list("recipes"):
		recipes[r["id"]] = r
	var want := {
		"engine_mk3": [2, {"scrap": 40, "copper": 24, "titanium": 12, "silicon": 4}],
		"engine_mk4": [2, {"scrap": 55, "copper": 32, "titanium": 20, "silicon": 8, "military_circuit": 1}],
		"engine_mk5": [3, {"scrap": 75, "copper": 40, "titanium": 30, "silicon": 12, "crystal": 2, "military_circuit": 2, "gate_alloy": 1}],
		"engine_scrap_mk2": [1, {"scrap": 26, "copper": 6}],
		"engine_scrap_mk3": [2, {"scrap": 36, "copper": 12, "titanium": 4}],
		"engine_scrap_mk4": [2, {"scrap": 50, "copper": 18, "titanium": 10, "military_circuit": 1}],
		"engine_neon_mk2": [2, {"scrap": 30, "copper": 16, "titanium": 6, "crystal": 4, "silicon": 8}],
		"engine_neon_mk3": [3, {"scrap": 40, "copper": 24, "titanium": 12, "crystal": 6, "silicon": 16}],
		"engine_neon_mk4": [3, {"scrap": 55, "copper": 32, "titanium": 20, "crystal": 8, "silicon": 24, "military_circuit": 1, "void_crystal": 1}],
		"strafe_jets_mk1": [1, {"scrap": 10, "copper": 5}],
		"strafe_jets_mk2": [1, {"scrap": 15, "copper": 8, "titanium": 3}],
		"strafe_jets_mk3": [2, {"scrap": 20, "copper": 12, "titanium": 6, "silicon": 2}],
		"longburn_mk1": [1, {"scrap": 20, "copper": 15}],
		"longburn_mk2": [1, {"scrap": 30, "copper": 24, "titanium": 6}],
		"longburn_mk3": [2, {"scrap": 40, "copper": 36, "titanium": 12, "silicon": 4}],
	}
	eq(want.size(), 15, "a recipe for each new engine")
	for id in want:
		check(recipes.has(id), id + " has a recipe")
		if recipes.has(id):
			var r: Dictionary = recipes[id]
			eq([r["output"]["item"], int(r["output"]["count"]), int(r["fab_level"]), r["category"]], [id, 1, want[id][0], "system"], id + " output and fabricator level")
			var got := {}
			for m in r["materials"]:
				got[m] = int(r["materials"][m])
			eq(got, want[id][1], id + " materials")
	# Mk4 and the Neon Mk4 need a key material, Mk5 two kinds; none of the new ones is known at the start
	var start: Array = Content.read("res://data/recipes.json")["start_known"]
	for id in want:
		check(not start.has(id), id + " is a blueprint to find or buy, not known at the start")
	for id in ["engine_mk1", "engine_scrap_mk1"]:
		check(start.has(id), id + " is still known at the start")


func test_the_key_materials_exist() -> void:
	var mats := {}
	for m in Content.list("materials"):
		mats[m["id"]] = m
	for id in ["military_circuit", "gate_alloy", "void_crystal"]:
		check(mats.has(id), id + " exists")
		if mats.has(id):
			eq([mats[id]["kind"], mats[id]["rarity"]], ["material", "very_rare"], id + " is a very rare material")
			check(str(mats[id].get("blurb", "")) != "" and str(mats[id].get("color", "")) != "", id + " has a blurb and a colour")
	var ship := Ship.new("t")
	for id in ["military_circuit", "gate_alloy", "void_crystal"]:
		check(ship.crafting.materials.has(id), "the fabricator knows " + id)
		eq(ship.crafting.name_of(id, ship.components), mats[id]["name"], id + " is named in the cargo")


# --- placed, powered, thrusting --------------------------------------------------------------------------

## A wall `thick` deep facing `rot` with engine `id` mounted through it (its outside half centred on u = 0), a
## reactor behind it and a cable between. Returns {ship, uid, id, rot}.
func _rig(id: String, rot: int, thick := 1) -> Dictionary:
	var ship := Wall.wall_ship(thick, rot)
	var def := ship.components.def(id)
	var width: int = def["size"][0]
	var depth: int = def["mount"]["outside"][1]
	var u0 := -width / 2
	var uid := ship.components.place_mount(ship.grid, id, Wall.corner(rot, u0, u0 + width - 1, -depth, -1), rot)
	ship.components.place(ship.grid, "reactor_mk2", Wall.corner(rot, 3, 6, thick, thick + 3), 0)
	for u in range(u0 + width - 1, 4):
		ship.cables.place(ship.grid, Wall.at(rot, u, thick))
	ship.refresh()
	return {"ship": ship, "uid": uid, "id": id, "rot": rot}


func test_every_engine_places_as_a_hull_mount_through_walls_of_different_thickness() -> void:
	for id in TABLE:
		var row: Array = TABLE[id]
		for rot in 4:
			for thick in [1, 3]:
				var tag := "%s, rot %d, %d thick" % [id, rot, thick]
				var d := _rig(id, rot, thick)
				var ship: Ship = d["ship"]
				check(d["uid"] >= 0, tag + ": placed")
				if d["uid"] < 0:
					continue
				var inst: Dictionary = ship.components.instances[d["uid"]]
				var w: int = 2 if id.begins_with("strafe") else 4
				eq(inst["cells"].size(), w * 2, tag + ": the inside half is %dx2" % w)
				eq(inst["out_cells"].size(), row[7][0] * row[7][1], tag + ": the outside half is %dx%d" % [row[7][0], row[7][1]])
				eq(inst["link"].size(), w * thick, tag + ": the link is the wall, as wide as the engine")
				eq(inst["out_hp"], ship.components.outside_hp_max(id), tag + ": the outside half is whole")
				check(ship.components.has_outside(d["uid"]) and ship.components.link_intact(ship.grid, d["uid"]), tag + ": linked")
				check(ship.power_state["powered"][d["uid"]], tag + ": powered")


func test_a_strafe_jets_pair_is_2x2_and_2x2_where_a_big_engine_is_4x4_and_4x3() -> void:
	var c := _comps()
	for id in ["strafe_jets_mk1", "strafe_jets_mk2", "strafe_jets_mk3"]:
		eq([c.def(id)["size"], c.def(id)["mount"]["outside"]], [[2, 2], [2, 2]], id + " is 2x2 + 2x2")
	for id in ["engine_mk4", "engine_mk5", "engine_scrap_mk4", "engine_neon_mk4"]:
		eq([c.def(id)["size"], c.def(id)["mount"]["outside"]], [[4, 2], [4, 3]], id + " is 4x2 + 4x3")
	var ship := Wall.wall_ship(2, 1)
	var uid: int = ship.components.place_mount(ship.grid, "engine_mk5", Wall.corner(1, -2, 1, -3, -1), 1)
	check(uid >= 0, "a Mk5 goes on a side wall as well")
	eq(ship.components.instances[uid]["out_cells"].size(), 12, "with its three-deep housing")


func test_every_engine_thrusts_by_its_numbers_times_its_line() -> void:
	for id in TABLE:
		var row: Array = TABLE[id]
		var want: float = float(row[3]) * float(OUTPUT[row[1]])
		var strafe: bool = id.begins_with("strafe")
		# a strafe pair sits on a side wall (nozzle to the right pushes the ship left, to the left pushes it right); the rest at the rear
		var rots := [1, 3] if strafe else [2]
		for rot in rots:
			var d := _rig(id, rot)
			var a := Arena.new(1)
			a.add_ship(d["ship"])
			var t: Dictionary = a.ships[0].thrusts
			var tag := "%s on rotation %d" % [id, rot]
			near(a.ships[0].thrust, want, tag + ": total thrust", 1e-5)
			if strafe:
				near(t["fwd"], 0.0, tag + ": nothing forward", 1e-6)
				near(t["left"] if rot == 1 else t["right"], want, tag + ": all of it sideways", 1e-5)
				near(t["right"] if rot == 1 else t["left"], 0.0, tag + ": and not the other way", 1e-6)
			else:
				near(t["fwd"], want, tag + ": all of it forward", 1e-5)
				near(t["left"] + t["right"], 0.0, tag + ": and nothing sideways", 1e-6)


func test_a_disabled_outside_half_stops_the_thrust() -> void:
	var d := _rig("engine_mk4", 2)
	var ship: Ship = d["ship"]
	ship.components.instances[d["uid"]]["out_hp"] = 0
	ship.mark_dirty()
	ship.refresh()
	var a := Arena.new(1)
	a.add_ship(ship)
	near(a.ships[0].thrust, 0.0, "a Mk4 with its outside half shot off pushes nothing")


# --- abilities -------------------------------------------------------------------------------------------

## A reactor and `part_id` turned round (so its nozzle faces down and it pushes forward) in the test room.
func _bare(part_id: String) -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["reactor"] = Fixture.put(ship, "reactor_mk2", 10, 10)
	d["part"] = Fixture.put(ship, part_id, 15, 10, 2)
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	return d


func test_the_kickjets_sputter_boost_triggers_and_its_multiplier_grows_with_the_tier() -> void:
	var mult := {"engine_scrap_mk1": 1.25, "engine_scrap_mk2": 1.30, "engine_scrap_mk3": 1.35, "engine_scrap_mk4": 1.40}
	for id in mult:
		var d := _bare(id)
		var ship: Ship = d["ship"]
		var base: float = float(TABLE[id][3]) * 0.9
		var a := Arena.new(1)
		a.add_ship(ship)
		near(a.ships[0].thrust, base, id + ": thrust before")
		eq(a.use_ability(0, d["part"]), "", id + ": Sputter Boost starts (no operator needed)")
		near(a.ships[0].thrust, base * mult[id], id + ": thrust x%s while it runs" % mult[id])
		near(Abilities.active_left(ship, d["part"], "sputter_boost"), 4.0, id + ": for 4 s")
		a.step(4.1)
		near(a.ships[0].thrust, base, id + ": back to normal after 4 s")
		check(Abilities.can_trigger(ship, d["part"]).begins_with("on cooldown"), id + ": then it rests")


func test_ion_surge_triggers_boosts_thrust_for_5_s_heats_15_a_second_and_rests_20_s() -> void:
	var mult := {"engine_neon_mk3": 1.3, "engine_neon_mk4": 1.35}
	for id in mult:
		var d := _bare(id)
		var ship: Ship = d["ship"]
		var base: float = float(TABLE[id][3]) * 1.3
		var a := Arena.new(1)
		a.add_ship(ship)
		near(a.ships[0].thrust, base, id + ": a Neon engine's thrust before (x1.3 of the line)")
		eq(Abilities.can_trigger(ship, d["part"]), "", id + ": ready")
		eq(a.use_ability(0, d["part"]), "", id + ": Ion Surge starts")
		near(a.ships[0].thrust, base * mult[id], id + ": thrust x%s" % mult[id])
		near(Abilities.active_left(ship, d["part"], "ion_surge"), 5.0, id + ": for 5 s")
		check(a.use_key(0, "engine")["refused"].size() == 1, id + ": the engine key finds it, already running")
		Abilities.tick(ship, 2.0)  # the abilities alone, no ambient heat
		near(ship.components.instances[d["part"]]["heat"], 30.0, id + ": 15 heat a second into the engine", 0.01)
		near(ship.components.instances[d["reactor"]]["heat"], 0.0, id + ": and none elsewhere")
		a.step(3.2)
		near(a.ships[0].thrust, base, id + ": back to normal after 5 s")
		check(Abilities.cooldown_left(ship, d["part"], "ion_surge") > 15.0, id + ": 20 s of rest")
	var fresh := Arena.new(1)
	var d := _bare("engine_neon_mk2")
	fresh.add_ship(d["ship"])
	eq(fresh.use_ability(0, d["part"]), "no such ability", "the Halo has no Ion Surge")


# --- the Drift: fuel ---------------------------------------------------------------------------------------

## A test room ship with a Mk2 reactor and `ids` as bare engines (4 wide each, one per row pair), all wired.
func _fuel_ship(ids: Array) -> Ship:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "reactor_mk2", 10, 10)
	var y := 9
	for id in ids:
		check(Fixture.put(ship, id, 15, y, 2) >= 0, "(setup: %s placed)" % id)
		Fixture.wire(ship, [Vector2i(14, y + 1), Vector2i(15, y + 1)])
		y += 2
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(14, 10), Vector2i(14, 12), Vector2i(14, 13), Vector2i(14, 14)])
	ship.inventory.counts.erase("fuel")
	ship.inventory.add("fuel", 6)
	ship.refresh()
	return ship


## The first neighbour of the current node that is not a gate.
func _next(c: Campaign) -> String:
	for o in c.neighbours(c.current):
		if c.node(o)["type"] != "gate":
			return o
	return ""


## Jump `n` times and return the fuel in the cargo after each jump.
func _hops(c: Campaign, ship: Ship, n: int) -> Array:
	var out := []
	for i in n:
		var r := c.jump(_next(c), ship)
		check(r["ok"], "hop %d: %s" % [i, r["why"]])
		out.append(ship.inventory.count("fuel"))
	return out


func test_an_engine_without_fuel_mult_and_a_ship_without_engines_pay_a_whole_fuel() -> void:
	var c := Campaign.new(2)
	var ship := _fuel_ship(["engine_mk1"])
	eq(c.jump_cost(ship), 100, "a Concord Mk1 (fuel_mult 1.0) costs 1 fuel")
	ship.components.by_id["engine_mk1"]["stats"].erase("fuel_mult")
	eq(c.jump_cost(ship), 100, "an engine with no fuel_mult counts as 1.0")
	ship.components.by_id["engine_mk1"]["stats"]["fuel_mult"] = 1.0
	var none := _fuel_ship([])
	eq(c.jump_cost(none), 100, "a ship with no powered engine pays a whole fuel")
	eq(_hops(c, ship, 3), [5, 4, 3], "1 fuel a jump, as before")
	eq(c.fuel_part, 0, "and no remainder")


func test_a_long_burn_ship_spends_one_fuel_every_two_jumps() -> void:
	var c := Campaign.new(2)
	var ship := _fuel_ship(["longburn_mk1"])
	eq(c.jump_cost(ship), 50, "a Long-Burn costs half a fuel")
	eq(Campaign.fuel_text(c.jump_cost(ship)), "0.5 fuel", "the map says 0.5 fuel")
	eq(_hops(c, ship, 6), [6, 5, 5, 4, 4, 3], "the first jump is free, the second pays, and so on")
	eq(c.jumps, 6, "every jump counts on the debt clock")
	eq(c.fuel_part, 0, "an even number of jumps leaves no remainder")
	_hops(c, ship, 1)
	eq(c.fuel_part, 50, "an odd one leaves half a fuel")


func test_with_an_empty_tank_a_long_burn_still_makes_the_free_half_and_then_stops() -> void:
	var c := Campaign.new(2)
	var ship := _fuel_ship(["longburn_mk2"])
	ship.inventory.counts.erase("fuel")
	check(c.jump_block(_next(c), ship) == "", "no fuel, but the next jump is already paid for")
	check(c.jump_block(_next(c), ship, true) != "", "so a drift jump is not on offer")
	check(c.jump(_next(c), ship)["ok"], "it jumps")
	eq(ship.inventory.count("fuel"), 0, "and the cargo is still empty")
	eq(c.jump_block(_next(c), ship), "no fuel", "the second half needs a whole fuel")
	check(not c.fuel_short(_fuel_ship(["longburn_mk2"])), "(a full tank is not short)")
	check(c.fuel_short(ship), "short now")
	check(c.jump_block(_next(c), ship, true) == "", "and now the drift jump is allowed")


func test_a_mixed_ship_pays_the_thrust_weighted_mean() -> void:
	var c := Campaign.new(2)
	# a Concord Mk1 (thrust 10, fuel 1.0) and a Long-Burn Mk1 (thrust 6, fuel 0.5): (10 + 3) / 16 = 0.8125
	var ship := _fuel_ship(["engine_mk1", "longburn_mk1"])
	ship.inventory.add("fuel", 14)  # 20
	eq(c.jump_cost(ship), 81, "0.8125 fuel, to the hundredth")
	eq(Campaign.fuel_text(81), "0.81 fuel", "shown as 0.81 fuel")
	_hops(c, ship, 10)
	eq([20 - ship.inventory.count("fuel"), c.fuel_part], [8, 10], "ten jumps cost 8.1 fuel: 8 spent, a tenth kept")
	# the line counts: a Neon Mk3 pushes 26 x 1.3 = 33.8, with fuel 1.1, beside the Long-Burn's 6 at 0.5
	var neon := _fuel_ship(["engine_neon_mk3", "longburn_mk1"])
	eq(c.jump_cost(neon), roundi((33.8 * 1.1 + 6.0 * 0.5) / 39.8 * 100.0), "the Neon engine weighs its thrust times the line")
	eq(c.jump_cost(neon), 101, "which is 1.01 fuel")
	# a heavier engine than 1.0 costs more than a fuel and the whole part is paid when it adds up
	var big := _fuel_ship(["engine_mk5"])
	eq(c.jump_cost(big), 130, "a Mk5 alone costs 1.3 fuel")
	var c2 := Campaign.new(3)
	eq(_hops(c2, big, 4), [5, 4, 3, 1], "1.3, 2.6, 3.9, then 5.2: 1 fuel, 1, 1, 2")


func test_engines_that_are_offline_do_not_count() -> void:
	var c := Campaign.new(2)
	var ship := Wall.wall_ship(1, 2)
	var big: int = ship.components.place_mount(ship.grid, "engine_mk4", Wall.corner(2, -6, -3, -3, -1), 2)
	var slow: int = ship.components.place_mount(ship.grid, "longburn_mk1", Wall.corner(2, -2, 1, -2, -1), 2)
	ship.components.place(ship.grid, "reactor_mk2", Wall.corner(2, 3, 6, 1, 4), 0)
	for u in range(-6, 4):
		ship.cables.place(ship.grid, Wall.at(2, u, 1))
	ship.refresh()
	check(big >= 0 and slow >= 0, "(setup: both mounted)")
	# Mk4 thrust 36 at fuel 1.2, Long-Burn 6 at 0.5: (43.2 + 3) / 42 = 1.1
	eq(c.jump_cost(ship), 110, "both working: 1.1 fuel")
	ship.components.instances[big]["out_hp"] = 0  # the Mk4's outside half is shot off
	eq(c.jump_cost(ship), 50, "the Mk4 pushes nothing, so only the Long-Burn is counted: 0.5 fuel")
	ship.components.instances[big]["out_hp"] = ship.components.outside_hp_max("engine_mk4")
	ship.components.instances[slow]["status"] = "disabled"
	eq(c.jump_cost(ship), 120, "a disabled Long-Burn is left out as well: 1.2 fuel")


func test_the_fraction_survives_save_and_load_and_an_old_save_loads_with_none() -> void:
	var c := Campaign.new(5)
	var ship := _fuel_ship(["longburn_mk1"])
	_hops(c, ship, 1)
	eq([c.fuel_part, ship.inventory.count("fuel")], [50, 6], "half a fuel is owed")
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))  # through real JSON
	eq(d["version"], 2, "saved as version 2")
	eq(d["fuel_part"], 50, "with the fraction in it")
	var back := Campaign.new(1)
	eq(back.load_dict(d), "", "loaded")
	eq(back.fuel_part, 50, "the fraction is back")
	_hops(back, ship, 1)
	eq([ship.inventory.count("fuel"), back.fuel_part], [5, 0], "and the next jump pays the whole fuel it was building towards")
	# a version 1 save has no fuel_part
	var old := d.duplicate(true)
	old["version"] = 1
	old.erase("fuel_part")
	var legacy := Campaign.new(1)
	legacy.fuel_part = 70
	eq(legacy.load_dict(old), "", "a version 1 save still loads")
	eq([legacy.fuel_part, legacy.jumps, legacy.current], [0, c.jumps, c.current], "with no fraction owed")
	var future := d.duplicate(true)
	future["version"] = 3
	check(Campaign.new(1).load_dict(future) != "", "a newer version is refused")
	var zero := d.duplicate(true)
	zero["version"] = 0
	check(Campaign.new(1).load_dict(zero) != "", "and so is none at all")


func test_the_map_shows_the_cost_of_the_next_jump() -> void:
	var MapView = load("res://scripts/ui/map_view.gd")
	var map = MapView.new()
	map.campaign = Campaign.new(2)
	var sim := ShipSimStub.new(_fuel_ship(["longburn_mk1"]))
	map.sim = sim
	eq(map.jump_cost_text(), "0.5 fuel", "a Long-Burn ship: 0.5 fuel")
	sim.ship = _fuel_ship(["engine_mk1"])
	eq(map.jump_cost_text(), "1 fuel", "a Concord Mk1: 1 fuel")
	sim.ship = _fuel_ship(["engine_mk4"])
	eq(map.jump_cost_text(), "1.2 fuel", "a Mk4: 1.2 fuel")
	map.sim = null
	eq(map.jump_cost_text(), "1 fuel", "with no ship, 1 fuel")
	eq(Campaign.fuel_text(5), "0.05 fuel", "a twentieth")
	eq(Campaign.fuel_text(125), "1.25 fuel", "a fuel and a quarter")
	map.free()
	sim.free()


## Stands in for the ShipSim node of the map: it only has a player ship.
class ShipSimStub extends Node:
	var ship

	func _init(p_ship) -> void:
		ship = p_ship

	func player_ship():
		return ship


# --- the stations --------------------------------------------------------------------------------------------

func test_the_stations_stock_the_new_engines_at_the_price_rule() -> void:
	var c := Campaign.new(1)
	var meridian := {"engine_mk2": 270, "engine_mk3": 480, "strafe_jets_mk1": 60, "strafe_jets_mk2": 140, "longburn_mk1": 120}
	var rusthold := {"engine_scrap_mk2": 200, "engine_scrap_mk3": 360}
	var prism := {"engine_neon_mk2": 680, "longburn_mk2": 270}
	for pair in [["meridian", meridian], ["rusthold", rusthold], ["prism", prism]]:
		for id in pair[1]:
			eq(c.stock_price(pair[0], id), pair[1][id], "%s sells %s for %d" % [pair[0], id, pair[1][id]])
	# nothing of tier 4 or 5 is ever sold, and no Strafe Jets Mk3 or Long-Burn Mk3 either
	for st in c.cfg["stations"]:
		for id in c.cfg["stations"][st]["stock"]:
			if TABLE.has(id):
				check(int(TABLE[id][2]) <= 3 and id not in ["strafe_jets_mk3", "longburn_mk3"], "%s sells %s, which is crafted only" % [st, id])
	var each: Array = []
	for st in ["rusthold", "meridian", "prism"]:
		each.append_array(c.cfg["stations"][st]["stock"].keys().filter(func(id): return TABLE.has(id)))
	var want := ["engine_mk1", "engine_mk2", "engine_mk3", "strafe_jets_mk1", "strafe_jets_mk2", "longburn_mk1", "engine_scrap_mk1", "engine_scrap_mk2",
		"engine_scrap_mk3", "engine_neon_mk1", "engine_neon_mk2", "longburn_mk2"]
	each.sort()
	want.sort()
	eq(each, want, "the engines the three stations list")
	# the price rule: the line's Mk1 price times the part value of the tier over the tier-1 one, to 10; Strafe Jets half
	var values: Dictionary = c.cfg["values"]["tier"]
	var mk1 := {"scrap": 90.0, "standard": 120.0, "neon": 300.0}
	for st in ["rusthold", "meridian", "prism"]:
		for id in c.cfg["stations"][st]["stock"]:
			if not TABLE.has(id) or OLD_IDS.has(id):
				continue
			var row: Array = TABLE[id]
			var raw: float = mk1[row[1]] * float(values[str(row[2])]) / float(values["1"]) * (0.5 if id.begins_with("strafe") else 1.0)
			eq(c.stock_price(st, id), roundi(raw / 10.0) * 10, "%s at %s follows the price rule (%s)" % [id, st, raw])


func test_a_station_sells_a_listed_engine_into_the_cargo() -> void:
	var c := Campaign.new(1)
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(ship)
	var credits := ship.inventory.count("credits")
	ship.inventory.add("credits", 1000)
	var r := c.buy(ship, "meridian", "strafe_jets_mk2")
	check(r["ok"], "bought: " + str(r["text"]))
	eq([ship.inventory.count("strafe_jets_mk2"), ship.inventory.count("credits")], [1, credits + 1000 - 140], "in the cargo, paid")
	check(not c.buy(ship, "meridian", "engine_mk4")["ok"], "a Mk4 is not sold")
	check(not c.buy(ship, "rusthold", "strafe_jets_mk1")["ok"], "and Rusthold does not sell Concord parts")
	check(not c.buy(ship, "prism", "engine_scrap_mk2")["ok"], "nor the Prism Scrapper ones")
