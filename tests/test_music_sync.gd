extends "res://tests/base_test.gd"
## The adaptive music (data/music.json v2): a piece's EXPLORE and BATTLE layers play in sync and a fight only cross-fades their volumes; the
## piece is picked by region; a region change cross-fades and keeps the fight; accents play in sync over the piece; the old (v1) file and
## missing files still work. No audio device and no scene tree: outside the tree nothing plays, so audio.gd simulates the players'
## positions in `_sim_pos` (start and seek write it, advance moves it) and these tests read and move them. Content: the black_box,
## ledger_ii and signal demos (tests/fixtures/music_v2.json); the engine loop stands in for an accent stem and the state tracks.

const Audio = preload("res://scripts/audio/audio.gd")
const Mood = preload("res://scripts/audio/mood.gd")
const FIXTURE := "res://tests/fixtures/music_v2.json"
const WAV_A := "res://assets/audio/sfx/engine_loop.wav"  # 3 s
const WAV_B := "res://assets/audio/sfx/beam_loop.wav"


func _node(data = null) -> Node:
	var a = Audio.new()
	a.setup()
	a.music_data = Audio._read(FIXTURE) if data == null else data
	return a


func _deck(a):
	return a._decks[a._deck_cur]


func _near(got: float, want: float, tol: float, msg: String) -> void:
	check(absf(got - want) <= tol, "%s: expected %s +- %s, got %s" % [msg, want, tol, got])


# --- which piece a place plays -------------------------------------------------------------------------------------

func test_region_resolution_order() -> void:
	var regions: Dictionary = Audio._read(FIXTURE)["regions"]
	eq(Mood.piece_for(regions, "human_core", "concord"), "signal", "the region comes first")
	eq(Mood.piece_for(regions, "somewhere", "concord"), "ledger_ii", "then the faction")
	eq(Mood.piece_for(regions, "somewhere", "nobody"), "black_box", "then the default")
	eq(Mood.piece_for(regions, "", ""), "black_box", "no region and no faction is the default")
	eq(Mood.piece_for({"faction:concord": "x"}, "r", "kett"), "", "nothing named, no default: no piece")
	eq(Mood.piece_for(regions, "human_core", "concord", true), "", "a Hollow place has only the Hollow's piece, and there is none")
	regions["faction:hollow"] = "signal"
	eq(Mood.piece_for(regions, "kett_hives", "kett", true), "signal", "the Hollow's piece beats the region's")
	eq(Mood.piece_for(regions, "kett_hives", "kett"), "black_box", "and a place that is not Hollow does not see it")
	var accents: Dictionary = Audio._read(FIXTURE)["accents"]
	eq(Mood.accent_for(accents, "kett_hives", "kett")["db"], -9, "an accent by region")
	eq(Mood.accent_for(accents, "human_core", "kett"), {}, "no accent for another region")
	eq(Mood.accent_for(accents, "kett_hives", "kett", true), {}, "and none over a Hollow piece")


func test_the_node_picks_the_piece_of_its_region() -> void:
	var a = _node()
	a.music_region("human_core", "concord")
	a.music_state("explore")
	eq(a.music_piece, "signal", "a region's piece")
	a.music_region("elsewhere", "concord")
	eq(a.music_piece, "ledger_ii", "its faction's after a jump")
	a.music_region("elsewhere", "kett")
	eq(a.music_piece, "black_box", "the default")
	a.free()


# --- the old file ----------------------------------------------------------------------------------------------------

func test_a_v1_file_works_as_before() -> void:
	var a = _node({"states": {"explore": [WAV_A, WAV_B], "combat": [WAV_B], "menu": [WAV_A]}, "volumes": {WAV_A: -3.0}})
	a.music_region("human_core", "concord")
	a.music_state("explore")
	eq(a.music_file, WAV_A, "the explore track plays")
	eq(a.music_piece, "", "no piece")
	eq(a._deck_cur, -1, "no deck used")
	var slot: int = a._cur
	a.music_state("combat")
	eq(a.music_file, WAV_B, "combat is a track of its own")
	check(a._cur != slot, "on the other player: the old cross-fade")
	a.music_region("elsewhere", "kett")
	eq(a.music_file, WAV_B, "a region changes nothing")
	eq(a.piece_starts, 0, "and no piece ever starts")
	a.free()


