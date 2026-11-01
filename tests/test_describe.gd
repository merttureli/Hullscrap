extends "res://tests/base_test.gd"
## Part descriptions (scripts/ui/describe.gd, data/describe.json) and the honest build palette: every family, weapon kind,
## damage type, trait, effect and stat in use has its line; every part has lore; the numbers come out of the data the game
## uses; the palette lists a part only when it is held or its blueprint is known.

const Describe = preload("res://scripts/ui/describe.gd")
const Palette = preload("res://scripts/build/palette.gd")
const Content = preload("res://scripts/data/content.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")

## The weapon fields that make a trait line, and the describe.json `effects` key of each.
const TRAITS := {"pierce": "pierce", "fire_chance": "fire", "splash": "splash", "ammo": "ammo", "jam_chance": "jam",
	"heat_per_shot": "heat", "breach_chance": "breach"}


func _lines(section: String):
	return Describe.data()[section]


func _has_line(section: String, key: String) -> bool:
	return str(_lines(section).get(key, "")).strip_edges() != ""


func test_every_family_kind_damage_type_and_effect_in_use_has_a_line() -> void:
	var families := {}
	var stats := {}
	var comp_effects := {}
	for d in Content.list("components"):
		families[str(d.get("family", ""))] = true
		for k in d.get("stats", {}):
			stats[k] = true
		for t in (d.get("effects", []) if d.get("effects") is Array else []):
			comp_effects[str(t)] = true
	for f in families:
		check(_has_line("families", f), "family " + f)
	for k in stats:
		check(_lines("stats").has(k), "stat " + k)
	for t in comp_effects:
		check(_has_line("effects", t), "part effect " + t)
	var weapons := Weapons.new()
	var fx_in_use := {}
	for id in weapons.defs:
		var w: Dictionary = weapons.def(id)
		check(_has_line("kinds", str(w["kind"])), "kind %s of %s" % [w["kind"], id])
		check(_has_line("damage", str(w["damage_type"])), "damage type %s of %s" % [w["damage_type"], id])
		for field in TRAITS:
			var v = w.get(field, 0)
			if (v is String and v != "") or (not v is String and float(v) > 0.0):
				check(_has_line("effects", TRAITS[field]), "trait %s of %s" % [TRAITS[field], id])
		for k in Effects.of(w):
			fx_in_use[str(k)] = true
			check(_has_line("effects", str(k)), "effect %s of %s" % [k, id])
		if w.get("rapid", false):
			check(_has_line("effects", "rapid"), "rapid")
		check(_has_line("effects", "turret" if w["turret"] else "fixed"), "aim of " + id)
	for k in ["acid", "spores", "shard", "sonic", "magnetic", "frost", "corrode", "split_on_shield", "intercept", "self_room", "needs_operator", "needs_crew_in_room", "ammo_mult"]:
		check(_has_line("effects", k), "every effect of effects.gd has a line: " + k)
	for k in _lines("self_room_parts"):
		check(Effects.SELF_ROOM.has(k), "self_room clause " + k + " is a self_room key")
	for k in Effects.SELF_ROOM:
		check(_has_line("self_room_parts", k), "self_room key " + k)
	for t in ["ammo", "gear", "special", "material"]:
		check(_has_line("items", t), "item kind " + t)
	for t in _lines("idle"):
		check(_has_line("effects", t), "an idle tag still has its line: " + t)


func test_every_component_has_a_blurb_and_says_what_it_does() -> void:
	var ship := Ship.new_starter()
	for id in ship.components.ids():
		var d := Describe.of(id, ship)
		check(str(ship.components.def(id).get("blurb", "")).strip_edges().length() > 10, id + " has a blurb")
		check(d["does"] != "" and d["lore"] != "", id + " says what it does, and has its lore")
		check(not Describe.text(id, ship).contains("{"), id + ": no template left unfilled")


func test_the_numbers_come_from_the_data() -> void:
	var ship := Ship.new_starter()
	var laser := Describe.text("laser_mk1", ship)
	for want in ["draws 2", "3 energy a shot", "every 2.1 s", "900 px", "Fixed gun", "Laser:", "Energy:", "Fire 5%"]:
		check(laser.contains(want), "laser_mk1 says " + want + ": " + laser)
	var turret := Describe.text("laser_turret_mk1", ship)
	for want in ["AUTO TURRET: aims and fires by itself (T toggles)", "270 deg arc", "tracks 120 deg", "80% accurate", "every 0.8 s", "0.6 energy a shot", "Rapid fire"]:
		check(turret.contains(want), "the rapid turret says " + want + ": " + turret)
	var eng := Describe.of("engine_mk1", ship, 2)
	eq(eng["rows"].filter(func(r): return r[0] == "Pushes")[0][1], "10 forward, 3 sideways either way", "a rear engine pushes forward, with a third sideways")
	check(Describe.text("engine_mk1", ship, 2).contains("Thrust: 10"), "engine_mk1 thrust")
	var side: String = Describe.of("strafe_jets_mk1", ship, 1)["rows"].filter(func(r): return r[0] == "Pushes")[0][1]
	check(side.begins_with("sideways only: 6 one way"), "a side-mounted engine is sideways only: " + side)
	var shield := Describe.text("shield_mk1", ship)
	for want in ["Layers: 1", "Sectors: 1", "Recharge: a layer back every 7 s", "waits 3 s more"]:
		check(shield.contains(want), "shield_mk1 says " + want + ": " + shield)
	eq(Abilities.shield_base(), 7.0, "the base the shield text follows")
	var rector := Describe.text("reactor_mk1", ship)
	check(rector.contains("makes %d" % int(ship.components.def("reactor_mk1")["power"])) and rector.contains("HP: 8"), "reactor_mk1: " + rector)
	check(Describe.text("medbay", ship).contains("Heals: 15 hp a second"), "the medbay heals at crew.json's rate")
	check(Describe.text("radar_mk1", ship).contains("6,000 px"), "radar range with a thousands comma")
	check(Describe.text("artemis_mk1", ship).contains("Passes through shields"), "a missile passes shields")


