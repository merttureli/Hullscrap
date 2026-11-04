extends "res://tests/base_test.gd"
## Panning the build view: a middle-mouse drag and the arrow keys move the camera over the build area (clamped, so the ship cannot be lost), Home centres it,
## the wheel zooms towards the cursor, and in play mode the middle button is left alone (it sends crew).

const BuildMode = preload("res://scripts/build/build_mode.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")


func _build() -> BuildMode:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(20, 20), defs)
	g.fill_circle_hull(9.0)
	var ship := Ship.new("T", g)
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	b.cam = Camera2D.new()
	return b


func _done(b: BuildMode) -> void:
	b.cam.free()
	b.sim.free()
	b.free()


func _mmb(pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_MIDDLE
	e.pressed = pressed
	return e


func _move(rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	return e


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_a_middle_drag_pans_the_build_view() -> void:
	var b := _build()
	b._unhandled_input(_mmb(true))
	check(b._panning, "the middle button starts a pan in build mode")
	b._unhandled_input(_move(Vector2(-64.0, -32.0)))
	eq(b.pan, Vector2(64.0, 32.0), "dragging left and up moves the view right and down (at zoom 1)")
	eq(b.cam.offset, b.pan, "the camera follows")
	b._unhandled_input(_mmb(false))
	check(not b._panning, "and letting go ends it")
	b.cam.zoom = Vector2(2.0, 2.0)
	b.pan = Vector2.ZERO
	b._unhandled_input(_mmb(true))
	b._unhandled_input(_move(Vector2(-64.0, 0.0)))
	eq(b.pan, Vector2(32.0, 0.0), "zoomed in, a drag of the same length moves less of the world")
	_done(b)


func test_the_pan_stays_inside_the_build_area_and_home_centres() -> void:
	var b := _build()
	b.pan_by(Vector2(100000.0, -100000.0))
	var a := b.pan_area()
	var centre := b.cam.position + b.pan
	check(a.has_point(centre) or (centre.x <= a.end.x and centre.y >= a.position.y), "the centre cannot leave the area")
	eq(centre, Vector2(a.end.x, a.position.y), "it stops at the corner")
	b.reset_pan()
	var mid := b.ship.world_pos
	check(b.pan.length() < 1.0 + b.pan_area().size.length() and (b.cam.position + b.pan).distance_to(mid) < float(BuildMode.CELL) * 3.0, "Home centres on the ship")
	b._unhandled_input(_key(KEY_RIGHT))
	check(b._pan_held.has(KEY_RIGHT), "an arrow key is taken as a pan")
	eq(BuildMode.pan_dir(b._pan_held), Vector2(1.0, 0.0), "to the right")
	b._pan_held.clear()
	b.pan_by(Vector2(500.0, 500.0))
	b._unhandled_input(_key(KEY_HOME))
	check((b.cam.position + b.pan).distance_to(mid) < float(BuildMode.CELL) * 3.0, "the Home key resets it")
	_done(b)


func test_zoom_goes_towards_the_cursor_and_play_mode_has_no_pan() -> void:
	var b := _build()
	b.cam.zoom = Vector2(1.0, 1.0)
	b._zoom(2.0, Vector2.INF)
	eq(b.pan, Vector2.ZERO, "no cursor: the old zoom about the centre")
	b.set_build(false)
	b._unhandled_input(_mmb(true))
	check(not b._panning, "the middle button does not pan in play mode (it sends crew)")
	b._unhandled_input(_key(KEY_LEFT))
	check(b._pan_held.is_empty() and b.pan == Vector2.ZERO, "and neither do the arrows")
	_done(b)
