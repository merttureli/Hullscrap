extends "res://tests/base_test.gd"
## The sound: data/audio.json against the files, the bare-tree no-ops, the voice rules (cooldown, caps, delay, loops), the music states and
## stings (and their absence), the mood rules, the ship's ears, the volume settings and the menu's Sound row. No audio device needed:
## the admission rules run on the node's own clock and ledger (advance).

const Audio = preload("res://scripts/audio/audio.gd")
const Mood = preload("res://scripts/audio/mood.gd")
const ShipAudio = preload("res://scripts/audio/ship_audio.gd")
const Ambience = preload("res://scripts/audio/ambience.gd")
const Content = preload("res://scripts/data/content.gd")
const Hazards = preload("res://scripts/combat/hazards.gd")
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
	var power_state := {}
	var crafting = null


class FakeCrafting:
	var working := {}
	var queue: Array = []
	var paused := false


class FakeJobs:
	var patients := {}
	var restocking := {}


## The sounds of data/audio.json: id -> definition (the `_doc` and `_beds` entries taken out).
func _sounds() -> Dictionary:
	var defs: Dictionary = Audio._read(Audio.DATA_PATH)
	defs.erase("_doc")
	defs.erase("_beds")
	return defs


func _node() -> Node:
	var a = Audio.new()
	a.setup()
	return a


# --- the data ----------------------------------------------------------------------------------------------------

func test_every_id_has_its_files_and_every_file_is_used() -> void:
	var defs := _sounds()
	check(defs.size() >= 100, "the sound table is there")
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
		check(str(d.get("bus", "")) in ["SFX", "UI", "Ambience", "Room"], "%s is on a known bus" % id)
	for f in DirAccess.get_files_at(SFX_DIR):
		if f.ends_with(".wav"):
			check(used.has(f), "%s is used by an id" % f)


func test_loops_loop_in_their_import_settings() -> void:
	var defs := _sounds()
	var loops := 0
	for id in defs:
		var looping: bool = bool(defs[id].get("loop", false))
		for f in defs[id]["files"]:
			var imp := FileAccess.get_file_as_string(SFX_DIR + f + ".import")
			check(imp.contains("edit/loop_mode=2") == looping, "%s: loop_mode matches the loop flag of %s" % [f, id])
		if looping:
			loops += 1
			var s: AudioStreamWAV = load(SFX_DIR + defs[id]["files"][0])
			check(s.stereo or str(defs[id]["bus"]) == "SFX" or id in ["drone_hum", "medbay_hum", "smelter_loop", "fabricator_loop"], "%s is a stereo loop (the small mono ones are a missile and the machines)" % id)
			check(s.get_length() >= 1.9, "%s is a few seconds long" % id)
			if str(defs[id]["bus"]) in ["Ambience", "Room"]:
				check(not bool(defs[id].get("positional", false)), "%s is ambience, heard from nowhere" % id)
	eq(loops, 23, "23 loops: 5 of round 1, the neon beam, the pyre, the room tone, 5 beds, 5 hazards, the drone, the missile, medbay, smelter, fabricator")


func test_buses_and_export() -> void:
	eq(str(ProjectSettings.get_setting("audio/buses/default_bus_layout")), "res://default_bus_layout.tres", "the layout is set in project.godot")
	for b in ["Master", "Music", "SFX", "UI", "Ambience", "Room"]:
		check(AudioServer.get_bus_index(b) >= 0, "bus %s exists" % b)
	eq(AudioServer.get_bus_send(AudioServer.get_bus_index("Room")), &"Ambience", "the Room bus sends to Ambience")
	check(AudioServer.get_bus_effect(AudioServer.get_bus_index("Room"), 0) is AudioEffectLowPassFilter, "and carries the low-pass the reactor's load opens")
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	eq(cfg.count("audio/_src/*"), cfg.count("exclude_filter="), "every export preset leaves the audio sources out")
	check(not cfg.contains("assets/audio"), "and none excludes the audio assets")


