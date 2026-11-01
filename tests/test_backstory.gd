extends "res://tests/base_test.gd"
## Who the crew are (scripts/crew/backstory.gd, data/backstory.json): the same crew member tells the same story every
## time and after a save, a unique character tells its lore, a drone says nothing much, and the story shows on the crew
## card, in the hire row and under the recruit's event text.

const Backstory = preload("res://scripts/crew/backstory.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const CrewBar = preload("res://scripts/ui/crew_bar.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Characters = preload("res://scripts/crew/characters.gd")
const Content = preload("res://scripts/data/content.gd")
const DriftTests = preload("res://tests/test_drift.gd")
const Events = preload("res://scripts/space/events.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Ship = preload("res://scripts/ship/ship.gd")


func _ship() -> Ship:
	var s: Ship = Ship.from_design("res://data/ships/starter_rustbucket.json")
	s.crew_plan = [{"name": "Soldier", "species": "human"}]
	Jobs.spawn_crew(s)
	return s


func test_the_same_name_and_species_tell_the_same_story() -> void:
	var a := Backstory.of("Gneiss", "basalt")
	eq(Backstory.of("Gneiss", "basalt"), a, "twice the same")
	check(a.begins_with("Back ") and a.contains("I'm out here because"), "two sentences of a life: " + a)
	var stories := {}
	for n in ["Slate", "Tuff", "Shale", "Flint", "Gabbro", "Cairn", "Scree", "Tor"]:
		stories[Backstory.of(n, "basalt")] = true
	check(stories.size() >= 7, "other names, other lives: %d of 8 differ" % stories.size())
	check(Backstory.of("Gneiss", "human") != a, "the species is part of the seed")


func test_every_species_has_a_home_and_a_story() -> void:
	var ids: Array = Content.ids("species")
	check(ids.size() >= 30, "30 species: %d" % ids.size())
	var home: Dictionary = Backstory.config()["home"]
	for id in ids:
		check(home.has(id), id + ": no home in data/backstory.json")
		var s := Backstory.of("Test", str(id))
		check(s != "" and not s.contains("{"), "%s: a whole story, no holes: %s" % [id, s])


func test_the_player_a_drone_and_an_unknown_species_are_handled() -> void:
	eq(Backstory.of("You", "human", "", true), Backstory.config()["player"], "the soldier has a line of their own")
	eq(Backstory.of("Bolt", "drone"), "Repair drone. Does not talk about it.", "a drone does not talk about it")
	var m := CrewMember.new("Bolt", Vector2.ZERO, "drone")  # the species may not exist: no crash
	eq(m.backstory(), "Repair drone. Does not talk about it.", "on the crew member too")
	var odd := Backstory.of("Zork", "klingon")
	check(odd.contains("where I'm from") and not odd.contains("{"), "an unknown species still has a story: " + odd)


func test_a_unique_character_shows_its_lore() -> void:
	var ids := Characters.ids()
	check(not ids.is_empty(), "there are characters")
	for id in ids:
		var c := Characters.entry(id)
		var m = CrewMember.from_character(id)
		eq(m.backstory(), str(c["lore"]), id + ": the lore, not a made-up life")
		eq(Backstory.intro(m.name, m.species, id), str(c["lore"]), id + ": and the recruit line is the lore as it stands")


func test_the_story_survives_a_save_and_load() -> void:
	var m := CrewMember.new("Gneiss", Vector2(3, 3), "basalt")
	var story := m.backstory()
	eq(m.to_dict()["story"], story, "saved")
	var back = CrewMember.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	eq(back.story, story, "through the JSON: kept as written")
	eq(back.backstory(), story, "and told again")
	var old := m.to_dict()
	old.erase("story")  # a save from before stories
	eq(CrewMember.from_dict(old).backstory(), story, "an old save gets the same story: it comes from the name and species")


func test_a_recruit_event_has_them_tell_it() -> void:
	var c := Campaign.new(1, {}, Events.new("res://tests"))
	var ship := _ship()
	var r := c.events.apply({"recruit": {"species": "fenn", "name": "Pipp"}}, c, ship, {})
	eq(r["told"], ['Pipp tells you: "%s"' % Backstory.of("Pipp", "fenn")], "what Pipp says about themselves")
	eq(ship.crew[-1].story, Backstory.of("Pipp", "fenn"), "and it is on the crew member from day one")
	var ev := {"id": "t", "type": "empty", "weight": 1, "once": false, "requires": {}, "text": "A fenn.",
		"choices": [{"text": "Hire", "outcomes": [{"weight": 100, "text": "Pipp signs on.", "effects": {"recruit": {"species": "fenn", "name": "Tuzzle"}}}]}]}
	var res := c.events.choose(ev, 0, c, ship, {})
	check(res["text"].begins_with("Pipp signs on.\n\nTuzzle tells you: \""), "under the outcome's text: " + res["text"])
	var chr := Characters.ids()[0]
	var res2 := c.events.apply({"recruit": {"character": chr}}, c, _ship(), {})
	eq(res2["told"], [str(Characters.entry(chr)["lore"])], "a unique character is told by their lore")


func test_the_hire_row_shows_the_story_and_the_card_tells_it() -> void:
	var t := DriftTests.new()
	var d := t._screen()
	var map = d["map"]
	var ship: Ship = d["sim"].player_ship()
	var c: Campaign = map.campaign
	map.event_panel.close()
	c.cfg = c.cfg.duplicate(true)
	c.cfg["prices"]["recruit_chance"] = 1.0
	c.roll_offers("rusthold", ship)
	var st = map.station_panel
	st.open("rusthold")
	ship.inventory.add("credits", 2000)
	var rows: Array = st.rows(2)
	var found := 0
	for i in rows.size():
		if rows[i]["kind"] == "recruit":
			var note: Dictionary = rows[i + 1]
			var offer: Dictionary = c.offers["rusthold"][rows[i]["index"]]
			eq(note["label"], Backstory.of(str(offer["name"]), str(offer["species"])), "the note under the hire is their story")
			check(note.has("story") and st.row_rect(2, i + 1).size.y > st.ROW_H * 0.9, "and it has room")
			found += 1
	check(found > 0, "there were recruits to read")
	var hire := 0
	for i in rows.size():
		if rows[i]["kind"] == "recruit":
			hire = i
			break
	st.act(2, hire)
	var m = ship.crew[-1]
	check(m.story != "" and m.to_dict().has("story"), "hired: the story is on them and in the save")
	var stub := StubView.new()
	stub.ship = ship
	var bar := CrewBar.new()
	bar.view = stub
	bar.size = Vector2(1600.0, 900.0)
	var rect := CrewBar.card_rects(ship.crew.size(), bar.size)[ship.crew.size() - 1]
	eq(bar._get_tooltip(rect.get_center()), "%s\n%s" % [m.name, m.story], "hover the card: the name and the story")
	eq(bar._get_tooltip(Vector2(5.0, 5.0)), "", "hover elsewhere: nothing")
	bar.free()
	t._free_screen(d)


## Just enough of the crew view (crew_view.gd) for the bar.
class StubView:
	extends RefCounted
	var ship
	var selected = null

	func ship_now():
		return ship

	func bar_visible() -> bool:
		return true


func test_every_starter_blurb_fits_the_hangar_card_and_the_core_three_have_a_history() -> void:
	var n := 0
	for d in Content.ships():
		if not (d["design"] is Dictionary and d["design"].has("hangar")):
			continue
		n += 1
		var blurb := str(d["design"].get("blurb", ""))
		check(blurb.length() > 60 and blurb.length() <= 230, "%s: a blurb of %d chars (the hangar draws 4 lines)" % [d["id"], blurb.length()])
	check(n >= 27, "all the pack starters: %d" % n)
	for id in ["starter_rustbucket", "starter_courier", "starter_prism"]:
		var blurb := str(Content.entry("ships", id).get("design", {}).get("blurb", ""))
		check(blurb.length() <= 230, id + ": fits the card")
		check(blurb.contains("Ma Gantry") or blurb.contains("Concord") or blurb.contains("Lumen"), id + ": says whose it was: " + blurb)
