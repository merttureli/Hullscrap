extends Node2D
## Boarding on screen (docs/BOARDING.md, stage B1): the soldier goes aboard another vessel (a Boarding visit, boarding.gd) and walks it in the dark
## with a flashlight toward the mouse and a motion tracker. The ship's own views are put away the way a fight does it (BuildMode.combat, the crew
## view, the sector view and the debris) and the ship's world stands still (ShipSim paused, the sector does not tick); the Hollow tide's
## linger clock keeps running (map_view.gd counts it while the map is shut).
## - The site is drawn by a ShipView on a plain Ship (the same tile art as a ship), the props and the soldier by this node over it, in the dark: a
##   CanvasModulate near black, the flashlight (a cone PointLight2D, shadows from the wall occluders of board_light.gd), a small light round the soldier,
##   dim red lights in some rooms and a green one in the airlock.
## - WASD walks (screen-relative, CrewMember.move_input on the site's walk grid), the mouse aims the light, the wheel zooms.
## - E: hold it on a container to open it (a progress ring), then the loot list shows: E takes all, 1-9 one row, Esc shuts it. Hold E for 4 s by a
##   locked door to hack it, tap E by a card door to use the keycard. E in the airlock leaves, and so does L (the Leave button) when no foe has hunted the party for a while. Esc is the pause menu; Ctrl+S is refused aboard.
## - The HUD (board_hud.gd): the site and its containers, the airlock marker (an arrow at the screen edge when it is off screen), the tracker.
## Stage B4: a shot is a bolt of light that flies to its hit point (board_fx.gd: the bolts, their pooled lights, the impacts, the flares; the events of the session
## carry the look and the flight time, and a hit waits for its bolt in `_later`), the HUD has party cards and a weapon bar (board_cards.gd), the crew picker is
## the loadout screen (board_loadout.gd; this node keeps its state: load_who, load_slot, loadout_* and the clicks), and a Spotter Cam in the party lights the rooms
## it sees as a camera feed (_update_feed).
## Stage B2 hooks: `contacts_source` (a Callable that returns the moving contacts for the tracker), `tracker.take_pings()` for the ping sound, and
## `session.site.free_anchors(room)` for where enemies stand. Scripts and tests drive `aim_override`, `e_override`, `wasd_override`, and call step(dt).

