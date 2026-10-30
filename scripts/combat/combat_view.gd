extends Node2D
## Combat mode on screen: press K in play mode to meet the test pirate. The camera zooms out to frame
## both ships, which are drawn at their arena transforms (ship_view.gd); the interior build mode
## and the walking crew are put away. W/S throttle, A/D turn, the mouse aims, LMB fires group 1 (lasers,
## bolts, beams), RMB group 2 (missiles, flak), 1-9 a single weapon, Space overcharges the shield,
## Esc leaves once the enemy is wrecked or 4000 px away, R restarts when you are wrecked.
## The rules live in combat_session.gd; this node reads input, runs the session, and draws the aim
## wedges, shots, impacts and the HUD (schematics, weapon bar). Placeholder effects, no art.

const Session = preload("res://scripts/combat/combat_session.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")
const Art = preload("res://scripts/view/art.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")
const GlowLayer = preload("res://scripts/view/glow_layer.gd")
const Schematic = preload("res://scripts/ui/schematic.gd")
const WeaponBar = preload("res://scripts/ui/weapon_bar.gd")

const PLAYER_SHOT := {"energy": Color("#7dffe8"), "kinetic": Color("#ffe07a"), "explosive": Color("#ffb04a"), "ion": Color("#b99bff")}
const ENEMY_SHOT := {"energy": Color("#ff6a4a"), "kinetic": Color("#ff9a6a"), "explosive": Color("#ff5a3a"), "ion": Color("#b99bff")}
const GROUP_COLORS := {1: Color("#5fd4ff"), 2: Color("#ff9a3c")}
const GREY := Color("#7a8494")
const BEAM_LIFE := 0.15
const MAX_FX := 500
const CAM_RATE := 3.0  ## how fast the camera settles, 1/s
const STAR_COUNT := 220
const ART_SCALE := 2.0  ## fewest screen px per source px for the effect and projectile art
const HINT := "W/S throttle   A/D turn   mouse aims   LMB group 1   RMB group 2   1-9 single weapon   Space overcharge shield   Esc leave"

var sim: Node  ## ShipSim
var build: Node  ## BuildMode (put away during the fight)
var crew: Node  ## crew view (put away too)
var cam: Camera2D
var active := false
var session: Session
## Scripts and tests drive these instead of the keyboard and mouse.
var aim_override: Variant = null  ## a world point, or null for the mouse
var input_override: Variant = null  ## {"throttle", "turn"}, or null for W/S/A/D
var hold_override := {}  ## fire group -> true: held down as if by the mouse

var _views: Array = []
var _fx_node: Node2D
var _glow: Node2D  # additive layer inside _fx_node for the glow of projectiles and effects
var _glow_quads: Array = []
var _stars_node: Node2D
var _stars: Array = []  # [unit position, depth, radius]
var _star_drift := Vector2.ZERO
var _fx: Array = []
var _cursor := 0
var _clock := 0.0
var _frame := 0
var _cam_pos := Vector2.ZERO
var _zoom := 0.5
var _saved_cam := {}
var _rng := RandomNumberGenerator.new()  # visual only
var _schem: Array = []
var _bar: Control
var _banner: Label
var _hint: Label
var _note := ""
var _note_until := 0.0
var _starfield: Node
var _hud_label: Node


func _ready() -> void:
	sim = get_node_or_null("../ShipSim")
	build = get_node_or_null("../BuildMode")
	crew = get_node_or_null("../Crew")
	cam = get_node_or_null("../Camera2D")
	_starfield = get_node_or_null("../Space/Starfield")
	_hud_label = get_node_or_null("../HUD/Label")
	_rng.seed = 4242
	_make_stars()
	_make_hud()
	set_process(true)


func _make_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in STAR_COUNT:
		_stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.2, 1.0), rng.randf_range(0.6, 1.9)])
	var space := get_node_or_null("../Space")
	if space == null:
		return
	_stars_node = Node2D.new()
	_stars_node.visible = false
	_stars_node.draw.connect(_draw_stars)
	space.add_child(_stars_node)


