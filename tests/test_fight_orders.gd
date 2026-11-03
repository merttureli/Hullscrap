extends "res://tests/base_test.gd"
## Crew orders in a ship fight: a middle click on your ship (or on your schematic) sends the selected crew to that room, the click maps
## through the ship's rotation, and the selection is made on the crew bar.

const Ship = preload("res://scripts/ship/ship.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const CrewBar = preload("res://scripts/ui/crew_bar.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Schematic = preload("res://scripts/ui/schematic.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")


func _npc(p_name: String, x: int, y: int) -> CrewMember:
	return CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y), 2), "human")


## A fight of the room ship cut in two by a wall at x 15 (west room x 9..14, east room x 16..21), with `crew` aboard, a breach in
## the west room's north wall, a broken engine and a damaged wall block there. {combat, crew (the CrewView), sim, build, ship}.
func _fight(crew: Array) -> Dictionary:
	var ship := Fixture.room_ship()
	for y in range(9, 17):
		ship.grid.force_tile(Vector2i(15, y), "wall")
	ship.grid.place_door("door", Vector2i(15, 12), Vector2i.DOWN)
	ship.grid.breach(Vector2i(9, 8))
	var engine := Fixture.put(ship, "engine_mk1", 10, 10)
	ship.components.instances[engine]["status"] = "malfunction"
	ship.grid.hp[Vector2i(14, 8)] = 2.0
	ship.mark_dirty()
	ship.refresh()
	ship.crew.append_array(crew)
	var sim := ShipSim.new()
	sim.ships = [ship]
	var build := BuildMode.new()
	build.sim = sim
	build.build_on = false
	var cv := CrewView.new()
	cv.build = build
	cv.sim = sim
	build.crew = cv
	var combat := CombatView.new()
	combat.sim = sim
	combat.build = build
	combat.crew = cv
	var why := combat.enter()
	check(why == "", "the fight starts: " + why)
	return {"combat": combat, "crew": cv, "sim": sim, "build": build, "ship": ship}


func _free(d: Dictionary) -> void:
	var c: CombatView = d["combat"]
	if c.active:
		c.leave()
	for k in ["combat", "crew", "sim", "build"]:
		d[k].free()


