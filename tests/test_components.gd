extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Components = preload("res://scripts/ship/components.gd")
const Cables = preload("res://scripts/ship/cables.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Content = preload("res://scripts/data/content.gd")
const Stats = preload("res://scripts/sim/stats.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const PartEffects = preload("res://scripts/sim/part_effects.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")

const COMPONENTS := "res://data/components.json"
const MATERIALS := "res://data/materials.json"
const ITEMS := "res://data/items.json"
const WEAPON_KINDS: Array[String] = ["laser", "bolt", "flak", "missile", "beam"]
const DAMAGE_TYPES: Array[String] = ["kinetic", "energy", "explosive", "ion"]
const REQUIRED_FIELDS: Array[String] = ["id", "name", "family", "line", "tier", "size", "color", "power", "priority", "manned", "hp", "heat_limit", "heat_per_s", "cooling", "stats"]
## The weapon parts of the first content pack (docs/CONTENT.md section 6): id -> [line, tier, size, kind, damage_type].
const WEAPON_PACK := {
	"pulse_mk1": ["standard", 1, [4, 2], "bolt", "energy"],
	"pulse_mk2": ["standard", 2, [4, 2], "bolt", "energy"],
	"rattle_burst_scrap": ["scrap", 1, [4, 2], "bolt", "kinetic"],
	"shrapnel_cannon_scrap": ["scrap", 1, [4, 2], "flak", "kinetic"],  # the inside half; its outside half is 4x3
	"bolt_thrower_scrap": ["scrap", 1, [4, 2], "missile", "explosive"],
	"artemis_mk1": ["standard", 1, [4, 2], "missile", "explosive"],
	"ion_blast_mk1": ["standard", 1, [4, 2], "laser", "ion"],
	"siren_ion_neon": ["neon", 1, [4, 2], "laser", "ion"],
	"heat_lance_neon": ["neon", 1, [4, 2], "beam", "energy"],
	"leech_laser": ["standard", 2, [4, 2], "laser", "energy"],
	"breach_harpoon": ["standard", 2, [4, 2], "bolt", "kinetic"],
}
const SHIELD_SECTORS: Array[int] = [1, 2, 4, 8]
const SHIELD_RECHARGE := {"shield_mk1": 7.0, "shield_scrap_mk1": 8.0, "shield_mk2": 5.5, "shield_neon_mk1": 4.0, "mirror_veil": 6.0, "sovereign_aegis": 4.5, "sporeling_mycelium_shield": 3.7}  ## stats.recharge (s a layer) of the parts that are not just their tier's number
const UNIQUES: Array[String] = ["leech_laser", "breach_harpoon", "mirror_veil", "afterburner"]


## A 21x21 circular hull (radius 10) with floor on every hull cell.
func _grid(floored := true) -> ShipGrid:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(21, 21), defs)
	g.fill_circle_hull(10.0)
	if floored:
		for c in g.hull:
			g.place("floor", c)
	return g


func _comps() -> Components:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	return c


## The cells of a w x h block with its top-left cell on `a`, row by row.
func _block(a: Vector2i, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in h:
		for x in w:
			out.append(a + Vector2i(x, y))
	return out


func test_data_is_complete() -> void:
	var c := _comps()
	var want := {
		"reactor_mk1": [8, 0, 1], "reactor_mk2": [14, 0, 2], "engine_mk1": [-2, 4, 1], "engine_mk2": [-3, 4, 2],
		"oxygen_gen": [-2, 1, 1], "shield_mk1": [-3, 3, 1], "laser_mk1": [-2, 5, 1], "laser_mk2": [-3, 5, 2], "laser_turret_mk1": [-3, 5, 1],
		"helm": [-1, 2, 1], "medbay": [-2, 3, 1], "bed": [0, 0, 1], "fabricator": [-2, 6, 1],
		"robot_arm": [-1, 6, 1], "laser_cutter": [-2, 6, 1], "assembly_rig": [-2, 6, 1], "nanoforge": [-4, 6, 1],
		"reactor_scrap_mk1": [6, 0, 1], "engine_scrap_mk1": [-2, 4, 1], "oxygen_scrap_mk1": [-2, 1, 1],
		"reactor_neon_mk1": [16, 0, 1], "engine_neon_mk1": [-2, 4, 1], "radiator": [-1, 2, 1],
		"pulse_mk1": [-2, 5, 1], "pulse_mk2": [-3, 5, 2], "rattle_burst_scrap": [-2, 5, 1], "shrapnel_cannon_scrap": [-2, 5, 1],
		"bolt_thrower_scrap": [-1, 5, 1], "artemis_mk1": [-2, 5, 1], "ion_blast_mk1": [-3, 5, 1], "siren_ion_neon": [-3, 5, 1],
		"heat_lance_neon": [-4, 5, 1], "leech_laser": [-3, 5, 2], "breach_harpoon": [-2, 5, 2],
		"shield_scrap_mk1": [-3, 3, 1], "shield_mk2": [-4, 3, 2], "shield_neon_mk1": [-4, 3, 1], "mirror_veil": [-3, 3, 2],
		"afterburner": [-3, 4, 2], "inertial_dampener": [-2, 3, 2], "battering_bow": [0, 0, 2], "reactor_scrap_kettle": [8, 0, 1],
		# racial tech, human / basalt / emberkin / fenn / kett (data/packs/tech_*): weapons
		"human_volley_rack": [-3, 5, 2], "human_concord_railgun": [-5, 5, 3], "human_flak_screen": [-4, 5, 2],
		"basalt_magma_spitter": [-3, 5, 2], "basalt_quarry_driver": [-4, 5, 3], "basalt_pumice_flak": [-4, 5, 2],
		"emberkin_pyre_lance": [-4, 5, 2], "emberkin_cinder_mortar": [-3, 5, 2], "emberkin_flare_turret": [-3, 5, 1],
		"fenn_twitch_cannon": [-3, 5, 2], "fenn_spark_lattice": [-4, 5, 2], "fenn_market_missile": [-3, 5, 2],
		"kett_hive_swarm_launcher": [-3, 5, 2], "kett_chitin_thrower": [-2, 5, 1], "kett_drone_picket": [-4, 5, 2],
		# racial tech, group a: components
		"emberkin_pyre_drive": [-3, 4, 2], "emberkin_furnace_core": [10, 0, 1], "emberkin_hearth_shield": [-4, 3, 2],
		"human_reactor_plus": [9, 0, 1], "human_comms_array": [-2, 3, 1], "human_crew_quarters_deluxe": [-1, 3, 1],
		"basalt_vacuum_forge": [11, 0, 1], "basalt_stonehide_bay": [-1, 3, 2], "basalt_gravity_anchor": [-2, 3, 2],
		"fenn_haggle_engine": [-3, 4, 2], "fenn_jury_reactor": [10, 0, 1], "fenn_quickfix_bay": [-2, 3, 1],
		"kett_hive_battery": [-5, 3, 2], "kett_nest_reactor": [7, 0, 1], "kett_brood_hold": [-1, 3, 1],
		# the Raft loop (docs/CONTENT.md section 11)
		"net_mouth_scrap": [0, 0, 1], "intake_mk1": [-1, 6, 1],
		"intake_mk2": [-1, 6, 2], "intake_mk3": [-2, 6, 3], "radar_mk1": [-1, 6, 1], "radar_mk2": [-2, 6, 2], "radar_mk3": [-3, 6, 3],
		"tractor_mk1": [-2, 6, 1], "tractor_mk2": [-3, 6, 2],
		# racial tech, group b (data/packs/tech_mire, _sporeling, _gauntling, _prismatic, _grundl): id -> [power, priority, tier]
		"mire_steam_lance": [-3, 5, 2], "mire_bog_mortar": [-3, 5, 2], "mire_mist_projector": [-3, 5, 1],
		"sporeling_spore_cannon": [-3, 5, 2], "sporeling_rot_pod": [-2, 5, 2], "sporeling_pollen_turret": [-2, 5, 1],
		"gauntling_arc_hammer": [-3, 5, 2], "gauntling_scrap_shotgun": [-2, 5, 1], "gauntling_tesla_picket": [-3, 5, 2],
		"prismatic_prism_lens": [-4, 5, 2], "prismatic_refractor": [-3, 5, 2], "prismatic_glimmer_turret": [-3, 5, 2],
		"grundl_slug_mortar": [-4, 5, 3], "grundl_grapple_harpoon": [-3, 5, 2], "grundl_barge_flak": [-3, 5, 2],
		"mire_rain_shield": [-4, 3, 2], "mire_wetwell_reactor": [10, 0, 1], "mire_spray_deck": [-1, 3, 1],
		"sporeling_bloom_reactor": [11, 0, 1], "sporeling_mycelium_shield": [-4, 3, 2], "sporeling_garden_bay": [-2, 1, 1],
		"gauntling_arc_core": [11, 0, 1], "gauntling_overclock_engine": [-3, 4, 2], "gauntling_graft_bay": [-2, 3, 1],
		"prismatic_lattice_shield": [-5, 3, 2], "prismatic_song_reactor": [8, 0, 1], "prismatic_resonance_helm": [-2, 2, 1],
		"grundl_hauler_thrusters": [-4, 4, 2], "grundl_freight_shield": [-5, 3, 2], "grundl_cargo_deck": [-1, 3, 1],
		# engine wave 1 (data/packs/engines_1)
		"engine_mk3": [-4, 4, 3], "engine_mk4": [-5, 4, 4], "engine_mk5": [-6, 4, 5], "engine_scrap_mk2": [-3, 4, 2], "engine_scrap_mk3": [-4, 4, 3],
		"engine_scrap_mk4": [-5, 4, 4], "engine_neon_mk2": [-3, 4, 2], "engine_neon_mk3": [-4, 4, 3], "engine_neon_mk4": [-5, 4, 4],
		"strafe_jets_mk1": [-1, 4, 1], "strafe_jets_mk2": [-2, 4, 2], "strafe_jets_mk3": [-2, 4, 3],
		"longburn_mk1": [-2, 4, 1], "longburn_mk2": [-3, 4, 2], "longburn_mk3": [-4, 4, 3],
		# ammo racks and conveyor belts (docs/CONTENT.md 4f)
		"ammo_rack": [0, 0, 1], "belt_drive_scrap": [-1, 2, 1], "belt_drive_std": [-1, 2, 2], "belt_drive_neon": [-1, 2, 3],
		# the smelters (docs/CONTENT.md section 12, data/packs/processing_1)
		"smelter_scrap_mk1": [-3, 7, 1], "smelter_mk1": [-3, 7, 1], "smelter_mk2": [-4, 7, 2], "smelter_mk3": [-5, 7, 3], "smelter_neon_mk1": [-4, 7, 1],
		# the rare factions (docs/CONTENT.md 18, data/packs/faction_barons, faction_leviathans)
		"gilded_lance": [-4, 5, 3], "baron_tithe_gun": [-4, 5, 3], "sovereign_turret": [-3, 5, 3], "sovereign_aegis": [-7, 3, 3], "starwhale_fin": [-4, 4, 4],
	}
	eq(c.ids().size(), want.size(), "component count")
	for id in want:
		check(c.has(id), id + " exists")
		var d := c.def(id)
		eq([d["power"], d["priority"], d["tier"]], want[id], id + " power, priority, tier")
		for k in ["name", "size", "color", "family", "manned", "stats", "line", "hp", "heat_limit", "heat_per_s", "cooling"]:
			check(d.has(k), "%s has %s" % [id, k])
	eq(c.def("reactor_mk1")["size"], [2, 4], "a tier 1-2 reactor is 2x4 (a crew body is 2x2; playtest 2, P2)")
	eq(c.def("engine_mk1")["size"], [2, 2], "a tier 1-2 engine is 2x2 inside (its barrel is 4x2 outside)")
	eq(c.def("engine_mk3")["size"], [4, 2], "a tier 3 engine is still 4x2")
	eq(c.def("afterburner")["size"], [4, 2], "and a unique one keeps its size")
	eq(c.def("oxygen_gen")["size"], [2, 4], "oxygen generator is 2x4")
	eq(c.def("robot_arm")["size"], [2, 2], "robot arm is 2x2")
	eq(c.def("helm")["size"], [2, 2], "even the helm is 2x2")
	eq(c.def("engine_mk2")["stats"]["thrust"], 18, "engine thrust")
	check(c.def("helm")["manned"], "the helm is manned")
	eq(c.def("nothing"), {}, "unknown id gives an empty def")


func test_footprint_rotation_swaps_size() -> void:
	var c := _comps()
	var a := Vector2i(3, 4)
	eq(c.footprint("engine_mk3", a, 0), _block(a, 4, 2), "4x2 at rot 0")
	eq(c.footprint("engine_mk3", a, 1), _block(a, 2, 4), "rot 1 makes it 2x4")
	eq(c.footprint("engine_mk3", a, 2), c.footprint("engine_mk3", a, 0), "rot 2 keeps the size")
	eq(c.footprint("engine_mk3", a, 3), c.footprint("engine_mk3", a, 1), "rot 3 swaps again")
	eq(c.footprint("engine_mk3", a, 4), c.footprint("engine_mk3", a, 0), "rot wraps at 4")
	eq(c.footprint("engine_mk3", a, -1), c.footprint("engine_mk3", a, 3), "negative rot wraps")
	eq(c.footprint("engine_mk1", a, 0), _block(a, 2, 2), "a tier 1 engine's inside half is 2x2")
	eq(c.footprint("reactor_mk1", a, 0), _block(a, 2, 4), "a tier 1 reactor is 2x4")
	eq(c.footprint("reactor_mk1", a, 1), _block(a, 4, 2), "and lies down at rot 1")
	eq(c.footprint("reactor_mk1", a, 1).size(), 8, "a 2x4 stays 8 cells")
	eq(c.footprint("oxygen_gen", a, 0), _block(a, 2, 4), "2x4 at rot 0")
	eq(c.footprint("oxygen_gen", a, 1), _block(a, 4, 2), "2x4 at rot 1 lies down")
	eq(c.footprint("nothing", a, 0).size(), 0, "unknown id has no cells")


func test_placement_needs_floor() -> void:
	var g := _grid(false)
	var c := _comps()
	eq(c.can_place(g, "reactor_mk1", Vector2i(4, 4), 0), "needs floor underneath", "bare hull")
	for p in _block(Vector2i(4, 4), 2, 4):
		if p != Vector2i(5, 7):
			g.place("floor", p)
	eq(c.can_place(g, "reactor_mk1", Vector2i(4, 4), 0), "needs floor underneath", "one cell still bare")
	g.place("floor", Vector2i(5, 7))
	eq(c.can_place(g, "reactor_mk1", Vector2i(4, 4), 0), "", "all eight cells floored")
	check(c.place(g, "reactor_mk1", Vector2i(4, 4), 0) > 0, "placed")
	eq(c.can_place(g, "nothing", Vector2i(4, 4), 0), "unknown component", "unknown id refused")
	eq(c.place(g, "nothing", Vector2i(4, 4), 0), -1, "unknown id not placed")


func test_placement_outside_the_hull() -> void:
	var g := _grid()
	var c := _comps()
	eq(c.can_place(g, "helm", Vector2i(0, 0), 0), "outside the hull", "corner is outside")
	eq(c.can_place(g, "engine_mk3", Vector2i(18, 10), 0), "outside the hull", "half off the grid")
	eq(c.can_place(g, "engine_mk3", Vector2i(-1, 10), 0), "outside the hull", "negative cells")
	eq(c.place(g, "helm", Vector2i(0, 0), 0), -1, "not placed")
	eq(c.instances.size(), 0, "nothing was added")


func test_walls_and_doors_are_not_floor() -> void:
	var g := _grid()
	var c := _comps()
	g.place("wall", Vector2i(4, 5))
	g.place("wall", Vector2i(7, 5))
	g.place("door", Vector2i(5, 5))  # a 2-cell piece: (5,5) and (6,5)
	eq(c.can_place(g, "helm", Vector2i(3, 5), 0), "needs floor underneath", "wall")
	eq(c.can_place(g, "helm", Vector2i(5, 5), 0), "needs floor underneath", "door")
	eq(c.can_place(g, "bed", Vector2i(4, 4), 0), "needs floor underneath", "wall and door under part of the footprint")
	eq(c.can_place(g, "helm", Vector2i(5, 3), 0), "", "plain floor next to it")


func test_overlap_names_the_other_component() -> void:
	var g := _grid()
	var c := _comps()
	var r := c.place(g, "reactor_mk1", Vector2i(3, 3), 0)  # x 3..4, y 3..6
	check(r > 0, "reactor placed")
	var want := "overlaps " + str(c.def("reactor_mk1")["name"])
	eq(c.can_place(g, "engine_mk3", Vector2i(4, 5), 0), want, "engine clips the reactor corner")
	eq(c.can_place(g, "reactor_mk2", Vector2i(3, 3), 0), want, "same cells")
	eq(c.place(g, "engine_mk3", Vector2i(4, 5), 0), -1, "overlap not placed")
	eq(c.can_place(g, "engine_mk3", Vector2i(5, 3), 0), "", "next to it is fine")
	eq(c.can_place(g, "engine_mk3", Vector2i(3, 7), 0), "", "below it is fine")
	var e := c.place(g, "engine_mk3", Vector2i(3, 7), 1)  # turned: x 3..4, y 7..10
	check(e > 0, "rotated engine placed")
	eq(c.can_place(g, "helm", Vector2i(3, 9), 0), "overlaps " + str(c.def("engine_mk3")["name"]), "rotated cells count")


func test_remove_frees_cells_and_uids_are_not_reused() -> void:
	var g := _grid()
	var c := _comps()
	var a := c.place(g, "engine_mk3", Vector2i(3, 3), 0)  # x 3..6, y 3..4
	var b := c.place(g, "helm", Vector2i(3, 5), 0)
	eq(a, 1, "uids start at 1")
	eq(b, 2, "and count up")
	eq(c.at(Vector2i(6, 4)), a, "at() finds the far cell")
	eq(c.at(Vector2i(7, 3)), -1, "at() is -1 on a free cell")
	eq(c.remove_at(Vector2i(4, 3)), "engine_mk3", "remove by any covered cell")
	eq(c.remove_at(Vector2i(4, 3)), "", "nothing left to remove")
	eq(c.at(Vector2i(3, 3)), -1, "first cell freed")
	eq(c.at(Vector2i(6, 4)), -1, "last cell freed")
	check(not c.instances.has(a), "instance gone")
	eq(c.can_place(g, "engine_mk3", Vector2i(3, 3), 0), "", "the cells can be used again")
	var again := c.place(g, "engine_mk1", Vector2i(3, 3), 0)
	eq(again, 3, "a new uid, not the freed one")
	c.remove_at(Vector2i(3, 5))
	eq(c.place(g, "helm", Vector2i(3, 5), 0), 4, "uids are never reused")


func test_components_round_trip() -> void:
	var g := _grid()
	var c := _comps()
	c.place(g, "reactor_mk2", Vector2i(4, 4), 0)
	c.place(g, "engine_mk1", Vector2i(9, 4), 1)
	c.place(g, "oxygen_gen", Vector2i(9, 9), 3)
	var gone := c.place(g, "helm", Vector2i(4, 9), 0)
	c.remove_at(Vector2i(4, 9))
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	var h := _comps()
	eq(h.load_dict(d), "", "loads")
	eq(h.instances.size(), 3, "same count")
	for uid in c.instances:
		eq(h.instances[uid], c.instances[uid], "instance %d" % uid)
	eq(h.at(Vector2i(10, 7)), c.at(Vector2i(10, 7)), "cell index rebuilt")
	eq(h.to_dict(), c.to_dict(), "dicts match")
	var next := h.place(g, "helm", Vector2i(4, 9), 0)
	check(next > gone, "uid counter survives a round trip")
	eq(h.load_dict({"version": 99, "instances": []}), "unsupported components version", "future saves refused")
	eq(h.load_dict({"version": 1, "next_uid": 5, "instances": [{"uid": 1, "id": "warp_core", "anchor": [1, 1], "rot": 0}]}), "unknown component warp_core", "unknown ids refused")


func test_cables_place_remove_and_round_trip() -> void:
	var g := _grid()
	var comps := _comps()
	var cables := Cables.new()
	eq(cables.can_place(g, Vector2i(0, 0)), "outside the hull", "outside the hull")
	eq(cables.can_place(g, Vector2i(10, 10)), "", "free hull cell")
	check(cables.place(g, Vector2i(10, 10)), "placed")
	eq(cables.can_place(g, Vector2i(10, 10)), "already a cable", "no duplicates")
	check(not cables.place(g, Vector2i(10, 10)), "second place refused")
	g.place("wall", Vector2i(9, 10))
	g.place("wall", Vector2i(12, 10))
	g.place("door", Vector2i(10, 10))  # a piece: (10,10) and (11,10)
	check(cables.has(Vector2i(10, 10)), "a cable under a door stays")
	check(cables.place(g, Vector2i(9, 10)), "cable under a wall")
	comps.place(g, "reactor_mk1", Vector2i(8, 4), 0)
	check(cables.place(g, Vector2i(9, 6)), "cable under a component")
	check(cables.place(g, Vector2i(20, 20)) == false, "outside the hull refused")
	var d: Dictionary = JSON.parse_string(JSON.stringify(cables.to_dict()))
	var back := Cables.new()
	eq(back.load_dict(d), "", "loads")
	eq(back.cells, cables.cells, "same cells")
	eq(back.to_dict(), cables.to_dict(), "dicts match")
	eq(back.load_dict({"version": 99}), "unsupported cables version", "future saves refused")
	check(back.remove(Vector2i(10, 10)), "removed")
	check(not back.remove(Vector2i(10, 10)), "nothing left to remove")
	eq(back.cells.size(), 2, "two cables left")


# --- weapons and shields content (docs/CONTENT.md section 6) -----------------------------------

func _raw_components() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(COMPONENTS))["components"]


## Every id a weapon may name as ammo: the materials and the items.
func _cargo_ids() -> Dictionary:
	var out := {}
	for m in JSON.parse_string(FileAccess.get_file_as_string(MATERIALS))["materials"]:
		out[m["id"]] = true
	for i in JSON.parse_string(FileAccess.get_file_as_string(ITEMS))["items"]:
		out[i["id"]] = true
	return out


func test_every_component_has_the_runtime_fields_in_the_data() -> void:
	var lines := Stats.load_lines()
	var seen := {}
	for d in _raw_components():
		var id: String = d.get("id", "?")
		check(not seen.has(id), id + " is listed once")
		seen[id] = true
		for k in REQUIRED_FIELDS:
			check(d.has(k), "%s has %s" % [id, k])
		check(lines.has(d.get("line", "")), id + " has a known line")
		check(d.get("tier", 0) >= 1 and d.get("tier", 0) <= 3, id + " tier is 1 to 3")
		check(d.get("hp", 0) > 0, id + " has hp")
		check(d.get("heat_limit", 0) > 0 and d.get("cooling", 0) > 0, id + " has a heat limit and cooling")
		check(d.get("heat_per_s", -1) >= 0, id + " has heat_per_s")
		check(typeof(d.get("unique", false)) == TYPE_BOOL, id + " unique is a bool")


func test_weapon_parts_and_weapon_stats_match() -> void:
	var c := _comps()
	var w := Weapons.new()
	for id in c.ids():
		if c.def(id)["family"] == "weapon":
			check(w.has(id), "weapon part %s has an entry in weapons.json" % id)
	for id in w.defs:
		if id.begins_with("test_"):
			continue
		check(c.has(id), "weapons.json entry %s is a component" % id)
		if c.has(id):
			eq(c.def(id)["family"], "weapon", id + " is in the weapon family")


func _species_ids() -> Array:
	var out := []
	for s in Content.list("species"):
		out.append(s["id"])
	return out


func test_weapon_stats_use_known_kinds_and_damage_types() -> void:
	var w := Weapons.new()
	for id in w.defs:
		var e: Dictionary = w.defs[id]
		check(e.get("kind", "") in WEAPON_KINDS, "%s kind %s is known" % [id, e.get("kind", "")])
		check(e.get("damage_type", "") in DAMAGE_TYPES, "%s damage_type %s is known" % [id, e.get("damage_type", "")])
		var d := w.def(id)
		check(float(d["damage"]) > 0.0 and float(d["cooldown"]) > 0.0 and float(d["range"]) > 0.0, id + " damage, cooldown and range are positive")
		check(int(d["shots"]) >= 1 and float(d["arc"]) > 0.0, id + " has shots and an arc")
		for k in ["fire_chance", "jam_chance", "breach_chance"]:
			check(float(d.get(k, 0.0)) >= 0.0 and float(d.get(k, 0.0)) <= 1.0, "%s %s is a chance" % [id, k])
		check(float(d.get("heat_per_shot", 0.0)) >= 0.0, id + " heat_per_shot is not negative")
		if e.get("kind", "") == "beam":
			check(float(d["duration"]) > 0.0, id + " beam has a duration")
		for problem in Effects.problems(e, _species_ids()):  # effects: old-style tags, or the keys of effects.gd
			check(false, "%s: %s" % [id, problem])


## Every id a crew_bonus / crew_needed / room_work_mult `who` may name: species, library traits, and "mechanical".
func _who_ids() -> Array:
	var out := _species_ids()
	out.append_array(TraitSet.library().keys())
	out.append("mechanical")
	return out


func test_every_ability_and_component_stat_passes_the_part_effects_validator() -> void:
	var who := _who_ids()
	var traits: Array = TraitSet.library().keys()
	var n := 0
	for c in Content.list("components"):
		n += c.get("abilities", []).size()
		for p in PartEffects.component_problems(c, who, traits):
			check(false, "%s: %s" % [c["id"], p])
	check(n >= 10, "the validator looked at the abilities (%d)" % n)


func test_every_ammo_id_is_cargo() -> void:
	var cargo := _cargo_ids()
	var w := Weapons.new()
	var n := 0
	for id in w.defs:
		if w.defs[id].has("ammo"):
			n += 1
			check(cargo.has(w.defs[id]["ammo"]), "%s ammo %s is a material or an item" % [id, w.defs[id]["ammo"]])
	check(n >= 2, "some weapons use ammo")
	eq(w.defs["bolt_thrower_scrap"]["ammo"], "scrap", "the Bolt Thrower fires scrap")
	eq(w.defs["artemis_mk1"]["ammo"], "missile", "the Artemis fires missiles")


func test_the_weapon_pack() -> void:
	var c := _comps()
	var w := Weapons.new()
	for id in WEAPON_PACK:
		var want: Array = WEAPON_PACK[id]
		check(c.has(id), id + " exists")
		if not c.has(id):
			continue
		var d := c.def(id)
		var size: Array = [2, 2] if int(want[1]) <= 2 and not d.get("unique", false) else want[2]  # a tier 1-2 gun's inside half is 2x2 (playtest 2, P2)
		eq([d["line"], d["tier"], d["size"]], [want[0], want[1], size], id + " line, tier, size")
		eq([d["family"], d["priority"], d["power"] < 0, d["manned"]], ["weapon", 5, true, true], id + " is a manned weapon station at priority 5")
		check(str(d.get("blurb", "")) != "", id + " has a blurb")
		eq([w.defs[id]["kind"], w.defs[id]["damage_type"]], [want[3], want[4]], id + " kind and damage type")
	eq(c.def("rattle_burst_scrap")["name"], "Rattle Burst", "name")
	eq([int(w.def("rattle_burst_scrap")["shots"]), w.defs["rattle_burst_scrap"]["rapid"]], [1, true], "Rattle Burst is the rapid tier-1 turret: a shot at a time")
	check(float(w.def("rattle_burst_scrap")["jam_chance"]) > 0.0, "Rattle Burst jams")
	eq(w.def("shrapnel_cannon_scrap")["shots"], 5, "Shrapnel Cannon fires five projectiles")
	eq(w.def("shrapnel_cannon_scrap")["damage"], 1.5, "of 1.5 damage each")
	eq(w.def("pulse_mk1")["speed"], 700, "pulses are projectiles with a speed")
	check(w.def("pulse_mk2")["damage"] > w.def("pulse_mk1")["damage"] and w.def("pulse_mk2")["cooldown"] < w.def("pulse_mk1")["cooldown"], "Pulse Mk2 hits harder and faster")
	check(w.def("artemis_mk1")["pass_shields"] and w.def("artemis_mk1")["splash"] > 0, "the Artemis passes shields and splashes")
	eq(w.defs["siren_ion_neon"]["effects"], ["lock_doors"], "Siren Ion locks doors")
	check(not w.defs["ion_blast_mk1"].has("effects"), "plain Ion Blast has no door lock")
	eq(w.defs["siren_ion_neon"]["damage"], w.defs["ion_blast_mk1"]["damage"], "Siren Ion is an Ion Blast in the damage it deals")
	check(absf(w.def("siren_ion_neon")["damage"] - 0.6 * w.def("ion_blast_mk1")["damage"]) < 1e-9, "less a turret's 40 percent")
	eq([w.def("heat_lance_neon")["fire_chance"], w.def("heat_lance_neon")["heat_per_shot"], w.def("heat_lance_neon")["duration"]], [0.3, 25.0, 1.5], "Heat Lance fires, heats and sweeps")
	eq(w.defs["leech_laser"]["effects"], ["drain_power"], "Leech Laser drains power")
	eq([w.def("breach_harpoon")["breach_chance"], w.defs["breach_harpoon"]["effects"]], [1.0, ["tether"]], "Breach Harpoon breaches and tethers")


func test_shields_have_layers_and_recharge() -> void:
	var c := _comps()
	var n := 0
	for id in c.ids():
		var d := c.def(id)
		if d["family"] != "shield":
			continue
		n += 1
		check(int(d["stats"].get("layers", 0)) >= 1, id + " has at least one layer")
		check(float(d["stats"].get("recharge", 0.0)) > 0.0, id + " has a positive recharge time")
		if not SHIELD_RECHARGE.has(id):  # the rest follow the tier table of data/weapons.json (x its neon factor on the neon line)
			var cfg: Dictionary = Abilities.shield_config()
			var want := float(cfg["tier_recharge"][str(int(d["tier"]))]) * (float(cfg["neon_mult"]) if d["line"] == "neon" else 1.0)
			check(absf(float(d["stats"].get("recharge", 0.0)) - want) < 0.05, "%s recharges in %s s (tier %d%s)" % [id, str(want), int(d["tier"]), ", neon" if d["line"] == "neon" else ""])
		var sectors = d["stats"].get("sectors")
		check(sectors != null and sectors == int(sectors) and int(sectors) in SHIELD_SECTORS, "%s sectors %s is an integer in 1, 2, 4 or 8" % [id, str(sectors)])
	check(n >= 5, "at least five shields")
	eq([int(c.def("shield_mk1")["stats"]["sectors"]), int(c.def("shield_scrap_mk1")["stats"]["sectors"]), int(c.def("shield_mk2")["stats"]["sectors"]), int(c.def("mirror_veil")["stats"]["sectors"])], [1, 1, 2, 1], "Mk1, scrap and unique shields are one piece, the Mk2 has two sectors")
	eq(int(c.def("shield_neon_mk1")["stats"]["sectors"]), 4, "the neon shield has four sectors")
	eq([c.def("shield_scrap_mk1")["name"], c.def("shield_scrap_mk1")["line"], int(c.def("shield_scrap_mk1")["stats"]["layers"])], ["Bubble Rig", "scrap", 1], "Bubble Rig")
	eq([c.def("shield_mk2")["line"], c.def("shield_mk2")["tier"], int(c.def("shield_mk2")["stats"]["layers"])], ["standard", 2, 2], "Shield Mk2")
	var neon := c.def("shield_neon_mk1")
	eq([neon["name"], neon["line"], int(neon["stats"]["layers"]), neon["stats"]["recharge"]], ["Neon Lattice Shield", "neon", 2, 4.0], "Neon Lattice Shield")
	check(neon["stats"]["recharge"] < c.def("shield_mk1")["stats"]["recharge"], "the neon shield recharges faster than the Mk1")
	for id in SHIELD_RECHARGE:
		eq(float(c.def(id)["stats"]["recharge"]), float(SHIELD_RECHARGE[id]), id + " recharge")
	check(Stats.load_lines()["neon"]["ion_vulnerability"] > 1.0, "and is ion-weak through its line")
	var veil := c.def("mirror_veil")
	eq([int(veil["stats"]["layers"]), veil["effects"]], [1, ["reflect_bolts_15"]], "Mirror Veil")


func test_uniques_are_marked() -> void:
	var c := _comps()
	for id in UNIQUES:
		check(c.has(id) and c.def(id).get("unique", false) == true, id + " is unique")
		check(str(c.def(id).get("blurb", "")) != "", id + " has a blurb")
	for id in WEAPON_PACK:
		if not id in UNIQUES:
			check(not c.def(id).get("unique", false), id + " is not unique")
