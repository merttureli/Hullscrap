extends Node
## The game's sound, one node in the main scene (not an autoload: headless tests and tools never need it). Views and UI reach it with the
## static helpers, which do nothing when the node is absent (a bare tree, a test):
##   Audio.fx(ctx, id, world_pos = null, gain_db = 0, delay = 0)   a one-shot from data/audio.json; with a world position (px) it is
##       positional (an AudioStreamPlayer2D heard relative to the camera, silent when far outside the view), else plain
##   Audio.fx_loop(ctx, key, id, on, volume = 1, pitch = 1, world_pos = null, fade_s = 0)   a loop (engine, beam, tractor, fire, repair, a
##       missile in flight, a hazard): call it each frame it should sound; it fades in, follows volume and pitch, and fades out on its own when
##       the calls stop (fade_s: seconds a full fade takes, 0 = the quick default)
##   Audio.mood(ctx, state)   the music state (menu, explore, combat, hollow, build), cross-faded; Audio.cue(ctx, id)   a music sting
## `ctx` is any node in the tree (or the SceneTree). Logic scripts (RefCounted) never call this; views and UI do, usually from the event lists
## the logic already makes. Sounds come from assets/audio/sfx (audio/_src/sfx/build_sfx.py), the music from data/music.json
## ({states: {state: [track files]}, stings: {id: file}, volumes: {file: dB}}; a file or a track that is missing just stays silent).
## Voice rules: a pool of players, a cooldown per id and a cap of voices per id (so six rapid turrets do not stack into noise), a random
## pitch of +-pitch_var, and no sound for a world position farther than NEAR view radii from the camera. The admission rules run on
## a clock and a ledger of their own (advance), so they work, and are tested, without the audio device or the scene tree.
## This node also directs the music from what the game is doing (mood.gd) and listens to the player's ship (ship_audio.gd): the red
## alert, the unlock and Ada stings, the crew's sounds, the footsteps, the machines. It also plays the ambience (ambience.gd): the ship's
## room tone (the Room bus's low-pass opens with the reactor's load), the space bed of the region's family (cross-faded over BED_FADE seconds)
## and the drone's hum; the hazard loops come from the fight (combat_view.gd). The Ambience slider sets the Ambience bus. Ctrl+M mutes everywhere.

const Mood = preload("res://scripts/audio/mood.gd")
const ShipAudio = preload("res://scripts/audio/ship_audio.gd")
const Ambience = preload("res://scripts/audio/ambience.gd")
const GROUP := "hs_audio"
const DATA_PATH := "res://data/audio.json"
const MUSIC_PATH := "res://data/music.json"
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const POOL_2D := 20  ## positional voices
const POOL_PLAIN := 14  ## plain voices
const FADE := 2.0  ## seconds of a music cross-fade
const DUCK_DB := -6.0  ## how far a sting dips the music while it plays
const DUCK_RATE := 40.0  ## dB per second of that dip
const LOOP_TTL := 0.35  ## seconds a loop goes on after the last call that asked for it
const LOOP_RATE := 8.0  ## how fast a loop fades in and out, volume per second
const PITCH_RATE := 1.5  ## how fast a loop's pitch follows, per second
const NEAR := 1.25  ## a world sound plays only within this many view radii of the camera
const ENEMY_DB := -6.0  ## the enemy ship's sounds against yours (callers pass it as gain_db)
const DEFAULTS := {"master": 0.8, "music": 0.6, "sfx": 0.8, "ambience": 0.8}  ## the volume sliders (linear, 0 to 1)
const BED_FADE := 3.0  ## seconds of the cross-fade between two space beds
const ROOM_RATE := 1.2  ## how fast the Room low-pass follows the reactor's load, per second
const STEP_ZOOM := 0.45  ## the soldier's boots are heard only with the camera at least this close (the main camera starts at 0.5)
const POLL := 0.1  ## seconds between two looks at what the game is doing

static var _table_cache := {}  # data/audio.json as table() reads it

