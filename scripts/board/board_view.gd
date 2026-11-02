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
##   locked door to hack it, tap E by a card door to use the keycard. E in the airlock leaves. Esc is the pause menu; Ctrl+S is refused aboard.
## - The HUD (board_hud.gd): the site and its containers, the airlock marker (an arrow at the screen edge when it is off screen), the tracker.
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

## Emitted when the soldier is back on the ship: Boarding.leave()'s result {cleared, said, name, kind, poi}.
signal finished(result: Dictionary)

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
var picking := false  ## the crew picker is up: the world stands still
var pick: Array = []  ## the names picked so far
var hollow_source := Callable()  ## () -> bool: has the Hollow taken this place (map_view.gd sets it; the visit notices when it does)
var tracers: Array = []  ## [{from, to (cells), t, foe}] the lines the shots drew, for the HUD
var light_on := true  ## F: the flashlight
var target := {}  ## what E would act on: {type ("airlock", "container", "door"), id, dist}
var hold := 0.0  ## seconds E has been held on the target
var panel := -1  ## the container whose loot list is open
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
var _down_t := 0.0
var _leave_t := 0.0  # seconds a "leave them behind?" question stands
var _skitter := 0.0
var _fight_t := 0.0  # seconds the combat music runs on after the last foe on the hunt
var _mood := "explore"
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
	target = {}
	message = ""
	feed.clear()
	tracker = Tracker.new()
	tracers.clear()
	light_on = true
	_down_t = 0.0
	_flicker = 0.0
	_leave_t = 0.0
	_fight_t = 0.0
	_mood = "explore"
	_anim = {}
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
	picking = ask_party and not Party.eligible(session.ship).is_empty()
	return ""


## The soldier is back on the ship. Emits `finished`.
func leave() -> void:
	if not active:
		return
	var result: Dictionary = session.leave()
	Audio.fx_loop(self, "hack", "repair_loop", false)
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
	_fake = Ship.new("Site", site.grid)
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
	if picking:  # the crew picker is up: he stands at the airlock, the dark waits
		_aim_at(dt)
		_update_lights(dt)
		if hud != null:
			hud.queue_redraw()
		return
	var before: Vector2 = m.pos
	if not s.downed:
		m.move_input(s.site.walk, _wasd(), dt, s.door_passable())
	if m.pos != before and not _follow:
		_follow = true
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
	for e in _red:
		var flicker: float = 1.0 + 0.12 * sin(_clock * 2.3 + float(e[2])) + (0.0 if not e[3] else 0.06 * sin(_clock * 11.0 + float(e[2]) * 3.0))
		e[0].energy = float(e[1]) * flicker * fk
		e[0].visible = not lights_up


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
	if s.downed:
		_down_t += dt
		if _down_t >= DOWN_S:
			leave()
			return
	if not s.downed:
		s.note_hollow(hollow_source.call() if hollow_source.is_valid() else false)
	s.tick(dt, _aim, light_on)
	if _fire_down() and panel < 0 and not s.downed:
		s.fire(_aim)
	for p in s.party:
		var pa: Dictionary = _anim.get(p["m"], PersonDrawer.new_state(p["m"]))
		PersonDrawer.animate(pa, p["m"], dt, p["m"].facing.angle())
		_anim[p["m"]] = pa
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
	for t in tracers:
		t["t"] += dt
	tracers = tracers.filter(func(t): return float(t["t"]) < float(Arms.cfg()["tracer_s"]))
	_play(s.take_events())


## Draw and sound the events of a tick.
func _play(evs: Array) -> void:
	for e in evs:
		var at: Vector2 = e.get("pos", e.get("from", Vector2.ZERO))
		var px := at * CELL
		match str(e["type"]):
			"shot":
				tracers.append({"from": e["from"], "to": e["to"], "t": 0.0, "foe": e["who"] != "soldier"})
				if e["who"] == "soldier":
					_muzzle_t = float(Arms.cfg()["flash_s"])
					_muzzle_at = e["from"]
				Audio.fx(self, "shot_" + str(e["class"]), px, 0.0 if e["who"] == "soldier" else -2.0)
			"swing":
				Audio.fx(self, "melee_swing", px)
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
				Audio.fx(self, "foe_hit", px)
			"down":
				Audio.fx(self, "foe_down", px)
			"hurt":
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


## The crew who can be taken along, [{name, species, hp, max_hp}].
func pick_rows() -> Array:
	return Party.eligible(session.ship).map(func(m): return {"name": m.name, "species": m.species, "hp": m.hp, "max_hp": m.max_hp})


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


