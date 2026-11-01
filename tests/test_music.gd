extends "res://tests/base_test.gd"
## data/music.json (the soundtrack: states -> loops, stings, volumes) against the files in assets/audio/music.
## The tracks are made by audio/_src/music/build_music.py.

const MUSIC_JSON := "res://data/music.json"
const STATES := ["menu", "explore", "combat", "hollow", "build"]
const STINGS := ["victory", "defeat", "jump", "region_cross", "ada_found", "unlock", "ending"]


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
