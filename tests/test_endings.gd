extends "res://tests/base_test.gd"
## Endings, landmarks, unlocks and the hangar (docs/CONTENT.md sections 13 and 19) without a screen: the `unlock`, `landmark`
## and `ending` event effects and their validator, the profile (unlocks, landmarks, the hall of ships), the score maths and the
## report, the ending screen's state, the win flowing from the event panel through the map to the front door, the hangar's list,
## its locked and unlocked ships and its keys. The unlocks, endings and ships come from the fixture pack in
## tests/fixtures/packs/endings (and the broken ones in endings_bad).

const Content = preload("res://scripts/data/content.gd")
const Events = preload("res://scripts/space/events.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Endings = preload("res://scripts/space/endings.gd")
const Unlocks = preload("res://scripts/space/unlocks.gd")
const Hangar = preload("res://scripts/space/hangar.gd")
const HangarView = preload("res://scripts/ui/hangar.gd")
const EndingScreen = preload("res://scripts/ui/ending_screen.gd")
const EventPanel = preload("res://scripts/ui/event_panel.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const Profile = preload("res://scripts/ui/profile.gd")
const FrontDoor = preload("res://scripts/ui/front_door.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const FIXTURES := "res://tests/fixtures/packs/"
const TMP := "user://test_endings_profile.json"
const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _scenario(name: String) -> void:
	Content.packs_root = FIXTURES + name


func _done() -> void:
	Content.packs_root = ""


## Remove the temporary profile and its hall folder.
func _clean() -> void:
	var dir := TMP.get_basename() + "_hall"
	for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + f))
	if DirAccess.dir_exists_absolute(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


func _events(list: Array) -> Events:
	var e := Events.new("res://tests")  # no *.json there
	for x in list:
		e.add(x, "test.json")
	return e


func _camp(list: Array = []) -> Campaign:
	return Campaign.new(1, {}, _events(list))


## An event of one choice with one outcome.
func _ev(id: String, effects: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var e := {"id": id, "type": "anomaly", "weight": 10, "once": false, "requires": {}, "text": "Text of " + id,
		"choices": [{"text": "Go", "outcomes": [{"weight": 100, "text": "Done", "effects": effects}]}]}
	e.merge(extra, true)
	return e


func _take(c: Campaign, id: String, ship: Ship) -> Dictionary:
	return c.events.choose(c.events.get_event(id), 0, c, ship, {"id": "n99", "type": "anomaly", "place": ""})


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _has(list: Array, parts: Array) -> bool:
	return list.any(func(m): return parts.all(func(p): return str(m).contains(p)))


# --- the unlock effect ------------------------------------------------------------------------------------------

func test_the_unlock_effect_is_kept_in_the_profile_and_shown() -> void:
	_scenario("endings")
	_clean()
	var prof := Profile.new(TMP)
	var c := _camp([_ev("u", {"unlock": "fx_tender"})])
	c.profile = prof
	var ship := _ship()
	var r := _take(c, "u", ship)
	check(r["ok"] and r["lines"].has("Unlocked: Fixture Tender"), "the event says 'Unlocked: Fixture Tender' (%s)" % str(r["lines"]))
	check(prof.has_unlock("fx_tender"), "the profile has it")
	check(Profile.new(TMP).has_unlock("fx_tender"), "and so does the file")
	eq(c.unlocks_earned, ["fx_tender"], "the run lists it")
	check(not _take(c, "u", ship)["lines"].has("Unlocked: Fixture Tender"), "earned again, it says nothing")
	eq(c.unlocks_earned.size(), 1, "and is listed once")
	var c2 := _camp([_ev("u", {"unlock": "fx_tender"})])
	c2.profile = prof
	check(_take(c2, "u", ship)["lines"].is_empty(), "a later run that already has it says nothing")
	eq(c2.unlocks_earned, [], "and lists nothing new")
	var r3 := c.events.apply({"unlock": ["no_such_unlock", "fx_fenn"]}, c, ship)
	eq(r3["lines"], ["Unlocked: Fenn start"], "an unknown id is skipped, a list works")
	_clean()
	_done()


func test_the_unlock_effect_works_without_a_profile() -> void:
	_scenario("endings")
	var c := _camp()
	var ship := _ship()
	eq(c.events.apply({"unlock": "fx_skin"}, c, ship)["lines"], ["Unlocked: Gilt hull"], "the line shows")
	eq(c.events.apply({"unlock": "fx_skin"}, c, ship)["lines"], [], "once per run")
	eq(c.unlocks_earned, ["fx_skin"], "the run keeps it")
	_done()


# --- landmarks ----------------------------------------------------------------------------------------------------

func test_a_landmark_is_recorded_once_per_profile_and_once_per_run() -> void:
	_clean()
	var prof := Profile.new(TMP)
	var ev := _ev("lm", {"items": {"scrap": 1}}, {"landmark": "Seeing the Fixture"})
	var c := _camp([ev])
	c.profile = prof
	var ship := _ship()
	var r := _take(c, "lm", ship)
	check(r["lines"].has("Landmark: Seeing the Fixture"), "the event says it is a landmark (%s)" % str(r["lines"]))
	eq(c.landmarks, ["lm"], "the run has it")
	eq(c.chronicle[0]["kind"], "landmark", "in the run log")
	eq(prof.landmarks["lm"]["title"], "Seeing the Fixture", "the profile has it, with its title")
	check(Profile.new(TMP).has_landmark("lm"), "in the file too")
	check(not _take(c, "lm", ship)["lines"].has("Landmark: Seeing the Fixture"), "meeting it again in the run says nothing")
	eq(c.landmarks.size(), 1, "and keeps one")
	prof.landmarks["lm"]["date"] = "2000-01-01"
	var c2 := _camp([ev])
	c2.profile = prof
	check(_take(c2, "lm", ship)["lines"].has("Landmark: Seeing the Fixture"), "a later run counts it again")
	eq(c2.landmarks, ["lm"], "in that run's log")
	eq(prof.landmarks["lm"]["date"], "2000-01-01", "while the profile keeps its first record")
	eq(prof.landmarks.size(), 1, "and one entry")
	_clean()


func test_a_landmark_title_and_the_rule_of_effects() -> void:
	var ship := _ship()
	var c := _camp([_ev("meet_ma_in_person", {"items": {"scrap": 1}}, {"landmark": true}), _ev("quiet", {}, {"landmark": true}), _ev("plain", {"items": {"scrap": 1}})])
	eq(Events.landmark_title(c.events.get_event("meet_ma_in_person")), "Meet Ma In Person", "true takes the event id as words")
	eq(Events.landmark_title(c.events.get_event("plain")), "", "no flag, no landmark")
	check(_take(c, "meet_ma_in_person", ship)["lines"].has("Landmark: Meet Ma In Person"), "the id title shows")
	check(_take(c, "quiet", ship)["lines"].is_empty(), "a choice with no effects does not count (the rule of once)")
	check(_take(c, "plain", ship)["lines"].all(func(l): return not l.begins_with("Landmark")), "and a plain event is no landmark")
	eq(c.landmarks, ["meet_ma_in_person"], "only the one is in the log")


# --- the ending effect ------------------------------------------------------------------------------------------

func test_the_ending_effect_is_handed_back_and_recorded_in_the_campaign() -> void:
	_scenario("endings")
	var c := _camp([_ev("fin", {"ending": "fx_end"}), _ev("go", {"items": {"scrap": 1}})])
	var ship := _ship()
	eq(_take(c, "go", ship)["ending"], "", "an ordinary outcome has no ending")
	eq(c.ending, "", "and the run goes on")
	var r := _take(c, "fin", ship)
	eq(r["ending"], "fx_end", "choose hands the ending back")
	eq(c.ending, "fx_end", "the campaign knows the run is won")
	eq(c.chronicle[-1]["kind"], "ending", "and the run log ends with it")
	eq(c.events.apply({"ending": "fx_end"}, c, ship)["ending"], "fx_end", "apply does as well (after_win effects use it)")
	var won := c.fight_done({"state": "won"}, ship, {"effects": {"ending": "fx_end"}})
	eq(won["ending"], "fx_end", "a won fight's after_win can end the run")
	eq(c.fight_done({"state": "won"}, ship)["ending"], "", "and one without does not")
	_done()


# --- from the event panel to the front door ----------------------------------------------------------------------

func _screen() -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [_ship()]
	var map := MapView.new()
	map.sim = sim
	map.size = Vector2(1600.0, 900.0)
	map.new_seed = 5
	map.open()
	map.event_panel.size = map.size
	map.event_panel.close()  # Ma's introduction
	return {"map": map, "sim": sim}


func _free_screen(d: Dictionary) -> void:
	d["map"].free()
	d["sim"].free()


func test_an_ending_outcome_opens_the_win_through_the_event_panel_and_the_map() -> void:
	_scenario("endings")
	var d := _screen()
	var map: MapView = d["map"]
	var old: Campaign = map.campaign
	var won: Array = []
	map.run_won.connect(func(camp, id): won.append([camp, id]))
	map.event_panel.open_event(_ev("fin", {"ending": "fx_end"}))
	eq(map.event_panel.choose(0), "", "the choice is taken")
	eq(map.event_panel.result["ending"], "fx_end", "the result carries the ending")
	eq(won.size(), 0, "nothing opens until Continue")
	map.event_panel.proceed()
	eq(won.size(), 1, "Continue ends the run")
	check(won[0][0] == old and won[0][1] == "fx_end", "with the finished campaign and the ending")
	eq(old.ending, "fx_end", "which knows its ending")
	check(map.campaign != old and map.campaign.ending == "", "a fresh campaign waits behind the ending screen")
	check(not map.visible and not map.event_panel.visible, "the map and the panel are put away")
	_free_screen(d)
	_done()


func test_a_won_fight_whose_after_win_ends_the_run_goes_to_the_ending_after_the_notice() -> void:
	_scenario("endings")
	var d := _screen()
	var map: MapView = d["map"]
	var won: Array = []
	map.run_won.connect(func(camp, id): won.append(id))
	map._fighting = true
	map._after_win = {"text": "The last gate-keeper falls.", "effects": {"ending": "fx_end"}}
	map._on_fight_finished({"state": "won", "enemy": null})
	check(map.event_panel.visible and map.event_panel.page == "result", "the notice of the won fight is up")
	eq(won.size(), 0, "the ending waits for it")
	map.event_panel.proceed()
	eq(won, ["fx_end"], "and comes after")
	_free_screen(d)
	_done()


func test_the_front_door_records_a_win_with_its_score_and_the_ship_in_the_hall() -> void:
	_scenario("endings")
	_clean()
	var fd := FrontDoor.new()
	fd.profile = Profile.new(TMP)
	var c := _camp([_ev("lm", {"items": {"scrap": 1}}, {"landmark": true})])
	c.profile = fd.profile
	c.jumps = 52
	var ship := _ship()
	_take(c, "lm", ship)
	c.finish("fx_end")
	var rep := fd.record_win(c, ship, "fx_end")
	var rec: Dictionary = fd.profile.runs[-1]
	check(rec["won"] and rec["ending"] == "fx_end" and rec["ending_title"] == "The Fixture Ending", "the record says it was won, and how")
	eq(rec["score"], rep["score"]["total"], "with the score of the report")
	eq(rec["jumps"], 52, "and the usual numbers")
	var line := Profile.run_line(rec)
	check(line.contains("The Fixture Ending") and line.contains("score %d" % rec["score"]), "the menu line names the ending and the score: " + line)
	eq(fd.profile.hall.size(), 1, "the ship went into the hall of ships")
	eq(fd.profile.hall[0]["ending"], "fx_end", "with its ending")
	check(Ship.from_design(fd.profile.hall_file(0)) != null, "as a design that loads again")
	check(not Profile.run_line({"ship": "X"}).contains("score"), "a lost run's line has no score")
	fd.free()
	_clean()
	_done()


# --- the score and the report -------------------------------------------------------------------------------------

func test_the_score_adds_up() -> void:
	_scenario("endings")
	var c := Campaign.new(3)
	c.jumps = 50
	c.landmarks = ["a", "b"]
	var ship := _ship()
	ship.inventory.add("credits", 1234 - ship.inventory.count("credits"))
	var crew := ship.crew.size()
	ship.crew[0].hp = 0.0
	var s = c.current_sector()
	var open: Array = s.pois.filter(func(p): return not ["station", "store"].has(p["type"]))  # a station or store never becomes done
	check(open.size() >= 2, "the start sector has POIs to finish")
	eq(Endings.pois_done(c), 0, "none done yet")
	s.resolve(open[0]["id"])
	s.resolve(open[1]["id"])
	eq(Endings.pois_done(c), 2, "two POIs done")
	var sc := Endings.score(c, ship, "fx_end")
	var want := 1000 + 123 + (crew - 1) * 50 + 2 * 10 + 2 * 100 - (50 - 40)
	eq(sc["total"], want, "base + credits/10 + crew x 50 + POIs x 10 + landmarks x 100 - jumps over par")
	eq(sc["rows"].map(func(r): return r["points"]), [1000, 123, (crew - 1) * 50, 20, 200, -10], "row by row")
	eq(sc["rows"][0]["label"], "The Fixture Ending", "the first row is the ending")
	var quick := Endings.score(c, ship, "fx_quick")
	eq(quick["total"], 500 + 123 + (crew - 1) * 50 + 20 + 200 - 40, "an ending's own par (10) replaces the common one (40)")
	c.jumps = 5000
	eq(Endings.score(c, ship, "fx_end")["total"], 0, "the score never goes below 0")
	c.jumps = 10
	eq(Endings.score(c, ship, "fx_end")["rows"][5]["points"], 0, "under par costs nothing")
	eq(Endings.score(c, null, "fx_end")["rows"][2]["points"], 0, "no ship, no crew")
	_done()


func test_the_report_has_what_the_screen_shows() -> void:
	_scenario("endings")
	var c := _camp([_ev("lm", {"unlock": "fx_skin"}, {"landmark": "Seeing the Fixture"})])
	var ship := _ship()
	c.jumps = 12
	_take(c, "lm", ship)
	c.events.apply({"unlock": "fx_tender"}, c, ship)
	c.finish("fx_end")
	var rep := Endings.report(c, ship, "fx_end")
	eq(rep["ending"]["title"], "The Fixture Ending", "the title")
	check(str(rep["ending"]["epilogue"]).length() > 20, "and the epilogue")
	eq(rep["landmarks"], [{"id": "lm", "title": "Seeing the Fixture", "jumps": 12}], "the landmarks")
	eq(rep["unlocks"].map(func(u): return u["name"]), ["Gilt hull", "Fixture Tender"], "the unlocks earned, in order")
	eq(rep["log"].map(func(x): return x["kind"]), ["landmark", "unlock", "unlock", "ending"], "the run log in order")
	eq(rep["log"][1]["text"], "Gilt hull", "an unlock reads as its name")
	eq(rep["log"][3]["text"], "The Fixture Ending", "and the ending as its title")
	check(rep["regions"].has("Clan Space"), "the regions visited include the start's: " + str(rep["regions"]))
	eq(rep["crew"].size(), ship.crew.size(), "the crew alive")
	eq(rep["ship"], ship.name, "the ship's name")
	check(Endings.report(c, null, "no_such_ending")["ending"]["title"] == "The End", "an unknown ending still reads")
	_done()


func test_the_ending_screen_opens_with_the_report_and_has_the_two_buttons() -> void:
	_scenario("endings")
	var c := _camp([_ev("lm", {"unlock": "fx_skin"}, {"landmark": true})])
	var ship := _ship()
	_take(c, "lm", ship)
	c.finish("fx_end")
	var rep := Endings.report(c, ship, "fx_end")
	var s := EndingScreen.new()
	s.size = Vector2(1600.0, 900.0)
	var got: Array = []
	s.chosen.connect(func(id): got.append(id))
	s.open_ending(rep, ship)
	check(s.visible and s.report["ending"]["id"] == "fx_end", "open_ending shows the report")
	var lay := s.layout()
	var p: Rect2 = lay["panel"]
	var parts := ["frame", "epilogue", "hall", "score", "unlocks", "log"]
	for k in parts:
		check(p.encloses(lay[k]), k + " is inside the panel")
	for i in parts.size():
		for j in range(i + 1, parts.size()):
			check(not lay[parts[i]].intersects(lay[parts[j]]), "%s and %s do not overlap" % [parts[i], parts[j]])
	check(lay["frame"].encloses(lay["art"]) and lay["art"].size == Vector2(640.0, 360.0), "the art is drawn at 2x inside its frame")
	check(lay["hall"].encloses(lay["ship"]), "the ship is drawn inside the hall frame")
	for i in 2:
		check(p.encloses(s.button_rect(i)), "button %d is inside the panel" % i)
		for k in parts:
			check(not s.button_rect(i).intersects(lay[k]), "button %d clears %s" % [i, k])
		eq(s.button_at(s.button_rect(i).get_center()), i, "a click on button %d finds it" % i)
	check(s.log_lines().size() <= EndingScreen.LIST_LINES, "the run log fits its box")
	check(s.log_lines()[1].begins_with("Crew alive (%d)" % ship.crew.size()), "it lists the crew: " + s.log_lines()[1])
	check(s.log_lines().any(func(l): return l.contains("Landmark: Lm")), "and the landmark: " + str(s.log_lines()))
	eq(s.unlock_lines(), ["Gilt hull  (hull skin)"], "the unlocks box")
	s._input(_key(KEY_N))
	check(not s.visible, "N closes it")
	s.open_ending(rep, ship)
	s._input(_key(KEY_DOWN))
	s._input(_key(KEY_ENTER))
	eq(got, ["new", "menu"], "N is New run, Down + Enter is Main menu")
	s.report = {}
	eq(s.unlock_lines(), ["Nothing new this run."], "no unlocks, no list")
	var many := []
	for i in 9:
		many.append({"jumps": i, "kind": "landmark", "text": "L%d" % i})
	s.report = {"log": many}
	var lines := s.log_lines()
	eq(lines.size(), EndingScreen.LIST_LINES, "a long log is cut to its box")
	check(lines[-1].begins_with("... and "), "with a count of the rest: " + lines[-1])
	s.free()
	_done()


# --- the profile --------------------------------------------------------------------------------------------------

func test_the_profile_keeps_unlocks_landmarks_and_loads_an_older_file() -> void:
	_clean()
	var p := Profile.new(TMP)
	check(not p.has_unlock("a") and not p.has_landmark("m"), "empty at first")
	check(p.unlock("a"), "a new unlock is new")
	check(not p.unlock("a"), "and then not")
	check(p.record_landmark("m", "Meeting"), "a new landmark is new")
	check(not p.record_landmark("m", "Meeting"), "and then not")
	var q := Profile.new(TMP)
	check(q.has_unlock("a") and q.has_landmark("m") and q.landmarks["m"]["title"] == "Meeting", "both are in the file")
	eq(Profile.VERSION, 6, "the file is version 6")
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string('{"version": 1, "hints": {"picked": true}, "runs": [{"ship": "Old"}]}')
	f.close()
	var old := Profile.new(TMP)
	check(old.unlocks.is_empty() and old.landmarks.is_empty() and old.hall.is_empty(), "a version 1 file loads with none of them")
	eq(old.runs.size(), 1, "and keeps its runs")
	f = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string('{"unlocks": 3, "landmarks": [1], "hall": [5, {"x": 1}]}')
	f.close()
	var bad := Profile.new(TMP)
	check(bad.unlocks.is_empty() and bad.landmarks.is_empty() and bad.hall.is_empty(), "wrong shapes are an empty profile")
	_clean()


func test_the_hall_of_ships_keeps_the_last_twenty() -> void:
	_clean()
	var prof := Profile.new(TMP)
	var ship := _ship()
	var design := Endings.design_of(ship)
	eq(design["crew"].size(), ship.crew.size(), "the design lists the crew alive")
	for i in 22:
		eq(prof.add_to_hall(design, {"ship": "S%d" % i, "ending": "fx_end", "score": i}), "", "ship %d is saved" % i)
	eq(prof.hall.size(), Profile.HALL_MAX, "twenty are kept")
	eq([prof.hall[0]["ship"], prof.hall[-1]["ship"]], ["S2", "S21"], "the newest twenty")
	eq(DirAccess.get_files_at(prof.hall_dir()).size(), Profile.HALL_MAX, "the dropped ones' files are gone")
	check(not FileAccess.file_exists(prof.hall_dir() + "/hall_0001.json") and FileAccess.file_exists(prof.hall_dir() + "/hall_0022.json"), "the oldest went, the newest stayed")
	var back = Ship.from_design(prof.hall_file(19))
	check(back != null and back.name == ship.name, "a hall file loads as a ship design")
	eq(back.crew_plan.size(), ship.crew.size(), "with its crew")
	eq(prof.hall_file(20), "", "there is no file past the end")
	var again := Profile.new(TMP)
	eq([again.hall.size(), again.hall_seq], [Profile.HALL_MAX, 22], "the hall and its counter are in the profile file")
	check(FileAccess.get_file_as_string(TMP).length() < 20000, "which stays small: the designs are files of their own")
	_clean()


func test_the_campaign_save_keeps_the_run_log() -> void:
	_scenario("endings")
	var c := _camp([_ev("lm", {"unlock": "fx_skin"}, {"landmark": "Seeing the Fixture"})])
	var ship := _ship()
	c.jumps = 7
	_take(c, "lm", ship)
	var d := c.to_dict()
	var c2 := Campaign.new(1)
	eq(c2.load_dict(d), "", "the save loads")
	eq([c2.landmarks, c2.unlocks_earned], [["lm"], ["fx_skin"]], "landmarks and unlocks are in it")
	eq(c2.chronicle.map(func(x): return x["kind"]), ["landmark", "unlock"], "and the run log")
	eq(c2.chronicle[0]["text"], "Seeing the Fixture", "with its text")
	eq(c2.ending, "", "a loaded run is not over")
	for k in ["landmarks", "unlocks_earned", "chronicle"]:
		d.erase(k)
	var c3 := Campaign.new(1)
	eq(c3.load_dict(d), "", "a save from before the endings still loads")
	eq([c3.landmarks, c3.unlocks_earned, c3.chronicle], [[], [], []], "with none of them")
	_done()


# --- the catalogues and their validators ---------------------------------------------------------------------------

func test_the_real_data_and_the_fixture_pack_validate() -> void:
	for msg in Unlocks.validate() + Endings.validate() + Hangar.validate():
		check(false, msg)
	for msg in Events.new().validate():
		check(false, msg)
	_scenario("endings")
	eq(Unlocks.validate(), [], "the fixture unlocks are sound")
	eq(Endings.validate(), [], "the fixture endings are sound")
	eq(Hangar.validate(), [], "and so are its ships")
	eq(Events.new().validate(), [], "and its events: unlock and ending ids exist")
	eq(Unlocks.for_ship("fx_wisp_c"), "fx_wisp", "an unlock names the ship it opens")
	eq(Unlocks.for_ship("starter_courier"), "", "and the starters have none")
	check(not Content.has("ships", "fx_not_built"), "a pending starter unlock names a design not built yet, and still validates")
	eq(Endings.title_of("fx_end"), "The Fixture Ending", "an ending's title")
	eq(Endings.title_of("nope"), "The End", "an unknown one reads The End")
	_done()


func test_the_validators_name_what_is_wrong() -> void:
	_scenario("endings_bad")
	var u := Unlocks.validate()
	check(_has(u, ["bad_kind", "unknown kind 'trophy'"]), "a kind that does not exist")
	check(_has(u, ["bad_ship", "no_such_design"]), "a starter ship that is no design")
	check(_has(u, ["bad_payload", "payload needs \"species\""]), "a payload without its key")
	check(_has(u, ["bad_text", "name must be a non-empty string"]) and _has(u, ["bad_text", "how must be"]) and _has(u, ["bad_text", "unknown key 'extra'"]), "a missing name and how, and a stray key")
	check(_has(u, ["bad_blueprint", "not a recipe"]), "a blueprint that is no recipe")
	check(u.all(func(m): return str(m).contains("unlocks.json")), "each message names the file")
	var e := Endings.validate()
	check(_has(e, ["bad_end", "title must"]) and _has(e, ["bad_end", "base_score must be a number"]) and _has(e, ["bad_end", "unknown key 'par'"]), "an ending with no title, a text for a score, a typo")
	var ev := Events.new().validate()
	check(_has(ev, ["bad_refs", "landmark must be"]), "a landmark that is a number")
	check(_has(ev, ["bad_refs", "unknown unlock id 'no_such_unlock'"]), "an unlock id that is not in the catalogue")
	check(_has(ev, ["bad_refs", "unknown ending id 'no_such_ending'"]), "an ending id that is not")
	check(_has(ev, ["bad_landmark", "a landmark needs a choice with effects"]), "a landmark nothing can record")
	_done()


func test_the_new_effect_keys_are_known_to_the_validator() -> void:
	for k in ["unlock", "ending"]:
		check(Events.EFFECT_KEYS.has(k), k + " is an effect")
	check(Events.EVENT_KEYS.has("landmark"), "landmark is an event key")
	check(Content.KINDS.has("unlocks") and Content.KINDS.has("endings"), "packs may carry unlocks.json and endings.json")


# --- the hangar -------------------------------------------------------------------------------------------------------

func test_the_hangar_lists_the_starters_and_their_locks() -> void:
	_scenario("endings")
	var list := Hangar.starters()
	var ids := list.map(func(e): return e["id"])
	for id in ["starter_rustbucket", "starter_courier", "starter_prism", "fx_tender", "fx_open_b", "fx_wisp_c"]:
		check(ids.has(id), id + " is in the hangar")
	check(not ids.has("pirate_raider") and not ids.has("rustfang_rammer"), "the enemies are not")
	var by := {}
	for e in list:
		by[e["id"]] = e
	eq([by["starter_rustbucket"]["group"], by["starter_courier"]["group"], by["starter_prism"]["group"]], ["Clans", "Concord", "Lumen"], "the three starters sit under their factions (data/hangar.json)")
	eq([by["starter_rustbucket"]["layout"], by["starter_rustbucket"]["unlock"]], ["A", ""], "layout A, open from the start")
	eq(by["starter_rustbucket"]["crew"].size(), 1, "with its crew: the soldier alone (playtest 2, A1)")
	check(by["starter_rustbucket"]["blurb"].length() > 30, "and its pitch")
	eq(Hangar.groups(list), ["Clans", "Concord", "Fixture", "Lumen", "Wisp"], "the tabs, in order")
	eq(by["fx_tender"]["unlock"], "fx_tender", "a design's own hangar.unlock")
	eq(by["fx_wisp_c"]["unlock"], "fx_wisp", "an unlock that names the design locks it too")
	for e in [by["starter_rustbucket"], by["starter_courier"], by["starter_prism"], by["fx_open_b"]]:
		check(not Hangar.locked(e, null), "%s is open with nothing earned" % e["id"])
	check(Hangar.locked(by["fx_tender"], null) and Hangar.locked(by["fx_wisp_c"], null), "the others are locked")
	_clean()
	var prof := Profile.new(TMP)
	prof.unlock("fx_tender")
	check(not Hangar.locked(by["fx_tender"], prof), "earning the unlock opens the ship")
	check(Hangar.locked(by["fx_wisp_c"], prof), "and only that one")
	eq(Hangar.hint(by["fx_tender"]), "Reach the Fixture ending.", "a locked ship says how to open it")
	eq(Hangar.hint({"unlock": "zzz"}), Hangar.LOCKED_HINT, "with a unlock that has no text, just 'Locked.'")
	eq(Hangar.find(list, "Fixture", "B"), ids.find("fx_open_b"), "find a group's layout")
	eq(Hangar.find(list, "Fixture", "C"), -1, "or none")
	eq(Hangar.open_count(list, "Fixture", null), [1, 2], "one of the Fixture's two is open")
	eq(Hangar.open_count(list, "Fixture", prof), [2, 2], "both with the unlock")
	_clean()
	_done()


## A hangar on a sim of its own with a build mode and a crew view wired in, and a profile.
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


func test_the_hangar_screen_dims_locked_ships_and_refuses_them() -> void:
	_scenario("endings")
	_clean()
	var prof := Profile.new(TMP)
	var d := _hangar(prof)
	var h: HangarView = d["h"]
	eq(h.cards.size(), 6, "three starters and three fixture ships")
	eq(h.cards[h.sel]["id"], "starter_rustbucket", "it opens on the first open ship")
	check(h.visible and not h.is_locked(h.sel), "and shows")
	h._input(_key(KEY_RIGHT))
	eq(h.cards[h.sel]["id"], "starter_courier", "Right is the next tab: Concord")
	h._input(_key(KEY_RIGHT))
	eq(h.cards[h.sel]["id"], "fx_tender", "and the next: Fixture, on layout A (kept)")
	check(h.is_locked(h.sel), "the Fixture Tender is locked")
	var why := h.choose(h.sel)
	eq(why, "Locked: Reach the Fixture ending.", "choosing it is refused with the hint")
	eq(h.message, why, "which the screen shows")
	eq(d["sim"].player_ship().name, "Starter", "the ship did not change")
	check(h.visible, "and the hangar stays")
	h._input(_key(KEY_ENTER))
	eq(d["sim"].player_ship().name, "Starter", "Enter on a locked ship does nothing either")
	h._input(_key(KEY_B))
	eq(h.cards[h.sel]["id"], "fx_open_b", "B is the Fixture's layout B")
	check(not h.is_locked(h.sel), "which is open")
	h._input(_key(KEY_C))
	eq(h.cards[h.sel]["id"], "fx_open_b", "there is no layout C there: nothing moves")
	h._input(_key(KEY_UP))
	eq(h.cards[h.sel]["id"], "fx_tender", "Up goes back to A")
	h._input(_key(KEY_DOWN))
	h._input(_key(KEY_DOWN))
	eq(h.cards[h.sel]["id"], "fx_tender", "Down wraps over the layouts the group has (A, B)")
	h._input(_key(KEY_LEFT))
	h._input(_key(KEY_LEFT))
	h._input(_key(KEY_LEFT))
	eq(h.cards[h.sel]["group"], "Wisp", "Left from the first tab wraps to the last")
	eq(h.cards[h.sel]["layout"], "C", "and takes that group's only layout")
	prof.unlock("fx_tender")
	prof.unlock("fx_wisp")
	h.open()
	var ids := h.cards.map(func(c): return c["id"])
	check(not h.is_locked(ids.find("fx_tender")) and not h.is_locked(ids.find("fx_wisp_c")), "with the unlocks earned the ships are open on the next visit")
	_free_all(d)
	_clean()
	_done()


func test_the_hangar_screen_loads_an_open_ship_and_shows_its_numbers() -> void:
	_scenario("endings")
	_clean()
	var d := _hangar(Profile.new(TMP))
	var h: HangarView = d["h"]
	var got: Array = []
	h.chosen.connect(func(): got.append(true))
	h.select_group("Concord")
	eq(h.cards[h.sel]["name"], "Courier", "the Concord tab holds the Courier")
	var pv := h.preview()
	check(not pv.is_empty(), "its preview loads")
	eq(pv["stats"]["weapons"], ["Pulse Mk1"], "with its weapons")
	check(pv["stats"]["supply"] >= pv["stats"]["demand"] and pv["stats"]["hull"] > 0.0, "power and hull")
	eq(h.choose(h.sel), "", "choosing an open ship works")
	eq(d["sim"].player_ship().name, "Courier", "the ship is the Courier")
	check(not h.visible and got.size() == 1, "the hangar is put away and says so")
	eq(h.choose(99), "no such ship", "an index off the list is refused")
	h.select_group("Fixture")
	check(h.preview().is_empty(), "a design that cannot be loaded has no preview, and nothing breaks")
	_free_all(d)
	_clean()
	_done()


func test_the_hangar_tabs_and_button_answer_the_mouse() -> void:
	_scenario("endings")
	_clean()
	var d := _hangar(Profile.new(TMP))
	var h: HangarView = d["h"]
	var lay := h.layout()
	var p: Rect2 = lay["panel"]
	check(p.encloses(lay["map"]) and p.encloses(lay["info"]) and p.encloses(lay["button"]), "plan, info and button are inside the panel")
	check(not lay["map"].intersects(lay["info"]), "the plan and the info do not overlap")
	eq(lay["groups"].size(), 5, "five tabs fit")
	for r in lay["groups"]:
		check(p.encloses(r), "a tab is inside the panel")
	eq(h.zone_at(lay["groups"][1].get_center()), {"kind": "group", "index": 1}, "a tab is found")
	h.click(lay["groups"][2].get_center())
	eq(h.cards[h.sel]["group"], "Fixture", "clicking a tab selects its group")
	h.click(lay["layouts"][1].get_center())
	eq(h.cards[h.sel]["id"], "fx_open_b", "clicking B selects layout B")
	eq(h.zone_at(lay["layouts"][2].get_center()), {}, "a layout the group lacks cannot be clicked")
	eq(h.zone_at(lay["button"].get_center()), {"kind": "button"}, "the button is found")
	h.click(lay["groups"][1].get_center())
	h.click(lay["button"].get_center())
	eq(d["sim"].player_ship().name, "Courier", "the button loads the selected open ship")
	_free_all(d)
	_clean()
	_done()


func test_n_asks_first_and_the_hangar_keeps_the_pickers_api() -> void:
	_scenario("endings")
	_clean()
	var d := _hangar(Profile.new(TMP))
	var h: HangarView = d["h"]
	h.close()
	h.ask()
	eq(h.mode, HangarView.Mode.CONFIRM, "ask() is the Y / N question")
	h._input(_key(KEY_N))
	check(not h.visible, "N keeps the ship")
	h.ask()
	h._input(_key(KEY_Y))
	check(h.visible and h.mode == HangarView.Mode.CHOOSE, "Y shows the hangar")
	var back := [0]
	h.on_escape = func(): back[0] += 1
	h._input(_key(KEY_ESCAPE))
	check(not h.visible and back[0] == 1, "Esc closes it and calls on_escape once")
	_free_all(d)
	_clean()
	_done()


func test_the_scene_uses_the_hangar_in_place_of_the_picker() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	var node = main.get_node_or_null("PickerLayer/ShipPicker")
	check(node != null and node.get_script() == HangarView, "main.tscn's picker node runs the hangar")
	main.free()