const Boarding = preload("res://scripts/board/boarding.gd")
const Site = preload("res://scripts/board/site.gd")
const BoardLight = preload("res://scripts/board/board_light.gd")
const BoardHud = preload("res://scripts/board/board_hud.gd")
const Tracker = preload("res://scripts/board/tracker.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Art = preload("res://scripts/view/art.gd")
const Audio = preload("res://scripts/audio/audio.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Party = preload("res://scripts/board/party.gd")
const Themes = preload("res://scripts/board/themes.gd")
const BoardFx = preload("res://scripts/board/board_fx.gd")
const Bolts = preload("res://scripts/board/bolts.gd")
const Kit = preload("res://scripts/board/kit.gd")
const Mods = preload("res://scripts/board/mods.gd")
const Air = preload("res://scripts/board/air.gd")

## Emitted when the soldier is back on the ship: Boarding.leave()'s result {cleared, said, name, kind, poi}.
signal finished(result: Dictionary)
## B3: the soldier talked to someone, or stepped into a marked room: the map opens the event of `ctx` ({id (the person, -1 for a spot), name, node, event}) on its
## event panel and calls talk_done() when it is over. The world stands still meanwhile.
signal talk_requested(ctx: Dictionary)

const AFX_S := 0.7  ## seconds a gear effect lasts (_draw_active_fx)
const CELL := 32.0
const DARK := Color(0.022, 0.026, 0.04)
const ZOOM := 1.1
const DOWN_S := 2.8  ## seconds the screen fades after the soldier goes down, before he comes to at the airlock
const HOLLOW_FLICKER_S := 3.5
const ZOOM_MIN := 0.12
const ZOOM_MAX := 2.5
const AIM_DEAD_ZONE := 0.3  ## cells: with the mouse this close to the soldier, the aim stays where it was
const FLASH_RANGE := 12.0  ## cells the flashlight reaches
const SELF_RANGE := 3.4  ## cells the small light round the soldier reaches
const SPACE := Color("#04060a")  ## outside the hull
const RED_RANGE := 7.0
## [fill, edge] of each prop as drawn when its theme says nothing else (data/boarding.json themes.colors).
const PROP_COLORS := {"crate": ["#8a6a3e", "#3d2c16"], "locker": ["#4d5f78", "#1c2431"], "cabinet": ["#6b727d", "#23272e"], "pallet": ["#6a5a3a", "#2c2416"],
	"terminal": ["#2b3340", "#10151c"], "heap": ["#5a5a5e", "#1c1c20"], "files": ["#9aa0a8", "#2a2e36"], "crystal": ["#8fe0ff", "#2a5a7a"], "cask": ["#7a5a30", "#2a1c0c"],
	"trophy": ["#a08a50", "#3a2e14"]}
const GREEN_RANGE := 4.5
const STEP_CELLS := 1.4  ## cells walked between two footsteps
const PANEL_FAR := 1.6  ## cells beyond reach at which the loot list shuts by itself
const FEED_S := 5.0  ## seconds a line of what was taken stays
const MESSAGE_S := 3.2
const HOLD_RESET := 0.25  ## seconds E may be let go before the progress is lost

var active := false
var session  ## boarding.gd
var sim: Node
var build: Node
var crew: Node
var cam: Camera2D
var sector: Node
var starfield: Node
var front: Node
var tracker := Tracker.new()
var contacts_source := Callable()  ## B2: () -> [{pos (cells), moving}]
var lights_up := false  ## debug: the site lit as if by day (screenshots)
## Scripts and tests drive these instead of the keyboard and mouse.
var aim_override: Variant = null  ## a world point (px)
var e_override: Variant = null  ## whether E is held
var wasd_override: Variant = null  ## a Vector2
var fire_override: Variant = null  ## whether the trigger is held
var ask_party := true  ## on entering, offer to take unposted crew along (scripts and tests that want to start walking set it false)
var picking := false  ## the loadout screen (the crew picker, B4) is up: the world stands still
var pick: Array = []  ## the names picked so far
var load_who := 0  ## the person whose kit the loadout screen shows: 0 the soldier, then the crew picked, in the order picked
var load_slot := {}  ## the slot whose choices are listed: {slot ("weapon", "body" or "mod"), idx}; empty = none
var load_msg := ""  ## why the last choice was refused
var hollow_source := Callable()  ## () -> bool: has the Hollow taken this place (map_view.gd sets it; the visit notices when it does)
var fx: BoardFx  ## B4: the bolts, their lights, the impacts (board_fx.gd)
var light_on := true  ## F: the flashlight
var target := {}  ## what E would act on: {type ("airlock", "container", "door"), id, dist}
var hold := 0.0  ## seconds E has been held on the target
var panel := -1  ## the container whose loot list is open
var talking := false  ## an event panel is up over the dark (a talk or a discovery): the world stands still
var talk_ctx := {}  ## the talk in progress (talk_requested's ctx)
var shop := -1  ## the person whose goods are on the list
var message := ""
var feed: Array = []  ## [{text, t}] what was taken, newest last
var ship_view: ShipView
var hud: Control

var _fake: Ship
var _over: Node2D
var _lights: Node2D
var _mod: CanvasModulate
var _flash: PointLight2D
var _muzzle: PointLight2D
var _muzzle_t := 0.0
var _muzzle_at := Vector2.ZERO
var _later: Array = []  # [{t, e}] events that happen when the bolt arrives (a hit, a flare lighting)
var _shake := 0.0  # px of screen shake left (a heavy weapon)
var _shake_rng := RandomNumberGenerator.new()
var _cam_lights := {}  # room id -> the PointLight2D of the Spotter Cam's feed
var _cam_energy := {}  # room id -> the energy it shows now (it fades in and out)
var _down_t := 0.0
var _go_t := -1.0  # seconds the Leave button's fade has run (-1: not leaving)
var _ask_leave := false  # "Leave <name> behind?" stands: Enter confirms, Esc cancels
var _leave_t := 0.0  # seconds a "leave them behind?" question stands
var _skitter := 0.0
var _fight_t := 0.0  # seconds the combat music runs on after the last foe on the hunt
var _fire_wait := false  # a click that picked or took something is not a shot: the trigger waits until the button is let go
var _mood := "explore"
var _afx: Array = []  # [{id, pos (cells), dir, t}] what the gear actives and a deflect look like for a moment (_draw_active_fx)
var _flicker := 0.0  # seconds of flickering lights left (the Hollow arrives)
var _self_light: PointLight2D
var _red: Array = []  # [[light, base energy, phase]]
var _door_occ := {}  # door id -> LightOccluder2D
var _layer: CanvasLayer
var _saved_cam := {}
var _clock := 0.0
var _e_prev := false
var _hold_gap := 0.0
var _hold_key := ""
var _msg_t := -100.0
var _walked := 0.0
var _anim := {}
var _aim := 0.0
var _saved_clear := Color(0.3, 0.3, 0.3)
var _follow := true  # the camera follows the soldier (frame_all lets go)


func _ready() -> void:
	sim = get_node_or_null("../ShipSim")
	build = get_node_or_null("../BuildMode")
	crew = get_node_or_null("../Crew")
	cam = get_node_or_null("../Camera2D")
	sector = get_node_or_null("../Sector")
	starfield = get_node_or_null("../Space/Starfield")
	front = get_node_or_null("../FrontDoor")


func _process(dt: float) -> void:
	if active:
		step(minf(dt, 0.1))


# --- entering and leaving ---------------------------------------------------------------------------------------

## Go aboard: `p_session` is a Boarding visit. "" when the soldier is on the site, else why not.
func enter(p_session) -> String:
	if active:
		return "already aboard"
	if p_session == null or not p_session.site.ok:
		return "no such vessel"
	if p_session.soldier.is_down():
		return "the soldier is down"
	session = p_session
	active = true
	_clock = 0.0
	hold = 0.0
	panel = -1
	talking = false
	talk_ctx = {}
	shop = -1
	target = {}
	message = ""
	feed.clear()
	tracker = Tracker.new()
	_later.clear()
	_shake = 0.0
	_shake_rng.seed = 91
	load_who = 0
	load_slot = {}
	load_msg = ""
	light_on = true
	_down_t = 0.0
	_flicker = 0.0
	_leave_t = 0.0
	_go_t = -1.0
	_ask_leave = false
	_fight_t = 0.0
	_mood = "explore"
	_anim = {}
	_afx = []
	_walked = 0.0
	_put_away(true)
	_build_nodes()
	_follow = true
	_saved_clear = RenderingServer.get_default_clear_color()
	RenderingServer.set_default_clear_color(SPACE)
	var at: Vector2 = session.soldier.pos * CELL
	if cam != null:
		_saved_cam = {"pos": cam.position, "zoom": cam.zoom, "offset": cam.offset}
		cam.offset = Vector2.ZERO
		cam.zoom = Vector2(ZOOM, ZOOM)
		cam.position = at
	Audio.mood(self, "explore")
	Audio.muffle_music(self, true)
	Audio.fx(self, "arrive", null, -6.0)
	say("Airlock sealed. %s." % session.site.site_name)
	pick = []
	picking = ask_party and _loadout_wanted()
	if picking:
		_open_loadout()
	return ""


## The soldier is back on the ship. Emits `finished`.
func leave() -> void:
	if not active:
		return
	var result: Dictionary = session.leave()
	Audio.fx_loop(self, "hack", "repair_loop", false)
	Audio.fx_loop(self, "flare", "flare_burn", false)
	Audio.mood(self, "explore")
	Audio.muffle_music(self, false)
	RenderingServer.set_default_clear_color(_saved_clear)
	_free_nodes()
	if cam != null and not _saved_cam.is_empty():
		cam.position = _saved_cam["pos"]
		cam.zoom = _saved_cam["zoom"]
		cam.offset = _saved_cam["offset"]
	_put_away(false)
	active = false
	session = null
	Audio.fx(self, "close")
	finished.emit(result)


## The Leave button (L): the party goes home after a short fade, as if they had walked out. Not while a foe hunts them; a crewman who is down is lost, so that
## asks first (`_ask_leave`; Enter confirms, Esc cancels). Returns "" when it began (or asked), else why not.
func quick_leave() -> String:
	if not active or picking or _go_t >= 0.0 or session.downed:
		return "busy"
	if not session.can_quick_leave():
		var why := str(Arms.cfg()["leave_hunted"])
		say(why + ".")
		Audio.fx(self, "error")
		return why
	var down: Array = session.downed_party()
	if not down.is_empty() and not _ask_leave:
		_ask_leave = true
		return ""
	_ask_leave = false
	_go_t = 0.0
	return ""


## The question's text: who is left behind and what goes with them.
func leave_question() -> String:
	var down: Array = session.downed_party()
	return "Leave %s behind? (lost for good%s)     Enter: leave     Esc: stay" % [", ".join(down), lost_note(down)]


## The ship's views make way (or come back). BuildMode.combat does most of it: no input, no drawing, no HUD; the ship's sim is held and
## the sector, its debris and the sky stand still.
func _put_away(away: bool) -> void:
	if build != null:
		build.combat = away
		build.visible = not away
		build.save_block = "Can't save aboard another vessel." if away else ""
	if away and sim != null and sim.has_method("set_paused"):
		sim.set_paused(true, "boarding")  # (build.combat, just set, had let the sim run for a fight)
	if crew != null:
		crew.visible = not away
		crew.set_process(not away)
	if starfield != null:
		starfield.visible = not away
	if sector != null:
		sector.set("boarding", away)


func _build_nodes() -> void:
	var site = session.site
	_fake = site.ship if site.ship != null else Ship.new("Site", site.grid)  # (a beaten ship is drawn as she is: her parts, her holes)
	ship_view = ShipView.new()
	add_child(ship_view)
	ship_view.show_ship(_fake)
	ship_view.pivot = Vector2.ZERO
	_over = Node2D.new()
	_over.z_index = 1
	_over.draw.connect(_draw_over)
	add_child(_over)
	_lights = Node2D.new()
	add_child(_lights)
	_mod = CanvasModulate.new()
	_mod.color = Color.WHITE if lights_up else DARK
	add_child(_mod)
	for r in BoardLight.occluder_rects(site.grid):
		_occluder(r)
	for d in site.doors:
		if d["lock"] != "gone":
			_door_occ[d["id"]] = _occluder(BoardLight.door_rect(d["cells"]))
	_flash = _light(BoardLight.cone_texture(), FLASH_RANGE, Color(1.0, 0.97, 0.88), 1.1, true, BoardLight.cone_texture().get_width() / 2.0)
	_self_light = _light(BoardLight.round_texture(), SELF_RANGE, Color(0.85, 0.9, 1.0), 0.55, false, 64.0)
	_muzzle = _light(BoardLight.round_texture(), 7.0, Color(1.0, 0.82, 0.5), 1.5, true, 64.0)
	_muzzle.visible = false
	_red.clear()
	for l in site.lights:
		var red: bool = l["color"] == "red"
		var node := _light(BoardLight.round_texture(), RED_RANGE if red else GREEN_RANGE, Color(1.0, 0.14, 0.08) if red else Color(0.2, 1.0, 0.45), 0.5 if red else 0.6, red, 64.0)
		node.position = l["pos"] * CELL
		_red.append([node, node.energy, float(hash(l["pos"]) % 628) / 100.0, red])
	_layer = CanvasLayer.new()
	_layer.layer = 3
	fx = BoardFx.new()
	fx.view = self
	fx.lights_root = _lights
	_layer.add_child(fx)
	hud = BoardHud.new()
	hud.view = self
	_layer.add_child(hud)
	add_child(_layer)
	_apply_lights_up()


func _light(tex: Texture2D, range_cells: float, colour: Color, energy: float, shadows: bool, half_px: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = tex
	l.texture_scale = range_cells * CELL / half_px
	l.color = colour
	l.energy = energy
	l.shadow_enabled = shadows
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.shadow_filter_smooth = 1.5
	_lights.add_child(l)
	return l


func _occluder(r: Rect2) -> LightOccluder2D:
	var o := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([r.position * CELL, Vector2(r.end.x, r.position.y) * CELL, r.end * CELL, Vector2(r.position.x, r.end.y) * CELL])
	o.occluder = poly
	_lights.add_child(o)
	return o


func _free_nodes() -> void:
	for n in [ship_view, _over, _lights, _mod, _layer]:
		if n != null:
			if n.is_inside_tree():
				n.queue_free()
			else:
				n.free()  # (a script or a test that has no scene)
	ship_view = null
	_over = null
	_lights = null
	_mod = null
	_layer = null
	hud = null
	fx = null
	_cam_lights.clear()
	_cam_energy.clear()
	_flash = null
	_muzzle = null
	_self_light = null
	_red.clear()
	_door_occ.clear()
	_fake = null


## Debug: light the whole site (the full layout in a screenshot) or put the dark back.
func set_lights_up(on: bool) -> void:
	lights_up = on
	_apply_lights_up()


func _apply_lights_up() -> void:
	if _mod != null:
		_mod.color = Color.WHITE if lights_up else DARK


## Zoom and centre the camera so the whole site is on screen.
func frame_all() -> void:
	if cam == null or session == null:
		return
	var b: Rect2i = session.site.bounds
	var size := get_viewport_rect().size if is_inside_tree() else Vector2(1600, 900)
	var z := minf(size.x / (float(b.size.x + 4) * CELL), size.y / (float(b.size.y + 4) * CELL))
	cam.zoom = Vector2(z, z)
	cam.position = (Vector2(b.position) + Vector2(b.size) / 2.0) * CELL
	_follow = false  # (it follows the soldier again when he walks)


# --- the frame ----------------------------------------------------------------------------------------------------

## One tick of `dt` seconds.
func step(dt: float) -> void:
	if not active or session == null:
		return
	_clock += dt
	var s = session
	var m = s.soldier
	if picking or talking:  # the crew picker or a talk is up: he stands still, the dark waits
		_aim_at(dt)
		_update_lights(dt)
		if hud != null:
			hud.queue_redraw()
		return
	var before: Vector2 = m.pos
	if not s.downed:
		m.move_input(s.site.walk, _wasd(), dt, s.soldier_passable())
	if m.pos != before and not _follow:
		_follow = true
	for e in _afx:
		e["t"] = float(e["t"]) + dt
	_afx = _afx.filter(func(e): return float(e["t"]) < AFX_S)
	_walked += m.pos.distance_to(before)
	if _walked >= STEP_CELLS:
		_walked = 0.0
		Audio.fx(self, "footstep", null, -4.0)
	_aim_at(dt)
	_interact(dt)
	if not active:
		return  # (E at the airlock left)
	_combat(dt)
	_update_lights(dt)
	if fx != null:
		fx.step(dt)
	_shake_cam(dt)
	_flare_sound()
	var contacts: Array = contacts_source.call() if contacts_source.is_valid() else s.contacts()
	tracker.tick(dt, m.pos, contacts)
	tracker.take_pings()
	for far in tracker.last_heard:  # the nearer it is, the higher and faster the beep
		Audio.fx(self, "tracker_ping_near" if far < 0.25 else ("tracker_ping_mid" if far < 0.6 else "tracker_ping_far"), null, -4.0)
	feed = feed.filter(func(f): return _clock - float(f["t"]) < FEED_S)
	if cam != null and _follow:
		cam.position = cam.position.lerp(m.pos * CELL, 1.0 - exp(-dt * 9.0))
	if _over != null:
		_over.queue_redraw()
	if hud != null:
		hud.queue_redraw()


func _wasd() -> Vector2:
	if wasd_override != null:
		return wasd_override
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		return Vector2.ZERO
	return Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))


func _e_down() -> bool:
	if e_override != null:
		return bool(e_override)
	return Input.is_key_pressed(KEY_E) and not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_META)