func _make_hud() -> void:
	var layer := get_node_or_null("../HUD")
	if layer == null:
		return
	for t in ["YOUR SHIP", "ENEMY"]:
		var s := Schematic.new()
		s.visible = false
		layer.add_child(s)
		_schem.append(s)
	_bar = WeaponBar.new()
	_bar.visible = false
	layer.add_child(_bar)
	_banner = Label.new()
	_banner.size = Vector2(1100.0, 60.0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 30)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.visible = false
	layer.add_child(_banner)
	_hint = Label.new()
	_hint.size = Vector2(1000.0, 44.0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color("#9fb6d0"))
	_hint.visible = false
	layer.add_child(_hint)


# --- entering and leaving ------------------------------------------------------------------------

## Start a fight with the ship in `path` (the test pirate by default). "" when it began, else why not.
func enter(path := Session.PIRATE_PATH) -> String:
	if active:
		return "already fighting"
	var player = sim.player_ship() if sim != null else null
	if player == null:
		return "no ship"
	var enemy: Ship = Session.load_ship(path)
	if enemy == null:
		return "cannot load " + path
	sim.ships.append(enemy)
	session = Session.new()
	session.start(player, enemy, enemy.rng_seed)
	active = true
	_cursor = 0
	_fx.clear()
	_note = ""
	_star_drift = Vector2.ZERO
	_put_away(true)
	if cam != null:
		_saved_cam = {"pos": cam.position, "zoom": cam.zoom}
		_cam_pos = cam.position
		_zoom = cam.zoom.x
	for i in 2:
		var v := ShipView.new()
		add_child(v)
		v.bind(session.arena, i)
		_views.append(v)
	_fx_node = Node2D.new()
	_fx_node.draw.connect(_draw_fx)
	add_child(_fx_node)
	_glow = GlowLayer.new()
	_fx_node.add_child(_glow)
	if not _schem.is_empty():
		_schem[0].bind(session.arena, Session.PLAYER, player.name if player.name != "Ship" else "Your ship")
		_schem[1].bind(session.arena, Session.ENEMY, enemy.name)
		_bar.bind(session, _aim)
	_show_hud(true)
	return ""


## Leave the fight: the enemy goes, the interior comes back, the camera returns.
func leave() -> void:
	if not active:
		return
	sim.ships.erase(session.arena.ships[Session.ENEMY].ship)
	for v in _views:
		v.queue_free()
	_views.clear()
	if _fx_node != null:
		_fx_node.queue_free()
		_fx_node = null
		_glow = null
	_fx.clear()
	_show_hud(false)
	_put_away(false)
	if cam != null and not _saved_cam.is_empty():
		cam.position = _saved_cam["pos"]
		cam.zoom = _saved_cam["zoom"]
	active = false
	session = null


## After being wrecked: back to the interior with the starter ship reloaded.
func restart() -> void:
	if not active or session.state() != "lost":
		return
	leave()
	# reload the ship the player picked (its design file); the empty starter hull only if none was picked
	if sim != null and sim.design_path != "":
		var why_d: String = sim.choose_ship(sim.design_path)
		if build != null:
			build.message = "ship reloaded" if why_d == "" else why_d
		return
	if build != null:
		var why: String = build.session.load_dict(Ship.new_starter().to_dict())
		build.build_on = true
		build.message = "starter ship reloaded" if why == "" else why


func _put_away(away: bool) -> void:
	if build != null:
		build.combat = away
		build.visible = not away
	if crew != null:
		crew.visible = not away
		crew.set_process(not away)
	if _starfield != null:
		_starfield.visible = not away
	if _stars_node != null:
		_stars_node.visible = away
	if _hud_label != null:
		_hud_label.visible = not away


func _show_hud(on: bool) -> void:
	for s in _schem:
		s.visible = on
	if _bar != null:
		_bar.visible = on
		_hint.visible = on
		_banner.visible = false