func test_the_shipped_music_json_plays_every_state() -> void:
	var a = _node(Audio._read(Audio.MUSIC_PATH))
	for s in ["menu", "build", "hollow", "explore", "combat"]:
		a.music_state(s)
		check(a.music_file != "", "state %s plays something" % s)
		check(FileAccess.file_exists(a.music_file) or ResourceLoader.exists(a.music_file), "and its file exists (%s)" % a.music_file)
	a.free()


# --- a fight ---------------------------------------------------------------------------------------------------------

func test_a_new_piece_starts_with_both_layers_together() -> void:
	var a = _node()
	a.music_state("explore")
	var d = _deck(a)
	eq(d.piece, "black_box", "the default piece")
	check(d.players[0].stream != null and d.players[1].stream != null, "both layers are loaded")
	eq(a.piece_starts, 1, "started once")
	eq(d.players[1].volume_db, -80.0, "BATTLE starts at -80 dB")
	eq(a._sim_pos[d.players[0]], a._sim_pos[d.players[1]], "both start at the same position")
	a.advance(Audio.FADE)
	_near(d.players[0].volume_db, 0.0, 0.01, "EXPLORE has faded in")
	_near(d.players[1].volume_db, -82.0, 0.01, "BATTLE stays silent (-80 dB, and its trim of -2)")
	a.free()


func test_combat_flips_the_layers_without_restarting() -> void:
	var a = _node()
	a.music_state("explore")
	var d = _deck(a)
	var ex: AudioStreamPlayer = d.players[0]
	var ba: AudioStreamPlayer = d.players[1]
	a.advance(Audio.FADE)
	a.advance(10.0)
	var length: float = ex.stream.get_length()
	var at: float = a._sim_pos[ex]
	_near(at, 12.0, 0.001, "the song is 12 s in")
	a.music_state("combat")
	eq(a.piece_starts, 1, "a fight starts nothing")
	eq(a._deck_cur, a._decks.find(d), "on the same deck")
	a.advance(Audio.BATTLE_IN / 2.0)
	check(ex.volume_db > -12.0 and ex.volume_db < -3.0, "half way: EXPLORE is down but heard (%s)" % ex.volume_db)
	check(ba.volume_db > -12.0 and ba.volume_db < -3.0, "BATTLE is up but not yet full (%s)" % ba.volume_db)
	a.advance(Audio.BATTLE_IN / 2.0)
	_near(ba.volume_db, -2.0, 0.01, "after 2 s: BATTLE is at full (its trim -2 dB)")
	_near(ex.volume_db, -80.0, 0.01, "EXPLORE is silent")
	var later := fposmod(at + Audio.BATTLE_IN, length)
	_near(a._sim_pos[ex], later, 0.001, "EXPLORE went on from where it was")
	_near(a._sim_pos[ba], later, 0.001, "and so did BATTLE")
	eq(a.sync_nudges, 0, "nothing needed nudging")
	eq(a.piece_starts, 1, "still one start")
	a.music_state("explore")
	a.advance(Audio.BATTLE_OUT / 2.0)
	check(ba.volume_db > -12.0 and ba.volume_db < -3.0, "the end of the fight takes 4 s: BATTLE is half way after 2")
	a.advance(Audio.BATTLE_OUT / 2.0)
	_near(ex.volume_db, 0.0, 0.01, "EXPLORE is back")
	_near(ba.volume_db, -82.0, 0.01, "BATTLE is gone")
	eq(a.piece_starts, 1, "the song never restarted")
	a.free()


# --- the sync ----------------------------------------------------------------------------------------------------

