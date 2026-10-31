extends "res://tests/base_test.gd"
## The content validator and the content packs (docs/CONTENT_PLAN.md sections 1 and 3). Every rule is a
## function that returns its problems, each naming the file and the id, and a test fails on every one. The
## rules run on the real data (the core files and every pack in data/packs/), on the fixture packs, and on
## small made-up data that breaks them on purpose. The fixture packs are in tests/fixtures/packs/, one folder
## of packs per scenario; a test points Content.packs_root at one and puts it back when it is done.

const Content = preload("res://scripts/data/content.gd")
const Balance = preload("res://scripts/data/balance.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Stats = preload("res://scripts/sim/stats.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const CrewAbilities = preload("res://scripts/crew/crew_abilities.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Regions = preload("res://scripts/space/regions.gd")

const FIXTURES := "res://tests/fixtures/packs/"
const EVENTS_SCRIPT := "res://scripts/space/events.gd"  ## the Drift's loader and validator, once it is on main
const ITEM_KINDS: Array[String] = ["ammo", "gear", "special"]
const RARITIES: Array[String] = ["common", "uncommon", "rare", "very_rare"]
const ENGINE := {"id": "x", "family": "engine", "line": "standard", "tier": 1, "power": -2, "hp": 6, "stats": {"thrust": 10}}


# --- the rules ------------------------------------------------------------------------------------

## "file: kind 'id'" for a message.
func _at(kind: String, e: Dictionary) -> String:
	var file := Content.file_of(kind, str(e.get("id", "")))
	return "%s: %s '%s'" % [file if file != "" else "(inline data)", kind, e.get("id", "?")]


## Every id cargo can hold. Components, materials and items share one namespace; credits is the money.
func _cargo_ids() -> Dictionary:
	var out := {"credits": true}
	for kind in ["components", "materials", "items"]:
		for id in Content.ids(kind):
			out[id] = true
	return out


func collision_problems() -> Array[String]:
	var out: Array[String] = []
	var seen := {"credits": "the money"}
	for kind in ["components", "materials", "items"]:
		for e in Content.list(kind):
			if seen.has(e["id"]):
				out.append("%s: the id is also used by %s" % [_at(kind, e), seen[e["id"]]])
			seen[e["id"]] = "a %s" % kind
	return out


func basics_problems(comps: Array, items: Array, materials: Array, lines: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for c in comps:
		var at := _at("components", c)
		var s = c.get("size")
		if str(c.get("name", "")) == "":
			out.append(at + ": has no name")
		if str(c.get("family", "")) == "":
			out.append(at + ": has no family")
		if not (s is Array and s.size() == 2 and (s[0] is float or s[0] is int) and (s[1] is float or s[1] is int) and s[0] >= 1 and s[1] >= 1):
			out.append(at + ": size must be [width, height] in cells")
		if not lines.is_empty() and not lines.has(str(c.get("line", Stats.DEFAULT_LINE))):
			out.append("%s: unknown line '%s'" % [at, c.get("line")])
		if int(c.get("tier", 1)) < 1:
			out.append(at + ": tier must be 1 or more")
		if c.has("stats") and not c["stats"] is Dictionary:
			out.append(at + ": stats must be an object")
	for e in items:
		if str(e.get("name", "")) == "" or not ITEM_KINDS.has(str(e.get("kind", ""))):
			out.append("%s: needs a name and a kind (%s)" % [_at("items", e), ", ".join(ITEM_KINDS)])
	for e in materials:
		if str(e.get("name", "")) == "" or not RARITIES.has(str(e.get("rarity", ""))):
			out.append("%s: needs a name and a rarity (%s)" % [_at("materials", e), ", ".join(RARITIES)])
	return out


func recipe_problems(recipes: Array, known: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for r in recipes:
		var at := _at("recipes", r)
		var o = r.get("output")
		if not (o is Dictionary and o.has("item")):
			out.append(at + ": has no output.item")
		elif not known.has(str(o["item"])):
			out.append("%s: makes '%s', which is not a component, an item or a material" % [at, o["item"]])
		var m = r.get("materials", {})
		if not m is Dictionary:
			out.append(at + ": materials must be an object of id -> count")
			continue
		for id in m:
			if not known.has(str(id)):
				out.append("%s: needs '%s', which is not a component, an item or a material" % [at, id])
	return out


func weapon_problems(comps: Array, weapons: Array) -> Array[String]:
	var out: Array[String] = []
	var have := {}
	for w in weapons:
		have[w["id"]] = true
	var parts := {}
	for c in comps:
		if c.get("family") == "weapon":
			parts[c["id"]] = true
			if not have.has(c["id"]):
				out.append(_at("components", c) + ": a weapon part needs an entry in weapons.json under its id")
	for w in weapons:
		if not parts.has(w["id"]) and not str(w["id"]).begins_with("test_"):  # test_ ids are fired by the arena without a part
			out.append(_at("weapons", w) + ": no weapon component has this id")
	return out


func ability_problems(comps: Array) -> Array[String]:
	var out: Array[String] = []
	for c in comps:
		var abilities = c.get("abilities", [])
		if not abilities is Array:
			out.append(_at("components", c) + ": abilities must be a list")
			continue
		for a in abilities:
			if not a is Dictionary:
				out.append(_at("components", c) + ": an ability must be an object")
				continue
			var at := "%s: ability '%s'" % [_at("components", c), a.get("id", "?")]
			if str(a.get("id", "")) == "":
				out.append(at + " has no id")
			if a.has("key") and not Abilities.KEYS.has(str(a["key"])):
				out.append("%s: key '%s' is not one of %s" % [at, a["key"], ", ".join(Abilities.KEYS)])
			if a.has("type") and not ["active", "passive"].has(str(a["type"])):
				out.append("%s: type must be active or passive, not '%s'" % [at, a["type"]])
			var effects = a.get("effects", {})
			if not effects is Dictionary:
				out.append(at + ": effects must be an object")
			else:
				for k in effects:
					if not Abilities.EFFECTS.has(str(k)):
						out.append("%s: effect '%s' is not one of %s" % [at, k, ", ".join(Abilities.EFFECTS)])
			var side = a.get("side_effects", [])
			if not side is Array:
				out.append(at + ": side_effects must be a list")
				continue
			for s in side:
				var t := str(s.get("type", "")) if s is Dictionary else ""
				if not Abilities.SIDE_EFFECTS.has(t):
					out.append("%s: side effect type '%s' is not one of %s" % [at, t, ", ".join(Abilities.SIDE_EFFECTS)])
	return out


func ship_problems(ships: Array, components: Dictionary, tiles: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for s in ships:
		var d: Dictionary = s["design"]
		var at := "%s: ship '%s'" % [s["path"], s["id"]]
		var seen := {}
		var comps = d.get("components", {})
		for inst in comps.get("instances", []) if comps is Dictionary else []:
			var id := str(inst.get("id", "")) if inst is Dictionary else ""
			if not components.has(id) and not seen.has(id):
				seen[id] = true
				out.append("%s: component '%s' does not exist" % [at, id])
		for t in d.get("tiles", []):
			var id := str(t[2]) if t is Array and t.size() >= 3 else ""
			if not tiles.has(id) and not seen.has(id):
				seen[id] = true
				out.append("%s: tile '%s' does not exist" % [at, id])
	return out


func species_problems(species: Array, traits: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for s in species:
		for t in s.get("traits", []):
			if not traits.has(str(t)):
				out.append("%s: trait '%s' is not defined" % [_at("species", s), t])
	return out


## Problems in the trait keys of one entry (a trait, or a species with keys inline): a key that is not in
## TraitSet.KEYS (only `strict` entries, the traits; a species has fields of its own), a group that is not an
## object of known sub-keys, a value that is not a number (a flag for the keys in TraitSet.FLAGS), a `body` that is not 1 or 2.
func _key_problems(at: String, e: Dictionary, strict: bool) -> Array[String]:
	var out: Array[String] = []
	for k in e:
		if not TraitSet.KEYS.has(k):
			if strict and not TraitSet.META.has(k):
				out.append("%s: uses the unknown key '%s' (known: %s)" % [at, k, ", ".join(TraitSet.KEYS.keys())])
			continue
		var subs: Array = TraitSet.KEYS[k]
		var v = e[k]
		if TraitSet.OPEN.has(k):
			out.append_array(TraitSet.extra_problems(at, k, v))
		elif subs.is_empty():
			var flag: bool = TraitSet.FLAGS.has(k)
			if not (v is bool if flag else (v is float or v is int)):
				out.append("%s: '%s' must be %s" % [at, k, "true or false" if flag else "a number"])
			elif k == "body" and not TraitSet.BODIES.has(int(v)):
				out.append("%s: 'body' must be %s" % [at, " or ".join(TraitSet.BODIES.map(func(b): return str(b)))])
		elif not v is Dictionary:
			out.append("%s: '%s' must be an object of %s" % [at, k, ", ".join(subs)])
		else:
			for sub in v:
				if not subs.has(sub):
					out.append("%s: '%s' has the unknown key '%s' (known: %s)" % [at, k, sub, ", ".join(subs)])
				elif not (v[sub] is float or v[sub] is int):
					out.append("%s: '%s.%s' must be a number" % [at, k, sub])
			out.append_array(TraitSet.extra_problems(at, k, v))
	return out


## Every trait of the library uses only known keys (TraitSet.KEYS) with numbers in them, and has a name.
func trait_problems(traits: Array) -> Array[String]:
	var out: Array[String] = []
	for t in traits:
		var at := _at("traits", t)
		if str(t.get("name", "")) == "":
			out.append(at + ": has no name")
		out.append_array(_key_problems(at, t, true))
	return out


## Species with trait keys inline use known ones, and the personal traits of crew.json exist in the library.
func crew_key_problems(species: Array, personal: Dictionary, traits: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for s in species:
		out.append_array(_key_problems(_at("species", s), s, false))
	for who in personal:
		for t in personal[who]:
			if not traits.has(str(t)):
				out.append("res://data/crew.json: traits of '%s': trait '%s' is not defined" % [who, t])
	return out


## The shape of the bands table, and every part of a family that has bands against its band.
func balance_problems(comps: Array, table: Dictionary, lines: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if table.is_empty() or not table.get("bands") is Dictionary:
		return ["%s: missing, or has no \"bands\"" % Balance.PATH]
	for family in table["bands"]:
		for tier in table["bands"][family]:
			var stats = table["bands"][family][tier]
			if not (str(tier).is_valid_int() and stats is Dictionary and not stats.is_empty()):
				out.append("%s: bands.%s.%s must be an object of stat -> number" % [Balance.PATH, family, tier])
				continue
			for stat in stats:
				if not (stats[stat] is float or stats[stat] is int):
					out.append("%s: bands.%s.%s.%s must be a number" % [Balance.PATH, family, tier, stat])
	var waivers = table.get("waivers", {})
	if not waivers is Dictionary:
		return out + ["%s: waivers must be an object of part id -> reason" % Balance.PATH]
	for id in waivers:
		if str(waivers[id]).strip_edges() == "":
			out.append("%s: the waiver for '%s' needs a reason" % [Balance.PATH, id])
		if not Content.has("components", str(id)):
			out.append("%s: the waiver for '%s' names no component" % [Balance.PATH, id])
	for c in comps:
		var r := Balance.check(table, c, lines)
		match r["status"]:
			"fail":
				for p in r["problems"]:
					out.append("%s: %s (fix it, give the part a quirk, or ask the lead for a waiver)" % [_at("components", c), p])
			"no_band":
				out.append("%s: %s" % [_at("components", c), r["problems"][0]])
			"stale_waiver":
				out.append("%s: the waiver in %s is not needed (the part is within its band, or exempt): remove it" % [_at("components", c), Balance.PATH])
	return out


## The component ids with no art of their own (art/components/<id>.png). A report, not a failure.
func missing_art() -> Array[String]:
	var out: Array[String] = []
	for id in Content.ids("components"):
		if not Content.has_art(id):
			out.append(id)
	return out


## Every trait a species may name: the library (data/traits.json, the packs, and the old table in species.json).
func _known_traits() -> Dictionary:
	return TraitSet.library()


func _tile_ids() -> Dictionary:
	var out := {}
	for id in Content.ids("tiles"):
		out[id] = true
	return out


func _component_ids() -> Dictionary:
	var out := {}
	for id in Content.ids("components"):
		out[id] = true
	return out


## The Drift's validator, when scripts/space/events.gd is on main and has one.
func event_problems() -> Array[String]:
	var out: Array[String] = []
	if not ResourceLoader.exists(EVENTS_SCRIPT):
		return out
	var script = load(EVENTS_SCRIPT)
	var ev = script.shared() if script.has_method("shared") else script.new()
	if ev != null and ev.has_method("validate"):
		for msg in ev.validate():
			out.append(str(msg))
	return out


## Every rule above on whatever Content holds now.
func all_problems() -> Array[String]:
	var lines := Stats.load_lines()
	var out: Array[String] = []
	out.append_array(Content.errors())
	out.append_array(collision_problems())
	out.append_array(basics_problems(Content.list("components"), Content.list("items"), Content.list("materials"), lines))
	out.append_array(recipe_problems(Content.list("recipes"), _cargo_ids()))
	out.append_array(weapon_problems(Content.list("components"), Content.list("weapons")))
	out.append_array(ability_problems(Content.list("components")))
	out.append_array(ship_problems(Content.ships(), _component_ids(), _tile_ids()))
	out.append_array(species_problems(Content.list("species"), _known_traits()))
	out.append_array(trait_problems(Content.list("traits")))
	out.append_array(crew_key_problems(Content.list("species"), CrewMember.config().get("traits", {}), _known_traits()))
	out.append_array(balance_problems(Content.list("components"), Balance.load_table(), lines))
	out.append_array(CrewAbilities.problems())  # the ability vocabulary, species abilities and every unique character
	out.append_array(event_problems())
	return out


func _none(problems: Array[String]) -> void:
	for p in problems:
		check(false, p)


func _has_line(problems: Array[String], parts: Array) -> bool:
	for p in problems:
		var all := true
		for part in parts:
			all = all and p.contains(part)
		if all:
			return true
	return false


# --- the real data --------------------------------------------------------------------------------

func test_every_file_loads_and_every_id_is_unique() -> void:
	_none(Content.errors())
	_none(collision_problems())


func test_components_items_and_materials_have_their_basics() -> void:
	_none(basics_problems(Content.list("components"), Content.list("items"), Content.list("materials"), Stats.load_lines()))


func test_recipes_point_at_real_items_components_and_materials() -> void:
	_none(recipe_problems(Content.list("recipes"), _cargo_ids()))


func test_every_weapon_part_has_weapon_stats_and_the_reverse() -> void:
	_none(weapon_problems(Content.list("components"), Content.list("weapons")))


func test_abilities_use_known_keys_effects_and_side_effects() -> void:
	_none(ability_problems(Content.list("components")))


func test_ships_use_real_components_and_tiles() -> void:
	check(Content.ships().size() >= 5, "the five design files are found")
	_none(ship_problems(Content.ships(), _component_ids(), _tile_ids()))


func test_species_use_defined_traits() -> void:
	_none(species_problems(Content.list("species"), _known_traits()))  # nothing to check until species.json is on main


func test_traits_use_only_known_keys() -> void:
	check(Content.list("traits").size() >= 17, "the library has the core traits and the packs'")
	_none(trait_problems(Content.list("traits")))
	_none(crew_key_problems(Content.list("species"), CrewMember.config().get("traits", {}), _known_traits()))


func test_events_pass_the_drift_validator_when_it_exists() -> void:
	_none(event_problems())


func test_regions_pass_the_region_rules() -> void:
	check(Content.regions().size() >= 15, "the 5 faction regions and the 10 homelands")
	_none(Regions.problems())  # the real data only (the homelands use pack species and parts); the rules: tests/test_regions.gd


func test_parts_are_within_their_balance_bands() -> void:
	_none(balance_problems(Content.list("components"), Balance.load_table(), Stats.load_lines()))


func test_art_presence_is_reported() -> void:
	var missing := missing_art()
	print("content: %d of %d placeable ids have no art of their own (the list is in docs/CONTENT_INDEX.md)" % [missing.size(), Content.ids("components").size()])
	check(missing.size() <= Content.ids("components").size(), "the count makes sense")


# --- the loader with no pack ------------------------------------------------------------------------

func test_read_gives_the_file_itself_when_no_pack_adds_to_it() -> void:
	_scenario("none")  # a folder with no packs
	for kind in Content.KINDS:
		var path := "res://data/%s.json" % kind
		if not FileAccess.file_exists(path):
			continue
		eq(JSON.stringify(Content.read(path)), JSON.stringify(JSON.parse_string(FileAccess.get_file_as_string(path))), kind + ".json is read back as it is")
	check(Content.read("res://data/weapons.json")["weapons"] is Dictionary, "weapons stay an object keyed by id")
	check(Content.read("res://data/components.json")["components"] is Array, "components stay a list")
	check(Content.read("res://data/recipes.json").has("start_known"), "recipes keep start_known")
	eq(JSON.stringify(Content.read("res://data/flight.json")), JSON.stringify(JSON.parse_string(FileAccess.get_file_as_string("res://data/flight.json"))), "another file is read as it is")
	_done()


func test_read_hands_out_copies() -> void:
	_scenario("none")
	var a = Content.read("res://data/components.json")
	a["components"][0]["hp"] = 999
	a["components"].pop_back()
	var b = Content.read("res://data/components.json")
	check(b["components"][0]["hp"] != 999 and b["components"].size() == a["components"].size() + 1, "changing what was read changes nothing for the next reader")
	var l := Content.list("components")
	l[0]["hp"] = 999
	check(Content.list("components")[0]["hp"] != 999, "nor does changing a list")
	_done()


func test_entries_know_where_they_came_from() -> void:
	check(Content.entry("components", "no_such_part").is_empty(), "no entry")
	eq(Content.origin("components", "engine_mk1"), "core", "core parts say so")
	eq(Content.origin("components", "no_such_part"), "", "and an unknown id has no origin")


# --- packs (the fixtures) -----------------------------------------------------------------------------

func _scenario(name: String) -> void:
	Content.packs_root = FIXTURES + name


func _done() -> void:
	Content.packs_root = ""


func test_root_can_point_at_a_fixture_folder() -> void:
	Content.root = "res://tests/fixtures/content_root"
	eq(Content.ids("components"), ["fx_core", "fx_packed"], "that folder's core file, then its packs/ folder")
	eq(Content.read("res://data/components.json")["components"].size(), 2, "and a loader asking for the real path gets it")
	eq(Content.list("weapons"), [], "a kind the folder lacks is empty")
	Content.root = Content.DATA_ROOT
	check(Content.has("components", "engine_mk1") and not Content.has("components", "fx_core"), "back to the real data")


func test_a_pack_adds_a_component_that_can_be_placed() -> void:
	_scenario("valid")
	var ship := Fixture.room_ship()
	check(ship.components.has("fx_thruster"), "the pack's component is defined")
	eq(ship.components.can_place(ship.grid, "fx_thruster", Vector2i(10, 10), 0), "", "and fits on the floor")
	check(Fixture.put(ship, "fx_thruster", 10, 10) >= 0, "and is placed")
	check(ship.crafting.recipes.has("fx_thruster"), "its recipe is there too")
	check(ship.components.has("engine_mk1"), "the core parts are still there")
	_done()
	check(not Fixture.room_ship().components.has("fx_thruster"), "without the pack it is gone again")


func test_a_pack_adds_weapons_items_events_ships_and_names() -> void:
	_scenario("valid")
	_none(Content.errors())
	check(Weapons.new().has("fx_gun"), "a weapon stat entry")
	check(Content.read("res://data/weapons.json")["weapons"] is Dictionary and Content.has("weapons", "laser_mk1"), "in the core's own shape, next to the core ones")
	check(Content.has("items", "fx_widget") and Content.has("events", "fx_event"), "an item and an event")
	var ship: Dictionary = Content.entry("ships", "fx_ship")
	check(ship.get("pack") == "a_first" and ship["design"]["name"] == "Fixture Ship", "a ship design")
	eq(Content.names()["fixture_pool"], ["Fixture Fenn", "Second Fenn"], "name pools join, without repeats")
	eq(Content.origin("components", "fx_gun"), "a_first", "the origin of a pack's part")
	eq(Content.file_of("components", "fx_gun"), FIXTURES + "valid/a_first/components.json", "and its file")
	_done()


func test_the_fixture_pack_passes_every_rule() -> void:
	_scenario("valid")
	_none(all_problems())
	_done()


func test_packs_load_in_alphabetical_order() -> void:
	_scenario("valid")
	_scenario("none")
	var core: Array = Content.ids("components")
	_scenario("valid")
	var ids: Array = Content.packs().map(func(p): return p["id"])
	eq(ids, ["a_first", "b_second"], "pack order")
	var parts: Array = Content.ids("components")
	eq(parts.slice(0, core.size()), core, "the core parts come first, in file order")
	eq(parts.slice(core.size()), ["fx_thruster", "fx_gun", "fx_engine_b"], "then a_first, then b_second, each in file order")
	_done()


func test_a_duplicate_id_is_an_error_that_names_the_file_and_id() -> void:
	_scenario("duplicate")
	var errs := Content.errors()
	eq(errs.size(), 1, "one error")
	check(_has_line(errs, ["duplicate", "fx_dup", FIXTURES + "duplicate/b_two/components.json", FIXTURES + "duplicate/a_one/components.json"]), "it names the id, the second file and the first")
	eq(Content.origin("components", "fx_dup"), "a_one", "the first one stays")
	eq(Content.entry("components", "fx_dup")["name"], "First Dup", "unchanged")
	_done()


func test_an_override_with_a_reason_replaces_the_entry() -> void:
	_scenario("override")
	_none(Content.errors())
	eq(Content.entry("components", "fx_x")["hp"], 9, "the later entry wins")
	eq(Content.entry("components", "fx_x")["name"], "Over X", "whole, not merged")
	eq(Content.origin("components", "fx_x"), "b_over", "and says where it came from")
	eq(Content.ids("components").count("fx_x"), 1, "one entry")
	var o := Content.overrides()
	eq(o.size(), 1, "one override is on record")
	eq([o[0]["id"], o[0]["pack"], o[0]["replaced"]], ["fx_x", "b_over", "a_base"], "which")
	check(str(o[0]["reason"]).contains("tougher"), "with its reason")
	_done()


func test_an_override_needs_a_reason_and_something_to_override() -> void:
	_scenario("override_bad")
	var errs := Content.errors()
	eq(errs.size(), 2, "two errors")
	check(_has_line(errs, ["fx_y", "non-empty reason", "c_noreason/components.json"]), "no reason")
	check(_has_line(errs, ["fx_z", "no earlier file defines it", "d_orphan/components.json"]), "nothing to override")
	eq(Content.entry("components", "fx_y")["hp"], 5, "an override without a reason changes nothing")
	_done()


func test_a_pack_with_a_fault_in_its_pack_json_is_an_error() -> void:
	_scenario("badmeta")
	var errs := Content.errors()
	check(_has_line(errs, ["no_requires/pack.json", "missing field 'requires'"]), "no requires")
	check(_has_line(errs, ["no_pack_json/pack.json", "missing"]), "no pack.json")
	check(_has_line(errs, ["bad_id/pack.json", "other_name", "folder name"]), "id is not the folder")
	check(_has_line(errs, ["orphan/pack.json", "requires pack 'ghost'"]), "requires a pack nobody has")
	check(_has_line(errs, ["typo_file/compnents.json", "not a file a pack reads"]), "a misspelt file name")
	check(_has_line(errs, ["broken_json/components.json", "not valid JSON"]), "broken JSON")
	eq(errs.size(), 6, "and nothing else: " + str(errs))
	_done()


# --- the rules catch what they are for ----------------------------------------------------------------

func test_the_recipe_rule_catches_unknown_references() -> void:
	var known := {"scrap": true, "laser_mk1": true}
	var recipes := [
		{"id": "ok", "output": {"item": "laser_mk1", "count": 1}, "materials": {"scrap": 3}},
		{"id": "bad_out", "output": {"item": "ghost", "count": 1}, "materials": {"scrap": 3}},
		{"id": "bad_in", "output": {"item": "laser_mk1", "count": 1}, "materials": {"unobtainium": 3}},
	]
	var p := recipe_problems(recipes, known)
	eq(p.size(), 2, "two problems")
	check(_has_line(p, ["bad_out", "'ghost'"]) and _has_line(p, ["bad_in", "'unobtainium'"]), "each names its recipe and the missing id")


func test_the_weapon_rule_catches_a_missing_entry_and_a_stray_one() -> void:
	var comps := [{"id": "gun_a", "family": "weapon"}, {"id": "gun_b", "family": "weapon"}, {"id": "engine_a", "family": "engine"}]
	var p := weapon_problems(comps, [{"id": "gun_a"}, {"id": "gun_c"}, {"id": "test_bolt"}])
	eq(p.size(), 2, "two problems")
	check(_has_line(p, ["gun_b", "needs an entry"]) and _has_line(p, ["gun_c", "no weapon component"]), "the part without stats, the stats without a part (test_ ids are fine)")


func test_the_ability_rule_catches_unknown_keys_effects_and_side_effects() -> void:
	var good := {"id": "a", "type": "active", "key": "engine", "effects": {"stat_mult": {"thrust": 1.2}}, "side_effects": [{"type": "heat", "rate": 3}]}
	var comps := [
		{"id": "fine", "abilities": [good]},
		{"id": "odd", "abilities": [{"id": "b", "key": "cargo", "effects": {"teleport": 1}, "side_effects": [{"type": "explode"}]}]},
	]
	var p := ability_problems(comps)
	eq(p.size(), 3, "three problems: " + str(p))
	check(_has_line(p, ["odd", "key 'cargo'"]) and _has_line(p, ["effect 'teleport'"]) and _has_line(p, ["side effect type 'explode'"]), "key, effect and side effect")


func test_the_ship_rule_catches_unknown_components_and_tiles() -> void:
	var ship := {"id": "s", "path": "p.json", "design": {"components": {"instances": [{"id": "laser_mk1"}, {"id": "ghost_part"}]}, "tiles": [[0, 0, "floor"], [1, 0, "ghost_tile"], [2, 0, "ghost_tile"]]}}
	var p := ship_problems([ship], {"laser_mk1": true}, {"floor": true})
	eq(p.size(), 2, "two problems, a tile once")
	check(_has_line(p, ["ship 's'", "component 'ghost_part'"]) and _has_line(p, ["tile 'ghost_tile'"]), "each names the ship and the id")


func test_the_species_rule_catches_an_undefined_trait() -> void:
	var p := species_problems([{"id": "fenn", "traits": ["fast_repair", "telepathy"]}], {"fast_repair": true})
	eq(p.size(), 1, "one problem")
	check(_has_line(p, ["fenn", "'telepathy'"]), "it names the species and the trait")


func test_the_trait_rule_catches_unknown_keys_and_bad_values() -> void:
	var good := {"id": "ok", "name": "Fine", "o2_use": 0.5, "mechanical": true, "work_mult": {"repair": 1.2}, "blurb": "words"}
	eq(trait_problems([good]).size(), 0, "a good bag")
	var p := trait_problems([
		{"id": "typo", "name": "Typo", "work_mults": {"repair": 2}},
		{"id": "sub", "name": "Sub", "work_mult": {"welding": 2}},
		{"id": "shape", "name": "Shape", "damage_taken": 2, "o2_use": "none", "mechanical": 1},
		{"id": "nameless", "o2_use": 0},
	])
	eq(p.size(), 6, "six problems: " + str(p))
	check(_has_line(p, ["typo", "unknown key 'work_mults'"]) and _has_line(p, ["sub", "'welding'"]), "a key and a sub-key, named with the trait")
	check(_has_line(p, ["shape", "'damage_taken' must be an object"]) and _has_line(p, ["shape", "'o2_use' must be a number"]) and _has_line(p, ["shape", "'mechanical' must be true or false"]), "values of the wrong kind")
	check(_has_line(p, ["nameless", "no name"]), "a name is needed")
	var q := crew_key_problems([{"id": "odd", "hp": 5, "work_mult": {"repair": "fast"}}], {"Rook": ["suit", "levitation"]}, {"suit": true})
	eq(q.size(), 2, "a species with a bad inline key, a personal trait that does not exist: " + str(q))
	check(_has_line(q, ["odd", "work_mult.repair"]) and _has_line(q, ["Rook", "'levitation'"]), "each names where it is")


func test_the_balance_rule_checks_a_part_against_its_band() -> void:
	var table := {"tolerance": 0.2, "bands": {"engine": {"1": {"thrust": 10, "power": -2, "hp": 6}}}, "waivers": {}}
	var lines := Stats.load_lines()
	var with := func(over: Dictionary) -> Dictionary:
		var d: Dictionary = ENGINE.duplicate(true)
		d.merge(over, true)
		return d
	eq(Balance.check(table, ENGINE, lines)["status"], "ok", "on the band")
	eq(Balance.check(table, with.call({"stats": {"thrust": 11.9}}), lines)["status"], "ok", "19% over is fine")
	var off: Dictionary = Balance.check(table, with.call({"stats": {"thrust": 13}}), lines)
	eq(off["status"], "fail", "30% over fails")
	check(str(off["problems"][0]).contains("thrust") and str(off["problems"][0]).contains("30%"), "and says which stat and by how much")
	eq(Balance.check(table, with.call({"hp": 4}), lines)["status"], "fail", "another stat: hp 4 against 6")
	eq(Balance.check(table, with.call({"stats": {}}), lines)["status"], "fail", "a missing stat")
	eq(Balance.check(table, with.call({"stats": {"thrust": 13}, "abilities": [{"id": "boost"}]}), lines)["status"], "quirk", "an ability is a quirk")
	eq(Balance.check(table, with.call({"stats": {"thrust": 13}, "quirk": "loud"}), lines)["status"], "quirk", "so is a quirk text")
	eq(Balance.check(table, with.call({"stats": {"thrust": 13}, "unique": true}), lines)["status"], "unique", "a unique is not held to the bands")
	eq(Balance.check(table, with.call({"tier": 4}), lines)["status"], "no_band", "no band for the tier")
	eq(Balance.check(table, {"id": "g", "family": "gun", "tier": 1}, lines)["status"], "none", "a family without bands")
	var neon: Dictionary = with.call({"line": "neon"})
	eq(Balance.check(table, neon, lines)["status"], "ok", "a line multiplies the band: Neon thrust 10 is the Standard 10 times the line, so it is on band")
	var waived := table.duplicate(true)
	waived["waivers"] = {"x": "old data"}
	eq(Balance.check(waived, with.call({"stats": {"thrust": 13}}), lines)["status"], "waived", "a waiver excuses a part that is off")
	eq(Balance.check(waived, ENGINE, lines)["status"], "stale_waiver", "and is flagged once the part is fine")
	var p := balance_problems([ENGINE], waived, lines)
	check(_has_line(p, ["waiver", "'x'"]), "which the rule reports (and a waiver for no component): " + str(p))
