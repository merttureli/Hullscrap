extends Node2D
## Combat mode on screen: press K in play mode to meet the test pirate. The camera zooms out to frame
## both ships, which are drawn at their arena transforms (ship_view.gd); the interior build mode
## and the walking crew are put away. W/S throttle, A/D turn, the mouse aims, LMB fires group 1 (lasers,
## bolts, beams), RMB group 2 (missiles, flak), Q group 3 (whatever the player put there), 1-9 a single weapon, Shift, Space and E use the engine, shield and utility abilities,
## the arrow keys shift the shield balance one step toward the bow, stern, port or starboard and End makes it even,
## Esc leaves once the enemy is wrecked or 4000 px away, R restarts when you are wrecked.
## The rules live in combat_session.gd; this node reads input, runs the session, and draws the aim
## wedges, shots, impacts and the HUD (schematics, weapon bar). Shots, beams and effects are drawn from
## art/projectiles and art/fx (scripts/view/art.gd) when that art exists, else as code-drawn placeholders.
## In sector space (the Sector node, sector_view.gd, gives the place: fight_place) the fight runs right there, in the
## sector's px: the sector's sky stays, the fight ends by itself WRECK_LINGER seconds after it is decided (won, captured,
## spared, escaped; a loss waits for R) or when the enemy is more than LEAVE_DISTANCE px away, it holds while the map or
## an event panel is open, and J opens the map to spool the jump drive (the campaign's, held while the enemy is within
## 2,000 px).