func test_a_shield_with_no_recharge_stat_uses_the_base() -> void:
	var ship := Ship.new_starter()
	var d: Dictionary = ship.components.def("shield_mk1").duplicate(true)  # a copy of this ship's own def, with no recharge
	d["id"] = "shield_plain"
	d["stats"].erase("recharge")
	ship.components.by_id["shield_plain"] = d
	check(Describe.text("shield_plain", ship).contains("Recharge: a layer back every 7 s"), "an unset recharge reads the shields block of weapons.json")
	var info := Palette.info(Palette.part_entry(ship, "shield_plain"), ship)
	check(info["rows"].has(["Recharge", "a layer back every 7 s"]), "and so does the card, not '2.0 s'")


func test_tags_no_code_reads_are_left_off_the_card() -> void:
	var ship := Ship.new_starter()
	for id in ["leech_laser", "siren_ion_neon", "breach_harpoon"]:
		var t := Describe.text(id, ship)
		check(not t.contains("Drains power") and not t.contains("Locks doors") and not t.contains("Tethers"), id + " promises nothing the game does not do")
	var d := Describe.of("basalt_magma_spitter", ship)
	check(d["kinds"].any(func(l): return str(l).begins_with("Acid:") and str(l).contains("1.5 a second for 4 s")), "an effect line carries its numbers: " + str(d["kinds"]))
	check(d["kinds"].any(func(l): return str(l).contains("vents 30% of the air")), "and the back-blast: " + str(d["kinds"]))


func test_an_item_gets_its_line_and_its_lore() -> void:
	var ship := Ship.new_starter()
	var d := Describe.of("pistol", ship)
	check(d["does"].contains("Gear") and d["lore"].contains("argument-settler"), "a pistol: " + str(d))
	check(Describe.of("polymer", ship)["does"].contains("raw material"), "a material")


# --- the honest build palette ---------------------------------------------------------------------------------------

func _part_ids(ship, cable := {}) -> Array:
	var out := []
	for tab in [Palette.Tab.SYSTEMS, Palette.Tab.WEAPONS, Palette.Tab.ENGINES, Palette.Tab.UTILITY]:
		for e in Palette.entries(tab, ship, cable):
			out.append(e["id"])
	return out


func test_a_fresh_runs_palette_lists_only_held_or_known_parts() -> void:
	var ship := Ship.new_starter()
	var ids := _part_ids(ship)
	check(ids.size() > 0 and ids.size() < ship.components.ids().size(), "a trimmed list: %d of %d" % [ids.size(), ship.components.ids().size()])
	for id in ids:
		check(ship.inventory.count(id) > 0 or ship.crafting.is_known(id), id + " is held or known")
	check(not ids.has("laser_mk2") and not ids.has("basalt_vacuum_forge"), "a part with no blueprint and none held is not listed")
	check(ids.has("laser_mk1") and ids.has("reactor_mk1"), "a known blueprint lists its card")
	var card := Palette.part_entry(ship, "laser_mk1")
	if ship.inventory.count("laser_mk1") == 0:
		eq(card["why"], "0 held, craft at the fabricator (C)", "known but not held says where to craft it")
	ship.crafting.unlock("laser_mk2")
	check(_part_ids(ship).has("laser_mk2"), "learning a blueprint adds its card")
	ship.crafting.unlock("basalt_vacuum_forge")
	check(_part_ids(ship).has("basalt_vacuum_forge"), "and so does a racial one")
	ship.inventory.add("leech_laser", 1)
	check(_part_ids(ship).has("leech_laser"), "a found part with no recipe shows once it is held")
	var cargo := Palette.entries(Palette.Tab.CARGO, ship, {})
	check(cargo.all(func(e): return e["count"] > 0 or e["kind"] == "item"), "the Cargo tab holds only what is held")


func test_the_belt_card_and_the_structure_tab_keep_the_basics() -> void:
	var ship := Ship.new_starter()
	var keys := Palette.entries(Palette.Tab.STRUCTURE, ship, {}).map(func(e): return e["key"])
	for id in ship.grid.defs.ids():
		check(keys.has("tile:" + id), "the Structure tab still lists " + id)
	check(keys.has("cable"), "and the cable")


func test_the_selection_card_describes_a_part_in_four_parts() -> void:
	var ship := Ship.new_starter()
	var info := Palette.info(Palette.part_entry(ship, "laser_turret_mk1"), ship)
	check(info["does"].begins_with("Shoots at enemy ships"), "what it does")
	check(info["rows"].has(["Fires", "every 0.8 s"]), "its stats")
	check(info["kinds"].any(func(l): return str(l).begins_with("Laser:")) and info["kinds"].any(func(l): return str(l).begins_with("Rapid fire")), "what its type means")
	check(info["blurb"].contains("tracks and fires by itself"), "the lore")