# --- input ----------------------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if not active:
			if e.keycode == KEY_K and not e.ctrl_pressed and build != null:
				if build.build_on:
					build.message = "K: switch to play mode (B) to fight"
				else:
					var why := enter()
					if why != "":
						build.message = why
				_handled()
			return
		_handled()
		match e.keycode:
			KEY_ESCAPE:
				if session.can_leave():
					leave()
				else:
					_say("Cannot disengage: wreck the enemy or get %d px away" % Session.LEAVE_DISTANCE)
			KEY_R:
				restart()
			KEY_SPACE:
				var why := session.arena.overcharge(Session.PLAYER)
				if why != "":
					_say("Overcharge: " + why)
			_:
				var n: int = e.keycode - KEY_1
				if n >= 0 and n <= 8:
					session.fire_slot(n + 1, _aim())
	elif active and e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			session.fire_group(1, _aim())
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			session.fire_group(2, _aim())


## The world point the mouse (or a script) aims at.
func _aim() -> Vector2:
	if aim_override != null:
		return aim_override
	return get_global_mouse_position() if is_inside_tree() else Vector2.ZERO


func _view_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(1600.0, 900.0)


func _say(text: String) -> void:
	_note = text
	_note_until = _clock + 2.5


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _helm() -> Dictionary:
	if input_override != null:
		return input_override
	return {"throttle": float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S)),
		"turn": float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))}


# --- the frame --------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if active:
		frame(dt)


## One frame of the fight: read the helm, run the session, turn its events into effects, move the camera.
func frame(dt: float) -> void:
	_clock += dt
	_frame += 1
	var st: String = session.state()
	session.input = _helm() if st != "lost" else {"throttle": 0.0, "turn": 0.0}
	if st != "lost":
		for g in [1, 2]:
			if hold_override.get(g, false) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT if g == 1 else MOUSE_BUTTON_RIGHT):
				session.fire_group(g, _aim())
	session.tick(dt)
	_consume_events()
	_age_fx(dt)
	var player = session.arena.ships[Session.PLAYER]
	_star_drift -= player.flight.vel * dt * 0.4
	_move_camera(dt)
	_update_hud()
	if _fx_node != null:
		_fx_node.queue_redraw()
	if _stars_node != null:
		_stars_node.queue_redraw()


func _move_camera(dt: float) -> void:
	var f := session.framing(_view_size())
	var k := 1.0 - exp(-CAM_RATE * dt)
	_cam_pos = _cam_pos.lerp(f["center"], k)
	_zoom = exp(lerpf(log(_zoom), log(f["zoom"]), k))
	if cam != null:
		cam.position = _cam_pos
		cam.zoom = Vector2(_zoom, _zoom)


func _update_hud() -> void:
	if _bar == null:
		return
	var vp := _view_size()
	_schem[0].position = Vector2(10.0, 10.0)
	_schem[1].position = Vector2(vp.x - Schematic.PANEL.x - 10.0, 10.0)
	_banner.position = Vector2((vp.x - _banner.size.x) / 2.0, vp.y * 0.28)
	_hint.position = Vector2((vp.x - _hint.size.x) / 2.0, 10.0)
	var text: String = session.end_text()
	if text == "" and _clock < _note_until:
		text = _note
	_banner.text = text
	_banner.visible = text != ""
	var co = session.arena.ships[Session.PLAYER]
	_hint.text = "%s\nenemy %d px   speed %d px/s" % [HINT, session.distance(), co.flight.vel.length()]


# --- effects ----------------------------------------------------------------------------------------

func _add_fx(f: Dictionary) -> void:
	f["t0"] = _clock
	_fx.append(f)
	if _fx.size() > MAX_FX:
		_fx.pop_front()


