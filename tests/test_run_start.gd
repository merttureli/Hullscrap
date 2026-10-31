extends "res://tests/base_test.gd"
## The unlocks that do something at the start of a run (docs/CONTENT.md sections 13 and 19, scripts/space/run_start.gd): a starting
## species swaps the soldier, a blueprint is known from the start, a map variant starts the Hollow tide ahead, a hull skin tints
## the plating; and the hangar's new-run row that chooses them. All against the real unlocks of the endings pack.

const Campaign = preload("res://scripts/space/campaign.gd")
const Unlocks = preload("res://scripts/space/unlocks.gd")
const RunStart = preload("res://scripts/space/run_start.gd")
const Content = preload("res://scripts/data/content.gd")
const Profile = preload("res://scripts/ui/profile.gd")
const HangarView = preload("res://scripts/ui/hangar.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")

const TMP := "user://test_run_start_profile.json"
const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const FIXTURES := "res://tests/fixtures/packs/"


## A canvas that only remembers the colour every texture was drawn with.
class Rec:
	extends RefCounted
	var mods: Array = []

	func draw_texture_rect_region(_tex, _rect, _src, modulate := Color.WHITE, _transpose := false, _clip := true) -> void:
		mods.append(modulate)

	func draw_set_transform_matrix(_m) -> void:
		pass


