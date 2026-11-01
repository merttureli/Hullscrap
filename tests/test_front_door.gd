extends "res://tests/base_test.gd"
## The front door without a screen: the menu state machine, the How to play text against the keys of the
## input handlers, the profile file (run records, first-run hints, version), the game over numbers from a
## campaign, the hint toasts and the campaign's new counters (events seen, fights won).

const Profile = preload("res://scripts/ui/profile.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")
const HelpPanel = preload("res://scripts/ui/help_panel.gd")
const GameOver = preload("res://scripts/ui/game_over.gd")
const HintToast = preload("res://scripts/ui/hint_toast.gd")
const FrontDoor = preload("res://scripts/ui/front_door.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const TMP := "user://test_front_door_profile.json"
const TMP_VERSION := "user://test_front_door_version.txt"


func _ids(entries: Array) -> Array:
	return entries.map(func(e): return e["id"])


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _clean() -> void:
	for p in [TMP, TMP_VERSION]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _starter() -> Ship:
	var s := Ship.from_design("res://data/ships/starter_courier.json")
	s.crew_plan = [{"name": "Soldier", "species": "human"}, {"name": "Ada", "species": "human"}, {"name": "Bram", "species": "basalt"}]  # (the real start is the soldier alone)
	Jobs.spawn_crew(s)
	return s


# --- the menu -------------------------------------------------------------------------------------------

func test_continue_is_listed_only_with_a_save() -> void:
	eq(_ids(MainMenu.entries(MainMenu.Mode.MAIN, false)), ["new", "help", "quit"], "main menu without a save")
	eq(_ids(MainMenu.entries(MainMenu.Mode.MAIN, true)), ["continue", "new", "help", "quit"], "main menu with a save")
	eq(_ids(MainMenu.entries(MainMenu.Mode.PAUSE, true)), ["resume", "help", "save_menu", "quit"], "pause menu")
	eq(_ids(MainMenu.entries(MainMenu.Mode.PAUSE, false)), ["resume", "help", "save_menu", "quit"], "pause menu does not depend on a save")


func test_menu_keys_choose_entries() -> void:
	var m := MainMenu.new()
	var got: Array = []
	m.chosen.connect(func(id): got.append(id))
	m.open(MainMenu.Mode.MAIN, false)
	eq(m.key(KEY_C), "", "C does nothing without a save")
	eq(m.key(KEY_ESCAPE), "", "Esc does nothing on the main menu")
	eq(m.key(KEY_ENTER), "new", "Enter presses the selected entry: New run when there is no save")
	eq(m.key(KEY_H), "help", "H is How to play")
	eq(m.key(KEY_Q), "quit", "Q quits")
	eq(m.key(KEY_3), "quit", "number keys press by position: 3 is Quit without a save")
	m.open(MainMenu.Mode.MAIN, true)
	eq(m.selected, 0, "Continue is selected when there is a save")
	eq(m.key(KEY_C), "continue", "C continues")
	m.open(MainMenu.Mode.MAIN, true)
	m.key(KEY_UP)
	eq(m.selected, 3, "Up from the first wraps to the last")
	m.key(KEY_DOWN)
	eq(m.selected, 0, "Down wraps back")
	eq(m.key(KEY_2), "new", "2 is New run with a save")
	m.open(MainMenu.Mode.PAUSE)
	eq(m.key(KEY_ESCAPE), "resume", "Esc resumes the pause menu")
	eq(m.key(KEY_S), "save_menu", "S saves and quits to the menu")
	eq(got, ["new", "help", "quit", "quit", "continue", "new", "resume", "save_menu"], "what was emitted")
	m.free()


func test_menu_buttons_can_be_clicked() -> void:
	var m := MainMenu.new()
	m.size = Vector2(1600.0, 900.0)
	m.open(MainMenu.Mode.MAIN, true)
	for i in m.list().size():
		eq(m.button_at(m.button_rect(i).get_center()), i, "button %d is where it is drawn" % i)
	eq(m.button_at(Vector2(5.0, 5.0)), -1, "nothing in the corner")
	m.free()


# --- how to play ------------------------------------------------------------------------------------------

## The keys of the input handlers, as the How to play screen writes them. build_mode.gd: B N M H O P E K
## Tab 1-9 R T Shift+R F Ctrl+Z/Y Ctrl+S/L Esc, the wheel and the three mouse buttons; crew_view.gd: WASD, E
## held, middle click; combat_view.gd and weapon_bar.gd: W S A D, the mouse, T, 1-9, Shift Space Q, the arrows
## and End, Esc, R; map_view.gd, event_panel.gd, station_panel.gd, shield_panel.gd, crafting_panel.gd as below.
const HANDLER_KEYS: Array[String] = [
	"W A S D", "E (hold)", "E on a door", "Middle click", "Left click", "G", "Mouse", "B", "O / P", "Wheel", "Ctrl+S / Ctrl+L", "N", "Esc", "F1",
	"Tab / Shift+Tab", "1 - 9", "Left mouse", "Shift+Left drag", "Ctrl+Left drag", "Right mouse", "T", "R", "Shift+R", "F", "Ctrl+Z / Ctrl+Y",
	"M", "Click a lit neighbour", "Shift+click", "Enter", "1 - 9 or click", "Enter / Space", "Click a marker", "E at the helm",
	"K", "W / S", "A / D", "Left / Right mouse", "Shift / Space / Q", "Arrows / End", "Y",
	"Right click", "Esc / Enter / M", "H", "H / Esc",
	"C", "Click, or Up / Down + Enter", "PgUp / PgDn", "Click a queued job", "U", "C / Esc",
]


func test_help_lists_every_key_of_the_input_handlers() -> void:
	var keys := HelpPanel.keys_text()
	for k in HANDLER_KEYS:
		check(keys.contains(k), "How to play has the key '%s'" % k)


## Y does two jobs: on the map it is the tow when you are out of fuel, in a fight it accepts a surrender.
func test_help_lists_y_for_the_map_and_for_the_fight() -> void:
	var where := {}
	for col in HelpPanel.COLUMNS:
		for sec in col:
			for row in sec[1]:
				if row[0] == "Y":
					where[str(sec[0])] = str(row[1])
	var map_text := ""
	var fight_text := ""
	for title in where:
		if title.begins_with("THE MAP"):
			map_text = where[title]
		elif title.begins_with("COMBAT"):
			fight_text = where[title]
	check(map_text.to_lower().contains("fuel") and map_text.contains("tow"), "map: Y tows you home when you are out of fuel: '%s'" % map_text)
	check(fight_text.contains("surrender"), "fight: Y accepts a surrender: '%s'" % fight_text)


func test_help_has_the_sections_and_the_first_run_box() -> void:
	var text := HelpPanel.all_text()
	for title in ["MOVING AND CREW", "BUILDING", "THE MAP AND EVENTS", "COMBAT", "STATIONS", "SHIELDS (H)", "CRAFTING (C)"]:
		check(text.contains(title), "section " + title)
	var steps := HelpPanel.first_run()
	eq(steps.size(), 6, "six first-run steps")
	eq(steps[3], "Pay Ma 100 credits every 8 jumps.", "the debt figures come from data/drift.json")
	check(steps[0].contains("M") and steps[5].contains("C"), "the first and last steps name their keys")
	for col in HelpPanel.COLUMNS:
		for sec in col:
			for row in sec[1]:
				check(str(row[0]) != "" and str(row[1]) != "", "a row of %s has keys and text" % sec[0])


## Every column of How to play ends above the footer line at the game's 1600 x 900 (the COMBAT column once ran off the screen).
func test_help_columns_fit_the_screen() -> void:
	var h := HelpPanel.new()
	h.size = Vector2(1600.0, 900.0)
	var limit: float = h.panel_rect().end.y - 28.0
	for c in HelpPanel.COLUMNS.size():
		check(h.column_end(c) <= limit, "help column %d ends at %d, under the footer line at %d" % [c, int(h.column_end(c)), int(limit)])
	h.free()


func test_f1_toggles_the_help_and_esc_closes_it() -> void:
	var h := HelpPanel.new()
	h.visible = false  # _ready does it in the scene
	var closed := [0]
	h.closed.connect(func(): closed[0] += 1)
	h._input(_key(KEY_F1))
	check(h.visible, "F1 opens it")
	h._input(_key(KEY_A))
	check(h.visible, "other keys leave it open")
	h._input(_key(KEY_F1))
	check(not h.visible, "F1 closes it")
	h._input(_key(KEY_F1))
	h._input(_key(KEY_ESCAPE))
	check(not h.visible, "Esc closes it")
	eq(closed[0], 2, "it said so each time")
	h.free()


# --- the profile ------------------------------------------------------------------------------------------

func test_profile_keeps_runs_and_shows_the_last_five_newest_first() -> void:
	_clean()
	var p := Profile.new(TMP)
	eq(p.runs.size(), 0, "no file, no runs")
	for i in 7:
		p.add_run({"ship": "Ship %d" % i, "jumps": i, "credits": 10 * i, "debt": 900, "crew": 2, "events": i, "fights": 1, "date": "2026-10-30"})
	eq(p.last_runs().size(), 5, "five shown")
	eq(p.last_runs()[0]["ship"], "Ship 6", "newest first")
	eq(p.last_runs()[4]["ship"], "Ship 2", "and the fifth is the fifth newest")
	var q := Profile.new(TMP)
	eq(q.runs.size(), 7, "the file was written and read back")
	eq(q.runs[0]["ship"], "Ship 0", "oldest first in the file")
	for i in 20:
		q.add_run({"ship": "More %d" % i})
	eq(q.runs.size(), Profile.MAX_RUNS, "the list is capped")
	eq(Profile.new(TMP).runs[-1]["ship"], "More 19", "the newest survives the cap")
	_clean()


func test_profile_survives_a_broken_file() -> void:
	_clean()
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var p := Profile.new(TMP)
	eq(p.runs.size(), 0, "broken JSON is an empty profile")
	check(p.hint_due("picked"), "and the first-run hints are due")
	f = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string('{"hints": 3, "runs": [1, "x", {"ship": "Ok"}]}')
	f.close()
	p = Profile.new(TMP)
	eq(p.runs.size(), 1, "only the records that are records are kept")
	_clean()


func test_run_line_is_one_line_with_the_numbers() -> void:
	var line := Profile.run_line({"ship": "Courier", "jumps": 14, "credits": 230, "debt": 480, "crew": 3, "events": 9, "fights": 4, "date": "2026-10-30"})
	eq(line, "2026-10-30  Courier: 14 jumps, 230 cr, debt 480, 3 crew, 9 events, 4 fights won", "the line")
	check(not line.contains("\n"), "one line")
	eq(Profile.run_line({}), "?: 0 jumps, 0 cr, debt 0, 0 crew, 0 events, 0 fights won", "an empty record still reads")
	eq(Profile.run_line({"ship": "X", "jumps": 1, "events": 1, "fights": 1}), "X: 1 jump, 0 cr, debt 0, 0 crew, 1 event, 1 fight won", "one of each is singular")


func test_first_run_hints_are_shown_once_and_only_in_the_first_run() -> void:
	_clean()
	var p := Profile.new(TMP)
	for id in Profile.HINTS:
		check(p.hint_due(id), id + " is due in a fresh profile")
	check(not p.hint_due("nonsense"), "an unknown hint is never due")
	p.mark_hint("picked")
	check(not p.hint_due("picked"), "shown once")
	check(p.hint_due("map"), "the others still wait")
	var q := Profile.new(TMP)
	check(not q.hint_due("picked") and q.hint_due("map") and q.hint_due("fight"), "the flags are in the file")
	q.add_run({"ship": "Rustbucket"})
	for id in Profile.HINTS:
		check(not q.hint_due(id), id + " is off once a run has ended")
	eq(FrontDoor.HINT_TEXT.keys(), Profile.HINTS, "every hint has its text, in order")
	eq(FrontDoor.HINT_TEXT["picked"], "B: play mode. Click a marker to set a course. M: map", "the first hint")
	eq(FrontDoor.HINT_TEXT["map"], "Click a lit node to jump there", "the second hint")
	eq(FrontDoor.HINT_TEXT["fight"], "Mouse steers, LMB fires, J: map to jump away", "the third hint")
	_clean()


func test_version_label_from_version_txt() -> void:
	_clean()
	eq(Profile.version_label(TMP_VERSION), "Beta 3 (dev)", "no file: dev")
	var f := FileAccess.open(TMP_VERSION, FileAccess.WRITE)
	f.store_string("Beta 3 a1b2c3d4e5f\n")
	f.close()
	eq(Profile.version_label(TMP_VERSION), "Beta 3 (a1b2c3d)", "the export's line gives the short hash")
	f = FileAccess.open(TMP_VERSION, FileAccess.WRITE)
	f.store_string("9f8e7d6\n")
	f.close()
	eq(Profile.version_label(TMP_VERSION), "Beta 3 (9f8e7d6)", "a bare hash works")
	f = FileAccess.open(TMP_VERSION, FileAccess.WRITE)
	f.store_string("Beta 3\n")
	f.close()
	eq(Profile.version_label(TMP_VERSION), "Beta 3 (dev)", "no hash in it: dev")
	_clean()


func test_clear_saves_deletes_only_what_exists() -> void:
	_clean()
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	check(Profile.has_save(TMP), "a file is a save")
	Profile.clear_saves([TMP, TMP_VERSION])
	check(not Profile.has_save(TMP), "it is gone")


# --- the end of a run ---------------------------------------------------------------------------------------

func test_game_over_numbers_come_from_the_campaign_and_the_ship() -> void:
	var s := _starter()
	var c := Campaign.new(11)
	c.jumps = 14
	c.debt = 480
	c.events_seen = 9
	c.fights_won = 4
	s.inventory.add("credits", 230 - s.inventory.count("credits"))
	var crew := s.crew.size()
	check(crew >= 2, "the starter has a crew")
	s.crew[0].hp = 0.0
	var st := GameOver.stats_of(c, s)
	eq(st["ship"], s.name, "the ship's name")
	eq([st["jumps"], st["credits"], st["debt"], st["events"], st["fights"]], [14, 230, 480, 9, 4], "jumps, credits, debt, events, fights")
	eq(st["crew"], crew - 1, "crew alive: those above 0 hp")
	eq(GameOver.stats_of(c, null)["crew"], 0, "no ship, no crew")


func test_game_over_buttons() -> void:
	var g := GameOver.new()
	var got: Array = []
	g.chosen.connect(func(id): got.append(id))
	g.open({"ship": "X"})
	check(g.visible, "open shows it")
	g._input(_key(KEY_N))
	check(not g.visible, "a button hides it")
	g.open({"ship": "X"})
	g._input(_key(KEY_DOWN))
	g._input(_key(KEY_ENTER))
	g.open({"ship": "X"})
	g._input(_key(KEY_M))
	eq(got, ["new", "menu", "menu"], "N, Down+Enter and M")
	g.size = Vector2(1600.0, 900.0)
	eq(g.button_at(g.button_rect(1).get_center()), 1, "the second button is where it is drawn")
	g.free()


func test_campaign_counts_events_and_fights_and_saves_them() -> void:
	var s := _starter()
	var c := Campaign.new(5)
	eq([c.events_seen, c.fights_won], [0, 0], "a new run starts at 0")
	c.fight_done({"state": "lost"}, s)
	c.fight_done({"state": "fled"}, s)
	eq(c.fights_won, 0, "a loss or a retreat is not a win")
	c.fight_done({"state": "won"}, s)
	c.fight_done({"state": "won"}, s)
	eq(c.fights_won, 2, "wins count")
	var a := c.arrive(s)  # Rusthold: Ma's call
	check(not a["event"].is_empty(), "arriving at the start node brings an event")
	eq(c.events_seen, 1, "which is counted")
	var d := c.to_dict()
	var c2 := Campaign.new(1)
	eq(c2.load_dict(d), "", "the save loads")
	eq([c2.events_seen, c2.fights_won], [1, 2], "the counters are in the save")
	d.erase("events_seen")
	d.erase("fights_won")
	var c3 := Campaign.new(1)
	eq(c3.load_dict(d), "", "a save from before the counters still loads")
	eq([c3.events_seen, c3.fights_won], [0, 0], "with 0")


# --- the toast ----------------------------------------------------------------------------------------------

func test_toasts_wait_their_turn_and_fade() -> void:
	var t := HintToast.new()
	t.push("one")
	t.push("two")
	eq(t.current, "one", "the first is shown")
	eq(t.queue, ["two"], "the second waits")
	near(t.alpha(), 1.0, "fully opaque while it stays")
	t.tick(HintToast.SHOW_FOR - 0.4)
	check(t.alpha() < 1.0 and t.alpha() > 0.0, "it fades at the end")
	t.tick(0.5)
	eq(t.current, "two", "then the next")
	t.tick(HintToast.SHOW_FOR + 0.1)
	eq(t.current, "", "then none")
	near(t.alpha(), 0.0, "invisible")
	t.free()


func near(a: float, b: float, msg: String) -> void:
	check(absf(a - b) < 0.001, "%s: expected %s, got %s" % [msg, str(b), str(a)])


func test_the_scene_has_the_front_door() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	check(main.get_node_or_null("FrontDoor") != null and main.get_node("FrontDoor").get_script() == FrontDoor, "main.tscn has the front door")
	main.free()