func _age_fx(_dt: float) -> void:
	var live: Array = []
	for f in _fx:
		if _clock - f["t0"] < f["life"]:
			live.append(f)
	_fx = live
	if session != null and _frame % 2 == 0:  # missiles smoke
		for p in session.arena.projectiles:
			if p["w"]["kind"] == "missile":
				_add_fx({"k": "puff", "pos": p["pos"] - p["vel"].normalized() * 8.0, "vel": -p["vel"].normalized() * 20.0, "life": 0.5, "r": 3.0, "grow": 14.0, "color": Color("#c9a37a", 0.55)})


func _consume_events() -> void:
	var arena = session.arena
	while _cursor < arena.events.size():
		_on_event(arena.events[_cursor])
		_cursor += 1


func _shot_color(owner: int, dtype: String) -> Color:
	return (PLAYER_SHOT if owner == Session.PLAYER else ENEMY_SHOT).get(dtype, Color.WHITE)


## An effect stuck to ship `idx` at the world point `pos`: it keeps its place on the hull as the ship moves.
func _on_ship(idx: int, pos: Vector2, f: Dictionary) -> void:
	f["ship"] = idx
	f["local"] = session.arena.world_to_local(idx, pos)
	_add_fx(f)


func _on_event(e: Dictionary) -> void:
	var arena = session.arena
	var pos: Vector2 = e["pos"]
	var idx: int = e["ship"]
	var n: Vector2 = e.get("n", Vector2.ZERO)
	var dir: Vector2 = e.get("dir", Vector2.ZERO)
	match e["type"]:
		"shot":
			if Art.fx("muzzle") != null:
				_add_fx({"k": "art", "name": "muzzle", "anchor": "muzzle", "pos": e["origin"], "angle": dir.angle() + PI / 2.0, "life": 0.14})
			else:
				_add_fx({"k": "flash", "pos": e["origin"], "life": 0.09, "r": 10.0, "color": _shot_color(idx, "energy" if e["kind"] in ["laser", "beam"] else "kinetic")})
		"beam":
			_add_fx({"k": "beam", "a": e["from"], "b": e["to"], "life": BEAM_LIFE, "color": _shot_color(idx, e["dtype"]),
				"kind": str(arena.weapons.def(str(e.get("weapon", "")))["kind"])})
		"hit":
			var big: bool = e["kind"] == "component"
			var col := Color("#ffb347") if big else Color("#ffe9a8")
			if e["dtype"] == "ion":
				col = Color("#b99bff")
			if big and Art.fx("explosion") != null:
				_on_ship(idx, pos, {"k": "art", "name": "explosion", "life": 0.5, "scale": 0.7})
			elif Art.fx("sparks") != null:
				_on_ship(idx, pos, {"k": "art", "name": "sparks", "life": 0.25, "scale": 0.7})
			else:
				_on_ship(idx, pos, {"k": "flash", "life": 0.22, "r": 18.0 if big else 11.0, "color": col})
			_sparks(pos, n, 7 if big else 4, col)
		"shield":
			var shot_dir := dir
			if Art.fx("shield_ripple") != null:
				_on_ship(idx, pos, {"k": "art", "name": "shield_ripple", "anchor": "impact", "life": 0.45, "scale": 1.5, "angle": (-shot_dir).angle() + PI / 2.0})
			else:
				_on_ship(idx, pos, {"k": "ring", "life": 0.55, "r": 70.0, "color": Color("#7fe4ff") if e.get("dtype", "") != "ion" else Color("#b99bff")})
			_on_ship(idx, pos, {"k": "flash", "life": 0.15, "r": 16.0, "color": Color("#bff2ff")})
			_sparks(pos, -shot_dir, 3, Color("#9fe8ff"))
		"deflect", "ricochet":
			var out := dir - 2.0 * dir.dot(n) * n if n != Vector2.ZERO else -dir
			var col := Color("#d6f3ff") if e["type"] == "deflect" else Color("#ffd27a")
			_add_fx({"k": "streak", "pos": pos, "dir": out, "len": 90.0, "life": 0.28, "color": col})
			_on_ship(idx, pos, {"k": "flash", "life": 0.12, "r": 9.0, "color": col})
		"breach":
			if Art.fx("explosion") != null:
				_on_ship(idx, pos, {"k": "art", "name": "explosion", "life": 0.6, "scale": 1.0})
			else:
				_on_ship(idx, pos, {"k": "flash", "life": 0.3, "r": 22.0, "color": Color("#ff5a3a")})
			for i in 6:
				var d := (n if n != Vector2.ZERO else Vector2.from_angle(_rng.randf() * TAU)).rotated(_rng.randf_range(-0.9, 0.9))
				_add_fx({"k": "puff", "pos": pos, "vel": d * _rng.randf_range(40.0, 110.0), "life": _rng.randf_range(0.6, 1.0), "r": 8.0, "grow": 26.0, "color": Color("#b9bfc9", 0.6)})
		"disable":
			if Art.fx("sparks") != null:
				_on_ship(idx, pos, {"k": "art", "name": "sparks", "life": 0.35, "scale": 1.5})
			else:
				_on_ship(idx, pos, {"k": "flash", "life": 0.3, "r": 24.0, "color": Color("#ffe14a")})
			_sparks(pos, Vector2.ZERO, 10, Color("#ffe14a"))
		"ignite":
			for i in 3:
				_add_fx({"k": "puff", "pos": pos, "vel": Vector2.from_angle(_rng.randf() * TAU) * 30.0, "life": 0.7, "r": 6.0, "grow": 16.0, "color": Color("#ff7a2a", 0.6)})
		"overcharge":
			_on_ship(idx, pos, {"k": "ring", "life": 0.8, "r": 260.0, "color": Color("#ffd24a")})
		"wreck":
			_on_ship(idx, pos, {"k": "ring", "life": 1.1, "r": 420.0, "color": Color("#ffb347")})
			if Art.fx("explosion") != null:
				_on_ship(idx, pos, {"k": "art", "name": "explosion", "life": 1.2, "scale": 4.0})
			else:
				_on_ship(idx, pos, {"k": "flash", "life": 0.6, "r": 90.0, "color": Color("#ffd9a0")})
			_sparks(pos, Vector2.ZERO, 36, Color("#ffcf7a"))
			for i in 10:
				_add_fx({"k": "puff", "pos": pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 120.0), "vel": Vector2.from_angle(_rng.randf() * TAU) * 40.0, "life": 1.4, "r": 24.0, "grow": 50.0, "color": Color("#8a8f99", 0.5)})