## Go aboard with the crew picked (none is allowed).
func confirm_party() -> void:
	if not picking:
		return
	picking = false
	var n: int = session.join_party(pick)
	_e_prev = true  # (a key still down does not count as a press)
	say("%d crew with you." % n if n > 0 else "Alone.")


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
			return float(Site.config()["hack_s"]) if session.site.doors[t["id"]]["lock"] == "hack" else 0.0
		"revive":
			return float(Arms.cfg()["revive_s"])
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
	var t := find_target()
	var key := "%s:%s" % [t.get("type", ""), t.get("id", "")]
	if key != _hold_key:
		_hold_key = key
		hold = 0.0
	target = t
	var need := _hold_need(t)
	var hacking := false
	if down and need > 0.0 and panel < 0:
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
	match str(target.get("type", "")):
		"airlock":
			var down: Array = s.downed_party()
			if not down.is_empty() and _leave_t <= 0.0:  # crew left down are lost: ask first
				_leave_t = float(Arms.cfg()["leave_confirm_s"])
				say("%s is down. Leaving now loses them. E again to go, Esc to stay." % ", ".join(down))
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
				if hud != null and picking:
					var pr: int = hud.pick_at(e.position)
					if pr == -2:
						confirm_party()
					elif pr >= 0:
						toggle_pick(pr)
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
		elif picking:
			if e.keycode >= KEY_1 and e.keycode <= KEY_9:
				toggle_pick(e.keycode - KEY_1)
			elif e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER or e.keycode == KEY_SPACE:
				confirm_party()
			elif e.keycode == KEY_ESCAPE:
				pick.clear()
				confirm_party()
		elif e.keycode == KEY_R:
			session.reload()
		elif e.keycode == KEY_Q:
			session.swap()
		elif e.keycode == KEY_F:
			toggle_light()
		elif e.keycode == KEY_ESCAPE:
			if _leave_t > 0.0:
				_leave_t = 0.0
				say("You stay.")
			elif panel >= 0:
				close_panel()
			elif front != null and front.has_method("open_pause"):
				front.open_pause()
		elif e.keycode >= KEY_1 and e.keycode <= KEY_9 and panel >= 0:
			take_row(e.keycode - KEY_1)


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
		_over.draw_rect(Rect2(Vector2(rect.position) * CELL, Vector2(rect.size) * CELL), Color(Color(str(rdefs[r["purpose"]]["tint"])), 0.09))
	_draw_hatch(site)
	for d in site.doors:
		if d["lock"] != "" and d["lock"] != "gone" and not session.unlocked.has(d["id"]):
			_draw_lock(d)
	var pdefs: Dictionary = Site.config()["props"]
	for p in site.props:
		_draw_prop(p, pdefs[p["prop"]])
	if str(target.get("type", "")) == "container":
		var tp: Dictionary = site.props[target["id"]]
		_over.draw_rect(Rect2(Vector2(tp["cell"]) * CELL, Vector2(tp["size"]) * CELL).grow(2.0), Color(1, 1, 1, 0.55), false, 2.0)
	_draw_foes()
	_draw_party()
	_draw_soldier()


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
	match p["prop"]:
		"crate":
			var r := Rect2(o + Vector2(3, 3), sz - Vector2(6, 6))
			_over.draw_rect(r, Color("#8a6a3e") if not spent else Color("#5a4a30"))
			_over.draw_rect(r, Color("#3d2c16"), false, 2.0)
			_over.draw_line(r.position, r.end, Color("#3d2c16"), 2.0)
			_over.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color("#3d2c16"), 2.0)
			if open:
				_over.draw_rect(r.grow(-6.0), Color(0, 0, 0, 0.55))
		"locker":
			var r2 := Rect2(o + Vector2(6, 2), sz - Vector2(12, 4))
			_over.draw_rect(r2, Color("#4d5f78") if not spent else Color("#34404f"))
			_over.draw_rect(r2, Color("#1c2431"), false, 2.0)
			_over.draw_line(r2.position + Vector2(r2.size.x / 2.0, 2), r2.position + Vector2(r2.size.x / 2.0, r2.size.y - 2), Color("#1c2431"), 2.0)
			_over.draw_circle(r2.position + Vector2(r2.size.x / 2.0 + 3.0, r2.size.y / 2.0), 1.6, Color("#c8d2e0"))
			if open:
				_over.draw_rect(Rect2(r2.position + Vector2(r2.size.x / 2.0, 2), Vector2(r2.size.x / 2.0 - 2, r2.size.y - 4)), Color(0, 0, 0, 0.6))
		"cabinet":
			var r3 := Rect2(o + Vector2(3, 4), sz - Vector2(6, 8))
			_over.draw_rect(r3, Color("#6b727d") if not spent else Color("#454a52"))
			_over.draw_rect(r3, Color("#23272e"), false, 2.0)
			for k in 2:
				var yy := r3.position.y + r3.size.y * (0.25 + 0.5 * k)
				_over.draw_line(Vector2(r3.position.x + 2, yy), Vector2(r3.end.x - 2, yy), Color("#23272e"), 2.0)
				_over.draw_line(Vector2(r3.get_center().x - 3, yy + 4), Vector2(r3.get_center().x + 3, yy + 4), Color("#c8d2e0"), 2.0)
		"pallet":
			var r4 := Rect2(o + Vector2(2, 2), sz - Vector2(4, 4))
			_over.draw_rect(r4, Color("#6a5a3a") if not spent else Color("#4a4030"))
			_over.draw_rect(r4, Color("#2c2416"), false, 2.0)
			var along := sz.x >= sz.y
			for k in 2:
				var f := (0.25 + 0.5 * k)
				var bx := Rect2(r4.position + (Vector2(r4.size.x * f - 7.0, r4.size.y / 2.0 - 7.0) if along else Vector2(r4.size.x / 2.0 - 7.0, r4.size.y * f - 7.0)), Vector2(14, 14))
				_over.draw_rect(bx, Color("#a58552") if not open else Color("#5a4a30"))
				_over.draw_rect(bx, Color("#2c2416"), false, 1.5)
		"terminal":
			var r5 := Rect2(o + Vector2(4, 3), sz - Vector2(8, 6))
			_over.draw_rect(r5, Color("#2b3340"))
			_over.draw_rect(r5, Color("#10151c"), false, 2.0)
			var scr := Rect2(r5.position + Vector2(3, 3), Vector2(r5.size.x - 6, r5.size.y * 0.55))
			var glow := 0.55 + 0.25 * sin(_clock * 5.0 + float(p["id"]))
			_over.draw_rect(scr, Color(0.2, 0.95, 0.8, glow if not spent else 0.15))
			for k in 3:
				_over.draw_line(scr.position + Vector2(3, 4 + 5 * k), scr.position + Vector2(scr.size.x - 3 - 4 * k, 4 + 5 * k), Color(0.02, 0.2, 0.18, 0.7), 1.5)
		"body":
			var c := o + sz / 2.0
			var ang := float(hash(p["cell"]) % 628) / 100.0
			var dir := Vector2.from_angle(ang)
			_over.draw_circle(c, 13.0, Color(0.25, 0.02, 0.02, 0.5))
			_over.draw_line(c - dir * 9.0, c + dir * 7.0, Color("#6b4a4a") if not spent else Color("#4a3636"), 8.0)
			_over.draw_circle(c + dir * 11.0, 4.5, Color("#c9a483") if not spent else Color("#8a735c"))
			_over.draw_line(c + dir.orthogonal() * 3.0, c + dir.orthogonal() * 10.0 - dir * 6.0, Color("#6b4a4a"), 3.0)
			_over.draw_line(c - dir.orthogonal() * 3.0, c - dir.orthogonal() * 10.0 - dir * 6.0, Color("#6b4a4a"), 3.0)
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
		"item": str(session.gun()["w"]["art"]), "down": m.is_down(), "work": false, "t": _clock, "head": m.head}
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
		"item": str(f["d"].get("weapon", "")), "down": f["dead"], "work": false, "t": _clock, "head": ""}
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


func _draw_party() -> void:
	for p in session.party:
		var m = p["m"]
		var a: Dictionary = _anim.get(m, PersonDrawer.new_state(m))
		var look: Dictionary = m.look if not m.look.is_empty() else ShipView.LOOKS.get(m.name, ShipView.OTHER_LOOK)
		var pose := {"species": Art.crew_rig(m.rig()), "move": a["angle"], "aim": a["aim"], "phase": a["phase"], "moving": a["moving"],
			"item": str(p["gun"]["w"]["art"]), "down": m.is_down(), "work": false, "t": _clock, "head": m.head}
		PersonDrawer.draw(_over, m.pos * CELL, pose, look, CELL)
