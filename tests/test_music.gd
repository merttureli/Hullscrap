extends "res://tests/base_test.gd"
## data/music.json (the soundtrack: states -> loops, stings, volumes) against the files in assets/audio/music.
## The tracks are made by audio/_src/music/build_music.py. Also the round-2 demos in assets/audio/music/demos: each
## direction has EXPLORE and BATTLE versions that must stay in sync (same length, onsets aligned), plus a transition.

const MUSIC_JSON := "res://data/music.json"
const STATES := ["menu", "explore", "combat", "hollow", "build"]
const STINGS := ["victory", "defeat", "jump", "region_cross", "ada_found", "unlock", "ending"]
const DEMO_DIR := "res://assets/audio/music/demos/"
const DEMOS := ["signal", "long_haul", "black_box", "ledger_ii"]
const REPORT := "res://audio/_src/music/report.json"


func _music() -> Dictionary:
	var f := FileAccess.open(MUSIC_JSON, FileAccess.READ)
	if f == null:
		failures.append("data/music.json is missing")
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _path(d: Dictionary, file: String) -> String:
	return str(d.get("dir", "res://assets/audio/music/")) + file


func test_states_cover_every_mood() -> void:
	var d := _music()
	var states: Dictionary = d.get("states", {})
	for s in STATES:
		check(states.has(s) and (states[s] as Array).size() > 0, "state %s lists at least one track" % s)
	check(states.get("explore", []).size() >= 2, "explore has two tracks to alternate")


func test_stings_cover_the_cues() -> void:
	var stings: Dictionary = _music().get("stings", {})
	for id in STINGS:
		check(stings.has(id), "sting %s exists" % id)


func test_every_file_named_exists() -> void:
	var d := _music()
	var files: Array = []
	for s in d.get("states", {}):
		files.append_array(d["states"][s])
	files.append_array((d.get("stings", {}) as Dictionary).values())
	files.append_array((d.get("volumes", {}) as Dictionary).keys())
	check(files.size() > 0, "music.json names files")
	for f in files:
		check(FileAccess.file_exists(_path(d, f)), "%s exists" % f)


func test_every_loop_imports_with_loop_on() -> void:
	var d := _music()
	for s in d.get("states", {}):
		for f in d["states"][s]:
			var imp := FileAccess.open(_path(d, f) + ".import", FileAccess.READ)
			check(imp != null, "%s has an .import file" % f)
			if imp != null:
				check(imp.get_as_text().contains("loop=true"), "%s imports with loop on" % f)


func test_stings_do_not_loop() -> void:
	var d := _music()
	for id in d.get("stings", {}):
		var imp := FileAccess.open(_path(d, d["stings"][id]) + ".import", FileAccess.READ)
		if imp != null:
			check(imp.get_as_text().contains("loop=false"), "sting %s imports with loop off" % id)


func test_demos_exist() -> void:
	for d in DEMOS:
		for v in ["explore", "battle", "transition"]:
			check(FileAccess.file_exists(DEMO_DIR + "%s_%s.ogg" % [d, v]), "demo %s_%s.ogg exists" % [d, v])


func test_demo_explore_and_battle_lengths_match() -> void:
	for d in DEMOS:
		var x := AudioStreamOggVorbis.load_from_file(DEMO_DIR + d + "_explore.ogg")
		var b := AudioStreamOggVorbis.load_from_file(DEMO_DIR + d + "_battle.ogg")
		check(x != null and b != null, "demo %s loads" % d)
		if x != null and b != null:
			check(x.get_length() > 60.0, "demo %s is about 70 s" % d)
			eq(b.get_length(), x.get_length(), "demo %s battle length matches explore" % d)


func test_demo_onsets_align() -> void:
	# build_music.py decodes both files and cross-correlates their onset curves; the best lag must be zero
	var f := FileAccess.open(REPORT, FileAccess.READ)
	check(f != null, "report.json exists")
	if f == null:
		return
	var demos: Dictionary = (JSON.parse_string(f.get_as_text()) as Dictionary).get("demos", {})
	for d in DEMOS:
		var sync: Dictionary = demos.get(d, {}).get("sync", {})
		check(sync.get("same_length", false), "demo %s: decoded sample counts match" % d)
		check(absf(float(sync.get("onset_lag_ms", 99.0))) <= 2.0, "demo %s: explore and battle onsets align" % d)


func test_demos_are_not_wired_in() -> void:
	check(not FileAccess.get_file_as_string(MUSIC_JSON).contains("demos"), "music.json does not name the demos")