## `count` sparks flying out from `pos`, mostly along `bias` (any direction when zero).
func _sparks(pos: Vector2, bias: Vector2, count: int, col: Color) -> void:
	for i in count:
		var d := bias.rotated(_rng.randf_range(-1.0, 1.0)) if bias != Vector2.ZERO else Vector2.from_angle(_rng.randf() * TAU)
		_add_fx({"k": "spark", "pos": pos, "vel": d * _rng.randf_range(90.0, 320.0), "life": _rng.randf_range(0.2, 0.5), "color": col})


# --- drawing ----------------------------------------------------------------------------------------

func _draw_stars() -> void:
	var c := _stars_node
	var vp := _view_size()
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color("#04060b"))
	var speed := _star_speed()
	for s in _stars:
		var depth: float = s[1]
		var p: Vector2 = s[0] * vp + _star_drift * depth
		p = Vector2(fposmod(p.x, vp.x), fposmod(p.y, vp.y))
		var col := Color(1, 1, 1, 0.25 + 0.6 * depth)
		c.draw_circle(p, s[2] * depth, col)
		if speed.length() > 30.0:  # streaks along the way the stars slide
			c.draw_line(p, p + speed * depth * 0.03, Color(col, col.a * 0.5), s[2] * depth * 0.8)


func _star_speed() -> Vector2:
	return -session.arena.ships[Session.PLAYER].flight.vel * 0.4 if session != null else Vector2.ZERO


## Screen pixels to world units at the current zoom.
func _px() -> float:
	return 1.0 / maxf(cam.zoom.x if cam != null else 1.0, 0.01)