func _middle(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_MIDDLE
	e.pressed = true
	e.position = at
	return e


func test_a_world_point_maps_to_the_cell_of_your_ship_at_any_rotation() -> void:
	var d := _fight([_npc("Ada", 10, 14)])
	var arena = d["combat"].session.arena
	for angle in [0.0, PI / 2.0, deg_to_rad(37.0)]:
		arena.ships[Session.PLAYER].flight.angle = angle
		arena.ships[Session.PLAYER].flight.pos = Vector2(400.0, -250.0)
		for cell in [Vector2i(10, 12), Vector2i(18, 13), Vector2i(12, 10)]:
			var hit: Dictionary = CombatView.ship_cell(arena, arena.cell_to_world(Session.PLAYER, cell))
			eq(hit.get("ship", -1), Session.PLAYER, "angle %.2f: the click is on your ship" % angle)
			eq(hit.get("cell", Vector2i(-1, -1)), cell, "angle %.2f: cell %s" % [angle, str(cell)])
	_free(d)


func test_a_click_off_the_ship_does_nothing() -> void:
	var ada := _npc("Ada", 10, 14)
	var d := _fight([ada])
	var combat: CombatView = d["combat"]
	var arena = combat.session.arena
	arena.ships[Session.PLAYER].flight.angle = deg_to_rad(37.0)
	var far: Vector2 = arena.ships[Session.PLAYER].flight.pos + Vector2(5000.0, 5000.0)
	check(CombatView.ship_cell(arena, far).is_empty(), "open space maps to no ship")
	eq(combat.order_at_world(far), "", "no order")
	check(ada.path.is_empty() and ada.job.is_empty(), "Ada stayed put")
	check(combat._views[Session.PLAYER].flash_left <= 0.0, "no flash")
	# the enemy's ship is not yours to order about
	var foe_at: Vector2 = arena.cell_to_world(Session.ENEMY, Vector2i(arena.ships[Session.ENEMY].ship.grid.tiles.keys()[0]))
	eq(combat.order_at_world(foe_at), "", "the enemy ship takes no order")
	check(ada.path.is_empty(), "still nothing")
	_free(d)


func test_with_nobody_selected_a_fight_click_sends_ada_and_flashes_the_room() -> void:
	var ada := _npc("Ada", 10, 14)
	var d := _fight([ada])
	var combat: CombatView = d["combat"]
	var arena = combat.session.arena
	arena.ships[Session.PLAYER].flight.angle = deg_to_rad(37.0)
	eq(d["crew"].order_target(), ada, "Ada is the one a click picks")
	combat.order_at_world(arena.cell_to_world(Session.PLAYER, Vector2i(19, 13)))
	check(not ada.path.is_empty(), "Ada walks")
	eq(ada.hold, 8.0, "and holds the order as long as in play mode")
	var v: ShipView = combat._views[Session.PLAYER]
	check(v.flash_left > 0.0 and v.flash_cells.has(Vector2i(19, 13)), "the east room flashes on the ship")
	check(not v.flash_cells.has(Vector2i(10, 12)), "not the west one")
	_free(d)


func test_a_group_order_in_a_fight_splits_the_jobs() -> void:
	var crew := [_npc("Ada", 10, 14), _npc("Rook", 12, 14), _npc("Juno", 11, 15)]
	var d := _fight(crew)
	var combat: CombatView = d["combat"]
	var cv: CrewView = d["crew"]
	var ship: Ship = d["ship"]
	var jobs: Jobs = d["sim"].jobs_of(ship)
	for i in 3:
		ship.refresh()
		jobs.tick(ship, 0.1, true)
	for m in crew:
		cv.toggle(m)
	eq(cv.selection().size(), 3, "three selected")
	combat.order_at_world(combat.session.arena.cell_to_world(Session.PLAYER, Vector2i(11, 12)))
	var kinds := {}
	for m in crew:
		check(not m.path.is_empty() or not m.job.is_empty(), "%s is on the move or has a job (extras stand by)" % m.name)
		eq(m.hold, 8.0, "%s holds the order as long as in play mode" % m.name)
		if not m.job.is_empty():
			check(bool(m.job.get("ordered", false)), "%s's job is an order" % m.name)
			kinds[str(m.job.get("type", ""))] = true
	check(kinds.size() >= 2, "the jobs are split among them: " + str(kinds.keys()))
	_free(d)


func test_a_click_on_the_schematic_orders_and_flashes_the_map() -> void:
	var ada := _npc("Ada", 10, 14)
	var d := _fight([ada])
	var combat: CombatView = d["combat"]
	var arena = combat.session.arena
	var schem := Schematic.new()
	schem.bind(arena, Session.PLAYER, "Your ship")
	combat._schem = [schem]
	var ship: Ship = d["ship"]
	var lay := Schematic.map_layout(ship, Schematic.MAP)
	var spot: Vector2 = lay["origin"] + Vector2(19.5, 13.5) * float(lay["s"])
	var at = Schematic.cell_under(ship, spot)
	check(at != null and Vector2i(floori(at.x), floori(at.y)) == Vector2i(19, 13), "the panel point maps back to the cell: " + str(at))
	check(Schematic.cell_under(ship, Vector2(2.0, 2.0)) == null, "the title bar is no cell")
	combat.order_from_map(spot)
	check(not ada.path.is_empty(), "Ada walks to the room clicked on the map")
	check(schem.flash_left > 0.0 and schem.flash_cells.has(Vector2i(19, 13)), "the room flashes on the schematic")
	check(combat._views[Session.PLAYER].flash_left <= 0.0, "not on the ship")
	eq(combat.order_from_map(Vector2(2.0, 2.0)), "", "a click off the map does nothing")
	combat._schem = []
	schem.free()
	_free(d)


func test_the_crew_bar_selects_and_shift_adds_in_a_fight() -> void:
	var crew := [_npc("Ada", 10, 14), _npc("Rook", 12, 14), _npc("Juno", 11, 15)]
	var d := _fight(crew)
	var cv: CrewView = d["crew"]
	var bar := CrewBar.new()
	bar.view = cv
	bar.size = Vector2(1600, 900)
	var cards := CrewBar.card_rects(3, bar.size)
	eq(bar.click(cards[0].get_center()), "select", "a click selects")
	eq(cv.selection(), [crew[0]], "just her")
	eq(bar.click(cards[2].get_center(), true), "toggle", "Shift adds")
	eq(cv.selection().size(), 2, "two selected")
	check(cv.fight_on(), "this is a ship fight")
	bar.free()
	_free(d)


func test_the_selected_crew_get_rings_on_the_fight_ship() -> void:
	var ada := _npc("Ada", 10, 14)
	var d := _fight([ada])
	var combat: CombatView = d["combat"]
	var v: ShipView = combat._views[Session.PLAYER]
	v.marked = [ada]
	check(v.marked.has(ada), "the ship view rings the selected")
	v.flash_room([Vector2i(10, 12)])
	check(v.flash_left > 0.0, "and flashes a room")
	v._process(2.0)
	eq(v.flash_left, 0.0, "the flash dies away")
	_free(d)


func test_a_middle_click_outside_a_fight_still_orders_in_play_mode() -> void:
	var ada := _npc("Ada", 10, 14)
	var ship := Fixture.room_ship()
	ship.crew.append(ada)
	var sim := ShipSim.new()
	sim.ships = [ship]
	var build := BuildMode.new()
	build.sim = sim
	build.build_on = false
	var cv := CrewView.new()
	cv.build = build
	cv.sim = sim
	build.crew = cv
	cv.order_at(Vector2(18.0, 12.0))
	check(not ada.path.is_empty(), "Ada walks in play mode")
	cv.free()
	build.free()
	sim.free()
