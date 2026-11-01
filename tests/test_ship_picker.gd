extends "res://tests/base_test.gd"
## The "Choose your ship" picker without a screen: its cards, 1/2/3 and click, Esc, the Y/N question,
## N in play mode (BuildMode) and what choosing does to the ship, the crew, the camera and the build palette.

const ShipPicker = preload("res://scripts/ui/ship_picker.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")


## A picker on a sim of its own, with a build mode and a crew view wired in, opened.
func _picker() -> Dictionary:
	var sim := ShipSim.new()
	var build := BuildMode.new()
	build.sim = sim
	var crew := CrewView.new()
	var cam := Camera2D.new()
	var p := ShipPicker.new()
	p.sim = sim
	p.build = build
	p.crew = crew
	p.cam = cam
	build.picker = p
	p.size = Vector2(1600.0, 900.0)
	p.load_cards()
	p.open()
	return {"p": p, "sim": sim, "build": build, "crew": crew, "cam": cam}


func _done(d: Dictionary) -> void:
	for k in d:
		d[k].free()


func _press(node, code: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	if node is ShipPicker:
		node._input(e)
	else:
		node._on_key(e)


func test_three_cards_with_a_name_a_character_and_the_numbers() -> void:
	var d := _picker()
	var p: ShipPicker = d["p"]
	eq(p.cards.map(func(c): return c["name"]), ["Rustbucket", "Courier", "Prism"], "keys 1, 2, 3 in this order")
	for c in p.cards:
		check(c["blurb"].length() > 30, c["name"] + " has a one-line character")
		var st: Dictionary = c["stats"]
		check(st["supply"] >= st["demand"] and st["demand"] > 0.0, c["name"] + ": power supply covers demand")
		check(st["mass"] > 100.0 and st["hull"] >= 150.0 and st["layers"] >= 0, c["name"] + ": mass, armour and shield layers")
		check(st["weapons"].size() >= 1, c["name"] + " lists its weapon")
		check(c["schematic"].arena != null, c["name"] + " has a schematic bound to an arena")
	eq(p.cards[0]["stats"]["weapons"], ["Bolt Thrower", "Rattle Burst"], "Rustbucket weapons by name")
	eq(p.cards[1]["stats"]["weapons"], ["Pulse Mk1"], "Courier weapons by name")
	eq(p.cards[2]["stats"]["weapons"], ["Heat Lance"], "Prism weapons by name")
	eq([p.cards[0]["stats"]["layers"], p.cards[1]["stats"]["layers"], p.cards[2]["stats"]["layers"] > 0], [0, 1, true], "the Rustbucket has no shield, the Courier one layer and the Prism its lattice")
	check(p.cards[0]["stats"]["mass"] > p.cards[1]["stats"]["mass"] and p.cards[1]["stats"]["mass"] > p.cards[2]["stats"]["mass"], "masses: Rustbucket > Courier > Prism")
	check(p.cards[0]["stats"]["hull"] > p.cards[1]["stats"]["hull"] and p.cards[1]["stats"]["hull"] > p.cards[2]["stats"]["hull"], "hulls: Rustbucket > Courier > Prism")
	_done(d)


func test_the_cards_sit_side_by_side_in_the_middle() -> void:
	var d := _picker()
	var p: ShipPicker = d["p"]
	var panel := p.panel_rect()
	check(abs(panel.get_center().x - 800.0) < 1.0 and abs(panel.get_center().y - 450.0) < 1.0, "the panel is centred")
	for i in 3:
		check(panel.encloses(p.card_rect(i)), "card %d is inside the panel" % i)
		eq(p.card_at(p.card_rect(i).get_center()), i, "a point on card %d finds it" % i)
		eq(p.cards[i]["schematic"].position, p.card_rect(i).position + Vector2(10.0, 10.0), "the schematic sits at the top of card %d" % i)
	check(not p.card_rect(0).intersects(p.card_rect(1)) and p.card_rect(0).end.x < p.card_rect(1).position.x, "cards do not overlap")
	eq(p.card_at(Vector2(5.0, 5.0)), -1, "nothing out in the corner")
	_done(d)


func test_a_number_key_loads_that_design_into_the_players_ship() -> void:
	for i in 3:
		var d := _picker()
		var p: ShipPicker = d["p"]
		var sim: ShipSim = d["sim"]
		eq(sim.player_ship().name, "Starter", "the empty hull until a choice is made")
		_press(p, KEY_1 + i)
		var want: String = ["Rustbucket", "Courier", "Prism"][i]
		eq(sim.player_ship().name, want, "key %d loads the %s" % [i + 1, want])
		eq(sim.design_path, ShipPicker.DESIGNS[i], "the sim remembers the design")
		check(not p.visible, "the picker is put away")
		check(sim.player_ship().grid.tiles.size() > 200, "and it is a built ship")
		sim.step(0.1)
		eq(sim.player_ship().power_state["powered"].values().count(false), 0, "everything aboard is powered on the first tick")
		_done(d)


func test_choosing_resets_the_crew_the_camera_and_the_build_palette() -> void:
	var d := _picker()
	var p: ShipPicker = d["p"]
	var crew: CrewView = d["crew"]
	var build: BuildMode = d["build"]
	var cam: Camera2D = d["cam"]
	var old = d["sim"].player_ship()
	crew.player = CrewMember.new("Soldier", Vector2(31.0, 31.0))
	crew.ada = CrewMember.new("Ada", Vector2(33.0, 31.0))
	build.sel_component = "no_such_system"
	cam.zoom = Vector2(0.5, 0.5)
	_press(p, KEY_2)
	check(crew.player == null and crew.ada == null, "the crew respawn on the new ship")
	check(d["sim"].player_ship() != old and build.ship == d["sim"].player_ship(), "the build mode follows the new ship")
	check(build.message.contains("Courier"), "the HUD welcomes you aboard: " + build.message)
	check(build.sel_component == "" or d["sim"].player_ship().components.has(build.sel_component), "a valid system is selected")
	check(build.session.ship == d["sim"].player_ship(), "the undo history belongs to the new ship")
	check(build.build_on, "build mode is still on")
	var f := ShipPicker.fit(build.grid, Vector2(1600.0, 900.0))
	eq(cam.zoom, Vector2(f["zoom"], f["zoom"]), "the camera zooms to the ship")
	eq(cam.position, f["pos"], "and centres on it")
	d["sim"].player_ship().crew.append(CrewMember.new("x"))
	check(d["sim"].player_ship().crew.size() == 1, "(the new ship starts crewless)")
	_done(d)


func test_the_camera_fit_shows_the_whole_hull_between_the_hud_panels() -> void:
	for path in ShipPicker.DESIGNS:
		var ship = preload("res://scripts/ship/ship.gd").from_design(path)
		for view in [Vector2(1600.0, 900.0), Vector2(1280.0, 720.0)]:
			var f := ShipPicker.fit(ship.grid, view)
			var z: float = f["zoom"]
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for c in ship.grid.hull:
				var w := (Vector2(c) - Vector2(ship.grid.size) / 2.0) * ShipPicker.CELL_PX  # world position of the cell
				for corner in [w, w + Vector2(ShipPicker.CELL_PX, ShipPicker.CELL_PX)]:
					var s: Vector2 = (corner - f["pos"]) * z + view / 2.0  # screen position
					lo = Vector2(minf(lo.x, s.x), minf(lo.y, s.y))
					hi = Vector2(maxf(hi.x, s.x), maxf(hi.y, s.y))
			check(lo.x >= ShipPicker.HUD_SIDE - 1.0 and hi.x <= view.x - ShipPicker.HUD_SIDE + 1.0, "%s: the hull is between the palette and the card at %s" % [path.get_file(), str(view)])
			check(lo.y >= ShipPicker.HUD_TOP - 1.0 and hi.y <= view.y - ShipPicker.HUD_BOTTOM + 1.0, "%s: and between the top bar and the mode bar at %s (%d..%d)" % [path.get_file(), str(view), lo.y, hi.y])


func test_escape_keeps_the_ship_and_a_bad_number_does_nothing() -> void:
	var d := _picker()
	var p: ShipPicker = d["p"]
	_press(p, KEY_9)
	_press(p, KEY_A)
	check(p.visible and d["sim"].player_ship().name == "Starter", "other keys change nothing and the picker stays")
	_press(p, KEY_ESCAPE)
	check(not p.visible, "Esc puts it away")
	eq(d["sim"].player_ship().name, "Starter", "and keeps the current ship")
	eq(d["sim"].design_path, "", "no design was chosen")
	_press(p, KEY_1)
	eq(d["sim"].player_ship().name, "Starter", "a closed picker ignores the keys")
	eq(p.choose(7), "no such ship", "an out-of-range card is refused")
	_done(d)


func test_a_click_on_a_card_chooses_it() -> void:
	var d := _picker()
	var p: ShipPicker = d["p"]
	var move := InputEventMouseMotion.new()
	move.position = p.card_rect(2).get_center()
	p._gui_input(move)
	eq(p.hover, 2, "the card under the mouse is highlighted")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(4.0, 4.0)
	p._gui_input(click)
	check(p.visible and d["sim"].player_ship().name == "Starter", "a click outside the cards does nothing")
	click.position = p.card_rect(0).get_center()
	p._gui_input(click)
	eq(d["sim"].player_ship().name, "Rustbucket", "a click on card 1 loads the Rustbucket")
	_done(d)


func test_n_in_play_mode_asks_and_y_or_n_answers() -> void:
	var d := _picker()
	var p: ShipPicker = d["p"]
	var build: BuildMode = d["build"]
	_press(p, KEY_ESCAPE)
	build.build_on = true
	_press(build, KEY_N)
	check(not p.visible, "N does nothing in build mode")
	build.build_on = false
	_press(build, KEY_N)
	check(p.visible and p.mode == ShipPicker.Mode.CONFIRM, "N in play mode asks 'Discard current ship?'")
	_press(p, KEY_2)
	eq(d["sim"].player_ship().name, "Starter", "a number key does not answer the question")
	_press(p, KEY_N)
	check(not p.visible, "N answers no")
	eq(d["sim"].player_ship().name, "Starter", "the ship stays")
	_press(build, KEY_N)
	_press(p, KEY_Y)
	check(p.visible and p.mode == ShipPicker.Mode.CHOOSE, "Y shows the three ships")
	_press(p, KEY_3)
	eq(d["sim"].player_ship().name, "Prism", "and a number loads one")
	check(not build.build_on, "play mode stays as it was")
	_press(build, KEY_N)
	_press(p, KEY_ESCAPE)
	check(not p.visible and d["sim"].player_ship().name == "Prism", "Esc on the question keeps the Prism")
	check(build._controls_text().contains("N new ship") and build._controls_text().contains("K fight"), "the play-mode HUD lists N and K")
	_done(d)


func test_the_build_mode_ignores_input_while_the_picker_is_open() -> void:
	var d := _picker()
	var build: BuildMode = d["build"]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	build._unhandled_input(click)
	check(not build.dragging, "no build stroke starts under the picker")
	var e := InputEventKey.new()
	e.keycode = KEY_B
	e.pressed = true
	build._unhandled_input(e)
	check(build.build_on, "B does not switch modes under the picker")
	d["p"].close()
	build._unhandled_input(e)
	check(not build.build_on, "once it is closed B works again")
	_done(d)


func test_a_bad_design_is_refused_and_changes_nothing() -> void:
	var sim := ShipSim.new()
	var old = sim.player_ship()
	check(sim.choose_ship("res://data/ships/nothing_here.json") != "", "a missing file is refused")
	check(sim.player_ship() == old and sim.design_path == "", "the ship and the design path are untouched")
	sim.free()