func _mouse_world() -> Variant:
	if aim_override != null:
		return aim_override
	return get_global_mouse_position() if is_inside_tree() else null


func _aim_at(dt: float) -> void:
	var at: Variant = _mouse_world()
	if at != null:
		var d: Vector2 = at - session.soldier.pos * CELL
		if d.length() > AIM_DEAD_ZONE * CELL:
			_aim = d.angle()
	var a: Dictionary = _anim.get(session.soldier, PersonDrawer.new_state(session.soldier))
	PersonDrawer.animate(a, session.soldier, dt, _aim)
	_anim[session.soldier] = a


func _update_lights(dt: float) -> void:
	if _flash == null:
		return
	var at: Vector2 = session.soldier.pos * CELL
	_flash.position = at
	_flash.rotation = _aim
	_self_light.position = at
	_flicker = maxf(_flicker - dt, 0.0)
	var fk := 1.0 - 0.75 * clampf(_flicker / 0.6, 0.0, 1.0) * (0.5 + 0.5 * sin(_clock * 43.0) * sin(_clock * 19.0)) if _flicker > 0.0 else 1.0
	_flash.energy = 1.1 * fk
	_self_light.energy = 0.55 * fk
	_flash.visible = not lights_up and light_on
	_self_light.visible = not lights_up
	_muzzle_t = maxf(_muzzle_t - dt, 0.0)
	_muzzle.visible = _muzzle_t > 0.0 and not lights_up
	_muzzle.position = _muzzle_at * CELL
	_muzzle.energy = 1.5 * _muzzle_t / float(Arms.cfg()["flash_s"])
	_update_feed(dt)
	for e in _red:
		var flicker: float = 1.0 + 0.12 * sin(_clock * 2.3 + float(e[2])) + (0.0 if not e[3] else 0.06 * sin(_clock * 11.0 + float(e[2]) * 3.0))
		e[0].energy = float(e[1]) * flicker * fk
		e[0].visible = not lights_up


## The Spotter Cam's feed (mods.gd): a flat light over each room it shows, a cool grey-green, that fades in and out as the soldier moves. A feed is not a lamp:
## nothing in the logic sees it (foes.gd reads the flashlight, the emergency lights and the flares only).
func _update_feed(dt: float) -> void:
	if session == null or _lights == null:
		return
	var tier := Mods.party_tier(session, "spotter_cam")
	var want := {}
	if tier > 0 and not lights_up:
		for rid in session.spotted:
			want[rid] = float(Mods.numbers("spotter_cam", tier)["glow"])
	for rid in want:
		if not _cam_lights.has(rid):
			_cam_lights[rid] = _feed_light(int(rid))
			_cam_energy[rid] = 0.0
	for rid in _cam_lights.keys():
		var target := float(want.get(rid, 0.0))
		_cam_energy[rid] = move_toward(float(_cam_energy[rid]), target, dt * 1.6)
		var l: PointLight2D = _cam_lights[rid]
		l.energy = float(_cam_energy[rid])
		l.visible = float(_cam_energy[rid]) > 0.001
		if target == 0.0 and float(_cam_energy[rid]) <= 0.001:
			l.queue_free() if l.is_inside_tree() else l.free()
			_cam_lights.erase(rid)
			_cam_energy.erase(rid)


## A light as wide as room `rid` and its walls (a texture with 8 px to a cell, drawn 4 times as big).
func _feed_light(rid: int) -> PointLight2D:
	var r: Rect2i = session.site.rooms[rid]["rect"]
	var w := (r.size.x + 2) * 8
	var h := (r.size.y + 2) * 8
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for x in w:
		img.set_pixel(x, 0, Color(0.55, 0.55, 0.55))
		img.set_pixel(x, h - 1, Color(0.55, 0.55, 0.55))
	for y in h:
		img.set_pixel(0, y, Color(0.55, 0.55, 0.55))
		img.set_pixel(w - 1, y, Color(0.55, 0.55, 0.55))
	var l := PointLight2D.new()
	l.texture = ImageTexture.create_from_image(img)
	l.texture_scale = CELL / 8.0
	l.color = Mods.color("spotter_cam").lerp(Color(0.62, 0.78, 0.74), 0.6)
	l.energy = 0.0
	l.visible = false
	l.shadow_enabled = false
	l.position = (Vector2(r.position) + Vector2(r.size) / 2.0) * CELL
	_lights.add_child(l)
	return l


# --- fighting -------------------------------------------------------------------------------------------------------

func _fire_down() -> bool:
	if fire_override != null:
		return bool(fire_override)
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and is_inside_tree()


## The weapons, the shots and what they sound like: the trigger while no list or picker is up, then everything the session says happened.
func _combat(dt: float) -> void:
	var s = session
	_leave_t = maxf(_leave_t - dt, 0.0)
	var fighting: bool = s.foes.live().any(func(f): return str(f["mode"]) in ["hunt", "attack", "cover", "flee", "stalk"] or float(f["track"]) > 0.0)
	_fight_t = 6.0 if fighting else maxf(_fight_t - dt, 0.0)
	var want := "combat" if _fight_t > 0.0 else ("hollow" if s.hollow else "explore")
	if want != _mood:
		_mood = want
		Audio.mood(self, want)
	if _go_t >= 0.0:
		_go_t += dt
		if s.downed:
			_go_t = -1.0
		elif _go_t >= float(Arms.cfg()["leave_fade_s"]):
			leave()
			return
	if s.downed:
		_down_t += dt
		if _down_t >= DOWN_S:
			leave()
			return
	if not s.downed:
		s.note_hollow(hollow_source.call() if hollow_source.is_valid() else false)
	s.tick(dt, _aim, light_on)
	if _fire_wait and not _fire_down():
		_fire_wait = false
	if _fire_down() and panel < 0 and shop < 0 and not s.downed and not _fire_wait and not picking:
		s.fire(_aim)
	for p in s.party:
		var pa: Dictionary = _anim.get(p["m"], PersonDrawer.new_state(p["m"]))
		PersonDrawer.animate(pa, p["m"], dt, p["m"].facing.angle())
		_anim[p["m"]] = pa
	for n in s.people.list:
		if n["state"] in ["here", "leaving"]:
			var na: Dictionary = _anim.get(n["m"], PersonDrawer.new_state(n["m"]))
			PersonDrawer.animate(na, n["m"], dt, n["m"].facing.angle())
			_anim[n["m"]] = na
	for f in s.foes.list:
		if f["kind"] != "sentry" and f["kind"] != "crawler":
			var a: Dictionary = _anim.get(f["m"], PersonDrawer.new_state(f["m"]))
			PersonDrawer.animate(a, f["m"], dt, f["m"].facing.angle())
			_anim[f["m"]] = a
	_skitter -= dt
	if _skitter <= 0.0:
		for f in s.foes.list:
			if f["kind"] == "crawler" and f["moved"] and not f["hidden"] and not f["dead"]:
				Audio.fx(self, "crawler_skitter", f["m"].pos * CELL, -6.0)
				_skitter = 0.45
	var due := []  # what happens when a bolt arrives: the hit, the flare lighting
	for q in _later:
		q["t"] = float(q["t"]) - dt
		if float(q["t"]) <= 0.0:
			due.append(q["e"])
	_later = _later.filter(func(q): return float(q["t"]) > 0.0)
	for e in due:
		_play_one(e)
	_play(s.take_events())


## Draw and sound the events of a tick. One with a `delay` (a hit, a flare lighting) waits for its bolt to arrive.
func _play(evs: Array) -> void:
	for e in evs:
		if float(e.get("delay", 0.0)) > 0.0:
			_later.append({"t": float(e["delay"]), "e": e})
		else:
			_play_one(e)