func test_weapon_sounds() -> void:
	var w := Weapons.new()
	var ids: Dictionary = Audio.table()
	for id in w.defs:
		var line := str(Content.entry("components", id).get("line", ""))
		var s: String = Audio.weapon_sound(w.def(id), line)
		check(ids.has(s), "weapon %s (line %s) sounds as %s, which exists" % [id, line, s])
		if ids.has(s):
			check(Audio.is_loop(s) == (str(w.def(id)["kind"]) == "beam"), "%s: a loop sound only for a beam" % id)
	eq(Audio.weapon_sound(w.defs["laser_mk1"]), "laser", "a laser")
	eq(Audio.weapon_sound(w.defs["laser_turret_mk1"]), "rapid_tick", "a fast turret ticks")
	eq(Audio.weapon_sound(w.defs["ion_blast_mk1"]), "ion", "ion has its own zap")
	eq(Audio.weapon_sound(w.defs["heat_lance_neon"]), "beam_loop", "a beam loops")
	eq(Audio.weapon_sound(w.defs["artemis_mk1"]), "missile_launch", "a missile")
	eq(Audio.weapon_sound(w.defs["test_flak"]), "flak", "flak")


func test_weapon_lines_and_signature_sounds() -> void:
	var w := Weapons.new()
	var ids: Dictionary = Audio.table()
	var sig := {"basalt_magma_spitter": "sig_magma", "kett_hive_swarm_launcher": "sig_swarm", "prismatic_refractor": "sig_crystal",
		"sporeling_spore_cannon": "sig_spore", "emberkin_pyre_lance": "sig_pyre", "fenn_twitch_cannon": "sig_pop", "grundl_slug_mortar": "sig_thunk",
		"mire_steam_lance": "sig_hiss", "gauntling_arc_hammer": "sig_arc", "human_volley_rack": "sig_volley"}
	for id in sig:
		eq(str(w.def(id).get("sound", "")), sig[id], "%s carries the sound key %s" % [id, sig[id]])
		eq(Audio.weapon_sound(w.def(id), "standard"), sig[id], "and its `sound` wins over the kind")
		eq(Audio.weapon_sound(w.def(id), "neon"), sig[id], "and over the line too")
	check(Audio.is_loop("sig_pyre") and not Audio.is_loop("sig_magma"), "the pyre lance roars as a loop, the rest are shots")
	eq(Audio.weapon_sound(w.def("shrapnel_cannon_scrap"), "scrap"), "flak_scrap", "a scrap flak rattles")
	eq(Audio.weapon_sound(w.def("rattle_burst_scrap"), "scrap"), "rapid_tick_scrap", "a scrap turret")
	eq(Audio.weapon_sound(w.def("bolt_thrower_scrap"), "scrap"), "missile_launch_scrap", "a scrap missile")
	eq(Audio.weapon_sound(w.def("siren_ion_neon"), "neon"), "ion_neon", "a neon ion zap")
	eq(Audio.weapon_sound(w.def("heat_lance_neon"), "neon"), "beam_loop_neon", "a neon beam hums brighter")
	eq(Audio.weapon_sound(w.def("laser_mk1"), "neon"), "laser_neon", "any laser of the neon line is glassy")
	eq(Audio.weapon_sound(w.def("laser_mk1"), "standard"), "laser", "standard keeps the plain sound")
	eq(Audio.weapon_sound(w.def("laser_mk1"), "mystery"), "laser", "a line with no version falls back to the kind")
	eq(Audio.weapon_sound({"kind": "bolt", "sound": "no_such_sound"}), "bolt", "a sound key the table does not know falls back to the kind")
	eq(Audio.weapon_sound({"kind": "bolt", "sound": "sig_pop"}, "scrap", ids), "sig_pop", "the key wins when the table has it")
	for id in w.defs:
		if w.defs[id].has("sound"):
			check(ids.has(str(w.defs[id]["sound"])), "%s: its sound key names a sound" % id)
	for kind in ["laser", "bolt", "flak", "missile_launch", "rapid_tick"]:
		check(ids.has(kind + "_scrap") and ids.has(kind + "_neon"), "%s has a scrap and a neon version" % kind)


