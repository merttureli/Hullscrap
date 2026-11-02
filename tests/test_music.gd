extends "res://tests/base_test.gd"
## data/music.json v2 (pieces with EXPLORE and BATTLE versions, regions -> pieces, states -> loops, stings, volumes)
## against the files in assets/audio/music. The tracks are made by audio/_src/music/build_music.py. A piece's two versions
## must stay in sync (same length, onsets aligned); so must the round-2 demos in assets/audio/music/demos.

const MUSIC_JSON := "res://data/music.json"
const STATES := ["menu", "hollow", "build"]
const PIECES := ["black_box"]
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
	for p in d.get("pieces", {}).values():
		files.append_array([p.get("explore", ""), p.get("battle", "")])
	files.append_array((d.get("volumes", {}) as Dictionary).keys())
	check(files.size() > 0, "music.json names files")
	for f in files:
		check(FileAccess.file_exists(_path(d, f)), "%s exists" % f)


func test_every_loop_imports_with_loop_on() -> void:
	var d := _music()
	var loops: Array = []
	for s in d.get("states", {}):
		loops.append_array(d["states"][s])
	for p in d.get("pieces", {}).values():
		loops.append_array([p.get("explore", ""), p.get("battle", "")])
	for f in loops:
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


func test_pieces_have_both_versions_in_sync() -> void:
	var d := _music()
	var pieces: Dictionary = d.get("pieces", {})
	for name in PIECES:
		check(pieces.has(name), "piece %s is in music.json" % name)
	for name in pieces:
		var p: Dictionary = pieces[name]
		check(float(p.get("bpm", 0)) > 40.0, "piece %s has its tempo" % name)
		var x := AudioStreamOggVorbis.load_from_file(_path(d, p.get("explore", "")))
		var b := AudioStreamOggVorbis.load_from_file(_path(d, p.get("battle", "")))
		check(x != null and b != null, "piece %s: both versions load" % name)
		if x != null and b != null:
			check(x.get_length() > 100.0, "piece %s is a full loop" % name)
			eq(b.get_length(), x.get_length(), "piece %s: battle length matches explore" % name)


func test_piece_onsets_align() -> void:
	var f := FileAccess.open(REPORT, FileAccess.READ)
	check(f != null, "report.json exists")
	if f == null:
		return
	var rep: Dictionary = (JSON.parse_string(f.get_as_text()) as Dictionary).get("pieces", {})
	for name in PIECES:
		var sync: Dictionary = rep.get(name, {}).get("sync", {})
		check(sync.get("same_length", false), "piece %s: decoded sample counts match" % name)
		check(absf(float(sync.get("onset_lag_ms", 99.0))) <= 2.0, "piece %s: explore and battle onsets align" % name)


func test_every_region_names_a_piece() -> void:
	var d := _music()
	var regions: Dictionary = d.get("regions", {})
	check(regions.has("default"), "regions has a default")
	for key in regions:
		check(d.get("pieces", {}).has(regions[key]), "region %s names a piece (%s)" % [key, regions[key]])
		check(key == "default" or key.begins_with("faction:") or key.begins_with("region:"), "region key %s is default, faction: or region:" % key)


func test_listening_demos_exist() -> void:
	for name in PIECES:
		check(FileAccess.file_exists(DEMO_DIR + "r3_%s_transition.ogg" % name), "r3_%s_transition.ogg exists" % name)