func test_the_sync_nudges_the_battle_layer_back() -> void:
	var a = _node()
	a.music_state("explore")
	var d = _deck(a)
	var ex: AudioStreamPlayer = d.players[0]
	var ba: AudioStreamPlayer = d.players[1]
	a.advance(5.0)
	a._sim_pos[ba] += 0.015
	eq(a.sync_layers(), 0, "15 ms apart is inside the tolerance")
	a._sim_pos[ba] = a._sim_pos[ex] - 0.019
	eq(a.sync_layers(), 0, "19 ms the other way too")
	a._sim_pos[ba] = a._sim_pos[ex] + 0.03
	eq(a.sync_layers(), 1, "30 ms apart: one nudge")
	eq(a._sim_pos[ba], a._sim_pos[ex], "BATTLE was seeked to where EXPLORE is")
	eq(a.sync_nudges, 1, "counted")
	# across the end of the loop: 10 ms apart is fine, 100 ms is not
	var length: float = ex.stream.get_length()
	a._sim_pos[ex] = length - 0.005
	a._sim_pos[ba] = 0.005
	eq(a.sync_layers(), 0, "10 ms apart across the loop point is in step")
	a._sim_pos[ba] = 0.095
	eq(a.sync_layers(), 1, "100 ms apart across it is not")
	_near(a._sim_pos[ba], length - 0.005, 0.0001, "and goes back to just before the end")
	a.free()


func test_the_sync_runs_every_second() -> void:
	var a = _node()
	a.music_state("explore")
	var d = _deck(a)
	a.advance(Audio.FADE)
	a._sim_pos[d.players[1]] += 0.2
	a.advance(0.5)
	eq(a.sync_nudges, 0, "not looked at yet")
	a.advance(0.5)
	eq(a.sync_nudges, 1, "a second after the last look it is nudged")
	_near(a._sim_pos[d.players[1]], a._sim_pos[d.players[0]], 0.0001, "back in step")
	a.free()


# --- regions ---------------------------------------------------------------------------------------------------------

func test_a_region_change_cross_fades_and_keeps_the_fight() -> void:
	var a = _node()
	a.music_region("human_core", "concord")
	a.music_state("explore")
	var old = _deck(a)
	a.advance(Audio.FADE)
	a.music_state("combat")
	a.advance(Audio.BATTLE_IN)
	_near(old.players[1].volume_db, 0.0, 0.01, "the old piece is in BATTLE (signal has no trim)")
	a.music_region("kett_hives", "kett")
	var nw = _deck(a)
	check(nw != old, "the new piece is on the other deck")
	eq(a.music_piece, "black_box", "it is the region's")
	eq(nw.mix, 1.0, "and it starts in BATTLE, the fight goes on")
	eq(a.piece_starts, 2, "one new start")
	eq(old.target, 0.0, "the old piece goes out")
	a.advance(Audio.REGION_FADE / 2.0)
	check(old.players[1].volume_db > -6.0 and old.players[1].volume_db < -1.0, "half way the old BATTLE is still heard (%s)" % old.players[1].volume_db)
	check(nw.players[1].volume_db > -9.0 and nw.players[1].volume_db < -1.0, "and the new BATTLE comes in (%s)" % nw.players[1].volume_db)
	_near(nw.players[0].volume_db, -80.0, 0.01, "the new EXPLORE is silent")
	a.advance(Audio.REGION_FADE / 2.0)
	eq(old.piece, "", "after 3 s the old piece has stopped")
	_near(nw.players[1].volume_db, -2.0, 0.01, "and the new BATTLE is at full")
	a.music_state("explore")
	a.music_region("human_core", "concord")
	eq(a.music_piece, "signal", "back in the first region, the fight over")
	eq(_deck(a).mix_to, 0.0, "the new piece is in EXPLORE")
	a.free()


func test_a_region_with_the_same_piece_keeps_it_playing() -> void:
	var a = _node()
	a.music_region("nowhere", "kett")
	a.music_state("explore")
	a.advance(10.0)
	var d = _deck(a)
	a.music_region("elsewhere", "other")
	eq(a.piece_starts, 1, "the same default piece: no new start")
	eq(_deck(a), d, "on the same deck")
	# the same song with an accent: a new deck takes over from the same position
	a.music_region("kett_hives", "kett")
	var nw = _deck(a)
	check(nw != d, "an accent makes a new take")
	_near(a._sim_pos[nw.players[0]], a._sim_pos[d.players[0]], 0.001, "that goes on from where the song is")
	check(nw.linear and d.linear, "the two takes cross-fade at equal gain, not equal power")
	a.free()


