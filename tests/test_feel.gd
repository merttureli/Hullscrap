extends "res://tests/base_test.gd"
## Flying and controls (the playtest 2 "feel" round): the soldier's screen-relative WASD, the mouse wheel over panels.

const BuildMode = preload("res://scripts/build/build_mode.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
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