func test_beds_map_to_region_families() -> void:
	var table: Dictionary = Audio.table().get("_beds", {})
	check(not table.is_empty(), "data/audio.json has a `_beds` map")
	var sounds := _sounds()
	for k in ["by_region", "by_faction"]:
		for id in table[k].values():
			check(sounds.has(id) and bool(sounds[id].get("loop", false)) and str(sounds[id]["bus"]) == "Ambience", "bed %s is an Ambience loop" % id)
	check(sounds.has(table["hollow"]) and sounds.has(table["default"]), "and the Hollow's and the default bed exist")
	var regions := Content.regions()
	check(regions.size() >= 10, "the regions are read")
	var seen := {}
	for r in regions:
		var bed := Ambience.bed_for(table, str(r["id"]), str(r.get("faction", "")))
		check(sounds.has(bed), "region %s has the bed %s" % [r["id"], bed])
		seen[bed] = true
	for bed in ["bed_boneyard", "bed_lumen", "bed_concord", "bed_clans", "bed_hollow"]:
		check(seen.has(bed), "some region plays %s" % bed)
	eq(Ambience.bed_for(table, "boneyard", "rustfangs"), "bed_boneyard", "the Boneyard")
	eq(Ambience.bed_for(table, "lumen_space", "lumen"), "bed_lumen", "Lumen space")
	eq(Ambience.bed_for(table, "concord_space", "concord"), "bed_concord", "Concord space")
	eq(Ambience.bed_for(table, "clan_space", "clans"), "bed_clans", "Clan space")
	eq(Ambience.bed_for(table, "gate_approaches", "hollow"), "bed_hollow", "the Gate approaches")
	eq(Ambience.bed_for(table, "lumen_space", "lumen", true), "bed_hollow", "a place the tide has taken has the Hollow's, whatever the region")
	eq(Ambience.bed_for(table, "nowhere", "nobody"), str(table["default"]), "an unknown place has the default bed")
	eq(Ambience.bed_for({}, "boneyard", "x"), "", "no table, no bed")


func test_hazards_have_loops() -> void:
	var sounds := _sounds()
	var hz: Dictionary = Hazards.config()["hazards"]
	check(hz.size() >= 5, "the five hazards are read")
	for id in hz:
		var s := Ambience.hazard_loop(id)
		check(s != "" and sounds.has(s) and bool(sounds[s].get("loop", false)), "hazard %s loops as %s" % [id, s])
		check(str(sounds[s]["bus"]) == "Ambience", "%s is on the Ambience bus" % s)
	eq(Ambience.hazard_loop("no_such_hazard"), "", "an unknown hazard has none")
	eq(Ambience.hazard_loop(""), "", "and no hazard none")


func test_ambience_mix_levels() -> void:
	var sounds := _sounds()
	for id in sounds:
		if str(sounds[id]["bus"]) in ["Ambience", "Room"]:
			check(float(sounds[id]["volume_db"]) <= 0.0, "%s is never boosted" % id)
	var report := FileAccess.get_file_as_string("res://audio/_src/sfx/report.txt")
	for line in report.split("\n"):
		var cols := line.split(" ", false)
		if cols.size() < 5 or not str(cols[0]).ends_with(".wav"):
			continue
		check(float(cols[3]) <= -1.0 + 0.001, "%s peaks under -1 dBFS" % cols[0])
		var rms := float(cols[4])
		var f := str(cols[0])
		if f.begins_with("bed_"):
			check(absf(rms + 30.0) <= 1.0, "%s sits near -30 dBFS (%s)" % [f, rms])
		elif f.begins_with("haz_"):
			check(absf(rms + 26.0) <= 1.0, "%s sits near -26 dBFS (%s)" % [f, rms])
		elif f.begins_with("footstep_") or f in ["drone_hum.wav", "room_tone.wav"]:
			check(absf(rms + 32.0) <= 1.0, "%s sits near -32 dBFS (%s)" % [f, rms])


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
	eq(a.settings(), {"master": 0.8, "music": 0.6, "sfx": 0.8, "ambience": 0.8}, "the defaults: 80, 60, 80, 80%")
	a.apply_settings({"master": 2.0, "music": -1.0, "junk": 5})
	eq(a.settings()["master"], 1.0, "clamped high")
	eq(a.settings()["music"], 0.0, "clamped low")
	eq(a.settings()["sfx"], 0.8, "a missing key keeps its value")
	a.set_volume("sfx", 0.25)
	eq(a.settings()["sfx"], 0.25, "one slider")
	eq(snappedf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))), 0.01), 0.25, "on the SFX bus")
	eq(snappedf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("UI"))), 0.01), 0.25, "and the UI bus")
	a.set_volume("ambience", 0.4)
	eq(a.settings()["ambience"], 0.4, "the Ambience slider")
	eq(snappedf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience"))), 0.01), 0.4, "is the Ambience bus")
	eq(snappedf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))), 0.01), 0.25, "and leaves the SFX bus alone")
	check(a.toggle_mute(), "Ctrl+M mutes")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "the master bus is muted")
	check(not a.toggle_mute(), "and again unmutes")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "the master bus is back")
	a.apply_settings(Audio.DEFAULTS)
	a.free()