func test_menu_build_and_hollow_have_their_tracks() -> void:
	var a = _node()
	a.music_state("explore")
	a.advance(Audio.FADE)
	var d = _deck(a)
	a.advance(5.0)
	var at: float = a._sim_pos[d.players[0]]
	a.music_state("build")
	eq(a.music_file, WAV_B, "build plays its track")
	eq(a.music_piece, "", "the piece is out")
	check(d.parked and d.target == 0.0, "and waits parked")
	a.advance(Audio.FADE)
	eq(d.gain, 0.0, "the piece has faded out")
	eq(d.piece, "black_box", "but plays on, silent")
	check(a._sim_pos[d.players[0]] > at, "so it comes back in time")
	eq(a._mgain[a._cur], 1.0, "the track is in")
	a.music_region("human_core", "concord")
	eq(a.piece_starts, 1, "a jump under a track starts nothing yet")
	a.music_state("explore")
	eq(a.music_piece, "signal", "the new region's piece comes in when the track goes")
	eq(a.piece_starts, 2, "started then")
	a.advance(Audio.FADE)
	eq(d.piece, "", "and the waiting one is gone")
	a.music_state("menu")
	a.music_state("explore")
	eq(a.piece_starts, 2, "from a menu back to the piece: it was waiting, nothing starts")
	a.advance(Audio.FADE)
	eq(_deck(a).gain, 1.0, "and it is back at full")
	a.free()


func test_hollow_takes_its_track_until_there_is_a_hollow_piece() -> void:
	var a = _node()
	a.music_state("explore")
	a.music_state("hollow")
	eq(a.music_file, WAV_A, "no Hollow piece: the hollow state's track")
	eq(a.music_piece, "", "no piece")
	a.music_state("combat")
	eq(a.music_piece, "black_box", "a fight in the Hollow is the region's piece (no Hollow piece)")
	a.free()
	var data := Audio._read(FIXTURE)
	data["regions"]["faction:hollow"] = "signal"
	a = _node(data)
	a.music_region("kett_hives", "kett")
	a.music_state("explore")
	eq(a.music_piece, "black_box", "outside the Hollow: the region's piece")
	a.music_state("hollow")
	eq(a.music_piece, "signal", "the Hollow piece, as regions names it")
	check(a._deck_cur >= 0, "on a deck")
	a.music_state("combat")
	eq(a.music_piece, "signal", "a fight in the Hollow stays in the Hollow's piece")
	eq(_deck(a).mix_to, 1.0, "in BATTLE")
	a.music_state("explore")
	eq(a.music_piece, "black_box", "out of the Hollow it is the region's again")
	a.free()


# --- accents ---------------------------------------------------------------------------------------------------------

func test_accents_start_and_stay_in_sync() -> void:
	var a = _node()
	a.music_region("kett_hives", "kett")
	a.music_state("explore")
	var d = _deck(a)
	var ex: AudioStreamPlayer = d.players[0]
	var ac: AudioStreamPlayer = d.players[2]
	check(ac.stream != null, "the region's accent stem is loaded")
	eq(a._sim_pos[ac], a._sim_pos[ex], "it starts with the piece")
	a.advance(Audio.FADE)
	_near(ac.volume_db, -9.0, 0.01, "at its dB")
	a.advance(10.3)
	var length: float = ac.stream.get_length()
	_near(a._sim_pos[ac], fposmod(a._sim_pos[ex], length), 0.0001, "it loops on its own length, in step with the piece")
	eq(a.sync_layers(), 0, "nothing to nudge")
	a._sim_pos[ac] = fposmod(a._sim_pos[ac] + 0.4, length)
	eq(a.sync_layers(), 1, "an accent that drifted is nudged")
	_near(a._sim_pos[ac], fposmod(a._sim_pos[ex], length), 0.0001, "back in step")
	a.music_state("combat")
	a.advance(Audio.BATTLE_IN)
	_near(ac.volume_db, -9.0, 0.01, "the accent plays on in the BATTLE layer")
	a.music_region("human_core", "concord")
	eq(_deck(a).streams[2], null, "another region has no accent")
	a.free()