var defs := {}  ## data/audio.json, id -> definition
var music_data := {}  ## data/music.json
var beds := {}  ## data/audio.json `_beds`: which space bed plays where (ambience.gd bed_for)
var bed_now := ""  ## the space bed asked for last
var volumes := DEFAULTS.duplicate()
var muted := false
var clock := 0.0  ## seconds this node has run (advance)
var music_now := ""  ## the music state asked for last
var music_file := ""  ## the track playing now ("" = none)
var front: Node  ## the siblings this node reads (set up in setup(), null when absent)
var build: Node
var combat: Node
var sector: Node
var sim: Node
var _rng := RandomNumberGenerator.new()  # which variant and how much pitch: heard, never simulated
var _cache := {}  # path -> stream, or null for a file that is missing
var _last := {}  # id -> clock of its last play
var _ledger: Array = []  # [{id, end}] the voices that sound now (by the clock), so the caps hold without the device
var _prev_file := {}  # id -> the variant played last
var _pool_2d: Array = []
var _pool: Array = []
var _loops := {}  # key -> {id, vol, target, seen, pitch, pitch_now, pos, player}
var _pending: Array = []  # delayed one-shots: {at, id, pos, gain}
var _music: Array = []  # two players, for the cross-fade
var _mgain := [0.0, 0.0]  # their fade (0 to 1)
var _mtarget := [0.0, 0.0]
var _mdb := [0.0, 0.0]  # and their track's trim
var _cur := -1  # the slot of the track that is in
var _visits := {}  # music state -> how often it was entered, to alternate its tracks
var _sting: AudioStreamPlayer
var _sting_until := 0.0
var _duck := 0.0
var _ready_done := false
var _mood := Mood.new()
var _ship_audio := ShipAudio.new()
var _poll_t := 0.0
var _red := false  # a hostile was in range at the last look
var _campaign = null
var _unlocks := 0
var _mute_key := false
var _ambience_rules := Ambience.new()
var _room_hz := Ambience.ROOM_CLOSED  # the Room bus's cutoff now
var _room_to := Ambience.ROOM_CLOSED  # and where it is going (the reactor's load)
var _bed_ids: Array = []  # the beds the table can name


## The Audio node of the tree `ctx` is in (a node or the SceneTree), or null: a bare tree, a test, a tool.
static func of(ctx):
	var tree := _tree_of(ctx)
	return tree.get_first_node_in_group(GROUP) if tree != null else null


static func _tree_of(ctx) -> SceneTree:
	if ctx is SceneTree:
		return ctx
	if ctx is Node and ctx.is_inside_tree():
		return ctx.get_tree()
	return null


## A one-shot; nothing happens without an Audio node.
static func fx(ctx, id: String, world_pos = null, gain_db := 0.0, delay := 0.0) -> void:
	var a = of(ctx)
	if a != null:
		a.play(id, world_pos, gain_db, delay)


## Keep loop `key` (a sound of data/audio.json that loops) going this frame, at `volume` (0 to 1) and `pitch`.
static func fx_loop(ctx, key: String, id: String, on: bool, volume := 1.0, pitch := 1.0, world_pos = null, fade_s := 0.0) -> void:
	var a = of(ctx)
	if a != null:
		a.loop(key, id, on, volume, pitch, world_pos, fade_s)


## The data/audio.json table, read once: id -> definition (plus the `_doc` and `_beds` entries).
static func table() -> Dictionary:
	if _table_cache.is_empty():
		_table_cache = _read(DATA_PATH)
	return _table_cache


## Is `id` a looping sound (a beam, a hazard)?
static func is_loop(id: String) -> bool:
	var d = table().get(id)
	return d is Dictionary and bool(d.get("loop", false))


## Ask for music state `state`.
static func mood(ctx, state: String) -> void:
	var a = of(ctx)
	if a != null:
		a.music_state(state)


## Play music sting `id` (victory, defeat, jump, region_cross, ada_found, unlock, ending).
static func cue(ctx, id: String) -> void:
	var a = of(ctx)
	if a != null:
		a.sting(id)


## The sound of weapon `w` (a weapons.gd definition) whose part is of equipment `line` ("scrap", "neon", "standard" or ""): its own `sound`
## key when it has one (the races' signature guns), else the kind's sound in the line's version if the table has one (laser_neon, flak_scrap ...),
## else the kind's sound. `ids` is the sound table (data/audio.json, read once when null).
static func weapon_sound(w: Dictionary, line := "", ids = null) -> String:
	var known: Dictionary = ids if ids != null else table()
	var own := str(w.get("sound", ""))
	if own != "" and known.has(own):
		return own
	var base := _kind_sound(w)
	var version := base + "_" + line
	return version if line != "" and line != "standard" and known.has(version) else base