func _play_one(e: Dictionary) -> void:
	var at: Vector2 = e.get("pos", e.get("from", Vector2.ZERO))
	var px := at * CELL
	match str(e["type"]):
		"shot":
			var look: Dictionary = e.get("look", Bolts.look(str(e.get("weapon", ""))))
			if fx != null:
				fx.shot(look, e["from"], e["to"], float(e.get("t", 0.0)), str(e["kind"]))
			if e["who"] == "soldier":
				_muzzle_t = float(Arms.cfg()["flash_s"])
				_muzzle_at = e["from"]
				if _muzzle != null:
					_muzzle.color = Color(str(look["color"]))
				_shake = maxf(_shake, float(look.get("shake", 0.0)))
			var snd := str(look.get("sound", ""))
			Audio.fx(self, snd if snd != "" else "shot_" + str(e["class"]), px, 0.0 if e["who"] == "soldier" else -2.0)
			if str(e["kind"]) in ["wall", "prop"] and str(look.get("impact", "spark")) != "none":  # the bolt biting in, when it gets there
				Audio.fx(self, "bolt_sizzle", e["to"] * CELL, -2.0, float(e.get("t", 0.0)))
		"swing":
			if fx != null:
				fx.swing(e["from"], float(e["dir"]), float(e["reach"]), Color(str(e.get("look", {}).get("color", "#ffffff"))))
			Audio.fx(self, "melee_swing", px)
		"active":
			_afx.append({"id": str(e["id"]), "pos": at, "dir": float(e.get("dir", 0.0)), "t": 0.0})
			Audio.fx(self, "arrive", px, -6.0)
		"deflect":
			_afx.append({"id": "deflect", "pos": at, "dir": 0.0, "t": 0.0})
			Audio.fx(self, "bolt_sizzle", px, -4.0)
		"flare":
			if fx != null:
				fx.flare(int(e["id"]), at)
		"flare_out":
			if fx != null:
				fx.flare_out(int(e["id"]))
		"click":
			Audio.fx(self, "empty_click", px)
			say("Empty. R reloads.")
		"reload":
			Audio.fx(self, "reload", px)
		"swap":
			Audio.fx(self, "reload", px, -8.0)
		"door":
			if _door_occ.has(e["id"]):
				_door_occ[e["id"]].visible = not bool(e["open"])
			if ship_view != null:
				ship_view.queue_redraw()
			if session.soldier.pos.distance_to(at) <= 12.0:
				Audio.fx(self, "door_open" if e["open"] else "door_close", null, -6.0)
		"hit":
			_hit_flash(e)
			Audio.fx(self, "foe_hit", px)
		"down":
			_hit_flash(e)
			Audio.fx(self, "foe_down", px)
		"hurt":
			_hit_flash(e)
			Audio.fx(self, "crew_hurt", px)
		"melee":
			Audio.fx(self, "melee_swing", px)
		"line":
			_toast(str(e["text"]))
		"whir":
			Audio.fx(self, "sentry_whir", px)
		"screech":
			Audio.fx(self, "crawler_screech", px)
		"emerge", "vanish":
			Audio.fx(self, "crawler_skitter", px)
		"hacked":
			Audio.fx(self, "unlock")
			say("Sentry hacked. It is yours now.")
		"hollow":
			_flicker = HOLLOW_FLICKER_S
			_toast(str(Arms.cfg()["hollow"]["toast"]))
			Audio.fx(self, "tide_warning")
		"downed":
			Audio.fx(self, "crew_hurt", px)
		"discover":
			_start_talk(session.discover(int(e["mark"])))


## A body was hit by a bolt: a flash in the bolt's colour where it landed.
func _hit_flash(e: Dictionary) -> void:
	if fx != null and e.has("tint"):
		fx.hit_flash(e["pos"], Color(str(e["tint"])))


## A little shake of the screen while a heavy weapon's kick lasts.
func _shake_cam(dt: float) -> void:
	if cam == null:
		return
	if _shake > 0.0:
		cam.offset = Vector2(_shake_rng.randf_range(-1.0, 1.0), _shake_rng.randf_range(-1.0, 1.0)) * _shake
		_shake = maxf(_shake - dt * 40.0, 0.0)
	elif cam.offset != Vector2.ZERO:
		cam.offset = Vector2.ZERO


## The flare's burn: a hiss where it lies while one burns.
func _flare_sound() -> void:
	var where = fx.a_flare() if fx != null else null
	Audio.fx_loop(self, "flare", "flare_burn", where != null, 0.9, 1.0, where * CELL if where != null else null)


## Does the music turn to its fight layer (a foe has noticed someone and is on the hunt, or did within the last few seconds)? The muffle stays on.
func fight_music() -> bool:
	return active and _fight_t > 0.0


## The crew who can be taken along, [{name, species, hp, max_hp}].
func pick_rows() -> Array:
	return Party.eligible(session.ship).map(func(m): return {"name": m.name, "species": m.species, "hp": m.hp, "max_hp": m.max_hp, "gear": _gear_text(m), "rounds": _rounds_if_aboard(m), "no_suit": Site.config().has("gear") and not Air.sealed(m)})


## What a crew member of the picker carries, in a few words: their weapons and body gear ("Service Pistol, Carbine, Basic Armour"), the sidearm when it is all.
func _gear_text(m) -> String:
	var names := []
	for w in Kit.weapons_of(m):
		names.append(str(Arms.weapon(str(w)).get("name", w)))
	if str(m.kit.get("body", "")) != "":
		names.append(session.ship.crafting.name_of(str(m.kit["body"]), session.ship.components))
	return ", ".join(names)


## The rounds a follower would come aboard with (a copy of the spare rounds, at least the floor), -1 for a weapon with no magazine.
func _rounds_if_aboard(m) -> int:
	var w := Arms.weapon(str(Kit.weapons_of(m)[0]))
	return maxi(session.reserve(), int(Arms.cfg()["follower_ammo_min"])) if not w.is_empty() and int(w["mag"]) > 0 else -1


## Pick or drop the `i`th crew member of the picker (at most party_max).
func toggle_pick(i: int) -> void:
	var rows := pick_rows()
	if i < 0 or i >= rows.size():
		return
	var name: String = rows[i]["name"]
	if pick.has(name):
		pick.erase(name)
	elif pick.size() < int(Arms.cfg()["party_max"]):
		pick.append(name)
	else:
		Audio.fx(self, "error")
	load_who = mini(load_who, loadout_people().size() - 1)
	load_slot = {}
	load_msg = ""


## Go aboard with nobody: the picked crew stay behind.
func go_alone() -> void:
	pick.clear()
	confirm_party()


## Go aboard with the crew picked (none is allowed) and the kits set on the loadout screen.
func confirm_party() -> void:
	if not picking:
		return
	var src = _src_soldier()
	if session.needs_suit() and not Air.sealed(src if src != null else session.soldier):  # her air is gone: he goes aboard in a sealed suit or not at all
		load_msg = Air.NO_SUIT_BOARD
		Audio.fx(self, "error")
		return
	picking = false
	if src != null:
		session.rearm(src)  # (his kit may have changed)
	var n: int = session.join_party(pick)
	_e_prev = true  # (a key still down does not count as a press)
	say("%d crew with you." % n if n > 0 else "Alone.")


# --- the loadout screen (B4) ----------------------------------------------------------------------------------------------

## The ship's own soldier (the crew member whose kit the screen sets; the visit walks a copy of him), null when the ship has none.
func _src_soldier():
	if session.ship != null:
		for m in session.ship.crew:
			if m.is_player:
				return m
	return null


## Does the boarding party screen open first? Always, for every kind of site: the party picker (with "Go alone") is how you choose who goes in. Only a visit with
## no ship behind it (a test) has none.
func _loadout_wanted() -> bool:
	return session.ship != null


## The screen opens: whoever has no kit yet is given the one they would have had (the soldier takes a spare hand weapon of the hold).
func _open_loadout() -> void:
	var src = _src_soldier()
	if src != null:
		Kit.materialize(session.ship, src, true)
	for m in Party.eligible(session.ship):
		Kit.materialize(session.ship, m)


## The people the screen sets, as the ship's own crew members: the soldier, then the crew picked in the order picked.
func loadout_people() -> Array:
	var out := []
	var src = _src_soldier()
	if src != null:
		out.append(src)
	var elig := Party.eligible(session.ship)
	for n in pick:
		for m in elig:
			if m.name == n:
				out.append(m)
	return out


## The note after "WEAPONS" on the loadout screen.
func weapons_note() -> String:
	return "Q swaps in the field." if load_who == 0 else "A crew mate fights with the first."


## Show person `i` (0 is the soldier).
func loadout_focus(i: int) -> void:
	load_who = clampi(i, 0, maxi(loadout_people().size() - 1, 0))
	load_slot = {}
	load_msg = ""


## Open the choices of a slot ("weapon", "body" or "mod", number `idx`); the same slot again shuts them.
func loadout_open(slot: String, idx: int) -> void:
	load_msg = ""
	if load_slot.get("slot", "") == slot and int(load_slot.get("idx", -1)) == idx:
		load_slot = {}
	else:
		load_slot = {"slot": slot, "idx": idx}


## The choices of the open slot (kit.gd options).
func loadout_options() -> Array:
	var people := loadout_people()
	if load_slot.is_empty() or load_who >= people.size():
		return []
	return Kit.options(session.ship, people[load_who], str(load_slot["slot"]), int(load_slot["idx"]))


## Take choice `i` of the open slot. Returns why not ("" when done); the reason is also kept in load_msg.
func loadout_choose(i: int) -> String:
	var opts := loadout_options()
	if i < 0 or i >= opts.size():
		return ""
	var o: Dictionary = opts[i]
	var m = loadout_people()[load_who]
	var why := ""
	match str(load_slot["slot"]):
		"weapon":
			why = Kit.set_weapon(session.ship, m, int(load_slot["idx"]), str(o["id"]))
		"body":
			why = Kit.set_body(session.ship, m, str(o["id"]))
		"mod":
			why = Kit.set_mod(session.ship, m, int(load_slot["idx"]), str(o["id"]))
	load_msg = why
	if why != "":
		Audio.fx(self, "error")
		return why
	load_slot = {}
	Audio.fx(self, "confirm")
	return ""


## F: the flashlight on or off.
func toggle_light() -> void:
	light_on = not light_on
	Audio.fx(self, "flashlight_click")
	_update_lights(0.0)


# --- interacting ----------------------------------------------------------------------------------------------------

