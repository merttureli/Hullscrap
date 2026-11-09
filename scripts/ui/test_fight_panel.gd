extends Control
## The test-fight page (K in play mode, Esc closes): pick your ship (a copy of the one you fly, or a test ship at a set power) and an enemy (a faction or race x role x
## stage with a seed, a race flagship, the test pirate or the rammer, or Random), then Fight. After each fight it comes back with a row in the session's results list
## (not saved). The rules are in combat/test_fights.gd, the fight is combat_view.gd's (enter with the `test` option: the run is never changed); this node draws and reads input.
## While it is open it swallows every key and click.

const Schematic = preload("res://scripts/ui/schematic.gd")
const TestFights = preload("res://scripts/combat/test_fights.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Threat = preload("res://scripts/space/threat.gd")

const BG := Color(0.04, 0.065, 0.1, 0.98)
const EDGE := Color("#3b5a78")
const HOT := Color("#7fd0ff")
const TEXT := Color("#e4f1ff")
const DIM_TEXT := Color("#8ea6bf")
const BTN := Color(0.075, 0.11, 0.16)
const ON := Color(0.14, 0.3, 0.45)
const GO := Color("#2f8f5a")
const MARGIN := 40.0
const COL_L := 60.0
const COL_R := 640.0
const MODES := ["stage", "flagship", "fixed"]
const MODE_LABEL := {"stage": "Faction or race", "flagship": "Race flagship", "fixed": "Test pirate / rammer"}
const MAX_ROWS := 8

var view: Node  ## the CombatView that runs the fight
var choices: Array = []  ## the player's column (TestFights.player_choices)
var sel := 0  ## the chosen player choice
var enemy := {}  ## the chosen enemy choice
var mode := "stage"
var faction := ""
var role := ""
var stage := 1
var results: Array = []  ## this session's rows (TestFights.result_row), oldest first
var message := ""
var rng := RandomNumberGenerator.new()  ## the Random button's rolls (a fixed seed: the same presses give the same picks)
var _zones: Array = []  # [Rect2, Callable]
var _sch: Array = []  # the two schematics
var _prev := [{}, {}]  # [{key, ship, arena}] for the player and the enemy previews
var _stats := [{}, {}]
var _skulls := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	rng.seed = 2026
	for i in 2:
		var s := Schematic.new()
		s.visible = false
		add_child(s)
		_sch.append(s)


# --- opening and closing ------------------------------------------------------------------------------------

## Show the page; `pick` ("pirate" or "rammer") preselects one of the two fixed enemies.
func open(pick := "") -> void:
	choices = TestFights.player_choices()
	sel = clampi(sel, 0, choices.size() - 1)
	if enemy.is_empty() or pick != "":
		if pick != "":
			mode = "fixed"
			pick_fixed(pick)
		else:
			faction = TestFights.factions()[0]
			role = TestFights.roles_of(faction)[0]
			set_kind(faction, role, stage)
	message = ""
	visible = true
	_refresh()
	queue_redraw()


func close() -> void:
	visible = false
	for s in _sch:
		s.visible = false
	_prev = [{}, {}]


## The fight is over (combat_view.gd): the page comes back with the row.
func show_result(row: Dictionary) -> void:
	results.append(row)
	open()


# --- picking --------------------------------------------------------------------------------------------------

func select_ship(i: int) -> void:
	sel = clampi(i, 0, choices.size() - 1)
	_refresh()


func set_mode(m: String) -> void:
	mode = m
	match m:
		"stage":
			set_kind(faction if faction != "" else TestFights.factions()[0], role, stage)
		"flagship":
			pick_flagship(TestFights.flagship_races()[0])
		_:
			pick_fixed("pirate")


## A generated enemy of (faction, role, stage); a role the faction does not fly is replaced by its first one.
func set_kind(f: String, r: String, st: int) -> void:
	mode = "stage"
	faction = f
	stage = clampi(st, 1, TestFights.STAGES)
	var roles := TestFights.roles_of(f)
	role = r if roles.has(r) else roles[0]
	var c := TestFights.stage_choice(faction, role, stage)
	if c.is_empty():
		message = "No %s %s flies at stage %d" % [faction, role, stage]
		return
	message = ""
	enemy = c
	_refresh()


## Another ship of the same kind (the next seed that gives one).
func new_seed() -> void:
	if mode != "stage" or enemy.is_empty():
		return
	var s := TestFights.next_seed(faction, role, stage, int(enemy["seed"]) + 1)
	if s < 0:
		return
	enemy = TestFights.stage_choice(faction, role, stage, s)
	_refresh()


func pick_flagship(race: String) -> void:
	mode = "flagship"
	enemy = TestFights.flagship_choice(race)
	_refresh()


func pick_fixed(id: String) -> void:
	mode = "fixed"
	enemy = TestFights.fixed_choices()[0 if id == "pirate" else 1]
	_refresh()


func random() -> void:
	var c := TestFights.random_choice(rng)
	enemy = c
	if c["id"].begins_with("stage:"):
		mode = "stage"
		faction = c["faction"]
		role = c["role"]
		stage = c["stage"]
	else:
		mode = "flagship" if c["id"].begins_with("flagship:") else "fixed"
	_refresh()


## Start the fight with the picks. "" when it began, else why not.
func fight() -> String:
	if view == null or enemy.is_empty():
		return "nothing to fight"
	var c: Dictionary = choices[sel]
	var mine = view.sim.player_ship() if view.sim != null else null
	var ship = TestFights.player_ship(c, mine)
	if ship == null:
		return "cannot build " + str(c["name"])
	var why: String = view.enter(str(enemy["path"]), {"test": {"player": ship, "ship_name": str(c["name"]), "enemy_name": str(enemy["label"]) + (" #%d" % int(enemy["seed"]) if int(enemy["seed"]) > 0 else "")}})
	if why != "":
		message = why
		return why
	visible = false
	for s in _sch:
		s.visible = false
	return ""


# --- previews -----------------------------------------------------------------------------------------------------

func _refresh() -> void:
	var cur = view.sim.player_ship() if view != null and view.sim != null else null
	var c: Dictionary = choices[sel]
	_set_prev(0, str(c["id"]), func(): return TestFights.player_ship(c, cur))
	_set_prev(1, str(enemy.get("path", "")), func(): return Session.load_ship(str(enemy["path"])) if not enemy.is_empty() else null)
	_skulls = 0
	if _prev[0].has("ship") and _prev[1].has("ship"):
		_skulls = int(Threat.rate(_prev[1]["ship"], _prev[0]["ship"])["skulls"])
	queue_redraw()


func _set_prev(i: int, key: String, make: Callable) -> void:
	if _prev[i].get("key", "") == key and i == 1:
		return
	var ship = make.call()
	if ship == null:
		_prev[i] = {}
		_stats[i] = {}
		_sch[i].visible = false
		return
	var arena = TestFights.preview_arena(ship)
	_prev[i] = {"key": key, "ship": ship, "arena": arena}
	_stats[i] = TestFights.stats_of(ship)
	_sch[i].bind(arena, 0, ship.name if ship.name != "Ship" else str(key))
	_sch[i].visible = visible


# --- input ------------------------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed:
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	if e.echo:
		return
	match e.keycode:
		KEY_ESCAPE:
			close()
		KEY_ENTER, KEY_KP_ENTER:
			fight()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		click(e.position)


## A click at `p` (this control's coordinates): the button under it acts.
func click(p: Vector2) -> void:
	for z in _zones:
		if z[0].has_point(p):
			z[1].call()
			queue_redraw()
			return


# --- drawing ------------------------------------------------------------------------------------------------------------

func _btn(r: Rect2, label: String, on := false, cb := Callable(), col := BTN) -> void:
	draw_rect(r, ON if on else col)
	draw_rect(r, HOT if on else EDGE, false, 2.0 if on else 1.0)
	_text(label, r.position + Vector2(8.0, r.size.y * 0.5 + 5.0), 14, TEXT)
	if cb.is_valid():
		_zones.append([r, cb])


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _para(text: String, at: Vector2, w: float, font_size: int, col: Color) -> void:
	draw_multiline_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, w, font_size, 4, col)