func _draw_fx() -> void:
	if session == null:
		return
	var c := _fx_node
	var arena = session.arena
	var px := _px()
	_glow_quads = []
	if session.state() != "lost":
		_draw_aim(c, px)
	for f in _fx:
		_draw_one(c, f, px)
	for p in arena.projectiles:
		_draw_shot(c, p, px)
	if _glow != null:
		_glow.show_quads(_glow_quads)


func _fx_pos(f: Dictionary) -> Vector2:
	if f.has("ship"):
		return session.arena.local_to_world(f["ship"], f["local"])
	return f["pos"] + f.get("vel", Vector2.ZERO) * (_clock - f["t0"])


func _draw_one(c: Node2D, f: Dictionary, px: float) -> void:
	var age: float = (_clock - f["t0"]) / f["life"]
	var col: Color = f["color"]
	var fade := 1.0 - age
	match f["k"]:
		"art":
			_draw_art_fx(c, f, age, px)
		"beam":
			if _draw_art_beam(c, f, age, px):
				return
			c.draw_line(f["a"], f["b"], Color(col, 0.25 * fade), 9.0 * px)
			c.draw_line(f["a"], f["b"], Color(col, 0.9 * fade), 3.0 * px)
			c.draw_line(f["a"], f["b"], Color(1, 1, 1, fade), 1.2 * px)
		"flash":
			var p := _fx_pos(f)
			c.draw_circle(p, f["r"] * px * (0.5 + 0.6 * age), Color(col, 0.35 * fade))
			c.draw_circle(p, f["r"] * px * 0.45 * fade, Color(1, 1, 1, 0.8 * fade))
		"ring":
			var p := _fx_pos(f)
			var radius: float = f["r"] * px * (0.1 + 0.9 * age) if f["r"] < 100.0 else f["r"] * (0.15 + 0.85 * age)
			c.draw_arc(p, radius, 0.0, TAU, 40, Color(col, 0.8 * fade), 2.5 * px, true)
		"spark":
			var p := _fx_pos(f)
			var v: Vector2 = f["vel"]
			c.draw_line(p, p - v.normalized() * (10.0 + 14.0 * fade) * px, Color(col, fade), 2.0 * px)
		"puff":
			var p := _fx_pos(f)
			var smoke = Art.fx("smoke")
			if smoke != null:
				_blit_art(c, smoke, smoke.life_frame(age), p, 0.0, _art_k(px) * (0.5 + float(f["r"]) / 24.0 + age * 0.5), "", Color(1, 1, 1, fade))
				return
			c.draw_circle(p, (f["r"] + f["grow"] * age) * px * 0.5 if f["r"] < 4.0 else f["r"] + f["grow"] * age, Color(col, col.a * fade))
		"streak":
			var from: Vector2 = f["pos"] + f["dir"] * 18.0 * age
			c.draw_line(from, from + f["dir"] * f["len"] * (0.4 + 0.6 * age), Color(col, 0.9 * fade), 3.0 * px)


func _draw_shot(c: Node2D, p: Dictionary, px: float) -> void:
	var w: Dictionary = p["w"]
	var col := _shot_color(p["owner"], w["damage_type"])
	var at: Vector2 = p["pos"]
	var v: Vector2 = p["vel"]
	var d := v.normalized()
	var art = Art.projectile(str(w["kind"]))
	if art != null:
		_draw_art_shot(c, art, at, d, px)
		return
	match w["kind"]:
		"missile":
			var side := d.rotated(PI / 2.0)
			c.draw_line(at - d * 40.0 * px, at, Color(col, 0.35), 4.0 * px)
			c.draw_colored_polygon(PackedVector2Array([at + d * 9.0 * px, at - d * 6.0 * px + side * 5.0 * px, at - d * 6.0 * px - side * 5.0 * px]), col)
			c.draw_circle(at - d * 7.0 * px, 3.0 * px, Color("#ffd27a"))
		"flak":
			c.draw_line(at - d * 12.0 * px, at, Color(col, 0.5), 2.0 * px)
			c.draw_circle(at, 2.5 * px, col)
		_:
			c.draw_line(at - d * 30.0 * px, at, Color(col, 0.5), 4.0 * px)
			c.draw_circle(at, 9.0 * px, Color(col, 0.22))
			c.draw_circle(at, 4.4 * px, col)
			c.draw_circle(at, 2.0 * px, Color.WHITE)


