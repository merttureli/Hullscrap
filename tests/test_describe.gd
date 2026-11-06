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

## The weapon fields that make a trait keyword, and the describe.json `keywords` id of each.
const TRAITS := {"pierce": "pierce", "fire_chance": "fire", "splash": "splash", "ammo": "ammo", "jam_chance": "jam",
	"heat_per_shot": "heat", "breach_chance": "breach", "pass_shields": "pass_shields"}
const LINE_COLS := [Color("#9c5a33"), Color("#8d9aab"), Color("#3cf2ff")]  ## scrap, standard, neon (ui_kit.gd LINE_COLORS)
const PANEL := Color("#2a3340")  ## the lightest panel a keyword is drawn on (ui_kit.gd ROW_BG)


func _lines(section: String):
	return Describe.data()[section]


func _has_line(section: String, key: String) -> bool:
	return str(_lines(section).get(key, "")).strip_edges() != ""


func _words(s: String) -> int:
	return s.split(" ", false).size()


## The keyword ids of every part and every weapon trait in use.
func _keywords_in_use() -> Dictionary:
	var out := {}
	var ship := Ship.new_starter()
	for id in ship.components.ids():
		for k in Describe.of(id, ship)["keywords"]:
			out[k["id"]] = true
	return out


func test_every_family_keyword_effect_and_stat_in_use_has_its_words() -> void:
	var families := {}
	var stats := {}
	for d in Content.list("components"):
		families[str(d.get("family", ""))] = true
		for k in d.get("stats", {}):
			stats[k] = true
	for f in families:
		check(_has_line("families", f), "family " + f)
		check(_words(str(_lines("families").get(f, ""))) <= 8, "the line of family %s is 8 words at most" % f)
	for k in stats:
		check(_lines("stats").has(k), "stat " + k)
	var weapons := Weapons.new()
	var in_use := {"auto": true, "rapid": true, "ammo_mult": true}
	for id in weapons.defs:
		var w: Dictionary = weapons.def(id)
		in_use[str(w["kind"])] = true
		in_use[str(w["damage_type"])] = true
		for field in TRAITS:
			var v = w.get(field, 0)
			if (v is String and v != "") or (v is bool and v) or (not v is String and not v is bool and float(v) > 0.0):
				in_use[TRAITS[field]] = true
		for k in Effects.of(w):
			if not str(k) in _lines("idle"):
				in_use[str(k)] = true
	for k in ["acid", "spores", "shard", "sonic", "magnetic", "frost", "corrode", "split_on_shield", "intercept", "self_room", "needs_operator", "needs_crew_in_room"]:
		in_use[k] = true  # every effect of effects.gd
	for k in ["manned", "hot", "faulty", "ion_weak", "quirk", "ability", "ablative", "lattice_power", "ram", "mod"]:
		in_use[k] = true  # the part's own
	for k in _keywords_in_use():
		in_use[k] = true
	for k in in_use:
		var kw: Dictionary = _lines("keywords").get(k, {})
		check(not kw.is_empty(), "keyword " + k)
		if kw.is_empty():
			continue
		check(str(kw.get("label", "")).strip_edges() != "", k + " has a label")
		check(str(kw.get("color", "")).begins_with("#") and str(kw["color"]).length() == 7, k + " has a colour")
		check(str(kw.get("hover", "")).strip_edges() != "", k + " has a hover line")
		check(_words(str(kw.get("hover", ""))) <= 12, "the hover line of %s is 12 words at most: %s" % [k, kw.get("hover")])
	for k in _lines("keywords"):
		check(in_use.has(k), "keyword %s is used by something" % k)
	for t in ["ammo", "gear", "special", "material", "mod"]:
		check(_has_line("items", t), "item kind " + t)
	for t in ["floor", "wall", "door", "piece", "cable", "belt"]:
		check(_has_line("tiles", t) and _words(_lines("tiles")[t]) <= 8, "tile line " + t)
	for t in _lines("idle"):
		check(not _lines("keywords").has(t), "an idle tag has no keyword: " + t)


## WCAG contrast of `c` on `bg`.
func _contrast(c: Color, bg: Color) -> float:
	var a := _lum(c)
	var b := _lum(bg)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