const DroneView = preload("res://scripts/combat/drone_view.gd")
const LimpetView = preload("res://scripts/combat/limpet_view.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const ImpactFx = preload("res://scripts/combat/impact_fx.gd")
const EffectFx = preload("res://scripts/combat/effect_fx.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Intent = preload("res://scripts/combat/intent.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const TestFights = preload("res://scripts/combat/test_fights.gd")
const TestFightPanel = preload("res://scripts/ui/test_fight_panel.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")
const Art = preload("res://scripts/view/art.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")
const GlowLayer = preload("res://scripts/view/glow_layer.gd")
const JumpBar = preload("res://scripts/ui/jump_bar.gd")
const Schematic = preload("res://scripts/ui/schematic.gd")
const Skulls = preload("res://scripts/ui/skulls.gd")
const WeaponBar = preload("res://scripts/ui/weapon_bar.gd")
const GunBadges = preload("res://scripts/ui/gun_badges.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const HazardBar = preload("res://scripts/ui/hazard_bar.gd")
const Audio = preload("res://scripts/audio/audio.gd")
const Ambience = preload("res://scripts/audio/ambience.gd")

const PLAYER_SHOT := {"energy": Color("#7dffe8"), "kinetic": Color("#ffe07a"), "explosive": Color("#ffb04a"), "ion": Color("#b99bff")}
const ENEMY_SHOT := {"energy": Color("#ff6a4a"), "kinetic": Color("#ff9a6a"), "explosive": Color("#ff5a3a"), "ion": Color("#b99bff")}
const GREY := Color("#7a8494")
const BEAM_LIFE := 0.15
const BLOCK_FLASH := 0.45  ## seconds a broken block flashes
const MAX_FX := 500
const SLOW_EASE_S := 0.3  ## real seconds the camera takes to zoom to your ship (Tab slow-down) and back
const CAM_RATE_EASE := 14.0  ## camera settle rate while it eases (the ease itself takes SLOW_EASE_S)
const CAM_RATE := 3.0  ## how fast the camera settles, 1/s
const SHAKE_DECAY := 7.0  ## how fast a screen shake dies away, 1/s
const STAR_COUNT := 220
const ART_SCALE := 2.0  ## fewest screen px per source px for the effect and projectile art
const HINT := "Mouse steers   W/S throttle   A/D strafe   LMB/RMB/Q fire groups   1-9 one gun   T auto   Shift/Space/E abilities   Esc leave"

const SHIELD_HINT := "   arrows shift the shield balance   End even"
const ENEMY_JUMP_DB := -8.0  ## the enemy's jump drive firing, against the player's own jump
const MISSILE_LOOPS := 3  ## missiles in flight that each get their whoosh (the nearest ones are heard anyway)
const WRECK_LINGER := 3.0  ## seconds a decided sector fight goes on showing its end before it ends by itself

## Emitted when the fight is left: {state ("won", "captured", "spared", "escaped", "fled" or "lost"), enemy (its Ship),
## threat (the enemy's skulls, 1-5), offer ({item: count}, only when "spared"), in_sector, pose ({pos, vel, angle, ang_vel}: where the player's ship is now), enemy_pos}.
signal finished(result: Dictionary)

var sim: Node  ## ShipSim
var build: Node  ## BuildMode (put away during the fight)
var crew: Node  ## crew view (put away too)
var cam: Camera2D
var sector: Node  ## the Sector node (sector_view.gd), if the scene has one
var active := false
var in_sector := false  ## this fight runs in the sector (see the top)
var session: Session
## Scripts and tests drive these instead of the keyboard and mouse.
var aim_override: Variant = null  ## a world point, or null for the mouse
var input_override: Variant = null  ## {"throttle", "turn"}, or null for W/S/A/D
var hold_override := {}  ## fire group -> true: held down as if by the mouse

var _page: Control  ## the test-fight page (K in play mode, test_fight_panel.gd); null in a bare view, where K starts the test pirate at once
var _test := {}  ## the test fight on: {ship_name, enemy_name, stash}; {} for an ordinary fight
var _views: Array = []
var _fx_node: Node2D
var _glow: Node2D  # additive layer inside _fx_node for the glow of projectiles and effects
var _glow_quads: Array = []
var _stars_node: Node2D
var _stars: Array = []  # [unit position, depth, radius]
var _star_drift := Vector2.ZERO
var _fx: Array = []
var _hold_slot := 0  ## the weapon slot of a limpet or pod kit whose key is held: its predicted path shows, and releasing the key throws it (limpet_view.gd)
var _trails2 := {}  # limpet or pod id -> its spark dots (limpet_view.gd)
var _trails := {}  # drone id -> its thruster puffs (drone_view.gd)
var _cursor := 0
var _clock := 0.0
var _frame := 0
var _cam_pos := Vector2.ZERO
var _zoom := 0.5
var _slow_mix := 0.0  # 0 = both ships framed, 1 = your ship framed (Tab slow-down); eased in real time
var _shake := 0.0  # screen px of camera shake left (a ram kicks it)
var _saved_cam := {}
var _rng := RandomNumberGenerator.new()  # visual only
var _schem: Array = []
var _bar: Control
var badges := GunBadges.new()  ## the chips on your guns, shared with the weapon bar
var _swallow := 0  ## a mouse button whose press was used on the weapon bar: it fires nothing until released
var _bar_extras: Control  # over the weapon bar: each turret's hit chance and whether it autofires
var _banner: Label
var _jump_bar: Control  # under the enemy schematic while it flees
var _hazard_bar: Control  # the fight's hazard line, under the hint (hazards.gd)
var _hint: Label
var _note := ""
var _note_until := 0.0
var _starfield: Node
var _over_t := 0.0  # seconds the fight has been over (the enemy wrecked, captured, spared or gone), in a sector fight
var _snd_state := "fighting"  # the session's state at the last frame, for the victory and defeat stings
var _layers := [-1, -1]  # whole shield layers up per ship at the last frame (-1 = not read yet), for the shield sounds
var _morale_seen := ""  # the enemy's morale state at the last frame, for the surrender chirp
var _hailing := false  # the enemy's hail was on the banner at the last look, for the hail chirp


func _ready() -> void:
	sim = get_node_or_null("../ShipSim")
	build = get_node_or_null("../BuildMode")
	crew = get_node_or_null("../Crew")
	cam = get_node_or_null("../Camera2D")
	_starfield = get_node_or_null("../Space/Starfield")
	sector = get_node_or_null("../Sector")
	_rng.seed = 4242
	_make_stars()
	_make_hud()
	set_process(true)


## A page or a test fight is up: the sector holds still (sector_view.gd) so the run stands as it was.
var testing: bool:
	get:
		return not _test.is_empty() or (_page != null and _page.visible)


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
	_page = TestFightPanel.new()
	_page.view = self
	layer.add_child(_page)
	_bar_extras = Control.new()
	_bar_extras.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_extras.draw.connect(_draw_bar_extras)
	_bar.add_child(_bar_extras)
	_banner = Label.new()
	_banner.size = Vector2(1100.0, 60.0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 30)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.visible = false
	layer.add_child(_banner)
	_jump_bar = JumpBar.new()
	layer.add_child(_jump_bar)
	_hazard_bar = HazardBar.new()
	layer.add_child(_hazard_bar)
	_hint = Label.new()
	_hint.size = Vector2(1000.0, 44.0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color("#9fb6d0"))
	_hint.visible = false
	layer.add_child(_hint)


# --- entering and leaving ------------------------------------------------------------------------

## Start a fight with the ship in `path` (the test pirate by default). "" when it began, else why not. `opts`:
## {enemy_pos}: where the enemy appears in a sector fight (else ahead of the ship). {test: {player, ship_name, enemy_name}}: a test fight (the page): `player`
## (a copy or a test ship) fights in the player's place, the real ship stays out of the simulation and out of the sector, and nothing reaches the run.
func enter(path := Session.PIRATE_PATH, opts := {}) -> String:
	if active:
		return "already fighting"
	var player = sim.player_ship() if sim != null else null
	if player == null:
		return "no ship"
	var enemy: Ship = Session.load_ship(path)
	if enemy == null:
		return "cannot load " + path
	var test: Dictionary = opts.get("test", {})
	if not test.is_empty():
		_test = {"ship_name": test["ship_name"], "enemy_name": test["enemy_name"], "stash": sim.lend_player(test["player"])}
		player = test["player"]
	sim.ships.append(enemy)
	var place: Dictionary = {} if not test.is_empty() else (sector.fight_place(opts.get("enemy_pos")) if sector != null and sector.has_method("fight_place") else {})
	in_sector = not place.is_empty()
	_over_t = 0.0
	session = Session.new()
	session.start(player, enemy, enemy.rng_seed, place)
	_snd_state = "fighting"
	_layers = [-1, -1]
	_morale_seen = ""
	_hailing = false
	active = true
	_cursor = 0
	_fx.clear()
	_note = ""
	_star_drift = Vector2.ZERO
	_slow_mix = 0.0
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
		_schem[1].threat = session.threat
		_schem[1].look = enemy.get_meta("style", {})
		_bar.bind(session, _aim, badges)
	_show_hud(true)
	return ""


## Leave the fight: the enemy goes, the interior comes back, the camera returns.
func leave() -> void:
	if not active:
		return
	var foe = session.arena.ships[Session.ENEMY]
	var mine = session.arena.ships[Session.PLAYER]
	var test_row := {}
	if not _test.is_empty():
		var st: String = session.state()
		test_row = TestFights.result_row(str(_test["ship_name"]), str(_test["enemy_name"]), TestFights.ending_text(st if st != "fighting" else "fled", session.morale.state == "offering", session.jump_ready()),
			session.arena.time(), Structure.structure_fraction(mine), Structure.structure_fraction(foe))
	var result := {"state": session.state() if session.state() != "fighting" else "fled", "enemy": foe.ship,
		"in_sector": in_sector, "pose": {"pos": mine.flight.pos, "vel": mine.flight.vel, "angle": mine.flight.angle, "ang_vel": mine.flight.ang_vel}, "enemy_pos": foe.flight.pos, "threat": session.threat}
	if result["state"] == "spared":
		result["offer"] = session.morale.offer.duplicate()
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
	_shake = 0.0
	if cam != null:
		cam.offset = Vector2.ZERO
	if cam != null and not _saved_cam.is_empty():
		cam.position = _saved_cam["pos"]
		cam.zoom = _saved_cam["zoom"]
	active = false
	session = null
	if not test_row.is_empty():  # a test fight tells nobody but the page: the real ship comes back, the wreck and the loot go nowhere
		sim.return_player(_test["stash"])
		_test = {}
		_page.show_result(test_row)
		return
	finished.emit(result)


## After being wrecked: back to the interior with the starter ship reloaded.
func restart() -> void:
	if not active or session.state() != "lost":
		return
	var was_test := not _test.is_empty()
	leave()
	if was_test:
		return  # (a test fight back to the page: nothing of the run to reload)
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
		_starfield.visible = not away or in_sector  # a sector fight keeps the sector's sky
	if _stars_node != null:
		_stars_node.visible = away and not in_sector


func _show_hud(on: bool) -> void:
	for s in _schem:
		s.visible = on
	if _bar != null:
		_bar.visible = on
		_hint.visible = on
		_banner.visible = false
		_jump_bar.bind(session if on else null)
		_hazard_bar.bind(session.arena if on else null)


# --- input ----------------------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if not active:
			if e.keycode == KEY_K and not e.ctrl_pressed and build != null and not build.combat:  # (build.combat with no fight: the soldier is aboard another vessel)
				if build.build_on:
					build.message = "Press B for play mode, then K to fight"
				elif _page != null:
					_page.open("rammer" if e.shift_pressed else "")
				else:
					var why := enter(Session.RAMMER_PATH if e.shift_pressed else Session.PIRATE_PATH)  # Shift+K: the Rustfang rammer
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
					_say("Can't leave: wreck them, get %d px away, or press J to jump" % Session.LEAVE_DISTANCE)
			KEY_J when in_sector:
				if build != null and build.get("drift") != null:
					build.drift.open()  # pick where to: the jump drive spools there (map_view.gd click_node)
			KEY_J:
				var why_jump: String = session.start_jump()
				var held: String = session.jump_hold()
				_say(why_jump if why_jump != "" else (held if held != "" else "Jumping in %d s. Stay alive" % int(Session.JUMP_SPOOL)))
			KEY_R:
				restart()
			KEY_Y:
				var why_y: String = session.accept_surrender()
				if why_y != "":
					_say(why_y)
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
				var why: String = session.shift_shield({KEY_UP: "up", KEY_DOWN: "down", KEY_LEFT: "left", KEY_RIGHT: "right"}[e.keycode])
				if why != "":
					_say("Shield balance: " + why)
				else:
					Audio.fx(self, "shield_shift")
			KEY_END:
				session.reset_shield()
				Audio.fx(self, "shield_shift")
			KEY_Q when not e.ctrl_pressed and not e.meta_pressed:
				session.fire_group(3, _aim())  # (the rest of the hold is in _process)
			KEY_T:
				_say("Auto guns: autofire %s" % ("on" if session.toggle_autofire() else "off"))
			KEY_SPACE:
				var why := session.arena.overcharge(Session.PLAYER)
				if why != "":
					_say("Overcharge: " + why)
			KEY_G:  # the selected crew member's ability (the crew bar shows how it went)
				if crew != null and crew.has_method("press_ability"):
					crew.press_ability()
			_:
				var n: int = e.keycode - KEY_1
				if n >= 0 and n <= 8:
					if session.slot_thrown(n + 1):
						_hold_slot = n + 1  # a thrown kit: hold to aim (the path shows), release to throw
					else:
						session.fire_slot(n + 1, _aim())
	elif e is InputEventKey and not e.pressed and _hold_slot > 0 and e.keycode - KEY_1 == _hold_slot - 1:
		var slot := _hold_slot
		_hold_slot = 0
		if active:
			var why: String = "" if session.fire_slot(slot, _aim()) else "can't throw that now"
			if why != "":
				_say(why)
			_handled()
	elif active and e is InputEventMouseMotion and _bar != null and not _bar.drag.is_empty():
		_bar.motion(e.position - _bar.position)  # a slot in hand follows the mouse
		_handled()
	elif active and e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _bar != null and not _bar.drag.is_empty():
		var moved: int = _bar.release(e.position - _bar.position)  # dropped on a section, or let go where it was
		if _bar.last_note != "":
			_say(_bar.last_note)
		elif moved >= 0:
			_say("Moved to %s" % GunBadges.style({"group": moved})["label"])
		_handled()
	elif active and e is InputEventMouseButton and e.pressed:
		if _bar != null and _bar.visible and e.button_index == MOUSE_BUTTON_LEFT and (_bar.head_click(e.position - _bar.position) or (e.alt_pressed and _bar.alt_click(e.position - _bar.position))):
			_swallow = e.button_index  # a click on a group's header (Ripple / Volley) or an Alt+click on a gun (piercing rounds) does not fire
			_say(_bar.last_note)
			_handled()
			return
		if _bar != null and _bar.visible and e.button_index == MOUSE_BUTTON_LEFT and _bar.grab(e.position - _bar.position, e.button_index):
			_swallow = e.button_index  # a left press on a slot takes it in hand (drag it to another section), it does not fire
			_handled()
			return
		if _bar != null and _bar.visible and e.button_index == MOUSE_BUTTON_RIGHT and _bar.click(e.position - _bar.position, e.button_index):
			_swallow = e.button_index  # a right-click on a slot cycles that gun's group, it does not fire
			if _bar.last_note != "":
				_say(_bar.last_note)
			_handled()
			return
		if e.button_index == MOUSE_BUTTON_LEFT:
			session.fire_group(1, _aim())
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			session.fire_group(2, _aim())
		elif e.button_index == MOUSE_BUTTON_MIDDLE:
			middle_click(e)


## A middle click in a fight: on your schematic it sends the crew to the room under the cursor, on your ship in the world likewise;
## anywhere else nothing happens. Returns what the crew bar said ("" for none).
func middle_click(e: InputEventMouseButton) -> String:
	for i in _schem.size():
		var p: Vector2 = _schem[i].make_input_local(e).position
		if _schem[i].visible and Rect2(Vector2.ZERO, Schematic.PANEL).has_point(p):
			return order_from_map(p) if i == Session.PLAYER else ""
	return order_at_world(make_input_local(e).position)


## Which ship has a built cell under the world point `world`: {ship (arena index), local (fractional grid point), cell (Vector2i)}, {} for open space.
static func ship_cell(arena, world: Vector2) -> Dictionary:
	for i in arena.ships.size():
		var local: Vector2 = arena.world_to_local(i, world)
		var cell := Vector2i(floori(local.x), floori(local.y))
		if arena.ships[i].ship.grid.tiles.has(cell):
			return {"ship": i, "local": local, "cell": cell}
	return {}


## Order the crew to the world point `world` if it is on your ship (the crew view's middle-click order: a group splits the
## room's jobs, one crew member walks there), and flash the room. Off your ship it does nothing. Returns the crew bar's text.
func order_at_world(world: Vector2) -> String:
	var hit := ship_cell(session.arena, world)
	if hit.is_empty() or int(hit["ship"]) != Session.PLAYER:
		return ""
	return _order(hit["local"], false)


## Order the crew to the cell of your schematic under `p` (the panel's px), if there is one; flash its room on the map.
func order_from_map(p: Vector2) -> String:
	var at = Schematic.cell_under(session.arena.ships[Session.PLAYER].ship, p)
	return "" if at == null else _order(at, true)


func _order(local: Vector2, on_map: bool) -> String:
	var text := ""
	if crew != null and crew.has_method("order_at"):
		text = str(crew.order_at(local))
	var ship = session.arena.ships[Session.PLAYER].ship
	var cell := Vector2i(floori(local.x), floori(local.y))
	var room: int = ship.atmosphere.room_of.get(cell, -1)
	var cells: Array = ship.atmosphere.rooms[room]["cells"] if room >= 0 and room < ship.atmosphere.rooms.size() else [cell]
	var target = _schem[Session.PLAYER] if on_map and not _schem.is_empty() else (_views[Session.PLAYER] if not _views.is_empty() else null)
	if target != null:
		target.flash_room(cells)
	return text


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
	var side := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))  # strafe with the mouse steering, turn with the keys
	return {"throttle": float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S)), "turn": side, "strafe": side}