## The sound of the kind of `w`: its kind, with the fast light turrets on their own soft tick and ion on its own zap.
static func _kind_sound(w: Dictionary) -> String:
	var kind := str(w.get("kind", ""))
	if kind == "beam":
		return "beam_loop"
	if kind == "laser" and str(w.get("damage_type", "")) == "ion":
		return "ion"
	if bool(w.get("turret", false)) and float(w.get("cooldown", 9.0)) <= 1.0:
		return "rapid_tick"
	match kind:
		"laser":
			return "laser"
		"bolt":
			return "bolt"
		"flak":
			return "flak"
		"missile":
			return "missile_launch"
	return "bolt"


func _ready() -> void:
	setup()


## Read the data, make the voices and the buses' volumes. Safe to call twice; _ready does it, a test calls it by hand.
func setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	_rng.seed = 7
	defs = _read(DATA_PATH)
	defs.erase("_doc")
	beds = defs.get("_beds", {})
	defs.erase("_beds")
	for k in ["by_region", "by_faction"]:
		for id in beds.get(k, {}).values():
			if not _bed_ids.has(id):
				_bed_ids.append(id)
	for k in ["hollow", "default"]:
		if beds.has(k) and not _bed_ids.has(beds[k]):
			_bed_ids.append(beds[k])
	music_data = _read(MUSIC_PATH)
	for i in POOL_2D:
		var p := AudioStreamPlayer2D.new()
		p.panning_strength = 0.5
		_pool_2d.append(p)
		add_child(p)
	for i in POOL_PLAIN:
		var q := AudioStreamPlayer.new()
		_pool.append(q)
		add_child(q)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		_music.append(m)
		add_child(m)
	_sting = AudioStreamPlayer.new()
	_sting.bus = "Music"
	add_child(_sting)
	var parent := get_parent()
	if parent != null:
		front = parent.get_node_or_null("FrontDoor")
		build = parent.get_node_or_null("BuildMode")
		combat = parent.get_node_or_null("Combat")
		sector = parent.get_node_or_null("Sector")
		sim = parent.get_node_or_null("ShipSim")
	_apply_buses()


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


# --- volumes -----------------------------------------------------------------------------------------------------

## The sliders: {master, music, sfx, ambience}, each 0 to 1. Anything else in `d` is ignored, a missing key keeps its value.
func apply_settings(d: Dictionary) -> void:
	for k in DEFAULTS:
		if d.has(k):
			volumes[k] = clampf(float(d[k]), 0.0, 1.0)
	_apply_buses()


func settings() -> Dictionary:
	return volumes.duplicate()


## Set one slider (`kind`: master, music, sfx or ambience) to `v`, 0 to 1.
func set_volume(kind: String, v: float) -> void:
	if DEFAULTS.has(kind):
		volumes[kind] = clampf(v, 0.0, 1.0)
		_apply_buses()


## Ctrl+M: mute or unmute everything. Returns the new state (true = muted).
func toggle_mute() -> bool:
	muted = not muted
	_apply_buses()
	return muted


## Put the sliders and the mute on the buses: Master, Music, Ambience (the Room bus sends to it); the SFX slider also takes the UI bus.
func _apply_buses() -> void:
	_bus("Master", volumes["master"])
	_bus("Music", volumes["music"])
	_bus("SFX", volumes["sfx"])
	_bus("UI", volumes["sfx"])
	_bus("Ambience", volumes["ambience"])
	var m := AudioServer.get_bus_index("Master")
	if m >= 0:
		AudioServer.set_bus_mute(m, muted)


static func _bus(bus_name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))


# --- one-shots ---------------------------------------------------------------------------------------------------