## CIE Lab of `c`.
func _lab(c: Color) -> Vector3:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	var r: float = f.call(c.r)
	var g: float = f.call(c.g)
	var b: float = f.call(c.b)
	var x := (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	var y := 0.2126 * r + 0.7152 * g + 0.0722 * b
	var z := (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	var t := func(v: float) -> float: return pow(v, 1.0 / 3.0) if v > 0.008856 else 7.787 * v + 16.0 / 116.0
	var fx: float = t.call(x)
	var fy: float = t.call(y)
	var fz: float = t.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


func test_keyword_colours_read_on_the_panels_and_differ_from_each_other_and_the_lines() -> void:
	var ids: Array = _lines("keywords").keys()
	var worst := 999.0
	for i in ids.size():
		var c := Color(str(_lines("keywords")[ids[i]]["color"]))
		check(_contrast(c, PANEL) >= 4.5, "%s reads on the dark panels (contrast %.2f)" % [ids[i], _contrast(c, PANEL)])
		for line in LINE_COLS:
			worst = minf(worst, _lab(c).distance_to(_lab(line)))
		for j in range(i + 1, ids.size()):
			var d := _lab(c).distance_to(_lab(Color(str(_lines("keywords")[ids[j]]["color"]))))
			worst = minf(worst, d)
			check(d >= 15.0, "%s and %s differ (dE %.1f)" % [ids[i], ids[j], d])
	for line in LINE_COLS:
		for k in ["laser", "bolt", "flak", "missile", "beam", "energy", "kinetic", "explosive", "ion", "auto"]:
			check(_lab(Color(str(_lines("keywords")[k]["color"]))).distance_to(_lab(line)) >= 15.0, k + " differs from the line colours")
	check(worst >= 15.0, "no two colours closer than dE 15: %.1f" % worst)


func _labels(id: String, ship) -> Array:
	return Describe.of(id, ship)["keywords"].map(func(k): return k["label"])


func test_every_component_has_a_blurb_and_says_what_it_does() -> void:
	var ship := Ship.new_starter()
	for id in ship.components.ids():
		var d := Describe.of(id, ship)
		check(str(ship.components.def(id).get("blurb", "")).strip_edges().length() > 10, id + " has a blurb")
		check(d["what"] != "" and d["lore"] != "", id + " says what it does, and has its lore")
		check(_words(d["what"]) <= 8, id + ": what it does is 8 words at most: " + d["what"])
		check(not d["lore"].substr(0, d["lore"].length() - 1).contains(". "), id + ": the lore is one sentence: " + d["lore"])
		check(not Describe.text(id, ship).contains("{"), id + ": no template left unfilled")
		for k in d["keywords"]:
			check(k["label"] != "" and k["hover"] != "" and k["color"] is Color, "%s: keyword %s is complete" % [id, k["id"]])
		for r in d["stats"]:
			check(r.size() == 2 and str(r[0]) != "" and str(r[1]).length() <= 28, "%s: a short stat, no sentences: %s" % [id, r])


func test_a_part_gets_its_keywords() -> void:
	var ship := Ship.new_starter()
	var laser := _labels("laser_mk1", ship)
	for want in ["LASER", "ENERGY", "FIRE 5%"]:
		check(laser.has(want), "laser_mk1 has " + want + ": " + str(laser))
	var turret := _labels("laser_turret_mk1", ship)
	for want in ["LASER", "AUTO", "RAPID"]:
		check(turret.has(want), "the rapid turret has " + want + ": " + str(turret))
	var missile := _labels("artemis_mk1", ship)
	for want in ["MISSILE", "PASSES SHIELDS"]:
		check(missile.has(want), "a missile has " + want + ": " + str(missile))
	check(not _labels("laser_mk1", ship).has("AUTO"), "a fixed gun is not AUTO")
	check(_labels("engine_mk1", ship).has("MANNED+") or _labels("reactor_mk1", ship).has("MANNED+") or _labels("helm", ship).has("MANNED+"), "a part that works better manned says so")
	check(_labels("smelter_mk1", ship).has("HOT"), "a part that overheats says HOT")
	check(not _labels("laser_mk1", ship).has("HOT"), "and one that does not does not")
	check(_labels("basalt_magma_spitter", ship).has("QUIRK"), "a part's own quirk is a chip (its hover says it)")
	var hover: String = Describe.of("laser_mk1", ship)["keywords"].filter(func(k): return k["id"] == "laser")[0]["hover"]
	eq(hover, "Hits instantly. Shields block it.", "a keyword's hover line")
	var kind := Describe.weapon_tags("laser_turret_mk1")
	eq(kind.map(func(k): return k["label"]), ["LASER", "AUTO"], "the palette's tags: the kind, and AUTO for a turret")
	eq(Describe.weapon_tags("engine_mk1"), [], "an engine has none")
	eq(Describe.weapon_kind("artemis_mk1"), "missile", "the kind the weapon bar colours by")


func test_the_numbers_come_from_the_data() -> void:
	var ship := Ship.new_starter()
	var laser := {}
	for r in Describe.of("laser_mk1", ship)["stats"]:
		laser[r[0]] = r[1]
	eq([laser["Damage"], laser["Every"], laser["Range"], laser["Power"], laser["HP"]], ["3", "2.1 s", "1260", "\u22122", "5 (out 10)"], "laser_mk1: " + str(laser))
	eq(laser["Size"], "2\u00d72 (out 4\u00d72)", "its size, both halves")
	check(laser["Gimbal"] == "5\u00b0" and laser["Fire"] == "LMB", "a fixed gun: how far it turns, which button: " + str(laser))
	var turret := {}
	for r in Describe.of("laser_turret_mk1", ship)["stats"]:
		turret[r[0]] = r[1]
	eq([turret["Damage"], turret["Every"], turret["Arc"], turret["Track"], turret["Hit"]], ["0.6", "0.8 s", "270\u00b0", "120\u00b0/s", "80%"], "a turret adds its arc, track and hit: " + str(turret))
	var eng := Describe.of("engine_mk1", ship, 2)
	eq(eng["stats"].filter(func(r): return r[0] == "Push")[0][1], "10 fwd, 3 side", "a rear engine pushes forward, with a third sideways")
	check(Describe.text("engine_mk1", ship, 2).contains("Thrust: 10"), "engine_mk1 thrust")
	var side: String = Describe.of("strafe_jets_mk1", ship, 1)["stats"].filter(func(r): return r[0] == "Push")[0][1]
	check(side.begins_with("6 side"), "a side-mounted engine is sideways only: " + side)
	var rear_slope: String = Describe.of("engine_mk1", ship, 0, 135.0)["stats"].filter(func(r): return r[0] == "Push")[0][1]
	eq(rear_slope, "7.07 fwd, 7.07 side", "an engine over a rear-facing 45 degree slope pushes along the slope, not sideways only")
	var front_slope: String = Describe.of("engine_mk1", ship, 0, 45.0)["stats"].filter(func(r): return r[0] == "Push")[0][1]
	eq(front_slope, "7.07 back, 7.07 side", "over a front-facing slope it brakes, and R does not help: " + front_slope)
	var shield := Describe.text("shield_mk1", ship)
	for want in ["Layers: 1", "Sectors: 1", "Layer HP: 4", "Regen: 1 HP/s after 3 s", "Broken: 5 s down"]:
		check(shield.contains(want), "shield_mk1 says " + want + ": " + shield)
	eq(Abilities.shield_base(), 7.0, "the base the shield text follows")
	var rector := Describe.text("reactor_mk1", ship)
	check(rector.contains("Power: +%d" % int(ship.components.def("reactor_mk1")["power"])) and rector.contains("HP: 8"), "reactor_mk1: " + rector)
	check(Describe.text("medbay", ship).contains("Heals: 15 hp/s"), "the medbay heals at crew.json's rate")
	check(Describe.text("radar_mk1", ship).contains("6,000 px"), "radar range with a thousands comma")
	var beam := {}
	for r in Describe.of("heat_lance_neon", ship)["stats"]:
		beam[r[0]] = r[1]
	check(str(beam["Damage"]).contains("/s"), "a beam's damage is per second: " + str(beam["Damage"]))
	var cost := Describe.of("laser_mk1", ship)
	eq([cost["cost"], cost["level"]], [ship.crafting.def("laser_mk1")["materials"], 1], "the cost is the recipe's")


func test_a_shield_with_no_hp_stats_uses_its_tiers_row() -> void:
	var ship := Ship.new_starter()
	var d: Dictionary = ship.components.def("shield_mk1").duplicate(true)  # a copy of this ship's own def, with no recharge
	d["id"] = "shield_plain"
	d["stats"].erase("recharge")
	ship.components.by_id["shield_plain"] = d
	check(Describe.text("shield_plain", ship).contains("Layer HP: 4"), "unset HP numbers read the tier's row of the shields block of weapons.json")
	var info := Palette.info(Palette.part_entry(ship, "shield_plain"), ship)
	check(info["stats"].has(["Layer HP", "4"]) and info["stats"].has(["Broken", "5 s down"]), "and so does the card")


func test_tags_no_code_reads_are_left_off_the_card() -> void:
	var ship := Ship.new_starter()
	for id in ["leech_laser", "siren_ion_neon", "breach_harpoon"]:
		var labels := _labels(id, ship)
		check(not labels.has("LOCK DOORS") and not labels.has("DRAIN POWER") and not labels.has("TETHER"), id + " promises nothing the game does not do")
	var d := Describe.of("basalt_magma_spitter", ship)
	check(d["keywords"].any(func(k): return k["id"] == "acid" and k["hover"].contains("4 s")), "an effect's hover carries its numbers: " + str(d["keywords"]))
	check(d["keywords"].any(func(k): return k["id"] == "self_room"), "and the back-blast is there")


func test_an_item_gets_its_line_and_its_lore() -> void:
	var ship := Ship.new_starter()
	for it in Content.list("items"):
		check(_words(Describe.of(str(it["id"]), ship)["what"]) <= 8, "%s: what it does is 8 words at most: %s" % [it["id"], Describe.of(str(it["id"]), ship)["what"]])
	var d := Describe.of("pistol", ship)
	check(d["what"].contains("gear") and d["lore"] == Describe.first_sentence(Content.entry("items", "pistol")["blurb"]), "a pistol: " + str(d))
	check(Describe.of("polymer", ship)["what"].contains("Raw material"), "a material")
	eq(Describe.first_sentence("One. Two. Three."), "One.", "the lore is cut to its first sentence")
	eq(Describe.first_sentence("No full stop"), "No full stop", "and left whole when there is one")


# --- the honest build palette ---------------------------------------------------------------------------------------

func _part_ids(ship, cable := {}) -> Array:
	var out := []
	for tab in [Palette.Tab.SYSTEMS, Palette.Tab.WEAPONS, Palette.Tab.ENGINES, Palette.Tab.UTILITY]:
		for e in Palette.entries(tab, ship, cable):
			out.append(e["id"])
	return out


func test_a_fresh_runs_palette_lists_only_held_parts() -> void:
	var ship := Ship.new_starter()
	var ids := _part_ids(ship)
	check(ids.size() > 0 and ids.size() < ship.components.ids().size(), "a trimmed list: %d of %d" % [ids.size(), ship.components.ids().size()])
	for id in ids:
		check(ship.inventory.count(id) > 0, id + " is held")
	check(not ids.has("laser_mk2") and not ids.has("basalt_vacuum_forge"), "a part with no blueprint and none held is not listed")
	var card := Palette.part_entry(ship, "laser_mk1")
	if ship.inventory.count("laser_mk1") == 0:
		check(not ids.has("laser_mk1"), "a known blueprint with none held is not listed")
		eq(card["why"], "Craft at Fabricator (C)", "known but not held says where to craft it")
	ship.crafting.unlock("laser_mk2")
	check(not _part_ids(ship).has("laser_mk2"), "learning a blueprint adds no card: only the hold does")
	ship.inventory.add("laser_mk2", 1)
	check(_part_ids(ship).has("laser_mk2"), "holding one does")
	ship.inventory.add("leech_laser", 1)
	check(_part_ids(ship).has("leech_laser"), "a found part with no recipe shows once it is held")
	var cargo := Palette.entries(Palette.Tab.CARGO, ship, {})
	check(cargo.all(func(e): return e["count"] > 0 or e["kind"] == "item"), "the Cargo tab holds only what is held")


func test_the_belt_card_and_the_structure_tab_keep_the_basics() -> void:
	var ship := Ship.new_starter()
	for m in ship.crafting.materials:
		ship.inventory.add(m, 1000)
	var keys := Palette.entries(Palette.Tab.STRUCTURE, ship, {"copper": 1}).map(func(e): return e["key"])
	for id in ship.grid.defs.ids():
		check(keys.has("tile:" + id), "the Structure tab still lists " + id)
	check(keys.has("cable"), "and the cable")


func test_the_selection_card_describes_a_part_in_a_few_lines() -> void:
	var ship := Ship.new_starter()
	ship.crafting.unlock("laser_turret_mk1")
	var info := Palette.info(Palette.part_entry(ship, "laser_turret_mk1"), ship)
	eq(info["what"], "Gun on a hull mount.", "what it does")
	check(info["stats"].has(["Every", "0.8 s"]), "its stats")
	check(info["keywords"].any(func(k): return k["label"] == "LASER") and info["keywords"].any(func(k): return k["label"] == "RAPID"), "its keywords")
	eq(info["lore"], "A swivelling laser that tracks and fires by itself.", "one line of lore")
	eq(info["cost"], ship.crafting.def("laser_turret_mk1")["materials"], "what it costs")
	eq(info["note"], "Craft at Fabricator (C)", "none held: where to craft it, and only then")
	ship.inventory.add("laser_turret_mk1", 1)
	eq(Palette.info(Palette.part_entry(ship, "laser_turret_mk1"), ship)["note"], "", "held: no note")
