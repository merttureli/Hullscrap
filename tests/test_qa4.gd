extends "res://tests/base_test.gd"
## Small fixes found in the Beta 4 playthrough (the qa4 track): the F1 screen, the Beta label, the Ledger's warnings, the hint toast and the menu's sound row.

const HelpPanel = preload("res://scripts/ui/help_panel.gd")
const Profile = preload("res://scripts/ui/profile.gd")
const Advisor = preload("res://scripts/sim/advisor.gd")
const FrontDoor = preload("res://scripts/ui/front_door.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")

const FIXTURE := "res://tests/fixtures/progression.json"


func test_how_to_play_names_the_ledger_key() -> void:
	var found := ""
	for col in HelpPanel.COLUMNS:
		for sec in col:
			for row in sec[1]:
				if str(row[0]) == "L":
					found = "%s: %s" % [sec[0], row[1]]
	check(found.contains("LEDGER") and found.contains("Ledger"), "the L key is on the F1 screen, under the Ledger: '%s'" % found)
	check(HelpPanel.all_text().contains("BOARDING"), "and the boarding keys are still there")


func test_the_beta_label_is_beta_4() -> void:
	eq(Profile.BETA, "Beta 4.1", "the main menu corner says Beta 4.1")


func _advisor() -> Advisor:
	return Advisor.new({}, JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)))


## The warden outguns you and the toll is short at once (the exit beacon with a thin purse): the urgent line (outgunned) is the one the card
## shows. It was shoved off by the toll line a second later, and its once-a-stage was spent unseen.
func test_two_warnings_at_once_the_more_urgent_stays_on_the_card() -> void:
	var a := _advisor()
	var both := [{"id": "outgunned", "level": 3.0}, {"id": "toll", "level": 30.0}]
	eq(a.fire(both, 1), "outgunned", "the more urgent one is first on the card")
	eq(a.fire(both, 1), "", "the next look does not fire the other over it")
	eq(a.warning["id"], "outgunned", "it is still the one on show")
	a.warning = {}  # it has run out (or was clicked away)
	eq(a.fire(both, 1), "toll", "the other one has its turn then")
	eq(a.fire([{"id": "outgunned", "level": 3.0}], 1), "", "(the first one is used up for the stage)")


func test_a_more_urgent_warning_replaces_a_less_urgent_one_on_show() -> void:
	var a := _advisor()
	eq(a.fire([{"id": "scrap", "level": 1.2}], 1), "scrap", "a minor one is on the card")
	eq(a.fire([{"id": "outgunned", "level": 2.0}, {"id": "scrap", "level": 1.2}], 1), "outgunned", "the urgent one comes before it")
	eq(a.warning["id"], "outgunned", "and takes the card")
	var b := _advisor()
	b.fire([{"id": "power", "level": 1.0}], 2)
	eq(b.fire([{"id": "power", "level": 2.0}], 2), "power", "the same warning grown a lot worse still fires again")


func test_the_hint_toast_clears_the_sectors_header_lines() -> void:
	check(FrontDoor.toast_top(false, false, true) >= 92.0, "flying: under the place and the helm line (they sit at y 38 to 90)")
	eq(FrontDoor.toast_top(false, false), 48.0, "build mode: under the top bar, as before")
	eq(FrontDoor.toast_top(true, false, true), 62.0, "a fight has its own header, the key hints")
	check(FrontDoor.toast_top(false, true, true) > 90.0, "the map's own header rules over the sector's")


func test_every_sound_label_stays_inside_its_slider() -> void:
	var m := MainMenu.new()
	m.size = Vector2(1600.0, 900.0)
	var font := ThemeDB.fallback_font
	for i in MainMenu.SOUND_KINDS.size():
		var r := m.slider_rect(i)
		var w := font.get_string_size("%s 100%%" % MainMenu.SOUND_KINDS[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var x := MainMenu.slider_label_x(w, r)
		check(x + w <= r.end.x + 0.01, "%s 100%% ends at %.0f, inside its slider (%.0f)" % [MainMenu.SOUND_KINDS[i][1], x + w, r.end.x])
		check(x >= (m.size.x - MainMenu.BTN.x) / 2.0 - 0.01 and x + w <= (m.size.x + MainMenu.BTN.x) / 2.0 + 0.01, "and inside the width of the buttons")
		if i > 0:
			var prev := m.slider_rect(i - 1)
			var pw := font.get_string_size("%s 100%%" % MainMenu.SOUND_KINDS[i - 1][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			check(MainMenu.slider_label_x(pw, prev) + pw < x, "%s does not run into the label before it" % MainMenu.SOUND_KINDS[i][1])
	m.free()


func test_a_body_gear_line_fits_its_loadout_slot() -> void:
	var Loadout = load("res://scripts/board/board_loadout.gd")
	var Kit = load("res://scripts/board/kit.gd")
	var font := ThemeDB.fallback_font
	var longest := 0.0
	for item in Kit.cfg()["bodies"]:
		var w := font.get_string_size(Loadout.body_sub(str(item)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		longest = maxf(longest, w)
		check(54.0 + w <= Loadout.SLOT.x - 4.0, "%s: '%s' is %.0f px, the slot has %.0f after its icon" % [item, Loadout.body_sub(str(item)), w, Loadout.SLOT.x - 58.0])
	check(longest > 60.0, "(measured the real lines)")
	eq(Loadout.body_sub("exosuit"), "35% less dmg, sealed", "the short form of the sentence for the slot")
	eq(Kit.body_line("exosuit"), "Takes 35% less damage. Sealed.", "the hover keeps the whole one")


## A thin purse at the exit with a few hundred scrap to sell gets the toll line (it waited for 600 scrap, so a poorer player heard nothing).
func test_the_toll_line_comes_with_a_few_hundred_scrap_to_sell() -> void:
	var a := Advisor.new(Advisor.load_words(), JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)))
	var v := {"stage": 3, "hops": 1, "warden_up": true, "credits_over_toll": -40, "scrap": 200}
	check(a.conditions(v).any(func(c): return c["id"] == "toll"), "200 scrap and short of the toll: the toll line")
	v["scrap"] = 50
	check(not a.conditions(v).any(func(c): return c["id"] == "toll"), "with next to no scrap there is nothing to sell: no line")


## The loadout's choice box shows every option the panel has room for (a tenth mod could not be reached with nine rows).
func test_the_loadout_choices_use_the_panels_height() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/board/board_loadout.gd")
	check(not src.contains("minf(float(opts.size()), 9.0)"), "no fixed nine-row cap")
	var Loadout = load("res://scripts/board/board_loadout.gd")
	check(floorf((540.0 - 38.0) / Loadout.ROW) >= 10.0, "a panel of 540 px holds ten rows or more")