## Play sound `id`. `world_pos` (px) makes a positional sound where its definition says so; `gain_db` adds to its volume (ENEMY_DB for
## the enemy's); `delay` waits that many seconds. Returns false when it did not play: unknown id, its cooldown, its voice cap, no free
## voice, too far from the camera, or a file that is missing.
func play(id: String, world_pos = null, gain_db := 0.0, delay := 0.0) -> bool:
	if delay > 0.0:
		_pending.append({"at": clock + delay, "id": id, "pos": world_pos, "gain": gain_db})
		return true
	var d: Dictionary = defs.get(id, {})
	if d.is_empty() or bool(d.get("loop", false)):
		return false
	if clock - float(_last.get(id, -1.0e9)) < float(d.get("cooldown", 0.0)):
		return false
	if voices_of(id) >= int(d.get("max_voices", 4)):
		return false
	var spatial: bool = bool(d.get("positional", false)) and world_pos is Vector2
	if spatial and not near(world_pos):
		return false
	var stream: AudioStream = _pick(id, d)
	if stream == null:
		return false
	var pitch := 1.0 + _rng.randf_range(-1.0, 1.0) * float(d.get("pitch_var", 0.0))
	var p = null
	if is_inside_tree():  # (a test drives the rules above without the tree: playback needs it)
		p = _free_voice(_pool_2d if spatial else _pool)
		if p == null:
			return false
		p.stream = stream
		p.bus = str(d.get("bus", "SFX"))
		p.volume_db = float(d.get("volume_db", 0.0)) + gain_db
		p.pitch_scale = pitch
		if spatial:
			p.global_position = world_pos
			p.max_distance = view_radius() * NEAR
			p.attenuation = 0.6
		p.play()
	_last[id] = clock
	_ledger.append({"id": id, "end": clock + stream.get_length() / pitch})
	return true


## How many voices of `id` sound now (by the clock).
func voices_of(id: String) -> int:
	var n := 0
	for v in _ledger:
		if v["id"] == id and v["end"] > clock:
			n += 1
	return n


## A variant of sound `d` (data/audio.json), not the one played last when there is another; null when no file can be loaded.
func _pick(id: String, d: Dictionary) -> AudioStream:
	var files: Array = d.get("files", [])
	if files.is_empty():
		return null
	var i := _rng.randi() % files.size()
	if files.size() > 1 and files[i] == _prev_file.get(id, ""):
		i = (i + 1) % files.size()
	_prev_file[id] = files[i]
	return _load(SFX_DIR + str(files[i]))


func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


func _free_voice(pool: Array):
	for p in pool:
		if not p.playing:
			return p
	return null


## Half the diagonal of what the camera sees, in world px (a default without a camera).
func view_radius() -> float:
	var cam := _camera()
	if cam == null:
		return 1100.0
	return (get_viewport().get_visible_rect().size / cam.zoom).length() * 0.5


func listener() -> Vector2:
	var cam := _camera()
	return cam.get_screen_center_position() if cam != null else Vector2.ZERO


## Is the world point `pos` close enough to the camera to be heard?
func near(pos: Vector2) -> bool:
	return not is_inside_tree() or pos.distance_to(listener()) <= view_radius() * NEAR


func _camera() -> Camera2D:
	return get_viewport().get_camera_2d() if is_inside_tree() else null


# --- loops ------------------------------------------------------------------------------------------------------

## Keep loop `key` (a loop sound `id`) going: `on` false lets it fade out; `volume` (0 to 1) and `pitch` follow smoothly; a `world_pos`
## makes it positional (the enemy's beam). Call it every frame it should sound: when the calls stop it fades out by itself. `fade_s` is how
## many seconds a full fade in or out takes (0: LOOP_RATE, the quick default; the space beds ask for BED_FADE).
func loop(key: String, id: String, on: bool, volume := 1.0, pitch := 1.0, world_pos = null, fade_s := 0.0) -> void:
	var L = _loops.get(key)
	var rate := LOOP_RATE if fade_s <= 0.0 else 1.0 / fade_s
	if not on:
		if L != null:
			L["target"] = 0.0
			L["rate"] = rate
		return
	if not bool(defs.get(id, {}).get("loop", false)):
		return
	if L == null:
		L = {"id": id, "vol": 0.0, "pitch_now": pitch, "player": null}
		_loops[key] = L
	L["rate"] = rate
	L["id"] = id
	L["target"] = clampf(volume, 0.0, 1.0)
	L["seen"] = clock
	L["pitch"] = pitch
	L["pos"] = world_pos


## The loops that sound now (keys).
func loops_on() -> Array:
	return _loops.keys().filter(func(k): return _loops[k]["target"] > 0.0)