## One frame `f` of `sheet`, turned by `angle` with its anchor pixel `anchor` (a name from the
## sheet's anchors; the frame's middle without one) at `at`, `k` world px per source px, and its
## glow layer (frame `f` of the glow sheet) on the additive layer.
func _blit_art(c: Node2D, sheet, f: int, at: Vector2, angle: float, k: float, anchor := "", mod := Color.WHITE) -> void:
	var pin: Vector2 = sheet.anchors[anchor] + Vector2(0.5, 0.5) if sheet.anchors.has(anchor) else Vector2(sheet.frame) / 2.0
	var xf := Transform2D(angle, at)
	var dest := Rect2(-pin * k, Vector2(sheet.frame) * k)
	c.draw_set_transform_matrix(xf)
	c.draw_texture_rect_region(sheet.texture, dest, sheet.region(f), mod)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	var g = sheet.glow
	if g != null:
		TileArt.emit(c, _glow_quads if _glow != null else null, {"tex": g.texture, "rect": Rect2(dest.position + g.offset * k, Vector2(g.frame) * k),
			"src": g.region(clampi(f, 0, g.count - 1)), "xf": xf, "mod": mod})


## Screen px per source px of the effect and projectile art, in world px: at least ART_SCALE on screen.
func _art_k(px: float) -> float:
	return maxf(ART_SCALE, ART_SCALE * px)


## A projectile sprite at `at` flying along `d` (the art faces up, plus its orientation_rot quarter
## turns), its "head" (else "center") pixel on `at`, looping its own animation.
func _draw_art_shot(c: Node2D, art, at: Vector2, d: Vector2, px: float) -> void:
	_blit_art(c, art, art.loop_frame(_clock), at, d.angle() + PI / 2.0 + art.orientation_rot * PI / 2.0, _art_k(px), "head" if art.anchors.has("head") else "center")


## An effect (art/fx/<name>) at the fx's place, played once over its life, turned by f["angle"], its
## f["anchor"] pixel (else the middle) on the spot.
func _draw_art_fx(c: Node2D, f: Dictionary, age: float, px: float) -> void:
	var art = Art.fx(str(f["name"]))
	if art != null:
		_blit_art(c, art, art.life_frame(age), _fx_pos(f), float(f.get("angle", 0.0)), _art_k(px) * float(f.get("scale", 1.0)), str(f.get("anchor", "")))


## The pieces a beam `length` px long is tiled from when one tile is `tile` px: [{"from": distance
## from the start, "len": px}], all full tiles but the last.
static func beam_pieces(length: float, tile: float) -> Array:
	var out := []
	var done := 0.0
	while done < length - 0.001 and tile > 0.0:
		var h := minf(tile, length - done)
		out.append({"from": done, "len": h})
		done += h
	return out