# --- what is missing ---------------------------------------------------------------------------------------------------

func test_missing_files_stay_silent() -> void:
	var data := Audio._read(FIXTURE)
	data["pieces"]["ghost"] = {"explore": "nope_explore.ogg", "battle": "nope_battle.ogg"}
	data["regions"]["region:lost"] = "ghost"
	data["accents"]["region:kett_hives"]["stem"] = "nope_accent.ogg"
	data["regions"]["region:half"] = "half"
	data["pieces"]["half"] = {"explore": "black_box_explore.ogg", "battle": "nope_battle.ogg"}
	data["regions"]["region:typo"] = "not_a_piece"
	var a = _node(data)
	a.music_region("lost", "kett")
	a.music_state("explore")
	eq(a.music_file, "", "a piece whose files are missing is silence")
	eq(a.music_piece, "", "no piece")
	eq(a._deck_cur, -1, "no deck")
	a.music_state("combat")
	a.advance(5.0)
	eq(a.music_file, "", "and a fight does not make a sound of it")
	a.music_region("half", "kett")
	eq(a.music_piece, "half", "a piece with only one layer plays that layer")
	check(_deck(a).streams[1] == null, "BATTLE is missing")
	a.advance(Audio.BATTLE_IN)
	_near(_deck(a).players[0].volume_db, -80.0, 0.01, "in a fight its EXPLORE layer fades out and nothing replaces it")
	a.music_region("kett_hives", "kett")
	check(a.music_piece == "black_box" and _deck(a).streams[2] == null, "a missing accent stem: the piece plays without it")
	a.advance(Audio.REGION_FADE)
	a.music_region("typo", "kett")
	eq(a.music_piece, "black_box", "a region naming a piece that is not there keeps what plays")
	a.music_state("explore")
	a.music_state("hollow")
	a.advance(Audio.FADE)
	a.free()
	var b = _node({"pieces": {}, "regions": {}})
	b.music_state("explore")
	eq(b.music_file, "", "pieces and regions with nothing in them: silence")
	b.free()


# --- the muffle --------------------------------------------------------------------------------------------------------

func _muffle_fx() -> AudioEffectLowPassFilter:
	var i := AudioServer.get_bus_index("Music")
	for k in AudioServer.get_bus_effect_count(i) if i >= 0 else 0:
		var e = AudioServer.get_bus_effect(i, k)
		if e is AudioEffectLowPassFilter and e.has_meta("hs_muffle"):
			return e
	return null


func test_muffle_puts_a_low_pass_on_the_music_bus() -> void:
	var a = _node()
	a.music_state("explore")
	a.muffle(true)
	eq(a.muffled, true, "muffled")
	a.advance(1.5)
	if AudioServer.get_bus_index("Music") < 0:
		a.free()
		return  # (no bus layout in this run)
	var fx := _muffle_fx()
	check(fx != null, "the Music bus has the low-pass")
	if fx != null:
		_near(fx.cutoff_hz, Audio.MUFFLE_HZ, 150.0, "its cutoff settles near the muffled one")
		var i := AudioServer.get_bus_index("Music")
		var k := 0
		for j in AudioServer.get_bus_effect_count(i):
			if AudioServer.get_bus_effect(i, j) == fx:
				k = j
		check(AudioServer.is_bus_effect_enabled(i, k), "and it is on")
		eq(a.music_piece, "black_box", "the piece plays on under it")
		a.muffle(false)
		a.advance(3.0)
		check(fx.cutoff_hz > Audio.OPEN_HZ * 0.9, "unmuffled, it opens again (%s)" % fx.cutoff_hz)
		check(not AudioServer.is_bus_effect_enabled(i, k), "and goes off")
	var b = _node()
	b.muffle(true)
	eq(_muffle_fx(), a._muf_fx, "a second node finds the same effect, it does not add another")
	b.muffle(false)
	b.advance(3.0)
	a.free()
	b.free()