func _step_loops(dt: float) -> void:
	for key in _loops.keys():
		var L: Dictionary = _loops[key]
		if clock - float(L.get("seen", -1.0e9)) > LOOP_TTL:
			L["target"] = 0.0
		var pos = L.get("pos")
		if pos is Vector2 and not near(pos):
			L["target"] = 0.0
		L["vol"] = move_toward(float(L["vol"]), float(L["target"]), float(L.get("rate", LOOP_RATE)) * dt)
		L["pitch_now"] = move_toward(float(L["pitch_now"]), float(L["pitch"]), PITCH_RATE * dt)
		var p = L["player"]
		if float(L["vol"]) <= 0.001 and float(L["target"]) <= 0.0:
			if p != null:
				p.stop()
				p.queue_free()
			_loops.erase(key)
			continue
		if not is_inside_tree():
			continue
		var d: Dictionary = defs[L["id"]]
		var spatial: bool = pos is Vector2 and bool(d.get("positional", false))
		if p == null:
			var stream := _load_loop(d)
			if stream == null:
				_loops.erase(key)
				continue
			p = AudioStreamPlayer2D.new() if spatial else AudioStreamPlayer.new()
			p.stream = stream
			p.bus = str(d.get("bus", "SFX"))
			if spatial:
				p.panning_strength = 0.5
				p.attenuation = 0.6
			add_child(p)
			p.play()
			L["player"] = p
		if spatial:
			p.global_position = pos
			p.max_distance = view_radius() * NEAR
		p.volume_db = float(d.get("volume_db", 0.0)) + linear_to_db(maxf(float(L["vol"]), 0.0001))
		p.pitch_scale = maxf(float(L["pitch_now"]), 0.05)
		if not p.playing:
			p.play()


## The first file of loop sound `d`, made to loop forward even if its import settings did not.
func _load_loop(d: Dictionary) -> AudioStream:
	var files: Array = d.get("files", [])
	var s := _load(SFX_DIR + str(files[0])) if not files.is_empty() else null
	if s is AudioStreamWAV and s.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() >> (2 if s.stereo else 1)  # 16-bit frames
	return s


# --- music --------------------------------------------------------------------------------------------------------

## Go to music state `state` (menu, explore, combat, hollow, build): the track of data/music.json for it fades in over FADE seconds as
## the old one fades out. Each visit to a state plays the next of its tracks. A state with no track (or no data/music.json) is silence.
func music_state(state: String) -> void:
	if state == music_now:
		return
	music_now = state
	var tracks: Array = music_data.get("states", {}).get(state, [])
	var n: int = _visits.get(state, 0)
	_visits[state] = n + 1
	var path := ""
	var track := ""
	var stream: AudioStream = null
	for i in tracks.size():
		track = str(tracks[(n + i) % tracks.size()])
		path = _music_path(track)
		stream = _load(path)
		if stream != null:
			break
	if stream == null:
		_fade_out()
		return
	if path == music_file and _cur >= 0:
		return  # two states share the track: it plays on
	var slot := 1 - _cur if _cur >= 0 else 0
	for i in 2:
		_mtarget[i] = 0.0
	_mtarget[slot] = 1.0
	_mgain[slot] = 0.0
	_mdb[slot] = _trim(track, path)
	_cur = slot
	music_file = path
	var p: AudioStreamPlayer = _music[slot]
	p.stream = stream
	p.volume_db = -80.0
	if is_inside_tree():
		p.play()


func _fade_out() -> void:
	_mtarget = [0.0, 0.0]
	_cur = -1
	music_file = ""


## The file of a track named in data/music.json: a res:// path as it is, else a file name in its `dir` (assets/audio/music by default;
## the .ogg is optional).
func _music_path(track: String) -> String:
	if track.begins_with("res://"):
		return track
	return str(music_data.get("dir", MUSIC_DIR)) + (track if track.get_extension() != "" else track + ".ogg")


## The trim in dB data/music.json gives a track (`volumes`, keyed by the name it is listed under or by its file name).
func _trim(track: String, path: String) -> float:
	var v: Dictionary = music_data.get("volumes", {})
	return float(v.get(track, v.get(path.get_file(), 0.0)))