## What E would act on now: the nearest of the hatch (in the airlock), a container within reach, a locked door.
func find_target() -> Dictionary:
	var s = session
	var p: Vector2 = s.soldier.pos
	if s.downed:
		return {}
	var reach := float(Site.config()["reach"])
	var best := {}
	var best_d := INF
	if s.at_airlock():
		best = {"type": "airlock", "id": 0, "dist": s.site.hatch_centre().distance_to(p)}
		best_d = float(best["dist"]) - 1.5  # (the airlock wins unless something else is right beside you)
	var skip := {}
	for id in s.opened:
		if not s.left.has(id):
			skip[id] = true
	var cid: int = s.site.nearest_container(p, reach, skip)
	if cid >= 0:
		var d: float = s.site.centre_of(s.site.props[cid]).distance_to(p)
		if d < best_d:
			best = {"type": "container", "id": cid, "dist": d}
			best_d = d
	var pid: int = s.people.nearest(p, float(Site.config()["people"]["talk_reach"]))
	if pid >= 0:  # a person comes before a crate, a door or the hatch
		best = {"type": "npc", "id": pid, "dist": s.people.find(pid)["m"].pos.distance_to(p)}
		best_d = -1.0
	var rev := -1
	var rev_d := INF
	for i in s.party.size():
		var d3: float = s.party[i]["m"].pos.distance_to(p)
		if s.party[i]["m"].is_down() and d3 <= float(Arms.cfg()["revive_reach"]) and d3 < rev_d:
			rev = i
			rev_d = d3
	if rev >= 0:  # a friend on the floor comes before a crate, a door or the hatch
		best = {"type": "revive", "id": rev, "dist": rev_d}
		best_d = -1.0
	var sentry = s.foes.hackable(p)
	if sentry != null:
		var d4: float = sentry["m"].pos.distance_to(p)
		if d4 < best_d:
			best = {"type": "sentry", "id": sentry["id"], "dist": d4}
			best_d = d4
	var did: int = s.site.nearest_locked_door(p, reach, s.unlocked)
	if did >= 0:
		var d2: float = s.site.door_centre(s.site.doors[did]).distance_to(p)
		if d2 < best_d:
			best = {"type": "door", "id": did, "dist": d2}
			best_d = d2
	return best


func _hold_need(t: Dictionary) -> float:
	match str(t.get("type", "")):
		"container":
			if session.opened.has(t["id"]):
				return 0.0
			return float(Site.config()["props"][session.site.props[t["id"]]["prop"]]["hold"])
		"door":
			return session.hack_time() if session.site.doors[t["id"]]["lock"] == "hack" else 0.0
		"revive":
			return session.revive_time()
		"sentry":
			return float(Arms.cfg()["hack_sentry_s"])
	return 0.0


func _interact(dt: float) -> void:
	var down := _e_down()
	var pressed := down and not _e_prev
	_e_prev = down
	var s = session
	if panel >= 0:
		var far: float = s.site.centre_of(s.site.props[panel]).distance_to(s.soldier.pos)
		if far > float(Site.config()["reach"]) + PANEL_FAR:
			close_panel()
	if shop >= 0:
		var seller: Dictionary = s.people.find(shop)
		if seller.is_empty() or seller["m"].pos.distance_to(s.soldier.pos) > float(Site.config()["people"]["talk_reach"]) + PANEL_FAR:
			close_shop()
	var t := find_target()
	var key := "%s:%s" % [t.get("type", ""), t.get("id", "")]
	if key != _hold_key:
		_hold_key = key
		hold = 0.0
	target = t
	var need := _hold_need(t)
	var hacking := false
	if down and need > 0.0 and panel < 0 and shop < 0:
		_hold_gap = 0.0
		hold += dt
		hacking = str(t.get("type", "")) in ["door", "sentry"]
		if hold >= need:
			hold = 0.0
			_finish_hold(t)
	else:
		_hold_gap += dt
		if _hold_gap > HOLD_RESET:
			hold = 0.0
	Audio.fx_loop(self, "hack", "repair_loop", hacking and hold > 0.0, 0.8)
	if pressed:
		press_e()


## A tap of E: take everything in the open list; else act on the target (leave at the airlock, open an opened container again, use a keycard).
func press_e() -> void:
	if not active:
		return
	var s = session
	if panel >= 0:
		take_from_panel("all")
		return
	if shop >= 0:
		return
	match str(target.get("type", "")):
		"npc":
			_start_talk(s.talk(int(target["id"])))
		"airlock":
			var down: Array = s.downed_party()
			if not down.is_empty() and _leave_t <= 0.0:  # crew left down are lost: ask first
				_leave_t = float(Arms.cfg()["leave_confirm_s"])
				say("%s is down. Leaving now loses them%s. E again to go, Esc to stay." % [", ".join(down), lost_note(down)])
				Audio.fx(self, "error")
				return
			leave()
		"revive", "sentry":
			say("Hold E.")
		"container":
			if s.opened.has(target["id"]) and s.left.has(target["id"]):
				open_panel(target["id"])
		"door":
			var d: Dictionary = s.site.doors[target["id"]]
			if d["lock"] == "card":
				var why: String = s.unlock(target["id"])
				if why != "":
					say(why)
					Audio.fx(self, "error")
				else:
					say("The %s keycard opens it." % str(d["card"]))
					Audio.fx(self, "unlock")
			elif d["lock"] == "hack":
				say("Hold E to hack the lock.")


## " and their kit (Carbine; Basic Armour)" when the crew who would be left behind carry anything, else "".
func lost_note(names: Array) -> String:
	var parts := []
	for n in names:
		var k: String = session.lost_kit(str(n))
		if k != "":
			parts.append(k)
	return " and their kit (%s)" % "; ".join(parts) if not parts.is_empty() else ""


func _finish_hold(t: Dictionary) -> void:
	var s = session
	if str(t.get("type", "")) == "container":
		s.open(t["id"])
		Audio.fx(self, "open")
		open_panel(t["id"])
	elif str(t.get("type", "")) == "door":
		s.unlock(t["id"], true)
		say("Lock hacked.")
		Audio.fx(self, "unlock")
	elif str(t.get("type", "")) == "revive":
		var who = s.party[t["id"]]["m"]
		s.revive_member(who)
		say("%s is up." % who.name)
		Audio.fx(self, "collect")
	elif str(t.get("type", "")) == "sentry":
		s.foes.hack(s.foes.find(t["id"]))


## Begin a talk: `ctx` is session.talk() or session.discover(). An event goes to the map's event panel (the world stands still until talk_done()); goods go on
## the list; a word is just said.
func _start_talk(ctx: Dictionary) -> void:
	if ctx.is_empty():
		return
	if ctx.has("say"):
		say(str(ctx["say"]))
		return
	if bool(ctx.get("shop", false)):
		open_shop(int(ctx["id"]))
		return
	if talk_requested.get_connections().is_empty():
		say("%s has nothing to say." % str(ctx.get("name", "Nobody")))
		return
	talking = true
	talk_ctx = ctx
	hold = 0.0
	_e_prev = true
	talk_requested.emit(ctx)


## The talk is over: what its outcomes asked for is carried out by the session, and the world goes on.
func talk_done(ops: Array, acted: bool) -> void:
	if not active or session == null:
		return
	talking = false
	_fire_wait = true  # (the click that ended the talk is not a shot)
	_e_prev = true
	var id := int(talk_ctx.get("id", -1))
	talk_ctx = {}
	var r: Dictionary = session.finish_talk(id, ops, acted)
	for l in r["lines"]:
		feed.append({"text": str(l), "t": _clock})
		say(str(l))
	if int(r["shop"]) >= 0:
		open_shop(int(r["shop"]))


## Show the goods of person `id`.
func open_shop(id: int) -> void:
	shop = id
	panel = -1
	Audio.fx(self, "open")


func close_shop() -> void:
	shop = -1


## Buy row `i` (0 based) of the goods on the list.
func buy_row(i: int) -> void:
	if shop < 0:
		return
	var r: Dictionary = session.buy(shop, i)
	if bool(r["ok"]):
		feed.append({"text": str(r["text"]), "t": _clock})
		Audio.fx(self, "collect")
	elif str(r["text"]) != "":
		say(str(r["text"]))
		Audio.fx(self, "error")


## Show the loot list of container `id` (an opened one).
func open_panel(id: int) -> void:
	panel = id
	if session.entries(id).is_empty():
		say("Empty.")
		panel = -1


func close_panel() -> void:
	panel = -1


## Take `what` ("all" or an entry key) from the open list. The lines go to the feed; a blueprint and a log also get a toast.
func take_from_panel(what: String) -> void:
	if panel < 0:
		return
	var lines: Array = session.take(panel, what)
	for l in lines:
		feed.append({"text": str(l), "t": _clock})
		if str(l).begins_with("Blueprint") or str(l).begins_with("Log"):
			_toast(str(l))
	if not lines.is_empty():
		Audio.fx(self, "collect")
	if session.entries(panel).is_empty():
		panel = -1


## Take the `i`th row (0 based) of the open list.
func take_row(i: int) -> void:
	if panel < 0:
		return
	var rows: Array = session.entries(panel)
	if i >= 0 and i < rows.size():
		take_from_panel(str(rows[i]["key"]))


func say(text: String) -> void:
	message = text
	_msg_t = _clock


func message_alive() -> bool:
	return message != "" and _clock - _msg_t < MESSAGE_S


func _toast(text: String) -> void:
	var toast = front.get("toast") if front != null else null
	if toast != null:
		toast.push(text)