func _clean() -> void:
	var dir := TMP.get_basename() + "_hall"
	if DirAccess.dir_exists_absolute(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


## A profile (in the temp file) that has earned `ids`.
func _profile(ids: Array) -> Profile:
	_clean()
	var p := Profile.new(TMP)
	for id in ids:
		p.unlock(str(id))
	return p


func _key(code: int, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	return e


func _crew_named(ship: Ship, who: String):
	for m in ship.crew:
		if m.name == who:
			return m
	return null


# --- the row of choices ---------------------------------------------------------------------------------------

func test_a_new_profile_has_nothing_to_choose() -> void:
	var p := _profile([])
	for slot in RunStart.SLOTS:
		eq(RunStart.options(p, slot).size(), 1, slot + ": only the default")
	check(not RunStart.has_choices(p), "so the row has no choices")
	eq(RunStart.blueprints(p), [], "and no blueprint is known from the start")
	eq(RunStart.clean({"species": "start_halcyon_gardener", "skin": "skin_lantern_lights"}, p), {"species": "", "variant": "", "skin": ""}, "an unlock it does not have is dropped")
	eq(RunStart.clean({}, null), {"species": "", "variant": "", "skin": ""}, "and null is nothing earned")
	_clean()


func test_the_row_offers_what_the_profile_has_and_cycles_over_it() -> void:
	var p := _profile(["start_halcyon_gardener", "start_basalt_gatewright", "map_hollow_tide", "skin_green_running_lights", "ship_halcyon_tender"])
	eq(RunStart.options(p, "species").map(func(o): return o["id"]), ["", "start_halcyon_gardener", "start_basalt_gatewright"], "the default, then the earned species in catalogue order")
	eq(RunStart.options(p, "variant").map(func(o): return o["id"]), ["", "map_hollow_tide"], "one map variant")
	eq(RunStart.options(p, "skin").map(func(o): return o["id"]), ["", "skin_green_running_lights"], "one skin; a starter ship is no choice of the row")
	check(RunStart.has_choices(p), "there is something to choose")
	var c := {}
	c = RunStart.cycle(c, p, "species", 1)
	eq(c["species"], "start_halcyon_gardener", "forward from the default")
	c = RunStart.cycle(c, p, "species", 1)
	c = RunStart.cycle(c, p, "species", 1)
	eq(c["species"], "", "wraps back to the default")
	c = RunStart.cycle(c, p, "species", -1)
	eq(c["species"], "start_basalt_gatewright", "and backwards from the default to the last")
	eq(RunStart.name_of(c, p, "species"), "Basalt Gatewright", "the row shows the unlock's name")
	eq(RunStart.name_of(c, p, "variant"), "Standard", "a slot at its default says so")
	_clean()


# --- species_start --------------------------------------------------------------------------------------------------

func test_a_starting_species_swaps_the_soldier() -> void:
	var p := _profile(["start_halcyon_gardener", "start_halcyon_scout"])
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	var before := ship.crew_plan.duplicate(true)
	var lines := RunStart.apply_ship(ship, {"species": "start_halcyon_gardener"}, p)
	eq(lines, ["Your soldier is Halcyon Gardener"], "it says what changed")
	eq(ship.crew_plan[0]["species"], "sporeling", "the soldier's entry is a Sporeling")
	eq(ship.crew_plan[0]["name"], "Soldier", "still called the soldier: the payload names no one")
	eq(ship.crew_plan.slice(1), before.slice(1), "the rest of the crew is as designed")
	Jobs.spawn_crew(ship)
	var me = _crew_named(ship, "Soldier")
	check(me != null and me.is_player and me.species == "sporeling", "aboard, the soldier is the player's, and a Sporeling")
	eq(ship.crew.size(), before.size(), "no one is added or lost")
	# a named soldier
	ship = Ship.from_design(RUSTBUCKET)
	RunStart.apply_ship(ship, {"species": "start_halcyon_scout"}, p)
	Jobs.spawn_crew(ship)
	me = _crew_named(ship, "Wick")
	check(me != null and me.is_player and me.species == "human", "Wick is the player's soldier, whatever his name")
	check(_crew_named(ship, "Soldier") == null, "and there is no second soldier")
	eq(ship.crew.filter(func(m): return m.is_player).size(), 1, "one player")
	_clean()


func test_a_starting_species_needs_the_unlock_and_a_crew_list() -> void:
	var p := _profile(["start_halcyon_scout"])
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	eq(RunStart.apply_ship(ship, {"species": "start_basalt_gatewright"}, p), [], "a species the profile has not earned is ignored")
	eq(ship.crew_plan[0]["species"], "human", "the soldier is as designed")
	var bare: Ship = Ship.new_starter()
	check(not RunStart.soldier(bare, "basalt"), "a ship with no crew list keeps its default crew")
	eq(bare.crew_plan, [], "untouched")
	var named: Ship = Ship.from_design(RUSTBUCKET)
	named.crew_plan = [{"name": "Rook", "species": "basalt"}]
	check(RunStart.soldier(named, "fenn", "Pip"), "a list with no soldier gets one at the front")
	eq(named.crew_plan[0], {"name": "Pip", "species": "fenn", "player": true}, "marked as the player's")
	_clean()


# --- blueprint ----------------------------------------------------------------------------------------------------

func test_blueprints_are_known_at_the_start_of_every_new_run() -> void:
	var p := _profile(["bp_lumen_siren", "bp_ma_shrapnel"])
	eq(RunStart.blueprints(p), ["shrapnel_cannon_scrap", "siren_ion_neon"], "the recipes of the earned blueprints")
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	check(not ship.crafting.is_known("siren_ion_neon"), "not known by the design")
	var lines := RunStart.apply_ship(ship, {}, p)
	check(ship.crafting.is_known("siren_ion_neon"), "known after the start")
	eq(lines, ["Known from the start: " + str(ship.components.def("siren_ion_neon").get("name"))], "with a line for it; Ma's Shrapnel was already known and says nothing")
	check(Ship.from_design(RUSTBUCKET).crafting.is_known("siren_ion_neon") == false, "a ship loaded again starts without it (the run's own state)")
	var back: Ship = Ship.from_design(RUSTBUCKET)
	back.load_dict(ship.to_dict())
	check(back.crafting.is_known("siren_ion_neon"), "and the ship's save keeps it")
	var plain: Ship = Ship.from_design(RUSTBUCKET)
	RunStart.apply_ship(plain, {}, _profile([]))
	check(not plain.crafting.is_known("siren_ion_neon"), "a profile without the unlock gets nothing")
	_clean()


# --- skin ---------------------------------------------------------------------------------------------------------

func test_a_skin_is_kept_on_the_ship_and_its_paint_comes_from_the_unlock() -> void:
	var p := _profile(["skin_lantern_lights"])
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	eq(ship.skin, "", "a ship has the plain hull")
	RunStart.apply_ship(ship, {"skin": "skin_lantern_lights"}, p)
	eq(ship.skin, "lantern_lights", "the skin id of the payload")
	var paint := Unlocks.skin_paint(ship.skin)
	check(paint.has("tint") and paint.has("lamp") and paint["tint"] is Color, "its paint is a tint and a lamp colour")
	eq(paint["lamp"], Color("#ffb347"), "the lamp colour is the payload's")
	var back: Ship = Ship.from_design(RUSTBUCKET)
	back.load_dict(ship.to_dict())
	eq(back.skin, "lantern_lights", "the ship's save keeps the skin")
	check(not Ship.from_design(RUSTBUCKET).to_dict().has("skin"), "and a plain ship writes none")
	RunStart.apply_ship(ship, {}, p)
	eq(ship.skin, "", "choosing the default takes it off")
	eq(Unlocks.skin_paint(""), {}, "no skin, no paint")
	eq(Unlocks.skin_paint("no_such_skin"), {}, "an unknown skin is the plain hull")
	_clean()


func test_the_hull_skin_tints_the_plating_and_lights_its_lamps() -> void:
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	var plan := TileArt.skin_plan(ship.grid)
	check(plan["cells"].size() > 0, "the ship has a skin to paint")
	var plain := Rec.new()
	TileArt.draw_skin(plain, plan, Vector2.ZERO, 32.0, 0.0)
	check(plain.mods.size() > 0, "it draws")
	var tinted := Rec.new()
	var paint := Unlocks.skin_paint("lantern_lights")
	TileArt.draw_skin(tinted, plan, Vector2.ZERO, 32.0, 0.0, null, paint)
	eq(tinted.mods.size(), plain.mods.size(), "the same pieces")
	eq(tinted.mods[0], plain.mods[0] * paint["tint"], "each plate is the line's tint times the skin's")
	check(tinted.mods[0] != plain.mods[0], "which is a different colour")
	var empty := Rec.new()
	TileArt.draw_skin(empty, plan, Vector2.ZERO, 32.0, 0.0, null, {})
	eq(empty.mods, plain.mods, "an empty paint is the plain hull")


# --- map_variant --------------------------------------------------------------------------------------------------

func test_a_map_variant_starts_the_hollow_tide_ahead_in_every_region() -> void:
	eq(Unlocks.tide_steps("hollow_tide"), 2, "the payload says two steps")
	eq(Unlocks.tide_steps("no_such_variant"), 0, "an unknown variant is nothing")
	var plain := Campaign.new(5)
	eq(plain.tide.steps, 0, "a normal run starts the tide at 0")
	var c := Campaign.new(5)
	c.set_variant("hollow_tide")
	eq(c.tide.steps, 2, "the variant starts it two steps on")
	check(c.flags.has("variant_hollow_tide"), "and sets its flag for the run")
	var far := ""
	for n in plain.drift.nodes:
		if plain.tide.jumps_until(str(n["id"])) > 2:
			far = str(n["id"])
			break
	check(far != "", "the region has a place the tide will take")
	eq(c.tide.jumps_until(far), plain.tide.jumps_until(far) - 2, "which falls two jumps sooner")
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	c.stage = 2
	c.enter_region("concord_space", ship)
	eq(c.tide.steps, 2, "the next region's tide starts ahead too")
	var d := c.to_dict()
	var back := Campaign.new(9)
	eq(back.load_dict(d), "", "the run saves and loads")
	check(back.flags.has("variant_hollow_tide"), "the variant survives it")
	back.stage = 3
	back.enter_region("lumen_space")
	eq(back.tide.steps, 2, "and still starts the tides ahead")
	plain.stage = 2
	plain.enter_region("concord_space")
	eq(plain.tide.steps, 0, "a run without it does not")


func test_the_map_applies_the_profiles_variant_to_a_new_campaign() -> void:
	var p := _profile(["map_hollow_tide"])
	var sim := ShipSim.new()
	sim.ships = [Ship.from_design(RUSTBUCKET)]
	var map := MapView.new()
	map.sim = sim
	map.profile = p
	map.size = Vector2(1600.0, 900.0)
	map.new_game(5)
	eq(map.campaign.tide.steps, 0, "nothing chosen: a normal tide")
	p.start = {"variant": "map_hollow_tide"}
	map.new_game(5)
	eq(map.campaign.tide.steps, 2, "the hangar's choice starts the new campaign's tide ahead")
	p.start = {"variant": "map_not_earned"}
	map.new_game(5)
	eq(map.campaign.tide.steps, 0, "a choice the profile does not back is ignored")
	map.free()
	sim.free()
	_clean()


# --- the Dead Gates are open only at the end ----------------------------------------------------------------------

func test_the_dead_gates_open_in_the_ending_region_only() -> void:
	var c := Campaign.new(2)
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	ship.inventory.add("fuel", 5)
	c.enter_region("gate_approaches")
	check(c.gate_dark("gate_1"), "in an early visit the gate is dark")
	c.current = c.drift.neighbours("gate_1")[0]
	eq(c.jump_block("gate_1", ship), Campaign.DARK_TEXT, "and the jump is refused")
	check(not c.gate_dark("n99"), "a node that does not exist is not a gate")
	c.stage = c.stages() + 1
	c.enter_region("gate_approaches")
	for g in ["gate_1", "gate_2", "gate_3"]:
		check(not c.gate_dark(g), g + " can be approached in the ending region")
		check(not c.is_hollow(g), g + " is never taken by the tide")
	c.current = c.drift.neighbours("gate_2")[0]
	eq(c.jump_block("gate_2", ship), "", "the ship may jump to the Scrapper Gate from a neighbour")
	c.current = "gate_2"
	c.visited["gate_2"] = true
	eq(c.arrive(ship)["node"]["type"], "gate", "and arrives at a gate")


# --- the unlock catalogue's own checks -----------------------------------------------------------------------------

func test_the_validator_checks_what_the_start_options_read() -> void:
	Content.packs_root = FIXTURES + "endings_bad"
	var u := Unlocks.validate()
	var has := func(parts: Array) -> bool: return u.any(func(m): return parts.all(func(p): return str(m).contains(p)))
	check(has.call(["bad_variant", "tide_steps"]), "a map variant with no tide_steps")
	check(has.call(["bad_tint", "tint must be a colour"]), "a tint that is no colour")
	check(has.call(["bad_name", "name must be a non-empty string"]), "a soldier's name that is empty")
	check(has.call(["bad_key", "unknown key 'colour'"]), "a payload key nobody reads")
	Content.packs_root = ""
	eq(Unlocks.validate(), [], "the real unlocks are sound")


# --- the hangar's row -----------------------------------------------------------------------------------------------

## A hangar on a sim of its own, wired like the scene, with the profile.
func _hangar(prof) -> Dictionary:
	var sim := ShipSim.new()
	var build := BuildMode.new()
	build.sim = sim
	var crew := CrewView.new()
	var cam := Camera2D.new()
	var h := HangarView.new()
	h.sim = sim
	h.build = build
	h.crew = crew
	h.cam = cam
	h.profile = prof
	build.picker = h
	h.size = Vector2(1600.0, 900.0)
	h.open()
	return {"h": h, "sim": sim, "build": build, "crew": crew, "cam": cam}


func _free_all(d: Dictionary) -> void:
	for k in d:
		d[k].free()


func test_the_hangar_row_cycles_with_keys_and_clicks() -> void:
	var p := _profile(["start_halcyon_gardener", "map_hollow_tide", "skin_lantern_lights", "skin_green_running_lights", "bp_lumen_siren"])
	var d := _hangar(p)
	var h: HangarView = d["h"]
	eq(h.start, {"species": "", "variant": "", "skin": ""}, "it opens on the defaults")
	h._input(_key(KEY_S))
	eq(h.start["species"], "start_halcyon_gardener", "S moves the soldier's species on")
	h._input(_key(KEY_S, true))
	eq(h.start["species"], "", "Shift+S goes back")
	h._input(_key(KEY_V))
	eq(h.start["variant"], "map_hollow_tide", "V is the map variant")
	h._input(_key(KEY_K))
	h._input(_key(KEY_K))
	eq(h.start["skin"], "skin_green_running_lights", "K steps through the skins")
	eq(h._row.map(func(o): return o["value"]), ["Ship's own", "The Tide Comes Early", "Green Running Lights"], "the row says what is chosen")
	eq(h._bp_names, ["The Quiet Lab's Siren"], "and lists the blueprints known from the start")
	var lay := h.layout()
	var panel: Rect2 = lay["panel"]
	for r in lay["opts"] + [lay["blueprints"]]:
		check(panel.encloses(r), "a cell of the row is inside the panel")
		check(not r.intersects(lay["map"]) and not r.intersects(lay["info"]), "and under the plan and the ship's numbers")
	check(not lay["button"].intersects(lay["opts"][2]), "the fly button is clear of the row")
	eq(h.zone_at(lay["opts"][0].get_center()), {"kind": "option", "index": 0}, "a cell is found")
	h.click(lay["opts"][0].get_center())
	eq(h.start["species"], "start_halcyon_gardener", "a click moves it on")
	h.click(lay["opts"][0].get_center(), true)
	eq(h.start["species"], "", "a right click goes back")
	_free_all(d)
	_clean()


func test_a_choice_with_nothing_earned_cannot_be_clicked() -> void:
	var p := _profile(["map_hollow_tide"])
	var d := _hangar(p)
	var h: HangarView = d["h"]
	var lay := h.layout()
	eq(h.zone_at(lay["opts"][0].get_center()), {}, "no species earned: the cell is dead")
	eq(h.zone_at(lay["opts"][1].get_center()), {"kind": "option", "index": 1}, "the variant is alive")
	h._input(_key(KEY_S))
	eq(h.start["species"], "", "and its key does nothing")
	_free_all(d)
	_clean()


func test_flying_a_ship_puts_the_row_on_it_and_remembers_it() -> void:
	var p := _profile(["start_halcyon_scout", "map_hollow_tide", "skin_lantern_lights", "bp_lumen_siren"])
	var d := _hangar(p)
	var h: HangarView = d["h"]
	h.cycle_option("species")
	h.cycle_option("variant")
	h.cycle_option("skin")
	eq(h.choose(h.sel), "", "the open ship is flown")
	var ship: Ship = d["sim"].player_ship()
	eq(ship.crew_plan[0], {"name": "Wick", "species": "human", "player": true}, "its soldier is Wick")
	eq(ship.skin, "lantern_lights", "it wears the skin")
	check(ship.crafting.is_known("siren_ion_neon"), "it knows the blueprint")
	eq(p.start, {"species": "start_halcyon_scout", "variant": "map_hollow_tide", "skin": "skin_lantern_lights"}, "the profile remembers the choice")
	eq(Profile.new(TMP).start["variant"], "map_hollow_tide", "in its file")
	h.open()
	eq(h.start["skin"], "skin_lantern_lights", "and the hangar opens on it next time")
	# fly again with the defaults
	h.start = {}
	h.cycle_option("species", 0)
	eq(h.choose(h.sel), "", "flown again with nothing chosen")
	ship = d["sim"].player_ship()
	eq(ship.crew_plan[0]["name"], "Soldier", "the soldier is the design's")
	eq(ship.skin, "", "with the plain hull")
	check(ship.crafting.is_known("siren_ion_neon"), "the blueprint is still known: it is not a choice")
	_free_all(d)
	_clean()
