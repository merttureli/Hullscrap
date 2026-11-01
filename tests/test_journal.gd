extends "res://tests/base_test.gd"
## The journal (scripts/ui/journal_panel.gd): J on the map lists the logs found this run, title first and then the text;
## it scrolls by a log, J / Esc close it, and the help screen lists the key and still fits at 1600 x 900.

const DriftTests = preload("res://tests/test_drift.gd")
const HelpPanel = preload("res://scripts/ui/help_panel.gd")
const JournalPanel = preload("res://scripts/ui/journal_panel.gd")


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_the_journal_lists_the_logs_found() -> void:
	var t := DriftTests.new()
	var d := t._screen()
	var map = d["map"]
	map.event_panel.close()
	var j: JournalPanel = map.journal_panel
	j.size = map.size
	eq(j.entries(), [], "no logs found yet")
	var ids: Array = map.campaign.events.logs.keys().slice(0, 3)
	check(ids.size() == 3, "the game has logs")
	for id in ids:
		map.campaign.logs_found[id] = true
	var list := j.entries()
	eq(list.size(), 3, "three found")
	for k in 3:
		var l: Dictionary = map.campaign.events.logs[ids[k]]
		eq([list[k]["title"], list[k]["text"]], [l["title"], l["text"]], "log %d: its title, then its text" % k)
	map.campaign.logs_found["no_such_log"] = true
	eq(j.entries().size(), 3, "an id the data no longer has is skipped")
	map.campaign.logs_found.erase("no_such_log")
	check(not j.visible, "closed to begin with")
	map._input(_key(KEY_J))
	check(j.visible, "J on the map opens it")
	var cards := j.visible_cards()
	check(cards.size() >= 1 and cards[0]["entry"]["id"] == ids[0], "the first log first")
	for c in cards:
		check(j.panel_rect().encloses(c["rect"]), "a card sits inside the panel")
	j.scroll(1)
	eq(j.top, 1, "down moves a log")
	j.scroll(-5)
	eq(j.top, 0, "and up stops at the first")
	j.scroll(50)
	eq(j.top, 2, "and down at the last")
	j._input(_key(KEY_J))
	check(not j.visible, "J closes it")
	map.open()
	check(map.visible, "the map is still open under it")
	map._input(_key(KEY_J))
	j._input(_key(KEY_ESCAPE))
	check(not j.visible and map.visible, "Esc closes the journal and leaves the map")
	t._free_screen(d)


func test_the_help_lists_the_journal_key_and_still_fits() -> void:
	check(HelpPanel.keys_text().contains("J\n") or HelpPanel.keys_text().begins_with("J\n") or HelpPanel.keys_text().ends_with("\nJ"), "How to play has the J key")
	var text := HelpPanel.all_text()
	check(text.contains("Journal"), "and says what it opens")
	var h := HelpPanel.new()
	h.size = Vector2(1600.0, 900.0)
	var limit: float = h.panel_rect().end.y - 28.0
	for c in HelpPanel.COLUMNS.size():
		check(h.column_end(c) <= limit, "help column %d ends at %d, under the footer line at %d" % [c, int(h.column_end(c)), int(limit)])
	h.free()