## A hitscan beam in art/projectiles/<kind> (it faces up, tiles along y), laid from `a` to `b` out of
## whole tiles and a cut last one (the sprite's head end), with its glow, and the kind's impact flare
## at `b`. False when there is no such art.
func _draw_art_beam(c: Node2D, f: Dictionary, age: float, px: float) -> bool:
	var art = Art.projectile(str(f.get("kind", "")))
	if art == null:
		return false
	var a: Vector2 = f["a"]
	var b: Vector2 = f["b"]
	var k := _art_k(px)
	var fade := 1.0 - age
	var xf := Transform2D((b - a).angle() + PI / 2.0, a)
	var frame: int = art.loop_frame(_clock)
	var w := float(art.frame.x) * k
	var g = art.glow
	var out = _glow_quads if _glow != null else null
	c.draw_set_transform_matrix(xf)
	for p in beam_pieces(a.distance_to(b), float(art.frame.y) * k):
		var rows: float = p["len"] / k  # source rows of this piece, from the head end of the frame
		var at := Vector2(-w / 2.0, -(p["from"] + p["len"]))
		c.draw_texture_rect_region(art.texture, Rect2(at, Vector2(w, p["len"])), Rect2(art.region(frame).position, Vector2(art.frame.x, rows)), Color(1, 1, 1, fade))
		if g != null:
			TileArt.emit(c, out, {"tex": g.texture, "rect": Rect2(at + Vector2(g.offset.x * k, 0.0), Vector2(float(g.frame.x) * k, p["len"])),
				"src": Rect2(g.region(clampi(frame, 0, g.count - 1)).position, Vector2(g.frame.x, rows)), "xf": xf, "mod": Color(1, 1, 1, fade)})
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	var hit = Art.projectile(str(f["kind"]) + "_impact")
	if hit != null:
		_blit_art(c, hit, hit.life_frame(age), b, 0.0, k, "center", Color(1, 1, 1, fade))
	return true


## The player's weapons: a faint wedge for the arc, a line to the aim point from each that can fire
## (dim while it cools), grey ones whose arc misses the aim point, and the crosshair.
func _draw_aim(c: Node2D, px: float) -> void:
	var arena = session.arena
	var co = arena.ships[Session.PLAYER]
	var aim := _aim()
	for w in session.weapons():
		var m: Dictionary = co.mounts[w["uid"]]
		var def: Dictionary = arena.weapons.def(m["id"])
		var origin: Vector2 = arena.local_to_world(Session.PLAYER, m["pos"])
		var st: Dictionary = session.slot_state(w["uid"], aim)
		var can: bool = st["status"] in ["ready", "cooling down"]
		var col: Color = GROUP_COLORS.get(w["group"], Color.WHITE) if can else GREY
		var arc := float(def["arc"])
		var reach := float(def["range"])
		if arc < 360.0:
			var axis: Vector2 = (m["pos"] - co.pivot).rotated(co.flight.angle)
			if axis.length_squared() < 1e-6:
				axis = Vector2.UP
			var a0 := axis.angle() - deg_to_rad(arc * 0.5)
			var pts := PackedVector2Array([origin])
			for i in 17:
				pts.append(origin + Vector2.from_angle(a0 + deg_to_rad(arc) * i / 16.0) * reach)
			c.draw_colored_polygon(pts, Color(col, 0.06 if can else 0.035))
			c.draw_line(origin, pts[1], Color(col, 0.22), 1.0 * px)
			c.draw_line(origin, pts[-1], Color(col, 0.22), 1.0 * px)
		else:
			c.draw_arc(origin, 40.0 * px, 0.0, TAU, 24, Color(col, 0.18), 1.0 * px)
		var to := aim - origin
		var end := origin + to.limit_length(reach)
		if can:
			c.draw_line(origin, end, Color(col, 0.7 if st["status"] == "ready" else 0.28), 1.6 * px)
		else:
			c.draw_line(origin, origin + to.normalized() * 36.0 * px, Color(col, 0.55), 1.4 * px)  # a short grey stub
	c.draw_arc(aim, 10.0 * px, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 1.5 * px)
	c.draw_line(aim - Vector2(16, 0) * px, aim - Vector2(5, 0) * px, Color(1, 1, 1, 0.8), 1.5 * px)
	c.draw_line(aim + Vector2(16, 0) * px, aim + Vector2(5, 0) * px, Color(1, 1, 1, 0.8), 1.5 * px)
	c.draw_line(aim - Vector2(0, 16) * px, aim - Vector2(0, 5) * px, Color(1, 1, 1, 0.8), 1.5 * px)
	c.draw_line(aim + Vector2(0, 16) * px, aim + Vector2(0, 5) * px, Color(1, 1, 1, 0.8), 1.5 * px)