# --- input ------------------------------------------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if not active:
		return
	if e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / 1.1)
			MOUSE_BUTTON_LEFT:
				_fire_wait = picking or panel >= 0 or shop >= 0
				if hud != null and not picking and hud.leave_rect().has_point(e.position):
					_fire_wait = true
					quick_leave()
				elif _ask_leave:
					_fire_wait = true
				elif hud != null and shop >= 0:
					buy_row(hud.shop_row_at(e.position))
				elif hud != null and picking:
					_loadout_click(hud.loadout_at(e.position))
				elif hud != null and panel >= 0:
					var row: int = hud.row_at(e.position)
					if row >= 0:
						take_row(row)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.ctrl_pressed or e.meta_pressed:
			if e.keycode == KEY_S:
				say("Can't save aboard another vessel.")
				Audio.fx(self, "error")
			elif e.keycode == KEY_L:
				say("Can't load aboard another vessel.")
				Audio.fx(self, "error")
		elif _ask_leave:
			if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER:
				quick_leave()
			elif e.keycode == KEY_ESCAPE:
				_ask_leave = false
				say("You stay.")
		elif picking:
			if not load_slot.is_empty() and e.keycode >= KEY_1 and e.keycode <= KEY_9:
				loadout_choose(e.keycode - KEY_1)
			elif e.keycode >= KEY_1 and e.keycode <= KEY_9:
				toggle_pick(e.keycode - KEY_1)
			elif e.keycode == KEY_A and load_slot.is_empty():
				go_alone()
			elif e.keycode == KEY_TAB:
				loadout_focus((load_who + 1) % maxi(loadout_people().size(), 1))
			elif e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER or e.keycode == KEY_SPACE:
				confirm_party()
			elif e.keycode == KEY_ESCAPE:
				if not load_slot.is_empty():
					load_slot = {}
				else:
					go_alone()
		elif e.keycode == KEY_L:
			quick_leave()
		elif e.keycode == KEY_R:
			session.reload()
		elif e.keycode == KEY_Q:
			session.swap()
		elif e.keycode == KEY_F:
			toggle_light()
		elif e.keycode == KEY_G:  # the active of the gear he wears (gear_active.gd)
			use_active()
		elif e.keycode == KEY_ESCAPE:
			if _leave_t > 0.0:
				_leave_t = 0.0
				say("You stay.")
			elif panel >= 0:
				close_panel()
			elif shop >= 0:
				close_shop()
			elif front != null and front.has_method("open_pause"):
				front.open_pause()
		elif e.keycode >= KEY_1 and e.keycode <= KEY_9 and panel >= 0:
			take_row(e.keycode - KEY_1)
		elif e.keycode >= KEY_1 and e.keycode <= KEY_9 and shop >= 0:
			buy_row(e.keycode - KEY_1)


## G: the active of the soldier's body gear toward the aim. The view says what happened.
func use_active() -> void:
	if session == null or session.soldier.is_down():
		return
	var r: Dictionary = session.use_active(_aim)
	if str(r["text"]) != "":
		say(str(r["text"]))
	Audio.fx(self, "arrive" if bool(r["ok"]) else "error", null, -8.0)


## A click on the loadout screen (hud.loadout_at): a person, a crew row, a slot, a choice or the go button.
func _loadout_click(hit: Dictionary) -> void:
	match str(hit.get("type", "")):
		"go":
			confirm_party()
		"alone":
			go_alone()
		"pick":
			toggle_pick(int(hit["i"]))
			if pick.has(str(pick_rows()[int(hit["i"])]["name"])):  # a crew mate just picked is the one shown
				load_who = loadout_people().size() - 1
		"person":
			loadout_focus(int(hit["i"]))
		"slot":
			loadout_open(str(hit["slot"]), int(hit["idx"]))
		"option":
			loadout_choose(int(hit["i"]))
		_:
			if not load_slot.is_empty():
				load_slot = {}


func _zoom(f: float) -> void:
	if cam != null:
		cam.zoom = (cam.zoom * f).clamp(Vector2(ZOOM_MIN, ZOOM_MIN), Vector2(ZOOM_MAX, ZOOM_MAX))


## Where the aim is on the screen (the cursor, or the point a script aims at).
func aim_screen() -> Vector2:
	if aim_override != null:
		return to_screen(aim_override / CELL)
	return get_viewport().get_mouse_position() if is_inside_tree() else Vector2.ZERO


## Screen position (the HUD's) of a point in cells.
func to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * (p * CELL) if is_inside_tree() else p * CELL


# --- drawing ----------------------------------------------------------------------------------------------------------

func _draw_over() -> void:
	if session == null:
		return
	var site = session.site
	var rdefs: Dictionary = Site.config()["rooms"]
	for r in site.rooms:
		if r["purpose"] == "gone":
			continue
		var rect: Rect2i = r["rect"]
		var wash := Color(Themes.wash(site.theme, Color(str(rdefs[r["purpose"]]["tint"]))), 0.09 if site.theme == "" else 0.2)
		if r.has("cells"):  # a room of a beaten ship is not a rectangle
			for c in r["cells"]:
				_over.draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)), wash)
		else:
			_over.draw_rect(Rect2(Vector2(rect.position) * CELL, Vector2(rect.size) * CELL), wash)
		if Air.bad(site.air_of(r["id"])):  # no air: a pale blue wash, and its name the first time it is seen
			var thin := Color(0.55, 0.8, 1.0, 0.22)
			if r.has("cells"):
				for c in r["cells"]:
					_over.draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)), thin)
			else:
				_over.draw_rect(Rect2(Vector2(rect.position) * CELL, Vector2(rect.size) * CELL), thin)
	_draw_air_labels(site)
	_draw_hatch(site)
	for d in site.doors:
		if d["lock"] != "" and d["lock"] != "gone" and not session.unlocked.has(d["id"]):
			_draw_lock(d)
	var pdefs: Dictionary = Site.config()["props"]
	for p in site.props:
		if not p.has("part"):  # (a beaten ship's parts are drawn by her own art)
			_draw_prop(p, pdefs[p["prop"]])
	if str(target.get("type", "")) == "container":
		var tp: Dictionary = site.props[target["id"]]
		_over.draw_rect(Rect2(Vector2(tp["cell"]) * CELL, Vector2(tp["size"]) * CELL).grow(2.0), Color(1, 1, 1, 0.55), false, 2.0)
	_draw_marks(site)
	_draw_feed_lines()
	_draw_scorch()
	_draw_foes()
	_draw_people()
	_draw_party()
	_draw_soldier()
	_draw_active_fx()


## The gear actives and a deflect for a moment: a Dash leaves a streak along its way, a Brace a ring round the soldier while it lasts, a Patch a ring that spreads to its reach.
func _draw_active_fx() -> void:
	var s = session
	if s.brace_t > 0.0:
		var c: Vector2 = s.soldier.pos * CELL
		_over.draw_arc(c, 17.0 + 1.5 * sin(_clock * 12.0), 0.0, TAU, 28, Color(0.55, 0.85, 1.0, 0.5 + 0.3 * minf(s.brace_t, 1.0)), 3.0, true)
	for e in _afx:
		var k: float = float(e["t"]) / AFX_S
		var at: Vector2 = e["pos"] * CELL
		match str(e["id"]):
			"dash":
				var to := at + Vector2.from_angle(float(e["dir"])) * float(Site.config()["actives"]["dash"]["cells"]) * CELL
				for i in 4:
					var off := Vector2(0, -6 + 4 * i).rotated(float(e["dir"]))
					_over.draw_line(at + off, to + off, Color(1.0, 0.75, 0.3, 0.55 * (1.0 - k)), 2.0)
			"patch":
				_over.draw_arc(at, float(Site.config()["actives"]["patch"]["reach"]) * CELL * minf(k * 2.0, 1.0), 0.0, TAU, 36, Color(0.4, 1.0, 0.55, 0.7 * (1.0 - k)), 3.0, true)
			"deflect":
				_over.draw_arc(at, 12.0 + 14.0 * k, 0.0, TAU, 20, Color(0.8, 0.7, 1.0, 0.8 * (1.0 - k)), 2.0, true)


## The Spotter Cam's rooms read as a camera feed: faint scan lines over what the feed lights.
func _draw_feed_lines() -> void:
	for rid in _cam_lights:
		if float(_cam_energy.get(rid, 0.0)) < 0.05:
			continue
		var r: Rect2i = session.site.rooms[rid]["rect"]
		var x0 := float(r.position.x) * CELL
		var x1 := float(r.end.x) * CELL
		var y := float(r.position.y) * CELL
		while y < float(r.end.y) * CELL:
			_over.draw_line(Vector2(x0, y), Vector2(x1, y), Color(0.0, 0.05, 0.03, 0.2), 1.0)
			y += 4.0


## The marks bolts left on the walls: a dark smudge with a hot rim that goes first, gone in about 20 s.
func _draw_scorch() -> void:
	if fx == null:
		return
	var life := float(Bolts.cfg()["scorch_s"])
	for sc in fx.scorch:
		var k := 1.0 - float(sc["age"]) / life
		var seed_a := float(int(sc["seed"]) % 628) / 100.0
		for i in 4:
			var o := Vector2.from_angle(seed_a + float(i) * 1.7) * (1.5 + float(i))
			_over.draw_circle(sc["pos"] + o, 3.4 - 0.4 * float(i), Color(0.02, 0.015, 0.01, 0.7 * k))
		var hot := 1.0 - float(sc["age"]) / 1.6
		if hot > 0.0:
			_over.draw_circle(sc["pos"], 3.0, Color(1.0, 0.55, 0.2, 0.6 * hot))