func _stat_line(i: int, at: Vector2) -> void:
	var st: Dictionary = _stats[i]
	if st.is_empty():
		return
	_text("Hull %d   Shield layers %d   Guns %d" % [roundi(st["hull"]), st["layers"], st["guns"]], at, 14, TEXT)
	_text("Power %.0f / %.0f   Threat %d" % [st["supply"], st["demand"], roundi(st["power"])], at + Vector2(0.0, 20.0), 14, TEXT if st["supply"] + 0.0001 >= st["demand"] else Color("#e0453a"))


func _draw() -> void:
	_zones.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.85))
	var p := Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN, MARGIN) * 2.0)
	draw_rect(p, BG)
	draw_rect(p, EDGE, false, 2.0)
	_text("Test fights", Vector2(COL_L, 78.0), 28, TEXT)
	_text("Real rules, nothing kept: your ship fights as a copy and the run is never changed.   Enter: Fight   Esc: close", Vector2(COL_L + 190.0, 78.0), 13, DIM_TEXT)
	# the player's column
	_text("YOUR SHIP", Vector2(COL_L, 118.0), 18, HOT)
	for i in choices.size():
		_btn(Rect2(COL_L, 130.0 + i * 34.0, 500.0, 30.0), choices[i]["name"], i == sel, select_ship.bind(i))
	var y0 := 130.0 + choices.size() * 34.0 + 14.0
	_para(str(choices[sel]["blurb"]), Vector2(COL_L, y0 + 14.0), 500.0, 13, DIM_TEXT)
	_sch[0].position = Vector2(COL_L, y0 + 50.0)
	_stat_line(0, Vector2(COL_L + 296.0, y0 + 70.0))
	# the enemy's column
	_text("ENEMY", Vector2(COL_R, 118.0), 18, HOT)
	var x := COL_R
	for m in MODES:
		_btn(Rect2(x, 130.0, 190.0, 30.0), MODE_LABEL[m], mode == m, set_mode.bind(m))
		x += 196.0
	_btn(Rect2(x, 130.0, 110.0, 30.0), "Random", false, random)
	var yy := 172.0
	match mode:
		"stage":
			var fx := COL_R
			for f in TestFights.factions():
				_btn(Rect2(fx, yy, 110.0, 28.0), str(f).capitalize(), f == faction, set_kind.bind(f, role, stage))
				fx += 114.0
				if fx > COL_R + 800.0:
					fx = COL_R
					yy += 32.0
			yy += 36.0
			fx = COL_R
			for r in TestFights.roles_of(faction):
				_btn(Rect2(fx, yy, 100.0, 28.0), str(r), r == role, set_kind.bind(faction, r, stage))
				fx += 104.0
			yy += 36.0
			for st in range(1, TestFights.STAGES + 1):
				_btn(Rect2(COL_R + (st - 1) * 48.0, yy, 44.0, 28.0), str(st), st == stage, set_kind.bind(faction, role, st))
			_btn(Rect2(COL_R + 400.0, yy, 110.0, 28.0), "New seed", false, new_seed)
			_text("seed %s" % str(enemy.get("seed", "")), Vector2(COL_R + 520.0, yy + 20.0), 14, DIM_TEXT)
		"flagship":
			var fx2 := COL_R
			for race in TestFights.flagship_races():
				_btn(Rect2(fx2, yy, 110.0, 28.0), str(race).capitalize(), enemy.get("id", "") == "flagship:" + race, pick_flagship.bind(race))
				fx2 += 114.0
				if fx2 > COL_R + 800.0:
					fx2 = COL_R
					yy += 32.0
		_:
			_btn(Rect2(COL_R, yy, 170.0, 28.0), "Test pirate", enemy.get("id", "") == "pirate", pick_fixed.bind("pirate"))
			_btn(Rect2(COL_R + 176.0, yy, 170.0, 28.0), "Rustfang rammer", enemy.get("id", "") == "rammer", pick_fixed.bind("rammer"))
	var ey := 372.0
	_text(str(enemy.get("label", "")) + ("   seed %d" % int(enemy["seed"]) if int(enemy.get("seed", 0)) > 0 else ""), Vector2(COL_R, ey), 16, TEXT)
	_sch[1].position = Vector2(COL_R, ey + 14.0)
	_stat_line(1, Vector2(COL_R + 296.0, ey + 34.0))
	if _skulls > 0:
		_text("%s against your pick" % Threat.label(_skulls), Vector2(COL_R + 296.0, ey + 84.0), 14, Color("#ffd24a"))
	if message != "":
		_text(message, Vector2(COL_R + 296.0, ey + 110.0), 14, Color("#e0453a"))
	# fight and results
	var by := 610.0
	_btn(Rect2(COL_L, by, 220.0, 44.0), "FIGHT", false, fight, GO)
	_text("RESULTS (this session)", Vector2(COL_R, by + 4.0), 16, HOT)
	if results.is_empty():
		_text("none yet", Vector2(COL_R, by + 26.0), 13, DIM_TEXT)
	for k in mini(results.size(), MAX_ROWS):
		_text(TestFights.row_text(results[results.size() - 1 - k]), Vector2(COL_R, by + 26.0 + k * 18.0), 13, TEXT)
	for s in _sch:
		s.visible = visible and s.arena != null