# --- the frame --------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if active:
		frame(dt)


## One frame of the fight: read the helm, run the session, turn its events into effects, move the camera.
func frame(dt: float) -> void:
	if in_sector and _panel_open():
		return  # the map or an event is up: the fight holds
	_clock += dt
	_frame += 1
	var st: String = session.state()
	session.input = _helm() if st != "lost" else {"throttle": 0.0, "turn": 0.0, "strafe": 0.0}
	session.cursor = _aim()
	if st != "lost":
		if _swallow != 0 and not Input.is_mouse_button_pressed(_swallow):
			_swallow = 0
		for g in [1, 2, 3]:
			var down: bool = Input.is_key_pressed(KEY_Q) and not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_META) if g == 3 \
				else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT if g == 1 else MOUSE_BUTTON_RIGHT) and _swallow != (MOUSE_BUTTON_LEFT if g == 1 else MOUSE_BUTTON_RIGHT)
			badges.held[g] = hold_override.get(g, false) or down
			if badges.held[g]:
				session.fire_group(g, _aim())
		badges.auto_on = session.arena.autofire.get(Session.PLAYER, true)
		badges.world_hover = badges.gun_at(session, _aim(), cam.zoom.x if cam != null else 1.0)
	session.tick(dt)
	if session.jump_ready():
		Audio.fx(self, "jump_ready")
		leave()  # the jump drive has spooled: away
		return
	if in_sector:
		var st_now: String = session.state()
		_over_t = _over_t + dt if st_now not in ["fighting", "lost"] else 0.0
		if _over_t >= WRECK_LINGER or (st_now == "fighting" and session.distance() > Session.LEAVE_DISTANCE):
			leave()  # the end has been seen (a wreck, a capture, a deal, a jump), or the enemy is out of range
			return
	_consume_events()
	_sound_frame()
	_age_fx(dt)
	var player = session.arena.ships[Session.PLAYER]
	_star_drift -= player.flight.vel * dt * 0.4
	_move_camera(dt)
	_update_hud()
	if _fx_node != null:
		_fx_node.queue_redraw()
	if _bar_extras != null:
		_bar_extras.queue_redraw()
	if _stars_node != null:
		_stars_node.queue_redraw()