func test_profile_keeps_the_volumes() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var p := Profile.new(TMP)
	eq(p.sound, {"master": 0.8, "music": 0.6, "sfx": 0.8, "ambience": 0.8}, "a new profile has the default volumes")
	p.sound["music"] = 0.35
	p.sound["sfx"] = 1.0
	p.sound["ambience"] = 0.15
	eq(p.save(), "", "saved")
	var q := Profile.new(TMP)
	eq(q.sound["music"], 0.35, "the music volume comes back")
	eq(q.sound["sfx"], 1.0, "and the SFX")
	eq(q.sound["ambience"], 0.15, "and the Ambience")
	eq(q.sound["master"], 0.8, "and the master")
	var f := FileAccess.open(TMP, FileAccess.WRITE)  # a version 3 file has no sound
	f.store_string(JSON.stringify({"version": 3, "hints": {}, "runs": []}))
	f.close()
	eq(Profile.new(TMP).sound, Profile.SOUND_DEFAULTS, "an older file loads with the defaults")
	f = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 4, "sound": {"master": 0.5, "music": 0.5, "sfx": 0.5}}))
	f.close()
	eq(Profile.new(TMP).sound["ambience"], 0.8, "a version 4 file has no Ambience slider yet: it takes the default")
	f = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 5, "sound": {"master": 7, "music": -2, "sfx": "x", "ambience": 9}}))
	f.close()
	var r := Profile.new(TMP)
	eq(r.sound["master"], 1.0, "a wild value is clamped")
	eq(r.sound["music"], 0.0, "low too")
	eq(r.sound["ambience"], 1.0, "the Ambience slider too")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func test_menu_sound_row() -> void:
	var m := MainMenu.new()
	m.size = Vector2(1600, 900)
	var got := []
	m.sound_changed.connect(func(k, v, fin): got.append([k, v, fin]))
	var r: Rect2 = m.slider_rect(1)
	check(r.position.y > m.button_rect(m.list().size() - 1).end.y, "the row sits under the buttons")
	eq(MainMenu.SOUND_KINDS.map(func(k): return k[0]), ["master", "music", "sfx", "ambience"], "Master, Music, SFX, Ambience")
	check(m.slider_rect(0).end.x < m.slider_rect(1).position.x and m.slider_rect(1).end.x < m.slider_rect(2).position.x and m.slider_rect(2).end.x < m.slider_rect(3).position.x, "four sliders side by side")
	check(m.slider_rect(0).position.x >= (m.size.x - MainMenu.BTN.x) / 2.0 - 0.01 and m.slider_rect(3).end.x <= (m.size.x + MainMenu.BTN.x) / 2.0 + 0.01, "inside the width of the buttons")
	eq(m.slider_at(r.get_center()), 1, "a click on the Music bar finds it")
	eq(m.slider_at(Vector2(5, 5)), -1, "elsewhere nothing")
	m.set_slider(1, r.position.x + r.size.x * 0.5, false)
	eq(got.back(), ["music", 0.5, false], "half way is 50%")
	eq(m.sound["music"], 0.5, "and the menu holds it")
	m.set_slider(1, r.position.x - 40.0, true)
	eq(got.back(), ["music", 0.0, true], "past the left end is 0, and final")
	m.nudge(2, 1.0)
	eq(got.back(), ["sfx", 0.85, true], "a wheel notch is 5%")
	m.set_slider(3, m.slider_rect(3).position.x + m.slider_rect(3).size.x * 0.25, true)
	eq(got.back(), ["ambience", 0.25, true], "the fourth slider is the Ambience")
	eq(m.slider_at(m.slider_rect(3).get_center()), 3, "and a click on its bar finds it")
	m.free()


# --- the room, the boots and the machines ---------------------------------------------------------------------------------