## "NO AIR" over each airless room the soldier has seen (session.air_seen), bright for the first seconds, then dim.
func _draw_air_labels(site) -> void:
	var font := ThemeDB.fallback_font
	for rid in session.air_seen:
		var k := clampf(1.0 - (float(session.air_seen[rid]) - 6.0) / 4.0, 0.3, 1.0)
		var at: Vector2 = site.centre_of_room(rid) * CELL
		var w := font.get_string_size("NO AIR", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_over.draw_string(font, at + Vector2(-w / 2.0, 6.0), "NO AIR", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7, 0.9, 1.0, k))


func _draw_hatch(site) -> void:
	var h: Array = site.airlock["hatch"]
	var n: Vector2 = site.airlock["normal"]
	for c in h:
		var r := Rect2(Vector2(c) * CELL, Vector2(CELL, CELL))
		_over.draw_rect(r, Color("#17402a"))
		for k in 4:
			var y := r.position.y + CELL * (k + 0.5) / 4.0
			_over.draw_line(Vector2(r.position.x + 3.0, y), Vector2(r.end.x - 3.0, y), Color("#58e08a"), 2.0)
	var mid: Vector2 = site.hatch_centre() * CELL
	_over.draw_circle(mid + n * 5.0, 5.0, Color(0.35, 1.0, 0.55, 0.5 + 0.4 * sin(_clock * 3.0)))


func _draw_lock(d: Dictionary) -> void:
	var a: Vector2i = d["cells"][0]
	var b: Vector2i = d["cells"][1]
	var r := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)) * CELL, Vector2(absf(a.x - b.x) + 1.0, absf(a.y - b.y) + 1.0) * CELL)
	var col := Color("#e8a23a") if d["lock"] == "hack" else Color(["#e0453a", "#4aa3ff", "#58d36a", "#e8c43a"][Site.KEY_NAMES.find(d["card"])])
	_over.draw_rect(r.grow(-3.0), Color(col, 0.38))
	_over.draw_rect(r.grow(-3.0), col, false, 2.0)
	var mid := r.get_center()
	_over.draw_circle(mid, 5.0, Color(col, 0.9))
	_over.draw_rect(Rect2(mid + Vector2(-3.0, 1.0), Vector2(6.0, 5.0)), Color(0.05, 0.05, 0.07))


func _draw_prop(p: Dictionary, def: Dictionary) -> void:
	var o: Vector2 = Vector2(p["cell"]) * CELL
	var sz: Vector2 = Vector2(p["size"]) * CELL
	var open: bool = session.opened.has(p["id"])
	var spent: bool = open and not session.left.has(p["id"])
	var pc: Array = Themes.colors(session.site.theme, str(p["prop"]), PROP_COLORS.get(str(p["prop"]), ["#888888", "#222222"]))  # [fill, edge], the theme's if it has them
	var fill: Color = pc[0].darkened(0.35) if spent else pc[0]
	var edge: Color = pc[1]
	match p["prop"]:
		"crate":
			var r := Rect2(o + Vector2(3, 3), sz - Vector2(6, 6))
			_over.draw_rect(r, fill)
			_over.draw_rect(r, edge, false, 2.0)
			_over.draw_line(r.position, r.end, edge, 2.0)
			_over.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), edge, 2.0)
			if open:
				_over.draw_rect(r.grow(-6.0), Color(0, 0, 0, 0.55))
		"locker":
			var r2 := Rect2(o + Vector2(6, 2), sz - Vector2(12, 4))
			_over.draw_rect(r2, fill)
			_over.draw_rect(r2, edge, false, 2.0)
			_over.draw_line(r2.position + Vector2(r2.size.x / 2.0, 2), r2.position + Vector2(r2.size.x / 2.0, r2.size.y - 2), edge, 2.0)
			_over.draw_circle(r2.position + Vector2(r2.size.x / 2.0 + 3.0, r2.size.y / 2.0), 1.6, Color("#c8d2e0"))
			if open:
				_over.draw_rect(Rect2(r2.position + Vector2(r2.size.x / 2.0, 2), Vector2(r2.size.x / 2.0 - 2, r2.size.y - 4)), Color(0, 0, 0, 0.6))
		"cabinet":
			var r3 := Rect2(o + Vector2(3, 4), sz - Vector2(6, 8))
			_over.draw_rect(r3, fill)
			_over.draw_rect(r3, edge, false, 2.0)
			for k in 2:
				var yy := r3.position.y + r3.size.y * (0.25 + 0.5 * k)
				_over.draw_line(Vector2(r3.position.x + 2, yy), Vector2(r3.end.x - 2, yy), edge, 2.0)
				_over.draw_line(Vector2(r3.get_center().x - 3, yy + 4), Vector2(r3.get_center().x + 3, yy + 4), Color("#c8d2e0"), 2.0)
		"pallet":
			var r4 := Rect2(o + Vector2(2, 2), sz - Vector2(4, 4))
			_over.draw_rect(r4, fill)
			_over.draw_rect(r4, edge, false, 2.0)
			var along := sz.x >= sz.y
			for k in 2:
				var f := (0.25 + 0.5 * k)
				var bx := Rect2(r4.position + (Vector2(r4.size.x * f - 7.0, r4.size.y / 2.0 - 7.0) if along else Vector2(r4.size.x / 2.0 - 7.0, r4.size.y * f - 7.0)), Vector2(14, 14))
				_over.draw_rect(bx, fill.lightened(0.3) if not open else fill.darkened(0.2))
				_over.draw_rect(bx, edge, false, 1.5)
		"terminal":
			var r5 := Rect2(o + Vector2(4, 3), sz - Vector2(8, 6))
			_over.draw_rect(r5, fill)
			_over.draw_rect(r5, edge, false, 2.0)
			var scr := Rect2(r5.position + Vector2(3, 3), Vector2(r5.size.x - 6, r5.size.y * 0.55))
			var glow := 0.55 + 0.25 * sin(_clock * 5.0 + float(p["id"]))
			_over.draw_rect(scr, Color(0.2, 0.95, 0.8, glow if not spent else 0.15))
			for k in 3:
				_over.draw_line(scr.position + Vector2(3, 4 + 5 * k), scr.position + Vector2(scr.size.x - 3 - 4 * k, 4 + 5 * k), Color(0.02, 0.2, 0.18, 0.7), 1.5)
		"heap":  # a mound of scrap
			var hc := o + sz / 2.0
			for k in 8:
				var a := float(hash([p["id"], k]) % 628) / 100.0
				var rr := 6.0 + float(hash([k, p["id"]]) % 5)
				_over.draw_circle(hc + Vector2.from_angle(a) * (4.0 + float(k % 3) * 3.5), rr, fill.lightened(0.12 * float(k % 3)))
				_over.draw_arc(hc + Vector2.from_angle(a) * (4.0 + float(k % 3) * 3.5), rr, 0.0, TAU, 10, edge, 1.5, true)
			if open:
				_over.draw_circle(hc, 8.0, Color(0, 0, 0, 0.5))
		"files":  # racks of folders
			var r6 := Rect2(o + Vector2(3, 3), sz - Vector2(6, 6))
			_over.draw_rect(r6, fill)
			_over.draw_rect(r6, edge, false, 2.0)
			for k in 4:
				var xx := r6.position.x + 3.0 + float(k) * (r6.size.x - 6.0) / 4.0
				_over.draw_rect(Rect2(xx, r6.position.y + 3.0, (r6.size.x - 6.0) / 4.0 - 2.0, r6.size.y - 6.0), Color("#e8e4d4") if not open else Color("#8a8678"))
				_over.draw_line(Vector2(xx, r6.position.y + 3.0), Vector2(xx, r6.end.y - 3.0), edge, 1.0)
		"crystal":  # a glowing cluster
			var cc := o + sz / 2.0
			var gl := 0.6 + 0.3 * sin(_clock * 2.2 + float(p["id"]))
			_over.draw_circle(cc, 18.0, Color(fill, 0.2 * gl))
			for k in 5:
				var ang := -PI / 2.0 + (float(k) - 2.0) * 0.5
				var tip := cc + Vector2.from_angle(ang) * (13.0 + float(k % 2) * 5.0)
				var side := Vector2.from_angle(ang).orthogonal() * 4.0
				_over.draw_colored_polygon(PackedVector2Array([cc + side, tip, cc - side]), Color(fill, 0.55 + 0.4 * gl) if not spent else Color(fill, 0.25))
				_over.draw_line(cc, tip, edge, 1.0)
		"cask":  # a rack of barrels
			var along2 := sz.x >= sz.y
			for k in 2:
				var kc := o + (Vector2(sz.x * (0.25 + 0.5 * k), sz.y / 2.0) if along2 else Vector2(sz.x / 2.0, sz.y * (0.25 + 0.5 * k)))
				_over.draw_circle(kc, 12.0, fill)
				_over.draw_arc(kc, 12.0, 0.0, TAU, 16, edge, 2.0, true)
				_over.draw_arc(kc, 6.0, 0.0, TAU, 12, edge, 1.5, true)
		"trophy":  # a case with a skull and horns on it
			var r7 := Rect2(o + Vector2(3, 5), sz - Vector2(6, 10))
			_over.draw_rect(r7, fill.darkened(0.2))
			_over.draw_rect(r7, edge, false, 2.0)
			var tc2 := r7.get_center()
			_over.draw_circle(tc2, 5.0, Color("#e8e0cc"))
			_over.draw_line(tc2 + Vector2(-4, -4), tc2 + Vector2(-11, -9), Color("#e8e0cc"), 2.0)
			_over.draw_line(tc2 + Vector2(4, -4), tc2 + Vector2(11, -9), Color("#e8e0cc"), 2.0)
		"body":
			var c := o + sz / 2.0
			var ang := float(hash(p["cell"]) % 628) / 100.0
			var dir := Vector2.from_angle(ang)
			_over.draw_circle(c, 13.0, Color(0.25, 0.02, 0.02, 0.5))
			_over.draw_line(c - dir * 9.0, c + dir * 7.0, Color("#6b4a4a") if not spent else Color("#4a3636"), 8.0)
			_over.draw_circle(c + dir * 11.0, 4.5, Color("#c9a483") if not spent else Color("#8a735c"))
			_over.draw_line(c + dir.orthogonal() * 3.0, c + dir.orthogonal() * 10.0 - dir * 6.0, Color("#6b4a4a"), 3.0)
			_over.draw_line(c - dir.orthogonal() * 3.0, c - dir.orthogonal() * 10.0 - dir * 6.0, Color("#6b4a4a"), 3.0)
		"corpse":  # the fallen foe is drawn lying; a ring says it can be searched
			if not spent:
				var cc: Vector2 = p["centre"] * CELL if p.has("centre") else o + sz / 2.0
				_over.draw_arc(cc, 17.0, 0.0, TAU, 24, Color(1, 1, 1, 0.28 + 0.12 * sin(_clock * 3.0)), 1.5, true)
		"cable":
			var base := o + Vector2(CELL * 0.15, CELL * 0.65)
			var pts := PackedVector2Array()
			for k in 5:
				pts.append(base + Vector2(CELL * 0.7 * k / 4.0, 3.0 * sin(float(k) * 2.0 + float(p["id"]))))
			_over.draw_polyline(pts, Color("#2a2a2e"), 4.0)
			_over.draw_polyline(pts, Color("#c8a83a"), 1.5)
			var ph := fposmod(_clock * 1.7 + float(p["id"]) * 0.37, 1.0)
			if ph < 0.14:  # a spark
				var tip: Vector2 = pts[pts.size() - 1]
				_over.draw_circle(tip, 3.0, Color(0.8, 0.95, 1.0, 0.95))
				for k in 4:
					_over.draw_line(tip, tip + Vector2.from_angle(float(k) * 1.7 + _clock * 40.0) * 8.0, Color(0.7, 0.9, 1.0, 0.9), 1.5)
		_:
			_over.draw_rect(Rect2(o + Vector2(4, 4), sz - Vector2(8, 8)), Color("#888"))