## Is the map of the Drift, or one of its panels, open over the fight?
func _panel_open() -> bool:
	var map = build.get("drift") if build != null else null
	return map != null and map.visible


func _move_camera(dt: float) -> void:
	dt /= maxf(Engine.time_scale, 0.01)  # (real time: the slow-down must not slow the camera)
	var slowed: bool = crew != null and crew.get("slow_banner") != null and crew.slow_banner.slow.on
	_slow_mix = move_toward(_slow_mix, 1.0 if slowed else 0.0, dt / SLOW_EASE_S)
	var f := blend_framing(session.framing(_view_size()), session.framing(_view_size(), 0.2, true), _slow_mix)
	var k := 1.0 - exp(-(CAM_RATE if _slow_mix <= 0.0 and not slowed else CAM_RATE_EASE) * dt)
	_cam_pos = _cam_pos.lerp(f["center"], k)
	_zoom = exp(lerpf(log(_zoom), log(f["zoom"]), k))
	if cam != null:
		cam.position = _cam_pos
		cam.zoom = Vector2(_zoom, _zoom)
		_shake *= exp(-SHAKE_DECAY * dt)
		cam.offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake / _zoom if _shake > 0.3 else Vector2.ZERO


## Between two framings ({center, zoom}): `t` 0 = `a`, 1 = `b`, eased; the zoom blends in logs.
static func blend_framing(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var e := smoothstep(0.0, 1.0, t)
	return {"center": a["center"].lerp(b["center"], e), "zoom": exp(lerpf(log(a["zoom"]), log(b["zoom"]), e))}


func _update_hud() -> void:
	if _bar == null:
		return
	var vp := _view_size()
	if not _views.is_empty() and crew != null and crew.has_method("selection"):
		_views[Session.PLAYER].marked = crew.selection()  # the selected crew get their rings on the ship
	_schem[0].position = Vector2(10.0, 10.0)
	_schem[1].position = Vector2(vp.x - Schematic.PANEL.x - 10.0, 10.0)
	_schem[0].intent = Intent.of(session.arena, session.ai, Session.PLAYER)
	_schem[1].reveal = TraitSet.reveals_enemy(session.arena.ships[Session.PLAYER].ship)  # a crew member with reveal_enemy: the enemy's crew show
	_banner.position = Vector2((vp.x - _banner.size.x) / 2.0, vp.y * 0.28)
	_hint.size.x = minf(1000.0, vp.x - 2.0 * (Schematic.PANEL.x + 24.0))  # between the two schematics
	_hint.position = Vector2((vp.x - _hint.size.x) / 2.0, 10.0)
	_jump_bar.position = _schem[1].position + Vector2(0.0, Schematic.PANEL.y + 6.0)
	var line := banner_line(session, _note if _clock < _note_until else "")
	var text: String = line["text"]
	var rated: bool = line["rated"]
	_banner.text = text
	_banner.visible = text != ""
	if rated:
		_banner.add_theme_color_override("font_color", Skulls.color(session.threat))
	else:
		_banner.remove_theme_color_override("font_color")
	var co = session.arena.ships[Session.PLAYER]
	_hint.text = "%s\nenemy %d px   speed %d px/s%s" % [HINT, session.distance(), co.flight.vel.length(), SHIELD_HINT if co.sectors > 1 and co.layers_cap > 0 else ""]


## The line of the banner: {text, rated (it is the threat rating, drawn in its colour)}. The end of the fight, then the threat
## rating, then a standing surrender offer or a fleeing enemy (a note must not hide those), the note (`note`, "" for none), the
## jump drive's hold and the rest of the enemy's morale.
static func banner_line(s: Session, note: String) -> Dictionary:
	var text: String = s.end_text()
	var rated := false
	if text == "":
		text = s.threat_banner()
		rated = text != ""
	if text == "" and s.morale.state in ["offering", "fleeing"]:
		text = s.morale.banner()
	if text == "":
		text = note
	if text == "" and s.jump_charge >= 0.0:
		text = s.jump_hold()
	if text == "":
		text = s.morale.banner()
	return {"text": text, "rated": rated}


## Under each turret's slot of the weapon bar: its hit chance against the enemy now (accuracy less the enemy's
## evasion) and whether the turrets fire by themselves (T).
func _draw_bar_extras() -> void:
	if session == null or _bar == null or not _bar.visible:
		return
	var lay: Dictionary = _bar.layout()
	var base := Vector2((_bar.size.x - lay["width"]) / 2.0, 0.0)
	var auto: bool = session.arena.autofire.get(Session.PLAYER, true)
	for sl in lay["slots"]:
		if not sl["w"]["turret"]:
			continue
		var st: Dictionary = session.slot_state(sl["w"]["uid"], _aim())
		var at: Vector2 = sl["rect"].position + base + Vector2(0.0, WeaponBar.SLOT.y + 10.0)  # under its slot
		var manual: bool = sl["w"]["group"] != 0  # a turret in LMB, RMB or Q fires on its button
		var text := "HIT %d%%  %s" % [roundi(float(st["hit"]) * 100.0), GunBadges.style(sl["w"])["label"] if manual else ("AUTO" if auto else "HOLD")]
		_bar_extras.draw_string(ThemeDB.fallback_font, at + Vector2(6.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WeaponBar.READY if auto or manual else WeaponBar.COOLING)


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


## The sounds that come from the fight's state rather than one event: the engine under the player's throttle, the victory and defeat
## stings when the fight is decided, a shield bubble going down or a layer coming back, a whoosh on each missile in flight, the fight's
## hazard as a loop, and the enemy's radio (its hail, its surrender).
func _sound_frame() -> void:
	var st: String = session.state()
	if st != _snd_state:
		_snd_state = st
		if st in ["won", "captured", "spared"]:
			Audio.cue(self, "victory")
		elif st == "lost":
			Audio.cue(self, "defeat")
	var mine = session.arena.ships[Session.PLAYER]
	if st != "lost" and not mine.wrecked:
		var drive := clampf(maxf(absf(float(session.input.get("throttle", 0.0))), 0.5 * absf(float(session.input.get("strafe", 0.0)))), 0.0, 1.0)
		Audio.fx_loop(self, "engine", "engine_loop", true, 0.2 + 0.8 * drive, 0.85 + 0.45 * drive)
	for i in 2:
		var co = session.arena.ships[i]
		var up: int = Shields.layers_up(co)
		if _layers[i] >= 0 and not co.wrecked:
			if _layers[i] > 0 and up == 0:
				_snd("shield_down", i, co.flight.pos)
			elif up > _layers[i]:
				_snd("shield_up", i, co.flight.pos)
		_layers[i] = up
	var n := 0
	for p in session.arena.projectiles:
		if n < MISSILE_LOOPS and str(p["w"]["kind"]) == "missile":
			Audio.fx_loop(self, "missile%d" % n, "missile_flight", true, 1.0 if p["owner"] == Session.PLAYER else 0.6, 1.0, p["pos"])
			n += 1
	var haz := Ambience.hazard_loop(str(session.arena.hazard.get("id", "")))
	if haz != "" and st == "fighting":
		Audio.fx_loop(self, "hazard", haz, true, 1.0, 1.0, null, 1.5)
	var ms: String = session.morale.state
	if ms != _morale_seen:
		_morale_seen = ms
		if ms == "offering":
			Audio.fx(self, "surrender_chirp")
	if _frame % 6 == 0:  # (the banner is a string: look at it a few times a second)
		var hail: bool = ms == "steady" and session.morale.banner() != ""
		if hail and not _hailing:
			Audio.fx(self, "hail_chirp")
		_hailing = hail


## The equipment line ("scrap", "standard", "neon") of the part weapon `id` of ship `idx` is: a weapon's sound has a version for each line.
func _line_of(idx: int, id: String) -> String:
	return str(session.arena.ships[idx].ship.components.def(id).get("line", ""))


## A sound at the world point `pos` of ship `idx`'s doing: the enemy's is quieter than yours (`enemy_db`), and only what is near the camera is heard.
func _snd(id: String, idx: int, pos: Vector2, gain := 0.0, enemy_db := Audio.ENEMY_DB) -> void:
	Audio.fx(self, id, pos, gain + (0.0 if idx == Session.PLAYER else enemy_db))


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
			if idx == Session.PLAYER and e.has("uid"):
				badges.on_fire(int(e["uid"]))
			var fire_sound := Audio.weapon_sound(arena.weapons.def(str(e.get("weapon", ""))), _line_of(idx, str(e.get("weapon", ""))))
			if not Audio.is_loop(fire_sound):  # (a beam sounds from its beam events)
				_snd(fire_sound, idx, e["origin"])
			if Art.fx("muzzle") != null:
				_add_fx({"k": "art", "name": "muzzle", "anchor": "muzzle", "pos": e["origin"], "angle": dir.angle() + PI / 2.0, "life": 0.14})
			else:
				_add_fx({"k": "flash", "pos": e["origin"], "life": 0.09, "r": 10.0, "color": _shot_color(idx, "energy" if e["kind"] in ["laser", "beam"] else "kinetic")})
		"beam":
			if str(arena.weapons.def(str(e.get("weapon", "")))["kind"]) == "beam":
				var beam_sound := Audio.weapon_sound(arena.weapons.def(str(e.get("weapon", ""))), _line_of(idx, str(e.get("weapon", ""))))
				if not Audio.is_loop(beam_sound):
					beam_sound = "beam_loop"
				Audio.fx_loop(self, "beam%d:%s" % [idx, beam_sound], beam_sound, true, 1.0 if idx == Session.PLAYER else 0.5, 1.0, null if idx == Session.PLAYER else e["from"])
			_add_fx({"k": "beam", "a": e["from"], "b": e["to"], "life": BEAM_LIFE, "color": _shot_color(idx, e["dtype"]),
				"kind": str(arena.weapons.def(str(e.get("weapon", "")))["kind"]), "weapon": str(e.get("weapon", ""))})
		"effect":  # a weapon effect (acid, spores, frost ...): effect_fx.gd says what it looks like
			if e.get("kind", "") == "intercept" and bool(e.get("hit", false)):
				_snd("missile_pop", idx, pos, 0.0, -3.0)  # point defence shot a missile down
			for f in EffectFx.of(arena, e):
				_add_effect_fx(f)
		"hit":
			if e.has("dot"):  # a damage over time ticking: just a wisp
				for f in EffectFx.dot(e):
					_add_effect_fx(f)
				return
			var weapon_art := str(e.get("weapon", ""))
			var big: bool = e["kind"] == "component"
			if e["dtype"] == "explosive":
				_snd("explosion_s", idx, pos, -2.0, -3.0)
			else:
				_snd("hit_hull", idx, pos, 0.0 if big else -3.0, -3.0)
			var col := Color("#ffb347") if big else Color("#ffe9a8")
			if e["dtype"] == "ion":
				col = Color("#b99bff")
			if weapon_art != "" and Art.projectile(weapon_art + "_impact") != null:  # the weapon's own impact art, when it has some
				_on_ship(idx, pos, {"k": "art", "src": "projectiles", "name": weapon_art + "_impact", "anchor": "center", "life": 0.45, "scale": 1.0})
			elif big and Art.fx("explosion") != null:
				_on_ship(idx, pos, {"k": "art", "name": "explosion", "life": 0.5, "scale": 0.7})
			elif Art.fx("sparks") != null:
				_on_ship(idx, pos, {"k": "art", "name": "sparks", "life": 0.25, "scale": 0.7})
			else:
				_on_ship(idx, pos, {"k": "flash", "life": 0.22, "r": 18.0 if big else 11.0, "color": col})
			_sparks(pos, n, 7 if big else 4, col)
		"limpet_stick", "limpet_off", "limpet_lost", "pod_breach":
			if e["type"] == "limpet_stick":
				_snd("hit_hull", idx, pos, -6.0, -3.0)
			elif e["type"] == "pod_breach":
				_snd("explosion_s", idx, pos, -5.0, -3.0)
			for f in LimpetView.effects(e, _rng):
				_add_impact_fx(f)
		"drone_launch", "drone_emerge", "drone_hit", "drone_down", "drone_home", "drone_shot":
			if e["type"] == "drone_down":
				_snd("explosion_s", idx, pos, -3.0, -3.0)
			elif e["type"] == "drone_hit":
				_snd("hit_hull", idx, pos, -4.0, -3.0)
			elif e["type"] == "drone_launch":
				_snd("door", idx, pos, -2.0, -3.0)
			for f in DroneView.effects(e, _rng):
				_add_impact_fx(f)
		"shield":
			_snd("hit_shield", idx, pos, 0.0, -3.0)
			var shot_dir := dir
			if Art.fx("shield_ripple") != null:
				_on_ship(idx, pos, {"k": "art", "name": "shield_ripple", "anchor": "impact", "life": 0.45, "scale": 1.0, "angle": (-shot_dir).angle() + PI / 2.0})
			else:
				_on_ship(idx, pos, {"k": "ring", "life": 0.55, "r": 70.0, "color": Color("#7fe4ff") if e.get("dtype", "") != "ion" else Color("#b99bff")})
			_on_ship(idx, pos, {"k": "flash", "life": 0.15, "r": 16.0, "color": Color("#bff2ff")})
			_sparks(pos, -shot_dir, 3, Color("#9fe8ff"))
		"deflect", "ricochet":
			var out := dir - 2.0 * dir.dot(n) * n if n != Vector2.ZERO else -dir
			var col := Color("#d6f3ff") if e["type"] == "deflect" else Color("#ffd27a")
			_add_fx({"k": "streak", "pos": pos, "dir": out, "len": 90.0, "life": 0.28, "color": col})
			_on_ship(idx, pos, {"k": "flash", "life": 0.12, "r": 9.0, "color": col})
			for f in ImpactFx.bounce(e):  # a small spark at the bounce point
				_add_impact_fx(f)
		"ram":  # two ships met hard: sparks and debris at the contact points, a shake, a line in the chronicle
			Audio.fx(self, "collision", pos)
			Audio.fx(self, "ram_impact", pos, -3.0)
			var r := ImpactFx.ram(arena, _cursor, Session.PLAYER, session.enemy_label.to_lower())
			for f in r["fx"]:
				_add_impact_fx(f)
			_shake = maxf(_shake, r["shake"])
			if r["line"] != "":
				_say(r["line"])
		"breach":
			_flash_block(idx, pos)
			_snd("breach", idx, pos, 0.0, -3.0)
			if Art.fx("explosion") != null:
				_on_ship(idx, pos, {"k": "art", "name": "explosion", "life": 0.6, "scale": 1.0})
			else:
				_on_ship(idx, pos, {"k": "flash", "life": 0.3, "r": 22.0, "color": Color("#ff5a3a")})
			for i in 6:
				var d := (n if n != Vector2.ZERO else Vector2.from_angle(_rng.randf() * TAU)).rotated(_rng.randf_range(-0.9, 0.9))
				_add_fx({"k": "puff", "pos": pos, "vel": d * _rng.randf_range(40.0, 110.0), "life": _rng.randf_range(0.6, 1.0), "r": 8.0, "grow": 26.0, "color": Color("#b9bfc9", 0.6)})
		"disable":
			_flash_block(idx, pos)
			if Art.fx("sparks") != null:
				_on_ship(idx, pos, {"k": "art", "name": "sparks", "life": 0.35, "scale": 1.5})
			else:
				_on_ship(idx, pos, {"k": "flash", "life": 0.3, "r": 24.0, "color": Color("#ffe14a")})
			_sparks(pos, Vector2.ZERO, 10, Color("#ffe14a"))
		"ignite":
			for i in 3:
				_add_fx({"k": "puff", "pos": pos, "vel": Vector2.from_angle(_rng.randf() * TAU) * 30.0, "life": 0.7, "r": 6.0, "grow": 16.0, "color": Color("#ff7a2a", 0.6)})
		"wreck_part":
			_flash_block(idx, pos)
			_snd("part_destroyed", idx, pos, 0.0, -3.0)
			if Art.fx("explosion") != null:
				_on_ship(idx, pos, {"k": "art", "name": "explosion", "life": 0.7, "scale": 1.6})
			else:
				_on_ship(idx, pos, {"k": "flash", "life": 0.4, "r": 40.0, "color": Color("#ffb347")})
			_sparks(pos, Vector2.ZERO, 16, Color("#ffcf7a"))
			for i in 4:
				_add_fx({"k": "puff", "pos": pos, "vel": Vector2.from_angle(_rng.randf() * TAU) * 30.0, "life": 1.0, "r": 12.0, "grow": 30.0, "color": Color("#8a8f99", 0.5)})
		"overcharge":
			_snd("ability", idx, pos, 0.0, -3.0)
			_on_ship(idx, pos, {"k": "ring", "life": 0.8, "r": 260.0, "color": Color("#ffd24a")})
		"ability":  # a system's ability switched on (an overcharge has its ring above)
			_snd("ability", idx, pos, 0.0, -3.0)
		"ion_lock":  # an ion hit locked the shield
			_snd("ion_lock", idx, pos, 0.0, -3.0)
		"escape":  # the enemy's jump drive fired: a flash where it was
			Audio.fx(self, "jump", pos, ENEMY_JUMP_DB)
			if Art.fx("jump_flash") != null:
				_add_fx({"k": "art", "name": "jump_flash", "pos": pos, "angle": e["angle"], "life": 0.5, "scale": 3.0})
			else:
				_add_fx({"k": "flash", "pos": pos, "life": 0.5, "r": 120.0, "color": Color("#bfe4ff")})
			_add_fx({"k": "ring", "pos": pos, "life": 0.8, "r": 420.0, "color": Color("#7fe4ff")})
		"wreck":
			Audio.fx(self, "explosion_l", pos)
			_on_ship(idx, pos, {"k": "ring", "life": 1.1, "r": 420.0, "color": Color("#ffb347")})
			if Art.fx("explosion") != null:
				_on_ship(idx, pos, {"k": "art", "name": "explosion", "life": 1.2, "scale": 4.0})
			else:
				_on_ship(idx, pos, {"k": "flash", "life": 0.6, "r": 90.0, "color": Color("#ffd9a0")})
			_sparks(pos, Vector2.ZERO, 36, Color("#ffcf7a"))
			for i in 10:
				_add_fx({"k": "puff", "pos": pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 120.0), "vel": Vector2.from_angle(_rng.randf() * TAU) * 40.0, "life": 1.4, "r": 24.0, "grow": 50.0, "color": Color("#8a8f99", 0.5)})


## A block broke (a wall shot open, a part disabled or wrecked): its cell lights up white for a moment, stuck to the ship.
func _flash_block(idx: int, pos: Vector2) -> void:
	_on_ship(idx, pos, {"k": "block", "life": BLOCK_FLASH, "color": Color("#ffffff")})


## An effect entry from EffectFx: on the hull it names (`stick`) or free in the world.
func _add_effect_fx(f: Dictionary) -> void:
	if f.has("stick"):
		_on_ship(int(f["stick"]), f["pos"], f)
	else:
		_add_fx(f)


## An effect from ImpactFx: art when there is, else the flash of its fallback size.
func _add_impact_fx(f: Dictionary) -> void:
	if f["k"] == "art" and Art.fx(str(f["name"])) == null:
		_add_fx({"k": "flash", "pos": f["pos"], "life": f["life"], "r": f["r"], "color": f["color"]})
	else:
		_add_fx(f)


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
		badges.draw_ship(c, session, cam.zoom.x if cam != null else 1.0, _aim())
	for f in _fx:
		_draw_one(c, f, px)
	for p in arena.projectiles:
		_draw_shot(c, p, px)
	DroneView.draw(c, arena, _clock, px, _trails, _glow_quads if _glow != null else null)
	LimpetView.draw(c, arena, _clock, px, _trails2, _glow_quads if _glow != null else null)
	if _hold_slot > 0 and session.state() == "fighting":
		var pred: Dictionary = session.slot_path(_hold_slot, _aim())
		if not pred.is_empty():
			var kit: Dictionary = session.arena.Drones.kit(str(session.bays()[_hold_slot - session.weapons().size() - 1]["kit"]))
			LimpetView.draw_path(c, pred, px, LimpetView.COLORS.get(str(kit["drone"].get("family", kit["drone"]["role"])), Color.WHITE))
	if _glow != null:
		_glow.show_quads(_glow_quads)


func _fx_pos(f: Dictionary) -> Vector2:
	if f.has("ship"):
		return session.arena.local_to_world(f["ship"], f["local"])
	return f["pos"] + f.get("vel", Vector2.ZERO) * (_clock - f["t0"])


func _draw_one(c: Node2D, f: Dictionary, px: float) -> void:
	var age: float = (_clock - f["t0"]) / f["life"]
	var col: Color = f.get("color", Color.WHITE)
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
				var tint := Color(col.r, col.g, col.b, col.a * fade) if f.get("tint", false) else Color(1, 1, 1, fade)  # a gas of the effect's colour
				_blit_art(c, smoke, smoke.life_frame(age), p, 0.0, _art_k(px) * (0.5 + float(f["r"]) / 24.0 + age * 0.5), "", tint)
				return
			c.draw_circle(p, (f["r"] + f["grow"] * age) * px * 0.5 if f["r"] < 4.0 else f["r"] + f["grow"] * age, Color(col, col.a * fade))
		"debris":  # a chip of hull tumbling away
			var p := _fx_pos(f)
			var a: float = f["spin"] * (_clock - f["t0"])
			var h: float = f["size"] * px
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-h, -h).rotated(a), p + Vector2(h, -h * 0.6).rotated(a), p + Vector2(h * 0.7, h).rotated(a), p + Vector2(-h * 0.8, h * 0.7).rotated(a)]), Color(col, fade))
		"block":  # a broken block's cell, flashing: a square the size of a cell, turned with the ship
			var p := _fx_pos(f)
			var h := 16.0
			var a: float = session.arena.ships[f["ship"]].flight.angle
			var pulse := fade * (0.55 + 0.45 * sin(age * 22.0))
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-h, -h).rotated(a), p + Vector2(h, -h).rotated(a), p + Vector2(h, h).rotated(a), p + Vector2(-h, h).rotated(a)]), Color(col, 0.55 * pulse))
		"streak":
			var from: Vector2 = f["pos"] + f["dir"] * 18.0 * age
			c.draw_line(from, from + f["dir"] * f["len"] * (0.4 + 0.6 * age), Color(col, 0.9 * fade), 3.0 * px)