func test_ship_audio_boots_drones_machines_and_load() -> void:
	var s := FakeShip.new()
	var me := CrewMember.new("Me", Vector2(3, 3))
	me.is_player = true
	var drone := CrewMember.new("Drone", Vector2(5, 5), "drone")
	s.crew = [me, drone]
	var jobs := FakeJobs.new()
	var ears := ShipAudio.new()
	var ev := ears.update(s, jobs)
	eq(ev["steps"], 0, "the first look is a baseline")
	eq(ev["drones"], 1, "a drone hovers")
	me.pos = Vector2(3.5, 3)
	eq(ears.update(s, jobs)["steps"], 0, "half a cell is not a step yet")
	me.pos = Vector2(4.6, 3)
	eq(ears.update(s, jobs)["steps"], 1, "a stride (1.5 cells) is a step")
	me.pos = Vector2(8.0, 3)
	eq(ears.update(s, jobs)["steps"], 2, "never more than two at a look")
	me.pos = Vector2(40, 3)
	eq(ears.update(s, jobs)["steps"], 0, "a move of the whole body (a load) is no walking")
	me.pos = Vector2(40.2, 3)
	eq(ears.update(s, jobs)["steps"], 0, "and a shuffle is not a step")
	drone.hp = 0.0
	eq(ears.update(s, jobs)["drones"], 0, "a broken drone does not hover")
	drone.hp = 10.0
	check(not ears.update(s, jobs)["healing"], "nobody in the medbay")
	jobs.patients = {4: "Bob"}
	check(ears.update(s, jobs)["healing"], "a patient on the medbay")
	jobs.restocking = {7: true}
	eq(ears.update(s, jobs)["restocked"], 0, "a rack being filled")
	jobs.restocking = {}
	eq(ears.update(s, jobs)["restocked"], 1, "a rack that is full now")
	eq(ears.update(s, jobs)["restocked"], 0, "said once")
	var cr := FakeCrafting.new()
	s.crafting = cr
	var ev2 := ears.update(s, jobs)
	check(not ev2["smelting"] and not ev2["fabricating"], "idle works")
	cr.working = {3: true}
	cr.queue = [{}]
	ev2 = ears.update(s, jobs)
	check(ev2["smelting"] and ev2["fabricating"], "a working smelter and a queue in the fabricator")
	cr.paused = true
	check(not ears.update(s, jobs)["fabricating"], "a fabricator held up is quiet")
	s.power_state = {"networks": [{"supply": 10.0, "demand": 12.0, "used": 5.0}, {"supply": 10.0, "demand": 4.0, "used": 4.0}]}
	eq(snappedf(float(ears.update(s, jobs)["load"]), 0.01), 0.45, "the load is the power used over the power made")
	s.power_state = {"networks": [{"supply": 0.0, "demand": 3.0, "used": 0.0}]}
	eq(ears.update(s, jobs)["load"], 0.0, "no reactor, no load")
	var f := FakeShip.new()
	f.crew = [me]
	f.fires = {Vector2i(1, 1): 0.5}
	ears.update(f, jobs)
	f.fires = {Vector2i(1, 1): 0.5, Vector2i(2, 1): 0.2}
	eq(ears.update(f, jobs)["ignited"], 1, "a new fire takes hold")
	eq(ears.update(f, jobs)["ignited"], 0, "said once")


func test_room_filter_opens_with_the_load() -> void:
	check(is_equal_approx(Ambience.room_cutoff(0.0), Ambience.ROOM_CLOSED), "idle: a dull hum")
	check(is_equal_approx(Ambience.room_cutoff(1.0), Ambience.ROOM_OPEN), "full: open")
	check(Ambience.room_cutoff(0.5) > Ambience.room_cutoff(0.25) and Ambience.room_cutoff(0.25) > Ambience.room_cutoff(0.0), "and rising between")
	check(is_equal_approx(Ambience.room_cutoff(2.0), Ambience.ROOM_OPEN), "a load over 1 is clamped")
	check(is_equal_approx(Ambience.room_cutoff(-1.0), Ambience.ROOM_CLOSED), "and under 0")
	var a = _node()
	a._room_to = Ambience.room_cutoff(1.0)
	for i in 30:
		a.advance(0.1)
	check(a._room_hz > Ambience.ROOM_OPEN * 0.9, "the Room bus's low-pass follows the load up")
	var fx = AudioServer.get_bus_effect(AudioServer.get_bus_index("Room"), 0)
	check(fx.cutoff_hz > Ambience.ROOM_OPEN * 0.9, "on the bus itself")
	a._room_to = Ambience.ROOM_CLOSED
	for i in 60:
		a.advance(0.1)
	check(a._room_hz < Ambience.ROOM_CLOSED * 1.1 and fx.cutoff_hz < Ambience.ROOM_CLOSED * 1.1, "and down again")
	a.free()


func test_hull_creaks_when_it_drops_under_half() -> void:
	var c := Ambience.new()
	check(not c.creak(1.0, 1.0), "a whole hull is quiet")
	check(not c.creak(0.52, 1.0), "a hull at 52% too")
	check(c.creak(0.49, 1.0), "under half: a creak at once")
	check(not c.creak(0.49, 10.0), "then it waits")
	check(not c.creak(0.49, 10.0), "20 s")
	check(c.creak(0.49, 5.0), "and again after 24 s")
	check(not c.creak(0.52, 1.0), "mended a little (52%) it goes on waiting, not creaking at once")
	check(not c.creak(0.6, 1.0), "mended past 55% it stops")
	check(c.creak(0.45, 1.0), "and creaks again when it drops")