## A one-shot music cue (data/music.json stings): the music dips DUCK_DB while it plays. False when there is none, or no such file.
func sting(id: String) -> bool:
	var file = music_data.get("stings", {}).get(id)
	if file == null:
		return false
	var path := _music_path(str(file))
	var stream := _load(path)
	if stream == null:
		return false
	_sting.stream = stream
	_sting.volume_db = _trim(str(file), path)
	if is_inside_tree():
		_sting.play()
	_sting_until = clock + stream.get_length()
	return true


func _step_music(dt: float) -> void:
	_duck = move_toward(_duck, DUCK_DB if clock < _sting_until else 0.0, DUCK_RATE * dt)
	for i in 2:
		var p: AudioStreamPlayer = _music[i]
		_mgain[i] = move_toward(_mgain[i], _mtarget[i], dt / FADE)
		if _mgain[i] <= 0.0 and _mtarget[i] <= 0.0:
			if p.playing:
				p.stop()
			continue
		p.volume_db = linear_to_db(maxf(sin(_mgain[i] * PI / 2.0), 0.0001)) + _mdb[i] + _duck  # equal power: the two fades sum to one
		if is_inside_tree() and not p.playing and _mtarget[i] > 0.0 and p.stream != null:
			p.play()  # a track whose file does not loop starts over


# --- the clock ----------------------------------------------------------------------------------------------------

## Advance the clock by `dt`: delayed sounds, loops and the music fades. _process does it; tests do it by hand.
func advance(dt: float) -> void:
	clock += dt
	_ledger = _ledger.filter(func(v): return v["end"] > clock)
	if not _pending.is_empty():
		var due := _pending.filter(func(e): return e["at"] <= clock)
		_pending = _pending.filter(func(e): return e["at"] > clock)
		for e in due:
			play(e["id"], e["pos"], e["gain"])
	_step_loops(dt)
	_step_music(dt)
	_step_room(dt)


func _process(dt: float) -> void:
	advance(dt)
	_mute_check()
	_poll_t += dt
	if _poll_t >= POLL:
		_direct(_poll_t)
		_poll_t = 0.0


## Ctrl+M, read from the keyboard state so no screen can swallow it.
func _mute_check() -> void:
	var down := Input.is_key_pressed(KEY_M) and Input.is_key_pressed(KEY_CTRL)
	if down and not _mute_key:
		var on := toggle_mute()
		var toast = front.get("toast") if front != null else null
		if toast != null:
			toast.push("Sound off (Ctrl+M)" if on else "Sound on")
	_mute_key = down


# --- directing: the music and the ship's ears ---------------------------------------------------------------------

## What the game is doing, for mood.gd.
func mood_inputs() -> Dictionary:
	var out := {}
	if front != null:
		var menu = front.get("menu")
		var over = front.get("over")
		var ending = front.get("ending")
		var picker = front.get("picker")
		out["menu"] = (menu != null and menu.visible and int(menu.mode) == 0) or (over != null and over.visible) \
			or (ending != null and ending.visible) or (picker != null and picker.visible)
	if combat != null:
		out["fight"] = bool(combat.get("active"))
	if build != null:
		out["build"] = bool(build.get("build_on")) and not bool(build.get("combat"))
		out["hostile"] = build.has_method("can_build") and build.can_build() != ""
		var map = build.get("drift")
		var c = map.get("campaign") if map != null else null
		if c != null:
			out["hollow"] = c.is_hollow(c.current)
			out["pressure"] = c.tide_pressure(c.current)
			out["region"] = str(c.region_id)
			out["faction"] = str(c.region_data.get("faction", ""))
	return out


func _direct(dt: float) -> void:
	var inp := mood_inputs()
	music_state(_mood.update(inp, dt))
	var red := bool(inp.get("hostile", false))
	if red and not _red:
		play("red_alert")
	_red = red
	_unlock_watch()
	var ship = sim.player_ship() if sim != null and sim.has_method("player_ship") else null
	var ev := _ship_audio.update(ship, sim.jobs_of(ship) if ship != null else null)
	var live := not get_tree().paused
	loop("repair", "repair_loop", bool(ev["repair"]) and live)
	loop("fire", "fire_loop", bool(ev["fire"]) and live)
	if int(ev["extinguished"]) > 0:
		play("extinguish")
	if int(ev["ignited"]) > 0:
		play("fire_whoomph")
	if int(ev["hurt"]) > 0:
		play("crew_hurt")
	if int(ev["beep"]) > 0:
		play("drone_beep")
	if int(ev["restocked"]) > 0:
		play("ammo_restock")
	if ev["joined"].has(ShipAudio.ada_name()):
		sting("ada_found")
	_footsteps(int(ev["steps"]), ship != null and not bool(inp.get("menu", true)))
	_ambience(inp, ev, live, dt)