func _draw_shot(c: Node2D, p: Dictionary, px: float) -> void:
	var w: Dictionary = p["w"]
	var col := _shot_color(p["owner"], w["damage_type"])
	var at: Vector2 = p["pos"]
	var v: Vector2 = p["vel"]
	var d := v.normalized()
	var art = Art.projectile_of(str(w.get("id", "")), str(w["kind"]))  # its own art by weapon id, else the kind's
	if art != null:
		_draw_art_shot(c, art, at, d, px, 0.7 if w.get("drone", false) else 1.0)  # a drone's shot is its family's art, scaled down
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
func _draw_art_shot(c: Node2D, art, at: Vector2, d: Vector2, px: float, scale := 1.0) -> void:
	_blit_art(c, art, art.loop_frame(_clock), at, d.angle() + PI / 2.0 + art.orientation_rot * PI / 2.0, _art_k(px) * scale, "head" if art.anchors.has("head") else "center")


## An effect (art/fx/<name>) at the fx's place, played once over its life, turned by f["angle"], its
## f["anchor"] pixel (else the middle) on the spot.
func _draw_art_fx(c: Node2D, f: Dictionary, age: float, px: float) -> void:
	var art = Art.projectile(str(f["name"])) if f.get("src", "") == "projectiles" else Art.fx(str(f["name"]))
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
	var art = Art.projectile_of(str(f.get("weapon", "")), str(f.get("kind", "")))
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
	var hit = Art.projectile_of(str(f.get("weapon", "")), str(f["kind"]), "_impact")
	if hit != null:
		_blit_art(c, hit, hit.life_frame(age), b, 0.0, k, "center", Color(1, 1, 1, fade))
	return true


