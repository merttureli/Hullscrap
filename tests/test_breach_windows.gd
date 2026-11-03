extends "res://tests/base_test.gd"
## The breach prompt takes R and V whatever window is open (Beta 3 known issue 1). The windows swallow every key, so they ask
## BreachPrompt.claims(e) first and let a claimed key through. (A test run has no scene tree to push events through; the whole
## path, a real event window open over a real breach, was driven in the main scene by hand.)

const Fixture = preload("res://tests/fixture_ship.gd")
const BreachPrompt = preload("res://scripts/ui/breach_prompt.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const STEP := 0.1

## Every window that swallows all keys while it is open.
const WINDOWS := ["event_panel", "station_panel", "region_choice", "journal_panel", "map_view", "crafting_panel", "shield_panel", "help_panel", "ledger_prompt"]


func _key(code: Key, pressed := true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	return e


## A prompt on a ship with a crew member and a breach, the card up. Returns {prompt, view, sim, build, ship}.
func _breached() -> Dictionary:
	var ship := Fixture.room_ship()
	ship.crew.append(CrewMember.new("Ada", Pathfinder.centre_of(Vector2i(12, 12), 2), "human"))
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	var view := CrewView.new()
	view.build = b
	view.sim = sim
	sim.set_paused(false)
	var prompt := BreachPrompt.new()
	prompt.view = view
	prompt.tick(STEP)
	ship.grid.breach(Vector2i(8, 12))
	ship.mark_dirty()
	ship.refresh()
	for i in 15:
		ship.atmosphere.tick(STEP, {})
		prompt.tick(STEP)
	return {"prompt": prompt, "view": view, "sim": sim, "build": b, "ship": ship}


func _free(d: Dictionary) -> void:
	Engine.time_scale = 1.0
	for k in ["prompt", "view", "sim", "build"]:
		d[k].free()


func test_a_window_asks_the_card_and_lets_r_and_v_through() -> void:
	var calm := BreachPrompt.new()
	check(not BreachPrompt.claims(_key(KEY_R)), "no card up: nothing is claimed")
	calm.free()
	var d := _breached()
	var prompt: BreachPrompt = d["prompt"]
	check(prompt.visible, "the card is up")
	check(BreachPrompt.claims(_key(KEY_R)), "R is the card's")
	check(BreachPrompt.claims(_key(KEY_V)), "V is the card's")
	for code in [KEY_1, KEY_Q, KEY_ENTER, KEY_ESCAPE, KEY_M, KEY_SPACE]:
		check(not BreachPrompt.claims(_key(code)), "%s stays the window's" % OS.get_keycode_string(code))
	check(not BreachPrompt.claims(_key(KEY_R, false)), "a release is not an answer")
	var echo := _key(KEY_R)
	echo.echo = true
	check(not BreachPrompt.claims(echo), "nor is a held key repeating")
	var ctrl := _key(KEY_V)
	ctrl.ctrl_pressed = true
	check(not BreachPrompt.claims(ctrl), "nor Ctrl+V")
	check(not BreachPrompt.claims(InputEventMouseButton.new()), "nor a mouse click")
	prompt._input(_key(KEY_R))
	check(not BreachPrompt.claims(_key(KEY_R)), "answered: the card is gone and R is the window's again")
	_free(d)
	check(not BreachPrompt.claims(_key(KEY_R)), "a freed prompt claims nothing")


func test_every_window_that_swallows_the_keys_asks_the_card_first() -> void:
	for w in WINDOWS:
		var src := FileAccess.get_file_as_string("res://scripts/ui/%s.gd" % w)
		var at := src.find("func _input(e: InputEvent) -> void:")
		check(at >= 0, "%s has an _input" % w)
		var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
		var claim := body.find("BreachPrompt.claims(e)")
		check(claim >= 0, "%s asks BreachPrompt.claims(e)" % w)
		# and before the line that swallows every key (the last such call; a closed window may take its own opening key above)
		var last := maxi(body.rfind("set_input_as_handled"), body.rfind("_handled()"))
		check(claim < last, "%s asks before it swallows a key" % w)