## The soldier's boots, when the camera is close enough to hear them (STEP_ZOOM): `n` steps since the last look, the second a beat after the first.
func _footsteps(n: int, playing: bool) -> void:
	if n <= 0 or not playing:
		return
	var cam := _camera()
	if cam != null and cam.zoom.x < STEP_ZOOM:
		return
	for i in n:
		play("footstep", null, 0.0, 0.12 * i)


## The ambience (ambience.gd), in a game and not in a menu: the room tone, whose low-pass opens with the reactor's load; the space bed of the
## region's family, cross-faded over BED_FADE seconds when it changes; the drone's hum; the medbay, smelter and fabricator while they work; and
## the hull's creak once it is under half.
func _ambience(inp: Dictionary, ev: Dictionary, live: bool, dt: float) -> void:
	var playing := inp.has("menu") and not bool(inp["menu"])
	bed_now = ""
	if playing:
		var hollow := bool(inp.get("hollow", false)) or float(inp.get("pressure", 0.0)) >= Mood.HOLLOW_PRESSURE
		bed_now = Ambience.bed_for(beds, str(inp.get("region", "")), str(inp.get("faction", "")), hollow)
	for id in _bed_ids:
		loop("bed:" + str(id), str(id), str(id) == bed_now, 1.0, 1.0, null, BED_FADE)
	loop("room", "room_tone", playing, 1.0, 1.0, null, 1.0)
	_room_to = Ambience.room_cutoff(float(ev["load"]))
	loop("drone", "drone_hum", playing and int(ev["drones"]) > 0, 1.0, 1.0, null, 1.0)
	loop("medbay", "medbay_hum", playing and bool(ev["healing"]) and live, 1.0, 1.0, null, 1.0)
	loop("smelter", "smelter_loop", playing and bool(ev["smelting"]) and live, 1.0, 1.0, null, 1.0)
	loop("fabricator", "fabricator_loop", playing and bool(ev["fabricating"]) and live, 1.0, 1.0, null, 1.0)
	if playing and _ambience_rules.creak(_hull_frac(), dt):
		play("hull_creak")


## The player's hull as a fraction of its integrity: the fight's while one is on, else the run's (campaign.gd); 1 when there is none to read.
func _hull_frac() -> float:
	if combat != null and bool(combat.get("active")):
		var session = combat.get("session")
		if session != null:
			var co = session.arena.ships[0]
			return clampf(float(co.hull) / maxf(float(co.hull_max), 1.0), 0.0, 1.0)
	var map = build.get("drift") if build != null else null
	var c = map.get("campaign") if map != null else null
	var ship = sim.player_ship() if sim != null and sim.has_method("player_ship") else null
	if c == null or ship == null:
		return 1.0
	return clampf(float(c.hull_left(ship)) / maxf(float(c.hull_max(ship)), 1.0), 0.0, 1.0)


## Let the Room bus's low-pass follow the reactor's load (in equal musical steps, ROOM_RATE a second).
func _step_room(dt: float) -> void:
	_room_hz = exp(lerpf(log(_room_hz), log(_room_to), minf(dt * ROOM_RATE, 1.0)))
	var i := AudioServer.get_bus_index("Room")
	if i >= 0 and AudioServer.get_bus_effect_count(i) > 0:
		var fx = AudioServer.get_bus_effect(i, 0)
		if fx is AudioEffectLowPassFilter:
			fx.cutoff_hz = _room_hz


## An unlock earned this run: its sound and sting (the campaign keeps the list).
func _unlock_watch() -> void:
	var map = build.get("drift") if build != null else null
	var c = map.get("campaign") if map != null else null
	if c != _campaign:
		_campaign = c
		_unlocks = c.unlocks_earned.size() if c != null else 0
		return
	if c != null and c.unlocks_earned.size() > _unlocks:
		play("unlock")
		sting("unlock")
	_unlocks = c.unlocks_earned.size() if c != null else 0