## The player's weapons. A fixed gun: a faint cone of its gimbal and a boresight line along its barrel (bright
## when it can fire, dim while it cools, a short grey stub when it cannot). A turret: a faint wedge of its arc,
## a ring where it turns and a line along its barrel. Then the crosshair.
func _draw_aim(c: Node2D, px: float) -> void:
	var arena = session.arena
	var co = arena.ships[Session.PLAYER]
	var aim := _aim()
	for w in session.weapons():
		var m: Dictionary = co.mounts[w["uid"]]
		var def: Dictionary = arena.weapons.def(m["id"])
		var pivot: Vector2 = arena.local_to_world(Session.PLAYER, m["pos"])
		var muzzle: Vector2 = arena.weapons.muzzle_of(arena, Session.PLAYER, m)
		var st: Dictionary = session.slot_state(w["uid"], aim)
		var can: bool = st["status"] in ["ready", "cooling down"]
		var col: Color = GunBadges.style(w)["color"] if can else GREY
		var reach := float(def["range"])
		var half := deg_to_rad(float(def["arc"]) * 0.5) if def["turret"] else deg_to_rad(float(def["gimbal"]))
		if half < PI - 0.01:
			var a0: float = Vector2(m["dir"]).rotated(co.flight.angle).angle() - half
			var pts := PackedVector2Array([pivot])
			for i in 17:
				pts.append(pivot + Vector2.from_angle(a0 + 2.0 * half * i / 16.0) * reach)
			c.draw_colored_polygon(pts, Color(col, 0.06 if can else 0.035))
			c.draw_line(pivot, pts[1], Color(col, 0.22), 1.0 * px)
			c.draw_line(pivot, pts[-1], Color(col, 0.22), 1.0 * px)
		if def["turret"]:
			c.draw_arc(pivot, 40.0 * px, 0.0, TAU, 24, Color(col, 0.18), 1.0 * px)
		var barrel: Vector2 = Vector2(m["aim"]).rotated(co.flight.angle)
		if can:
			c.draw_line(muzzle, muzzle + barrel * reach, Color(col, 0.7 if st["status"] == "ready" else 0.28), 1.6 * px)
		else:
			c.draw_line(muzzle, muzzle + barrel * 36.0 * px, Color(col, 0.55), 1.4 * px)  # a short grey stub
	c.draw_arc(aim, 10.0 * px, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 1.5 * px)
	c.draw_line(aim - Vector2(16, 0) * px, aim - Vector2(5, 0) * px, Color(1, 1, 1, 0.8), 1.5 * px)
	c.draw_line(aim + Vector2(16, 0) * px, aim + Vector2(5, 0) * px, Color(1, 1, 1, 0.8), 1.5 * px)
	c.draw_line(aim - Vector2(0, 16) * px, aim - Vector2(0, 5) * px, Color(1, 1, 1, 0.8), 1.5 * px)
	c.draw_line(aim + Vector2(0, 16) * px, aim + Vector2(0, 5) * px, Color(1, 1, 1, 0.8), 1.5 * px)
