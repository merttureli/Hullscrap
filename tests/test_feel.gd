extends "res://tests/base_test.gd"
## Flying and controls (the playtest 2 "feel" round): the soldier's screen-relative WASD, the mouse wheel over panels.

const BuildMode = preload("res://scripts/build/build_mode.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Characters = preload("res://scripts/crew/characters.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Endings = preload("res://scripts/space/endings.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")

const UP := Vector2(0, -1)  ## W on the screen


func _near(got: Vector2, want: Vector2, msg: String) -> void:
	check(got.distance_to(want) < 0.001, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func test_screen_up_in_the_ships_frame_follows_the_way_it_is_drawn() -> void:
	_near(CrewView.screen_to_grid(UP, 0.0), Vector2(0, -1), "unturned: up is grid -y")
	_near(CrewView.screen_to_grid(UP, PI), Vector2(0, 1), "bow down the screen: up is grid +y")
	_near(CrewView.screen_to_grid(UP, PI / 2.0), Vector2(-1, 0), "turned a quarter clockwise: up is grid -x")
	_near(CrewView.screen_to_grid(UP, -PI / 2.0), Vector2(1, 0), "turned a quarter the other way: up is grid +x")
	_near(CrewView.screen_to_grid(Vector2(1, 0), PI), Vector2(-1, 0), "right on the screen is grid -x with the ship turned round")
	_near(CrewView.screen_to_grid(Vector2.ZERO, 1.0), Vector2.ZERO, "no keys, no move")
	var diag := CrewView.screen_to_grid(Vector2(1, -1), PI / 4.0)  # W+D, ship turned an eighth: an axis in the grid
	_near(diag.normalized(), Vector2(0, -1), "a diagonal on the screen can be an axis in the grid")


func test_wasd_reads_the_angle_the_view_is_drawn_at() -> void:
	var view := CrewView.new()
	_key(KEY_W, true)
	_near(view._wasd(), Vector2(0, -1), "W, ship unturned (build mode)")
	view.rotation = PI
	_near(view._wasd(), Vector2(0, 1), "W with the ship drawn at PI")
	view.rotation = PI / 2.0
	_near(view._wasd(), Vector2(-1, 0), "W with the ship drawn at PI/2")
	_key(KEY_W, false)
	_key(KEY_D, true)
	view.rotation = PI
	_near(view._wasd(), Vector2(-1, 0), "D with the ship drawn at PI")
	_key(KEY_D, false)
	_near(view._wasd(), Vector2.ZERO, "nothing held")
	view.free()


# --- the wheel over a panel -------------------------------------------------------------------------

func _wheel(at: Vector2, up := true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.position = at
	e.global_position = at
	return e


func test_the_wheel_over_a_panel_scrolls_it_and_never_zooms_but_over_the_world_it_zooms() -> void:
	var sim := ShipSim.new()
	sim.ships = [Fixture.room_ship()]
	var b := BuildMode.new()
	b.sim = sim
	b.cam = Camera2D.new()
	b.hud = Hud.new()
	b.hud.setup(b)
	b.hud.layout(Vector2(1600.0, 500.0))  # short, so the palette has something to scroll
	var palette: Control = b.hud.palette
	check(palette._max_scroll() > 0.0, "the palette has more cards than fit")
	var before: Vector2 = b.cam.zoom
	var panels := {"palette": palette, "card": b.hud.card, "top bar": b.hud.top_bar, "mode bar": b.hud.mode_bar, "log": b.hud.log_panel}
	for name in panels:
		var c: Control = panels[name]
		b.wheel(_wheel(c.position + c.size / 2.0, false))
		eq(b.cam.zoom, before, "the wheel over the %s leaves the zoom alone" % name)
	var inside: Vector2 = palette.position + palette.size / 2.0
	palette._gui_input(_wheel(inside, false))  # the panel gets the event and scrolls
	check(palette.scroll > 0.0, "the palette scrolled: %s" % palette.scroll)
	b.wheel(_wheel(inside, false))
	eq(b.cam.zoom, before, "still no zoom")
	var open := Vector2(800.0, 200.0)  # between the side panels
	check(not b.hud.over_ui(open), "(nothing there)")
	b.wheel(_wheel(open, true))
	check(b.cam.zoom.x > before.x, "the wheel over the world zooms in: %s" % str(b.cam.zoom))
	b.wheel(_wheel(open, false))
	b.wheel(_wheel(open, false))
	check(b.cam.zoom.x < before.x, "and out: %s" % str(b.cam.zoom))
	b.cam.free()
	b.hud.free()
	sim.free()
	b.free()


func test_the_wheel_is_told_from_other_mouse_events() -> void:
	for up in [true, false]:
		check(UiKit.is_wheel(_wheel(Vector2.ZERO, up)), "a wheel step")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	check(not UiKit.is_wheel(click), "a click is not")
	check(not UiKit.is_wheel(InputEventMouseMotion.new()), "nor is a motion")
	check(not UiKit.is_wheel(InputEventKey.new()), "nor a key")


# --- repairs take longer -----------------------------------------------------------------------------

func test_repairs_take_about_twice_as_long_as_in_beta_2() -> void:
	var j: Dictionary = Jobs.jcfg()
	eq(float(j["repair_breach"]["seconds"]), 14.0, "a breach: 14 s (was 6)")
	eq(float(j["repair_component"]["seconds"]), 12.0, "a part: 12 s (was 5)")
	eq(float(j["repair_crew"]["rate"]), 4.0, "mending a machine crew member: 4 hp a second (was 8)")
	eq(float(j["repair_belt"]["seconds"]), 4.0, "a belt cell: 4 s (was 2)")
	eq(float(j["extinguish"]["rate"]), 0.5, "fires are put out as fast as before")


# --- Continue keeps the crew -------------------------------------------------------------------------

func _person(who: String, species: String, x: int, y: int) -> CrewMember:
	return CrewMember.new(who, Pathfinder.centre_of(Vector2i(x, y)), species)


## A ship with three crew: the soldier, Ada (hurt, with her ability cooling down) and a recruit who is a character
## and wears gear. One crew member has bled out (in dead_crew) and the design had a crew list.
func _crewed() -> Ship:
	var ship := Fixture.room_ship()
	var soldier := _person("Soldier", "human", 12, 12)
	soldier.is_player = true
	soldier.look = {"suit": "#2a5d8f", "hair": "#c9a46a", "tool": "#ffd24a"}
	var ada := _person("Ada", "human", 16, 13)
	ada.hp = 37.5
	ada.ability_cd = 12.25
	ada.look = {"suit": "#d9822b", "hair": "#4a2f1d", "tool": "#ffd24a"}
	var chars := Characters.ids()
	check(not chars.is_empty(), "(setup: the data has characters)")
	var recruit: CrewMember = CrewMember.from_character(chars[0], Pathfinder.centre_of(Vector2i(18, 11)))
	recruit.equip("suit")
	recruit.hp = recruit.max_hp * 0.5
	recruit.revived = true
	ship.crew.append_array([soldier, ada, recruit])
	ship.dead_crew.append("Fallen")
	ship.crew_plan = [{"name": "Soldier", "species": "human", "player": true}, {"name": "Ada", "species": "human"}]
	return ship


func _same_person(a: CrewMember, b: CrewMember) -> void:
	var tag: String = a.name
	eq(b.name, a.name, "%s: name" % tag)
	eq(b.species, a.species, "%s: species" % tag)
	eq(b.is_player, a.is_player, "%s: the soldier" % tag)
	eq(b.character, a.character, "%s: character" % tag)
	eq(b.look, a.look, "%s: look" % tag)
	eq(b.head, a.head, "%s: head" % tag)
	eq(b.gear_traits, a.gear_traits, "%s: gear" % tag)
	eq(b.hp, a.hp, "%s: hp" % tag)
	eq(b.max_hp, a.max_hp, "%s: max hp" % tag)
	eq(b.cell(), a.cell(), "%s: cell" % tag)
	eq(b.pos, a.pos, "%s: place" % tag)
	eq(b.ability, a.ability, "%s: ability" % tag)
	eq(b.ability_cd, a.ability_cd, "%s: ability cooldown" % tag)
	eq(b.revived, a.revived, "%s: revive spent" % tag)
	eq(b.speed, a.speed, "%s: speed" % tag)


func test_a_saved_ship_brings_its_crew_back_as_they_were() -> void:
	var ship := _crewed()
	var d: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))  # through the file, as Ctrl+S / Continue do
	eq(d["version"], 6, "saved as version 6")
	eq(d["crew_state"].size(), 3, "three people in the save")
	var back := Ship.new_starter()
	var stale := _person("Stale", "human", 5, 5)  # a crew member of the ship that was loaded into
	back.crew.append(stale)
	back.dead_crew.append("Ghost")
	eq(back.load_dict(d), "", "loads")
	eq(back.crew.size(), 3, "the same three, not the ones that were aboard before")
	check(not back.crew.has(stale), "(the old crew are gone)")
	for i in 3:
		_same_person(ship.crew[i], back.crew[i])
	eq(back.crew[2].character, ship.crew[2].character, "the recruit is still the character")
	check(back.crew[2].is_player == false and back.crew[0].is_player, "and the soldier is the soldier")
	eq(back.crew[1].hp, 37.5, "the hurt one is still hurt")
	eq(back.dead_crew, ["Fallen"], "the dead stay dead (and Ghost is not carried over)")
	eq(back.crew_plan, ship.crew_plan, "the design's crew list too")
	eq(back.to_dict()["crew_state"], d["crew_state"], "and saving again gives the same save")


func test_a_downed_crew_member_and_a_bleed_out_survive_a_save() -> void:
	var ship := Fixture.room_ship()
	var m := _person("Rook", "human", 12, 12)
	m.hp = 0.0
	m.down_t = 7.5
	ship.crew.append(m)
	var back := Ship.new_starter()
	eq(back.load_dict(JSON.parse_string(JSON.stringify(ship.to_dict()))), "", "loads")
	check(back.crew[0].is_down(), "still down")
	eq(back.crew[0].down_t, 7.5, "and still bleeding for as long")


func test_an_older_save_loads_and_leaves_the_crew_alone() -> void:
	var ship := _crewed()
	var d: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
	for k in ["crew_state", "dead_crew", "crew_plan"]:
		d.erase(k)
	d["version"] = 5  # a Beta 2 save
	var back := Ship.new_starter()
	var mate := _person("Mate", "human", 14, 14)
	back.crew.append(mate)
	eq(back.load_dict(d), "", "a version 5 save loads")
	eq(back.crew, [mate], "with the old behaviour: the crew the ship has stay (the view spawns the design's list)")
	var nobody := Ship.new_starter()
	eq(nobody.to_dict().has("crew_state"), false, "a ship with no crew writes none")
	var empty := _crewed()
	empty.crew.clear()
	empty.dead_crew.clear()
	eq(empty.to_dict().has("crew_state"), false, "nor one that has nobody and no dead")


func test_a_malformed_crew_in_a_save_is_refused_and_changes_nothing() -> void:
	var d: Dictionary = JSON.parse_string(JSON.stringify(_crewed().to_dict()))
	var back := Ship.new_starter()
	var mate := _person("Mate", "human", 14, 14)
	back.crew.append(mate)
	var before: Vector2i = back.grid.size
	var bad := d.duplicate(true)
	bad["crew_state"][1] = {"name": "NoPlace"}
	check(back.load_dict(bad) != "", "a person with no place is refused")
	bad = d.duplicate(true)
	bad["crew_state"] = "three"
	check(back.load_dict(bad) != "", "a crew that is not a list is refused")
	bad = d.duplicate(true)
	bad["crew_plan"] = [5]
	check(back.load_dict(bad) != "", "a crew list that is not entries is refused")
	eq(back.crew, [mate], "the crew did not change")
	eq(back.grid.size, before, "nor did the ship")


func test_a_hall_of_ships_design_is_not_a_saved_run() -> void:
	var ship := _crewed()
	var design := Endings.design_of(ship)
	for k in ["crew_state", "dead_crew", "crew_plan"]:
		check(not design.has(k), "the design has no %s" % k)
	eq(design["crew"].size(), 3, "just its crew list [{name, species}]")