## Run the node's ambience for `secs` seconds as the game does: a look every 0.1 s, the clock on.
func _run(a, inp: Dictionary, ev: Dictionary, secs: float, live := true) -> void:
	for i in roundi(secs / 0.1):
		a._ambience(inp, ev, live, 0.1)
		a.advance(0.1)


func test_the_ambience_plays_by_place_and_crossfades() -> void:
	var a = _node()
	var ev := ShipAudio.new().update(null)
	a._ambience({"menu": true}, ev, true, 0.1)
	eq(a.bed_now, "", "no bed in a menu")
	check(a.loops_on().is_empty(), "and nothing loops")
	var inp := {"menu": false, "region": "boneyard", "faction": "rustfangs", "hollow": false, "pressure": 0.0}
	a._ambience(inp, ev, true, 0.1)
	eq(a.bed_now, "bed_boneyard", "the Boneyard's bed")
	check("room" in a.loops_on() and "bed:bed_boneyard" in a.loops_on(), "with the room tone")
	check(not ("drone" in a.loops_on()) and not ("medbay" in a.loops_on()), "and no machines")
	_run(a, inp, ev, 1.5)
	var v: float = a._loops["bed:bed_boneyard"]["vol"]
	check(v > 0.4 and v < 0.6, "half way in after 1.5 s of a 3 s fade (%s)" % v)
	_run(a, inp, ev, 1.6)
	eq(a._loops["bed:bed_boneyard"]["vol"], 1.0, "fully in after 3 s")
	inp = {"menu": false, "region": "lumen_space", "faction": "lumen", "hollow": false, "pressure": 0.0}
	_run(a, inp, ev, 0.1)
	eq(a.bed_now, "bed_lumen", "Lumen space swaps the bed")
	_run(a, inp, ev, 1.5)
	var old: float = a._loops["bed:bed_boneyard"]["vol"]
	var fresh: float = a._loops["bed:bed_lumen"]["vol"]
	check(old > 0.4 and old < 0.6 and fresh > 0.4 and fresh < 0.6, "the two cross-fade (%s out, %s in)" % [old, fresh])
	_run(a, inp, ev, 1.6)
	check(not a._loops.has("bed:bed_boneyard"), "the old bed is gone after 3 s")
	eq(a._loops["bed:bed_lumen"]["vol"], 1.0, "the new one is in")
	inp["pressure"] = 0.7
	_run(a, inp, ev, 0.1)
	eq(a.bed_now, "bed_hollow", "the tide close by turns the bed to the Hollow's")
	ev = {"load": 0.8, "drones": 2, "healing": true, "smelting": true, "fabricating": true}
	_run(a, inp, ev, 0.6)
	for k in ["drone", "medbay", "smelter", "fabricator"]:
		check(k in a.loops_on(), "%s runs" % k)
	check(a._room_to > Ambience.room_cutoff(0.7), "and the room filter heads for the load")
	_run(a, inp, ev, 0.2, false)
	check(a._loops["medbay"]["target"] == 0.0 and a._loops["drone"]["target"] > 0.0, "paused: the machines stop, the drone's hover stays")
	a.free()


func test_footsteps_and_hazard_loop_through_the_node() -> void:
	var a = _node()
	a._footsteps(0, true)
	eq(a.voices_of("footstep"), 0, "no steps, no sound")
	a._footsteps(2, false)
	eq(a.voices_of("footstep"), 0, "not in a game")
	a._footsteps(2, true)
	eq(a.voices_of("footstep"), 1, "the first step at once")
	a.advance(0.13)
	eq(a.voices_of("footstep"), 2, "the second a beat after")
	for i in 8:  # the fight asks for it every frame, 0.1 s apart here
		a.loop("hazard", Ambience.hazard_loop("ion_storm"), true, 1.0, 1.0, null, 1.5)
		a.advance(0.1)
	var v: float = a._loops["hazard"]["vol"]
	check(v > 0.4 and v < 0.6, "a hazard loop fades in over its fade: 0.8 s of 1.5 s (%s)" % v)
	a.loop("hazard", Ambience.hazard_loop("ion_storm"), false, 1.0, 1.0, null, 1.5)
	a.advance(2.0)
	check(not a._loops.has("hazard"), "and out")
	a.free()
