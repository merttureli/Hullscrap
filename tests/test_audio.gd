extends "res://tests/base_test.gd"
## The sound: data/audio.json against the files, the bare-tree no-ops, the voice rules (cooldown, caps, delay, loops), the music states and
## stings (and their absence), the mood rules, the ship's ears, the volume settings and the menu's Sound row. No audio device needed:
## the admission rules run on the node's own clock and ledger (advance).

const Audio = preload("res://scripts/audio/audio.gd")
const Mood = preload("res://scripts/audio/mood.gd")
const ShipAudio = preload("res://scripts/audio/ship_audio.gd")
const Profile = preload("res://scripts/ui/profile.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const SFX_DIR := "res://assets/audio/sfx/"
const TMP := "user://test_audio_profile.json"
const WAV_A := "res://assets/audio/sfx/engine_loop.wav"
const WAV_B := "res://assets/audio/sfx/beam_loop.wav"


class FakeShip:
	var fires := {}
	var crew: Array = []
	var clock := 0.0


func _node() -> Node:
	var a = Audio.new()
	a.setup()
	return a


# --- the data ----------------------------------------------------------------------------------------------------

func test_every_id_has_its_files_and_every_file_is_used() -> void:
	var defs: Dictionary = Audio._read(Audio.DATA_PATH)
	defs.erase("_doc")
	check(defs.size() >= 40, "the sound table is there")
	var used := {}
	for id in defs:
		var d: Dictionary = defs[id]
		check(d.has("files") and not d["files"].is_empty(), "%s has files" % id)
		for f in d.get("files", []):
			used[f] = true
			check(FileAccess.file_exists(SFX_DIR + f), "%s: %s exists" % [id, f])
			check(load(SFX_DIR + f) is AudioStreamWAV, "%s: %s imports as a WAV" % [id, f])
		for k in ["volume_db", "pitch_var", "max_voices", "cooldown", "bus", "positional"]:
			check(d.has(k), "%s has %s" % [id, k])
		check(str(d.get("bus", "")) in ["SFX", "UI"], "%s is on SFX or UI" % id)
	for f in DirAccess.get_files_at(SFX_DIR):
		if f.ends_with(".wav"):
			check(used.has(f), "%s is used by an id" % f)


func test_loops_loop_in_their_import_settings() -> void:
	var defs: Dictionary = Audio._read(Audio.DATA_PATH)
	defs.erase("_doc")
	var loops := 0
	for id in defs:
		var looping: bool = bool(defs[id].get("loop", false))
		for f in defs[id]["files"]:
			var imp := FileAccess.get_file_as_string(SFX_DIR + f + ".import")
			check(imp.contains("edit/loop_mode=2") == looping, "%s: loop_mode matches the loop flag of %s" % [f, id])
		if looping:
			loops += 1
			var s: AudioStreamWAV = load(SFX_DIR + defs[id]["files"][0])
			check(s.stereo, "%s is a stereo loop" % id)
			check(s.get_length() >= 1.9, "%s is a few seconds long" % id)
	eq(loops, 5, "five loops: beam, engine, tractor, repair, fire")


func test_buses_and_export() -> void:
	eq(str(ProjectSettings.get_setting("audio/buses/default_bus_layout")), "res://default_bus_layout.tres", "the layout is set in project.godot")
	for b in ["Master", "Music", "SFX", "UI"]:
		check(AudioServer.get_bus_index(b) >= 0, "bus %s exists" % b)
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	eq(cfg.count("audio/_src/*"), cfg.count("exclude_filter="), "every export preset leaves the audio sources out")
	check(not cfg.contains("assets/audio"), "and none excludes the audio assets")


func test_weapon_sounds() -> void:
	var w := Weapons.new()
	var ids: Dictionary = Audio._read(Audio.DATA_PATH)
	for id in w.defs:
		var s: String = Audio.weapon_sound(w.defs[id])
		check(ids.has(s), "weapon %s sounds as %s, which exists" % [id, s])
	eq(Audio.weapon_sound(w.defs["laser_mk1"]), "laser", "a laser")
	eq(Audio.weapon_sound(w.defs["laser_turret_mk1"]), "rapid_tick", "a fast turret ticks")
	eq(Audio.weapon_sound(w.defs["ion_blast_mk1"]), "ion", "ion has its own zap")
	eq(Audio.weapon_sound(w.defs["heat_lance_neon"]), "beam_loop", "a beam loops")
	eq(Audio.weapon_sound(w.defs["artemis_mk1"]), "missile_launch", "a missile")
	eq(Audio.weapon_sound(w.defs["test_flak"]), "flak", "flak")


# --- no node, no sound --------------------------------------------------------------------------------------------

func test_without_an_audio_node_everything_is_silent() -> void:
	check(Audio.of(null) == null, "no context: no node")
	check(Audio.of(Engine.get_main_loop()) == null, "a bare tree has none")
	var lone := Node.new()
	check(Audio.of(lone) == null, "a node outside any tree has none")
	Audio.fx(null, "click")
	Audio.fx(lone, "hit_hull", Vector2(5, 5), -3.0, 0.5)
	Audio.fx_loop(lone, "engine", "engine_loop", true, 0.5, 1.2)
	Audio.mood(Engine.get_main_loop(), "combat")
	Audio.cue(lone, "victory")
	lone.free()
	check(true, "the helpers did not error")


# --- the voice rules ----------------------------------------------------------------------------------------------

func test_cooldown_and_voice_cap() -> void:
	var a = _node()
	check(a.play("laser"), "the first shot plays")
	check(not a.play("laser"), "the same id again at once is in its cooldown")
	a.advance(0.05)
	check(a.play("laser"), "after the cooldown it plays")
	a.advance(0.05)
	check(a.play("laser"), "third")
	a.advance(0.05)
	check(a.play("laser"), "fourth")
	eq(a.voices_of("laser"), 4, "four voices sound")
	a.advance(0.05)
	check(not a.play("laser"), "the fifth is over the cap of four")
	a.advance(0.3)
	eq(a.voices_of("laser"), 0, "the voices end with their sound")
	check(a.play("laser"), "and a new one plays")
	check(a.play("click"), "other ids are not held up")
	check(not a.play("no_such_sound"), "an unknown id is a quiet false")
	check(not a.play("engine_loop"), "a loop is not a one-shot")
	a.free()


func test_six_rapid_turrets_do_not_stack() -> void:
	var a = _node()
	var played := 0
	for i in 6:  # six turrets in the same frame
		if a.play("rapid_tick"):
			played += 1
	eq(played, 1, "one tick for the burst")
	a.free()


func test_variants_never_repeat_back_to_back() -> void:
	var a = _node()
	var last := ""
	for i in 12:
		a.advance(0.5)
		a.play("hit_hull")
		var f: String = a._prev_file["hit_hull"]
		check(f != last, "variant %d differs from the one before" % i)
		last = f
	a.free()


func test_delayed_sound_and_pitch_range() -> void:
	var a = _node()
	check(a.play("arrive", null, 0.0, 0.4), "a delayed sound is accepted")
	eq(a.voices_of("arrive"), 0, "but silent until its time")
	a.advance(0.3)
	eq(a.voices_of("arrive"), 0, "still waiting")
	a.advance(0.2)
	eq(a.voices_of("arrive"), 1, "now it sounds")
	a.free()


func test_loops_follow_calls_and_fade_out_alone() -> void:
	var a = _node()
	a.loop("e", "engine_loop", true, 0.6, 1.1)
	a.advance(0.1)
	check("e" in a.loops_on(), "the loop is on")
	check(a._loops["e"]["vol"] > 0.0 and a._loops["e"]["vol"] <= 0.6, "it fades in toward its volume")
	a.loop("e", "engine_loop", true, 0.6, 1.1)
	a.advance(0.2)
	check("e" in a.loops_on(), "kept alive by the calls")
	a.advance(0.6)  # nobody asks any more
	check(not ("e" in a.loops_on()), "it lets go by itself")
	a.advance(1.0)
	check(not a._loops.has("e"), "and is gone once silent")
	a.loop("b", "beam_loop", true)
	a.loop("b", "beam_loop", false)
	a.advance(1.0)
	check(not a._loops.has("b"), "off fades it out at once")
	a.loop("x", "laser", true)
	check(not a._loops.has("x"), "a one-shot id is no loop")
	a.free()


# --- music ---------------------------------------------------------------------------------------------------------

func test_music_states_alternate_and_tolerate_missing_files() -> void:
	var a = _node()
	a.music_data = {}
	a.music_state("menu")
	eq(a.music_file, "", "no data/music.json: silence, no error")
	check(not a.sting("victory"), "and no stings")
	a.music_data = {"states": {"explore": ["missing_a.ogg", "missing_b.ogg"]}, "stings": {"victory": "missing.ogg"}}
	a.music_now = ""
	a.music_state("explore")
	eq(a.music_file, "", "tracks that are missing stay silent")
	check(not a.sting("victory"), "a missing sting file too")
	a.music_data = {"states": {"explore": [WAV_A, WAV_B], "combat": [WAV_B], "hollow": []}, "stings": {"victory": WAV_A}, "volumes": {WAV_A: -3.0}}
	a.music_now = ""
	a._visits = {}
	a.music_state("explore")
	eq(a.music_file, WAV_A, "the first visit plays the first track")
	var slot: int = a._cur
	a.advance(Audio.FADE)
	eq(a._mgain[slot], 1.0, "it has faded in")
	eq(a._mdb[slot], -3.0, "with its trim from the volumes table")
	a.music_state("combat")
	eq(a.music_file, WAV_B, "combat plays its track")
	check(a._cur != slot, "on the other player: a cross-fade")
	a.advance(Audio.FADE)
	eq(a._mgain[slot], 0.0, "the old track has faded out")
	a.music_state("hollow")
	eq(a.music_file, "", "a state with no track fades to silence")
	a.music_state("explore")
	eq(a.music_file, WAV_B, "the next visit to explore plays its next track")
	a.music_state("explore")
	eq(a.music_file, WAV_B, "asking for the state it is in changes nothing")
	a.free()


func test_sting_ducks_the_music() -> void:
	var a = _node()
	a.music_data = {"stings": {"victory": WAV_A}}
	check(a.sting("victory"), "the sting plays")
	a.advance(0.2)
	eq(a._duck, Audio.DUCK_DB, "the music dips 6 dB")
	a.advance(a._sting_until)
	a.advance(0.2)
	eq(a._duck, 0.0, "and comes back when it is over")
	a.free()


# --- mood ----------------------------------------------------------------------------------------------------------

func test_mood_rules() -> void:
	eq(Mood.raw({}), "explore", "nothing special is explore")
	eq(Mood.raw({"menu": true, "fight": true}), "menu", "a menu wins")
	eq(Mood.raw({"fight": true, "hollow": true}), "combat", "a fight beats the Hollow")
	eq(Mood.raw({"hostile": true}), "combat", "a hostile in range is combat")
	eq(Mood.raw({"build": true, "pressure": 0.9}), "build", "build mode beats the tide")
	eq(Mood.raw({"pressure": 0.59}), "explore", "below 0.6 it is just the tide coming")
	eq(Mood.raw({"pressure": 0.6}), "hollow", "tide pressure 0.6 is the Hollow")
	eq(Mood.raw({"hollow": true}), "hollow", "a place the tide has taken")


func test_mood_holds_combat_and_settles() -> void:
	var m := Mood.new()
	m.state = "explore"
	eq(m.update({"fight": true}, 0.1), "combat", "a fight is combat at once")
	eq(m.update({}, 1.0), "combat", "one second after it: still combat")
	eq(m.update({}, 2.5), "combat", "3.5 s after: still")
	eq(m.update({}, 1.0), "explore", "past 4 s: back to explore")
	eq(m.update({"pressure": 0.7}, 0.3), "explore", "the Hollow waits to settle")
	eq(m.update({"pressure": 0.7}, 0.6), "hollow", "then follows")
	eq(m.update({"menu": true}, 0.1), "menu", "a menu is at once")
	eq(m.update({}, 0.1), "explore", "and leaving it too")


# --- the ship's ears -----------------------------------------------------------------------------------------------

func test_ship_audio_reads_the_crew_and_fires() -> void:
	var s := FakeShip.new()
	var bob := CrewMember.new("Bob", Vector2.ZERO)
	var drone := CrewMember.new("Drone", Vector2.ZERO, "drone")
	s.crew = [bob, drone]
	var ears := ShipAudio.new()
	var ev := ears.update(s)
	check(not ev["repair"] and not ev["fire"] and ev["joined"].is_empty(), "the first look is only a baseline")
	bob.job = {"type": "repair_component", "key": "x"}
	ev = ears.update(s)
	check(ev["repair"], "a crew member on a repair job with nowhere to walk is mending")
	bob.path = [Vector2i(1, 1)]
	ev = ears.update(s)
	check(not ev["repair"], "still walking to it: not yet")
	bob.path = []
	bob.job = {"type": "repair_component", "hand": true, "t": 0.0}
	s.clock = 5.0
	check(not ears.update(s)["repair"], "a hand job that was not worked lately is not mending")
	s.clock = 0.2
	check(ears.update(s)["repair"], "a hand job being worked is")
	bob.job = {}
	s.fires = {Vector2i(2, 2): 0.5, Vector2i(3, 2): 0.4}
	ev = ears.update(s)
	check(ev["fire"] and ev["extinguished"] == 0, "fires burn")
	s.fires = {Vector2i(2, 2): 0.5}
	eq(ears.update(s)["extinguished"], 1, "one fewer fire is one put out")
	bob.hp -= 10.0
	eq(ears.update(s)["hurt"], 1, "a crew member lost hit points")
	drone.hp -= 10.0
	eq(ears.update(s)["hurt"], 0, "a drone breaks, it is not hurt")
	drone.job = {"type": "repair_component"}
	eq(ears.update(s)["beep"], 1, "a drone starting a job beeps")
	eq(ears.update(s)["beep"], 0, "once")
	var ada := CrewMember.new(ShipAudio.ada_name(), Vector2.ZERO)
	s.crew.append(ada)
	check(ears.update(s)["joined"].has(ShipAudio.ada_name()), "Ada coming aboard is seen")
	check(ears.update(null)["joined"].is_empty(), "no ship, no sounds")
	var s2 := FakeShip.new()  # a loaded save: a new soldier and the crew with them, Ada among them: no sting
	var me := CrewMember.new("Me", Vector2.ZERO)
	me.is_player = true
	s2.crew = [me]
	ears.update(s2)
	var me2 := CrewMember.new("Me", Vector2.ZERO)
	me2.is_player = true
	s2.crew = [me2, CrewMember.new(ShipAudio.ada_name(), Vector2.ZERO)]
	check(ears.update(s2)["joined"].is_empty(), "a new soldier means a load: the crew is the baseline")
	s2.crew.append(CrewMember.new("Newcomer", Vector2.ZERO))
	eq(ears.update(s2)["joined"], ["Newcomer"], "and one who comes aboard after that is seen")


# --- settings -------------------------------------------------------------------------------------------------------

func test_volume_settings_apply_and_clamp() -> void:
	var a = _node()
	eq(a.settings(), {"master": 0.8, "music": 0.6, "sfx": 0.8}, "the defaults: 80, 60, 80%")
	a.apply_settings({"master": 2.0, "music": -1.0, "junk": 5})
	eq(a.settings()["master"], 1.0, "clamped high")
	eq(a.settings()["music"], 0.0, "clamped low")
	eq(a.settings()["sfx"], 0.8, "a missing key keeps its value")
	a.set_volume("sfx", 0.25)
	eq(a.settings()["sfx"], 0.25, "one slider")
	eq(snappedf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))), 0.01), 0.25, "on the SFX bus")
	eq(snappedf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("UI"))), 0.01), 0.25, "and the UI bus")
	check(a.toggle_mute(), "Ctrl+M mutes")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "the master bus is muted")
	check(not a.toggle_mute(), "and again unmutes")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "the master bus is back")
	a.apply_settings(Audio.DEFAULTS)
	a.free()