func _draw_soldier() -> void:
	var m = session.soldier
	var a: Dictionary = _anim.get(m, PersonDrawer.new_state(m))
	var look: Dictionary = m.look if not m.look.is_empty() else ShipView.LOOKS.get(m.name, ShipView.OTHER_LOOK)
	var pose := {"species": Art.crew_rig(m.rig()), "move": a["angle"], "aim": a["aim"], "phase": a["phase"], "moving": a["moving"],
		"item": str(session.gun()["w"]["art"]), "down": m.is_down(), "work": false, "t": _clock, "head": m.head, "body": PersonDrawer.gear_of(m)}
	PersonDrawer.draw(_over, m.pos * CELL, pose, look, CELL)


# --- drawing the foes -----------------------------------------------------------------------------------------------

func _draw_foes() -> void:
	for v in session.foes.vents:
		var r := Rect2(v * CELL - Vector2(11, 11), Vector2(22, 22))
		_over.draw_rect(r, Color("#20252d"))
		_over.draw_rect(r, Color("#0a0c10"), false, 2.0)
		for k in 4:
			_over.draw_line(r.position + Vector2(3, 4 + 5 * k), r.position + Vector2(19, 4 + 5 * k), Color("#0a0c10"), 2.0)
	for pass_no in 2:  # the fallen first, the standing over them
		for f in session.foes.list:
			if f["hidden"] or bool(f["dead"]) != (pass_no == 0):
				continue
			match str(f["kind"]):
				"sentry":
					_draw_sentry(f)
				"crawler":
					_draw_crawler(f)
				_:
					_draw_foe(f)


func _draw_foe(f: Dictionary) -> void:
	var m = f["m"]
	var a: Dictionary = _anim.get(m, PersonDrawer.new_state(m))
	var look := {"suit": "#888888", "hair": "#2a2018", "tool": "#cfd5dd"}
	look.merge(f["d"].get("look", {}), true)
	var pose := {"species": Art.crew_rig("human"), "move": a["angle"], "aim": a["aim"], "phase": a["phase"], "moving": a["moving"],
		"item": str(f["d"].get("weapon", "")), "down": f["dead"], "work": false, "t": _clock, "head": "", "body": str(f.get("gear", ""))}
	PersonDrawer.draw(_over, m.pos * CELL, pose, look, CELL)


func _draw_sentry(f: Dictionary) -> void:
	var c: Vector2 = f["m"].pos * CELL
	var hacked: bool = f["team"] == "player"
	var dir := Vector2.from_angle(float(f["aim"]))
	_over.draw_circle(c, 11.0, Color("#2a2f38") if not f["dead"] else Color("#1a1d22"))
	_over.draw_arc(c, 11.0, 0.0, TAU, 20, Color("#0c0e12"), 2.0, true)
	if f["dead"]:
		return
	_over.draw_line(c, c + dir * 18.0, Color("#10131a"), 5.0)
	_over.draw_line(c, c + dir * 18.0, Color("#59626f"), 2.5)
	var led := Color("#58e08a") if hacked else (Color("#ff3b2e") if float(f["track"]) > 0.0 else Color("#e8a23a"))
	_over.draw_circle(c - dir * 3.0, 2.5, led)


func _draw_crawler(f: Dictionary) -> void:
	var m = f["m"]
	var c: Vector2 = m.pos * CELL
	var dir: Vector2 = m.facing
	var col := Color("#0c0c10") if not f["dead"] else Color("#1b1b20")
	var wob := sin(_clock * 18.0 + float(f["id"])) * (0.0 if f["frozen"] or f["dead"] else 1.0)
	for k in 3:  # legs
		for sgn in [-1.0, 1.0]:
			var o: Vector2 = dir.orthogonal() * sgn
			var base := c + dir * (float(k) - 1.0) * 4.0
			_over.draw_line(base, base + o * 9.0 + dir * (float(k) - 1.0) * 4.0 + dir * wob * 2.0, col, 1.5)
	_over.draw_circle(c, 6.0, col)
	_over.draw_circle(c + dir * 6.0, 3.8, col)
	_over.draw_circle(c - dir * 6.0, 4.2, col)
	if not f["dead"]:
		_over.draw_circle(c + dir * 7.5 + dir.orthogonal() * 1.6, 0.9, Color("#c8a0a0"))
		_over.draw_circle(c + dir * 7.5 - dir.orthogonal() * 1.6, 0.9, Color("#c8a0a0"))


## An unread note on a marked terminal or body: a small pale sheet. (A strange room shows nothing until he steps in.)
func _draw_marks(site) -> void:
	for m in site.marks:
		if session.seen_marks.has(m["id"]) or m["kind"] == "room":
			continue
		var at: Vector2 = m["pos"] * CELL + Vector2(7.0, -8.0)
		var pulse := 0.6 + 0.3 * sin(_clock * 3.0 + float(m["id"]))
		_over.draw_rect(Rect2(at, Vector2(8, 10)), Color(0.92, 0.9, 0.78, pulse))
		_over.draw_rect(Rect2(at, Vector2(8, 10)), Color(0.3, 0.28, 0.2), false, 1.0)
		_over.draw_line(at + Vector2(2, 3), at + Vector2(6, 3), Color(0.3, 0.28, 0.2), 1.0)
		_over.draw_line(at + Vector2(2, 6), at + Vector2(6, 6), Color(0.3, 0.28, 0.2), 1.0)


## The people who are not hostile: standing, or walking off. A captive has a rope round them.
func _draw_people() -> void:
	for n in session.people.list:
		if not (n["state"] in ["here", "leaving"]):
			continue
		var m = n["m"]
		var a: Dictionary = _anim.get(m, PersonDrawer.new_state(m))
		var look: Dictionary = {"suit": "#888888", "hair": "#2a2018", "tool": "#cfd5dd"}
		look.merge(m.look, true)
		var pose := {"species": Art.crew_rig(m.rig()), "move": a["angle"], "aim": a["aim"], "phase": a["phase"], "moving": a["moving"],
			"item": str(n["d"].get("weapon", "")), "down": false, "work": false, "t": _clock, "head": m.head, "body": PersonDrawer.gear_of(m)}
		PersonDrawer.draw(_over, m.pos * CELL, pose, look, CELL)
		if n["role"] == "captive":
			var c: Vector2 = m.pos * CELL
			_over.draw_arc(c, 13.0, 0.3, 2.6, 10, Color("#c8b070"), 2.0, true)
			_over.draw_arc(c, 13.0, 3.5, 5.8, 10, Color("#c8b070"), 2.0, true)
			_over.draw_circle(c + Vector2(0, 13.0), 2.0, Color("#c8b070"))


func _draw_party() -> void:
	for p in session.party:
		var m = p["m"]
		var a: Dictionary = _anim.get(m, PersonDrawer.new_state(m))
		var look: Dictionary = m.look if not m.look.is_empty() else ShipView.LOOKS.get(m.name, ShipView.OTHER_LOOK)
		var pose := {"species": Art.crew_rig(m.rig()), "move": a["angle"], "aim": a["aim"], "phase": a["phase"], "moving": a["moving"],
			"item": str(p["gun"]["w"]["art"]), "down": m.is_down(), "work": false, "t": _clock, "head": m.head, "body": PersonDrawer.gear_of(m)}
		PersonDrawer.draw(_over, m.pos * CELL, pose, look, CELL)