func test_profile_keeps_the_volumes() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var p := Profile.new(TMP)
	eq(p.sound, {"master": 0.8, "music": 0.6, "sfx": 0.8}, "a new profile has the default volumes")
	p.sound["music"] = 0.35
	p.sound["sfx"] = 1.0
	eq(p.save(), "", "saved")
	var q := Profile.new(TMP)
	eq(q.sound["music"], 0.35, "the music volume comes back")
	eq(q.sound["sfx"], 1.0, "and the SFX")
	eq(q.sound["master"], 0.8, "and the master")
	var f := FileAccess.open(TMP, FileAccess.WRITE)  # a version 3 file has no sound
	f.store_string(JSON.stringify({"version": 3, "hints": {}, "runs": []}))
	f.close()
	eq(Profile.new(TMP).sound, Profile.SOUND_DEFAULTS, "an older file loads with the defaults")
	f = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 4, "sound": {"master": 7, "music": -2, "sfx": "x"}}))
	f.close()
	var r := Profile.new(TMP)
	eq(r.sound["master"], 1.0, "a wild value is clamped")
	eq(r.sound["music"], 0.0, "low too")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func test_menu_sound_row() -> void:
	var m := MainMenu.new()
	m.size = Vector2(1600, 900)
	var got := []
	m.sound_changed.connect(func(k, v, fin): got.append([k, v, fin]))
	var r: Rect2 = m.slider_rect(1)
	check(r.position.y > m.button_rect(m.list().size() - 1).end.y, "the row sits under the buttons")
	check(m.slider_rect(0).end.x < m.slider_rect(1).position.x and m.slider_rect(1).end.x < m.slider_rect(2).position.x, "three sliders side by side")
	eq(m.slider_at(r.get_center()), 1, "a click on the Music bar finds it")
	eq(m.slider_at(Vector2(5, 5)), -1, "elsewhere nothing")
	m.set_slider(1, r.position.x + r.size.x * 0.5, false)
	eq(got.back(), ["music", 0.5, false], "half way is 50%")
	eq(m.sound["music"], 0.5, "and the menu holds it")
	m.set_slider(1, r.position.x - 40.0, true)
	eq(got.back(), ["music", 0.0, true], "past the left end is 0, and final")
	m.nudge(2, 1.0)
	eq(got.back(), ["sfx", 0.85, true], "a wheel notch is 5%")
	m.free()
