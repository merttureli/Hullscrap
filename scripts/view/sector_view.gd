extends Node2D
## Sector space on screen (docs/CONTENT.md section 11, the view): in play mode the ship flies through the sector of the
## campaign's current node. This node runs it and draws what is round the ship.
## - The helm (helm.gd): with a course set and someone at the helm the autopilot flies there; E at the helm gives the
##   player the combat flight controls and E again hands back. Cruise (x1.8, data/sectors.json) out of combat.
## - The sector (sector.gd): the passing ships, a POI within 800 px runs its event in the event panel (map_view.gd
##   open_poi), and the jump drive's spool (Campaign.tick_jump, started from the map) shows on the HUD; when it fires the
##   ship arrives in the new sector.
## - The camera follows the ship, and BuildMode and the crew are drawn moved and turned to its place (the interior at
##   normal zoom; the wheel zooms out to the sector). The starfield moves with the camera and takes the region's nebula.
## - Fights in place: the combat view asks fight_place(); while one is on its hostile is in Sector.hostiles (the jump
##   block, the real flight numbers), and when it ends the ship takes the fight's place. A win or a capture leaves the
##   wreck as a POI, already salvaged: the salvage pick comes from the map (map_view.gd, Salvage.event_for).
## - Red alert: BuildMode's hostiles_source is red_alert_hostiles() (the fight's enemy and the passing pirates).
## - When the Hollow tide takes the place the ship is in (sector.hollow), the HUD says FALL_TEXT; debris_view.gd thins the field.
## - in_play() and the `played` signal say when the sector runs (play mode, nothing open over it, no fight), for clocks
##   that count play time (the Hollow tide's linger).
## - Under the ship: the POIs the radar sees (flat placeholder shapes), the passing ships, the course line and the
##   spool ring. On the HUD: the compass ring (contacts, the course and debris within 2,000 px as dots), edge markers
##   (art/ui/poi_icons.png: the icon, the distance, the type once identified; Radar.contacts) that set a course when
##   clicked (again: cancel), and the sector, helm and jump drive lines. A radar that identifies (Mk2 and up) also names a
##   passing ship by its kind and rates the threat of one that may fight in skulls under its marker (Radar.threat).
## Off on the build screen (build mode is the old upright view at the origin, and the world holds) and with the old
## instant jump. frame(dt) runs one tick without the scene tree, so tests can drive it.

const Helm = preload("res://scripts/space/helm.gd")
const Radar = preload("res://scripts/space/radar.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Art = preload("res://scripts/view/art.gd")

const DEBRIS_DOTS := 2000.0  ## px: debris this near shows on the compass ring
const THREAT_S := 2.0  ## seconds a contact's skulls are kept before they are rated again
const SKULL_STEP := 13.0  ## screen px between two skulls under a marker
const FLASH_S := 0.45  ## seconds the jump flash plays on arrival
const SAY_S := 4.0  ## seconds a message stays
const FALL_TEXT := "The tide is here. Something is coming."  ## the HUD line when the Hollow tide takes the place the ship is in
const ICON := 32.0  ## screen px of a marker icon (the 16 px art at 2x)
const EDGE := 46.0  ## screen px the edge markers keep from the border
const TOP := 66.0  ## screen px down to the sector's lines (under the HUD's top bar)
const BOTTOM := 180.0  ## screen px the edge markers keep from the bottom (the HUD's mode bar and key hints)
const CYAN := Color("#43e6ff")
const AMBER := Color("#e1a136")
const RED := Color("#e0413b")
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
## Emitted each frame the ship is in play in its sector (in_play()), with the seconds that passed.
signal played(dt: float)

const TYPE_COLORS := {"station": Color("#e1a136"), "store": Color("#6bd34a"), "trader": Color("#6bd34a"), "distress": Color("#e0413b"),
	"wreck": Color("#9aa0a6"), "abandoned_station": Color("#8c96a3"), "mining_field": Color("#c2956a"), "unknown": Color("#c8ced8"),
	"pirate_nest": Color("#e0413b"), "concord_checkpoint": Color("#4fa3ff"), "anomaly": Color("#c06bff"), "quest": Color("#f2c744")}

var sim: Node  ## ShipSim
var build: Node  ## BuildMode (its `drift` is the map, which owns the campaign)
var crew: Node  ## the crew view (the player's soldier)
var combat: Node  ## the combat view
var debris_node: Node  ## the debris view (its pieces: the rocks to avoid, the dots on the ring)
var cam: Camera2D
var starfield: Node
var helm := Helm.new()
var message := ""
## Tests drive these instead of the scene: the hand on the helm ({throttle, side, cursor}) and whether it is manned.
var hand_override = null
var manned_override = null
var _campaign = null  # the campaign the helm flies in
var _sector = null  # and its sector
var _clock := 0.0
var _said := -100.0
var _posed := false  # BuildMode and the crew are moved to the ship's place
var _flash := 0.0
var _hollow_seen := false  # whether the sector was Hollow at the last look: the HUD tells when it falls
var _markers: Array = []  # [{rect (screen), id}] of the last HUD frame, for clicks
var _threats := {}  # POI id -> {n (skulls), t (the clock it was rated at)} for this sector
var _layer: CanvasLayer
var _hud: Control
var _icons = null
var _icons_read := false


func _init() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 2
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.draw.connect(_draw_hud)
	_layer.add_child(_hud)
	add_child(_layer)


func _ready() -> void:
	sim = get_node_or_null("../ShipSim")
	build = get_node_or_null("../BuildMode")
	crew = get_node_or_null("../Crew")
	combat = get_node_or_null("../Combat")
	debris_node = get_node_or_null("../Debris")
	cam = get_node_or_null("../Camera2D")
	starfield = get_node_or_null("../Space/Starfield")
	if combat != null and combat.has_signal("finished"):
		combat.finished.connect(_on_fight_finished)
	if build != null and "hostiles_source" in build:
		build.hostiles_source = red_alert_hostiles


func _process(dt: float) -> void:
	frame(minf(dt, 0.25))


# --- what the other nodes ask -----------------------------------------------------------------------------------

## The campaign (the map's), or null.
func campaign():
	var map = _map()
	return map.campaign if map != null else null


func _map():
	return build.get("drift") if build != null else null


func _ship():
	return sim.player_ship() if sim != null else null


## Is the ship in sector space: a campaign on the light-speed flow and a ship?
func flying() -> bool:
	var c = campaign()
	return c != null and not c.instant_jump() and _ship() != null


## The sector the ship is in (null off sector space).
func current():
	return campaign().current_sector() if flying() else null


## Does the player have the helm (E) right now? Then WASD fly the ship, not the soldier.
func piloting() -> bool:
	return flying() and helm.manual and build != null and not build.build_on and not _fighting()


## Is a hostile ship within `radius` px of the ship (a fight in the sector)? The build screen is refused then.
func hostile_near(radius: float) -> bool:
	var s = current()
	return s != null and s.hostile_near(radius)


## Is the ship in play in its sector now: play mode, the map and its panels shut, no fight? The sector's clocks run
## then (`played` is emitted with each frame of it).
func in_play() -> bool:
	var map = _map()
	return flying() and build != null and not build.build_on and not (map != null and map.visible) and not (combat != null and combat.get("active"))


## The hostile ships about for BuildMode's red alert (hostiles_source): the enemy of a fight in the sector and the
## passing pirates (Sector.hostile_ships), in the build screen's frame (ship.world_pos for the ship), so their distance
## to it is right.
func red_alert_hostiles() -> Array:
	var s = current()
	var ship = _ship()
	var out := []
	if s == null or ship == null:
		return out
	for p in s.hostile_ships():
		out.append(ship.world_pos + (p - s.ship_pos))
	return out


## The arena ship of the player in a fight in the sector, else null.
func _fight_ship():
	if not _fighting() or combat.get("session") == null:
		return null
	return combat.session.arena.ships[Session.PLAYER]


func _fighting() -> bool:
	return combat != null and combat.get("active") and combat.get("in_sector")


## Where the ship's cells are in the sector: the build view's px (ship.world_pos at the grid centre) to sector px, from
## the fight's arena while a fight is on, else from the helm.
func ship_frame() -> Transform2D:
	var ship = _ship()
	if ship == null:
		return Transform2D.IDENTITY
	var co = _fight_ship()
	if co != null:
		return Helm.frame_of(ship, co.flight.pos, co.flight.angle, co.pivot)
	return helm.frame(ship)


func ship_velocity() -> Vector2:
	var co = _fight_ship()
	return co.flight.vel if co != null else helm.flight.vel


## Where a fight starts in sector space (combat_session.gd start()'s `place`): the ship as it flies, and the enemy at
## `enemy_pos` (else SPAWN_DISTANCE ahead), never nearer than SPAWN_DISTANCE. {} off sector space: the old arena.
func fight_place(enemy_pos = null) -> Dictionary:
	if not flying():
		return {}
	_sync(campaign(), _ship())
	return helm.fight_place(enemy_pos, Session.SPAWN_DISTANCE, _sector.size)


# --- the tick --------------------------------------------------------------------------------------------------

## One tick of `dt` seconds: the helm, the sector, the spool and the triggers in play mode (all held while the map or an
## event is open), then the ship's place on screen.
func frame(dt: float) -> void:
	_clock += dt
	_flash = maxf(_flash - dt, 0.0)
	var map = _map()
	var ship = _ship()
	if map != null and map.campaign == null and ship != null and build != null and not build.build_on:
		map.new_game()  # play mode needs a campaign: the sector
	if not flying():
		_unpose()
		visible = false
		_layer.visible = false
		return
	var c = campaign()
	_sync(c, ship)
	var s = _sector
	helm.refresh(ship)
	var playing: bool = build != null and not build.build_on
	var fighting := _fighting()
	var co = _fight_ship()
	if co != null:
		var foe = combat.session.arena.ships[Session.ENEMY]
		s.hostiles = [] if foe.wrecked else [foe.flight.pos]
		s.ship_pos = co.flight.pos
		s.ship_vel = co.flight.vel
		s.ship_angle = co.flight.angle
	else:
		s.hostiles.clear()
	if playing and not (map != null and map.visible):
		if not fighting:
			if helm.manual and (crew == null or crew.get("player") == null or crew.player.is_down()):
				helm.manual = false
			helm.step(dt, s, _manned(ship), _hand(), s.hostile_near(float(helm.cfg["real_within"])), _rocks())
			if helm.arrived != "":
				_say("Arrived at %s." % helm.arrived)
		if not s.tick(dt, ship).is_empty():
			_say("A ship shows on the radar.")
		if s.hollow != _hollow_seen:
			_hollow_seen = s.hollow
			if s.hollow:
				_say(FALL_TEXT)
		_spool(dt, c, ship)
		if not fighting and _sector == s and map != null and not map.visible:
			var res: Dictionary = s.trigger(c, ship)
			if not res.is_empty():
				map.open_poi(res, s)
	if playing and not _fighting():
		_pose(ship)
	elif not playing:
		_unpose()
	visible = playing
	_layer.visible = playing
	if in_play():
		played.emit(dt)
	if starfield != null:
		starfield.set("region", "gate" if str(c.node(c.current).get("type", "")) == "gate" else str(_sector.region))
	queue_redraw()
	_hud.queue_redraw()


## The campaign or its current sector changed (a jump, a tow, a load, a new run): the helm takes the ship's place there.
func _sync(c, ship) -> void:
	var s = c.current_sector()
	if c == _campaign and s == _sector:
		return
	_campaign = c
	_sector = s
	_threats.clear()
	_hollow_seen = s.hollow
	helm.refresh(ship)
	helm.place(s.ship_pos, s.ship_vel, s.ship_angle)
	helm.clear_course()
	helm.manual = false


## The jump drive charges; when it fires a fight in the sector is left behind and the ship arrives in the new sector.
func _spool(dt: float, c, ship) -> void:
	match c.tick_jump(dt, _sector.hostile_near(c.hostile_range()), ship):
		"jumped":
			if combat != null and combat.get("active"):
				combat.leave()
			_flash = FLASH_S
			_say(" ".join(["Arrived at %s." % c.label(c.current)] + c.last_jump.get("notes", [])))
			_sync(c, ship)
		"failed":
			_say("The jump failed: %s" % c.last_jump.get("why", ""))


func _manned(ship) -> bool:
	if manned_override != null:
		return bool(manned_override)
	return Helm.is_manned(ship, crew.get("player") if crew != null else null)


## The player's flight controls while they have the helm: W/S thrust, A/D strafe (or turn), the mouse steers.
func _hand() -> Dictionary:
	if hand_override != null:
		return hand_override
	if not helm.manual or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		return {}
	return {"throttle": float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S)),
		"side": float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), "cursor": get_global_mouse_position() if is_inside_tree() else null}


## The big drifting pieces the autopilot steers round: [{pos, r}].
func _rocks() -> Array:
	var out := []
	var d = debris_node.get("debris") if debris_node != null else null
	if d == null:
		return out
	var big := float(helm.cfg["avoid"]["size"])
	for p in d.pieces:
		if float(p["r"]) * 2.0 >= big:
			out.append({"pos": p["pos"], "r": p["r"]})
	return out


## Move BuildMode and the crew to the ship's place and heading, and the camera onto it.
func _pose(ship) -> void:
	var f := helm.frame(ship)
	if build != null:
		build.transform = f
	if crew != null:
		crew.transform = f
	if cam != null:
		cam.position = helm.flight.pos
	_posed = true


## Back to the build screen's upright view at the origin.
func _unpose() -> void:
	if not _posed:
		return
	if build != null:
		build.transform = Transform2D.IDENTITY
	if crew != null:
		crew.transform = Transform2D.IDENTITY
	if cam != null:
		cam.position = Vector2.ZERO
	_posed = false


## A fight in the sector is over: the ship is where the fight left it, and a win or a capture leaves the enemy's wreck
## (marked salvaged: the map shows the salvage pick).
func _on_fight_finished(result: Dictionary) -> void:
	if not result.get("in_sector", false) or _sector == null:
		return
	var p: Dictionary = result["pose"]
	helm.place(p["pos"], p["vel"], p["angle"], p["ang_vel"])
	helm.sync_to(_sector)
	_sector.hostiles.clear()
	if result.get("state", "") in ["won", "captured"]:
		var foe = result.get("enemy")
		var label := "Wreck of %s" % foe.name if foe != null and str(foe.name) not in ["", "Ship"] else ""
		_sector.add_wreck(result["enemy_pos"], label)["state"] = Sector.DONE  # the salvage pick is the map's, once


func _say(text: String) -> void:
	message = text
	_said = _clock


# --- input ----------------------------------------------------------------------------------------------------

## E at a working helm: the player takes the helm; E again hands it back to the autopilot.
func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_E) or e.ctrl_pressed:
		return
	if toggle_helm():
		get_viewport().set_input_as_handled()


## E pressed: take or hand back the helm. True when it did either (the key is used up).
func toggle_helm() -> bool:
	var map = _map()
	if not flying() or build == null or build.build_on or _fighting() or (map != null and map.visible):
		return false
	if helm.manual:
		helm.manual = false
		_say("You hand the helm back to the autopilot.")
		return true
	if helm.why_not == "" and Helm.helm_near(_ship(), crew.get("player") if crew != null else null) >= 0:
		helm.manual = true
		_say("You have the helm: mouse steers, W/S thrust, A/D strafe. E hands it back.")
		return true
	return false


## A click on a marker sets the course there (on the course's own marker: cancels it).
func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if click(e.position):
		get_viewport().set_input_as_handled()


## A click at screen point `at`. True when it hit a marker.
func click(at: Vector2) -> bool:
	var map = _map()
	if not visible or _fighting() or (map != null and map.visible):
		return false
	for i in range(_markers.size() - 1, -1, -1):
		if _markers[i]["rect"].has_point(at):
			return choose(str(_markers[i]["id"]))
	return false


## Set the course to POI `id` (cancel it if it is the course already). True when the POI exists.
func choose(id: String) -> bool:
	var poi: Dictionary = _sector.find(id) if _sector != null else {}
	if poi.is_empty():
		return false
	if str(helm.course.get("poi", "")) == id:
		helm.clear_course()
		_say("Course cancelled.")
	else:
		helm.set_course(id)
		_say("Course set: %s." % poi["name"])
	return true


# --- the HUD's words ------------------------------------------------------------------------------------------------

## "4.2k px" or "850 px".
static func dist_text(d: float) -> String:
	return "%.1fk px" % (d / 1000.0) if d >= 1000.0 else "%d px" % roundi(d)


## The name a contact shows: its name once its type is known (a passing ship by its kind), else "Contact".
static func contact_name(ct: Dictionary) -> String:
	return Radar.title(ct)


## The skulls (1 to 5) of the ship behind contact `ct`, 0 when it shows none (Radar.threat: a radar that identifies, a ship that
## may fight). Kept THREAT_S seconds a contact, as building the enemy to rate it costs a little.
func threat_of(ct: Dictionary) -> int:
	if Radar.fighter_kind(ct["poi"]) == "" or not bool(ct.get("scanned", false)):
		return 0
	var id := str(ct["poi"]["id"])
	var e: Dictionary = _threats.get(id, {})
	if e.is_empty() or _clock - float(e["t"]) > THREAT_S:
		e = {"n": Radar.threat(campaign(), _ship(), ct), "t": _clock}
		_threats[id] = e
	return int(e["n"])


## The sector's title: the node and the region.
func title() -> String:
	var c = campaign()
	return "%s  -  %s" % [c.label(c.current), c.region_name()]


## What the helm is doing, in words.
func helm_line() -> String:
	var speed := "%d px/s, %s" % [roundi(helm.flight.vel.length()), "cruise x%s" % String.num(helm.cruise, 1) if helm.cruise > 1.0 else "combat speed"]
	match helm.state:
		"grounded":
			return "HELM: the ship cannot fly (%s)" % helm.why_not
		"manual":
			return "YOU HAVE THE HELM: mouse steers, W/S thrust, A/D strafe, E hands back   (%s)" % speed
		"unmanned":
			return "HELM UNMANNED: the ship coasts. Crew go to the helm, or take it yourself (E)   (%s)" % speed
		"autopilot":
			var to = helm.target(_sector)
			return "AUTOPILOT to %s, %s   (%s)" % [helm.course_name(_sector), dist_text(helm.flight.pos.distance_to(to)) if to != null else "?", speed]
	return "No course: click a marker to set one   (%s)" % speed


## The jump drive's line ("" when it is idle).
func spool_line() -> String:
	var st: Dictionary = campaign().jump_status()
	if not st["active"]:
		return ""
	if st["blocked"]:
		return "JUMP DRIVE HELD: %s" % campaign().HOSTILES_TEXT
	return "JUMP DRIVE: %s in %.1f s" % [campaign().label(str(st["to"])), maxf(float(st["total"]) - float(st["t"]), 0.0)]


# --- drawing in the sector ----------------------------------------------------------------------------------------

func _px() -> float:
	var z: float = cam.zoom.x if cam != null else 0.5
	return 1.0 / maxf(z, 0.01)


func _draw() -> void:
	if _sector == null or not visible:
		return
	var px := _px()
	for ct in Radar.contacts(_sector, _ship()):
		if ct["known_type"] == Radar.CONTACT:  # not identified: a blip, not its shape
			draw_circle(ct["poi"]["pos"], 6.0 * px, Color(CYAN, 0.6))
			draw_arc(ct["poi"]["pos"], (14.0 + 6.0 * sin(_clock * 3.0)) * px, 0.0, TAU, 24, Color(CYAN, 0.4), 1.5 * px)
		else:
			_draw_poi(ct["poi"], px)
	var to = helm.target(_sector)
	if to != null:
		var from: Vector2 = helm.flight.pos
		_dashed(from, to, CYAN, 2.0 * px, 18.0 * px, 12.0 * px, _clock * 30.0 * px)
		_icon("course", to, ICON * px, Color(1, 1, 1, 0.9))
	_draw_spool(px)


## A POI's flat placeholder: a station ring, a ship hull, wreck pieces, a rock field, a beacon pod, a swirl.
func _draw_poi(poi: Dictionary, px: float) -> void:
	var at: Vector2 = poi["pos"]
	var col: Color = TYPE_COLORS.get(str(poi["type"]), TEXT)
	var a := 0.45 if poi["state"] == Sector.DONE and not bool(Sector.config()["poi_types"].get(poi["type"], {}).get("repeat", false)) else 1.0
	var seed_h := hash(str(poi["id"]))
	match str(poi["type"]):
		"station", "store":
			var r := 900.0 if poi["type"] == "station" else 560.0
			draw_circle(at, r, Color("#1b222c", a))
			draw_arc(at, r, 0.0, TAU, 96, Color(col, a), 28.0)
			draw_arc(at, r * 0.55, 0.0, TAU, 64, Color("#59667a", a), 18.0)
			for k in 6:
				var d := Vector2.from_angle(_clock * 0.03 + k * TAU / 6.0)
				draw_line(at + d * r * 0.55, at + d * r, Color("#59667a", a), 22.0)
				draw_circle(at + d * r, 30.0, Color(col.lightened(0.4), a * (0.5 + 0.5 * sin(_clock * 3.0 + k))))
			draw_circle(at, r * 0.25, Color("#2a3340", a))
			draw_circle(at, r * 0.12, Color(col, a))
		"wreck", "abandoned_station":
			var big := 2.2 if poi["type"] == "abandoned_station" else 1.0
			for k in 4:
				var off := Vector2.from_angle(float((seed_h >> (k * 3)) % 628) / 100.0) * 180.0 * k * big
				_hull(at + off, float((seed_h >> k) % 314) / 100.0 + k, 260.0 * big / (1.0 + k * 0.3), Color("#3a3f47", a), Color("#9a5428", a))
		"mining_field":
			for k in 11:
				var ang := float((seed_h >> k) % 628) / 100.0 + k * 0.7
				var off := Vector2.from_angle(ang) * (120.0 + 110.0 * k)
				_rock(at + off, 70.0 + float((seed_h >> (k + 2)) % 90), k + seed_h, Color(col.darkened(0.35), a))
		"distress", "quest":
			draw_circle(at, 80.0, Color("#2a3340", a))
			draw_circle(at, 36.0, Color(col, a))
			var pulse := fmod(_clock, 1.6) / 1.6
			draw_arc(at, 80.0 + 400.0 * pulse, 0.0, TAU, 48, Color(col, a * (1.0 - pulse)), 3.0 * px)
		"anomaly":
			for k in 4:
				draw_arc(at, 180.0 + 150.0 * k, _clock * (0.4 + 0.15 * k), _clock * (0.4 + 0.15 * k) + PI * 1.3, 32, Color(col, a * (0.7 - 0.12 * k)), 18.0)
		"pirate_nest":
			_rock(at, 480.0, seed_h, Color("#3b2f2a", a))
			for k in 5:
				draw_circle(at + Vector2.from_angle(k * 1.3) * 340.0, 26.0, Color(col, a * (0.5 + 0.5 * sin(_clock * 4.0 + k))))
		_:  # a ship: unknown, trader, checkpoint, a passing contact
			var heading: float = poi["vel"].angle() + PI / 2.0 if poi.get("vel") is Vector2 and poi["vel"] != Vector2.ZERO else float(seed_h % 628) / 100.0
			_hull(at, heading, 320.0 if poi["type"] != "concord_checkpoint" else 520.0, Color(col.darkened(0.55), a), Color(col, a))


## A pointed hull of `size` px at `at`, nose along `heading` (flight.gd convention).
func _hull(at: Vector2, heading: float, size: float, fill: Color, edge: Color) -> void:
	var pts := PackedVector2Array()
	for v in [Vector2(0, -1.0), Vector2(0.45, -0.2), Vector2(0.4, 0.7), Vector2(0, 0.5), Vector2(-0.4, 0.7), Vector2(-0.45, -0.2)]:
		pts.append(at + (v * size).rotated(heading))
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, edge, maxf(3.0, size * 0.04))


func _rock(at: Vector2, r: float, seed_h: int, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 8:
		pts.append(at + Vector2.from_angle(k * TAU / 8.0) * r * (0.75 + 0.25 * float((seed_h >> k) & 3) / 3.0))
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, col.darkened(0.5), maxf(2.0, r * 0.06))


## The jump drive's charge round the ship (art/fx/jump_spool, red while held), and the flash on arrival.
func _draw_spool(px: float) -> void:
	var st: Dictionary = campaign().jump_status()
	var at: Vector2 = _sector.ship_pos
	var r: float = helm.radius * 1.3
	if st["active"]:
		var sheet = Art.fx("jump_spool")
		var tint := RED if st["blocked"] else Color.WHITE
		if sheet != null:
			var f: int = sheet.life_frame(float(st["frac"]))
			draw_texture_rect_region(sheet.texture, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), sheet.region(f), tint)
		draw_arc(at, r, -PI / 2.0, -PI / 2.0 + TAU * float(st["frac"]), 64, RED if st["blocked"] else CYAN, 4.0 * px)
	if _flash > 0.0:
		var sheet = Art.fx("jump_flash")
		var k := 1.0 - _flash / FLASH_S
		if sheet != null:
			draw_texture_rect_region(sheet.texture, Rect2(at - Vector2(r, r) * 1.5, Vector2(r, r) * 3.0), sheet.region(sheet.life_frame(k)))
		else:
			draw_circle(at, r * (0.5 + k), Color(1, 1, 1, 1.0 - k))


func _dashed(a: Vector2, b: Vector2, col: Color, width: float, dash: float, gap: float, phase: float) -> void:
	var d := b - a
	var n := d.length()
	if n < 1.0:
		return
	var u := d / n
	var t := -fmod(phase, dash + gap)
	while t < n:
		var t0 := maxf(t, 0.0)
		var t1 := minf(t + dash, n)
		if t1 > t0:
			draw_line(a + u * t0, a + u * t1, col, width)
		t += dash + gap


## The POI icon `kind` (a POI type, "contact" or "course") centred on `at`, `size` px across, on `canvas`.
func _icon(kind: String, at: Vector2, size: float, mod := Color.WHITE, canvas: CanvasItem = null) -> void:
	var cv: CanvasItem = canvas if canvas != null else self
	if not _icons_read:
		_icons_read = true
		_icons = Art.load_sheet("%s/ui/poi_icons" % Art.root)
	if _icons != null and _icons.has_anim(kind):
		cv.draw_texture_rect_region(_icons.texture, Rect2(at - Vector2(size, size) / 2.0, Vector2(size, size)), _icons.region(_icons.start_of(kind)), mod)
	else:
		cv.draw_circle(at, size * 0.4, Color(TYPE_COLORS.get(kind, CYAN), mod.a))


# --- the HUD --------------------------------------------------------------------------------------------------------

func _draw_hud() -> void:
	_markers = []
	if _sector == null or not _layer.visible or not is_inside_tree():
		return
	var vp := _hud.size
	var font := ThemeDB.fallback_font
	if not _fighting():
		var xf := get_viewport().get_canvas_transform()
		var centre: Vector2 = xf * helm.flight.pos
		var ring := maxf(minf(vp.x, vp.y) * 0.42, helm.radius * get_viewport().get_canvas_transform().get_scale().x + 30.0)
		_draw_ring(centre, ring)
		var contacts := Radar.contacts(_sector, _ship())
		for ct in contacts:
			_draw_marker(ct, xf, centre, vp)
	var lines: Array = [] if _fighting() else [[title(), DIM_TEXT, 14], [helm_line(), CYAN if helm.state == "autopilot" else TEXT, 15]]  # a fight has its own HUD
	var sl := spool_line()
	if sl != "":
		lines.append([sl, RED if campaign().jump_status()["blocked"] else AMBER, 16])
	if message != "" and _clock - _said < SAY_S:
		lines.append([message, TEXT, 14])
	if lines.is_empty():
		return
	var y := 76.0 if _fighting() else TOP  # under the fight's key hints
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[2]).x)
	_hud.draw_rect(Rect2(Vector2((vp.x - w) / 2.0 - 12.0, y - 18.0), Vector2(w + 24.0, 22.0 * lines.size() + 8.0)), Color(0.04, 0.05, 0.08, 0.72))
	for l in lines:
		var tw: float = font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[2]).x
		_hud.draw_string_outline(font, Vector2((vp.x - tw) / 2.0, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[2], 4, Color(0, 0, 0, 0.9))
		_hud.draw_string(font, Vector2((vp.x - tw) / 2.0, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[2], l[1])
		y += 22.0
	var st: Dictionary = campaign().jump_status()
	if st["active"]:
		var bar := Rect2(Vector2(vp.x / 2.0 - 160.0, y - 8.0), Vector2(320.0, 8.0))
		_hud.draw_rect(bar, Color(0.1, 0.12, 0.16, 0.9))
		_hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(st["frac"]), bar.size.y)), RED if st["blocked"] else AMBER)


## The compass ring round the ship: ticks, N E S W, debris within 2,000 px as faint dots, a pip per contact, the course.
func _draw_ring(centre: Vector2, ring: float) -> void:
	var font := ThemeDB.fallback_font
	_hud.draw_arc(centre, ring, 0.0, TAU, 128, Color(0.6, 0.85, 1.0, 0.28), 1.5, true)
	for k in 24:
		var d := Vector2.UP.rotated(k * TAU / 24.0)
		var long := k % 6 == 0
		_hud.draw_line(centre + d * (ring - (10.0 if long else 5.0)), centre + d * ring, Color(0.6, 0.85, 1.0, 0.5 if long else 0.3), 1.5)
	for k in 4:
		var d := Vector2.UP.rotated(k * PI / 2.0)
		var letter: String = ["N", "E", "S", "W"][k]
		_hud.draw_string(font, centre + d * (ring - 22.0) + Vector2(-5.0, 5.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.9, 1.0, 0.6))
	var d = debris_node.get("debris") if debris_node != null else null
	if d != null:
		for p in d.pieces:
			var off: Vector2 = p["pos"] - helm.flight.pos
			if off.length() <= DEBRIS_DOTS and off.length() > 1.0:
				_hud.draw_circle(centre + off.normalized() * (ring + 6.0), 1.6, Color(1.0, 0.9, 0.6, 0.35))
	for ct in Radar.contacts(_sector, _ship()):
		var u := Vector2.UP.rotated(float(ct["bearing"]))
		var col: Color = TYPE_COLORS.get(str(ct["known_type"]), CYAN)
		_hud.draw_circle(centre + u * ring, 4.0, Color(col, 0.45 if ct["poi"]["state"] == Sector.DONE else 0.95))
	var to = helm.target(_sector)
	if to != null and to.distance_to(helm.flight.pos) > 1.0:
		var u: Vector2 = (to - helm.flight.pos).normalized()
		var tip := centre + u * (ring + 16.0)
		_hud.draw_colored_polygon(PackedVector2Array([tip, tip - u * 14.0 + u.orthogonal() * 8.0, tip - u * 14.0 - u.orthogonal() * 8.0]), CYAN)


## A contact's marker: on it when it is on screen, else on the screen's edge toward it. Icon, name and distance.
func _draw_marker(ct: Dictionary, xf: Transform2D, centre: Vector2, vp: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var poi: Dictionary = ct["poi"]
	var at: Vector2 = xf * poi["pos"]
	var inner := Rect2(Vector2(EDGE, EDGE + 40.0), vp - Vector2(EDGE * 2.0, EDGE + 40.0 + BOTTOM))
	if not inner.has_point(at):
		at = _to_edge(centre, at, inner)
	var done: bool = poi["state"] == Sector.DONE and not bool(Sector.config()["poi_types"].get(poi["type"], {}).get("repeat", false))
	var alpha := 0.45 if done else 1.0
	var kind: String = str(ct["known_type"])
	var course: bool = str(helm.course.get("poi", "")) == str(poi["id"])
	if course:
		_hud.draw_arc(at, ICON * 0.75, 0.0, TAU, 32, CYAN, 2.0, true)
	_icon(kind, at, ICON, Color(1, 1, 1, alpha), _hud)
	var label := "%s  %s" % [contact_name(ct), dist_text(float(ct["distance"]))]
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var tp := Vector2(clampf(at.x - tw / 2.0, 4.0, vp.x - tw - 4.0), at.y + ICON * 0.5 + 14.0)
	_hud.draw_string_outline(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9 * alpha))
	_hud.draw_string(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(CYAN if course else TEXT, alpha))
	var rect := Rect2(at - Vector2(ICON, ICON) * 0.6, Vector2(ICON, ICON) * 1.2).merge(Rect2(tp + Vector2(0.0, -12.0), Vector2(tw, 16.0)))
	var skulls := threat_of(ct)
	if skulls > 0:
		var row := Vector2(tp.x + tw / 2.0 - SKULL_STEP * 2.5, tp.y + 12.0)
		_draw_skulls(row, skulls, alpha)
		rect = rect.merge(Rect2(row + Vector2(0.0, -8.0), Vector2(SKULL_STEP * 5.0 + 24.0, 16.0)))
	_markers.append({"rect": rect, "id": poi["id"]})


## `n` of 5 small skulls in a row from `at` (the row's left middle) and "n/5" after them: lit ones in the band's colour
## (1-2 dim, 3 amber, 4-5 red), as the region cards and the enemy's schematic show a rating.
func _draw_skulls(at: Vector2, n: int, alpha: float) -> void:
	var on := RED if n >= 4 else (AMBER if n == 3 else DIM_TEXT)
	for i in 5:
		var c := Color(on if i < n else Color("#3a4350"), alpha)
		var o := at + Vector2(SKULL_STEP * i + 6.0, 0.0)
		_hud.draw_circle(o, 5.0, c)
		_hud.draw_rect(Rect2(o + Vector2(-3.0, 3.0), Vector2(6.0, 4.0)), c)
		_hud.draw_circle(o + Vector2(-2.0, 0.0), 1.4, Color("#10151c", alpha))
		_hud.draw_circle(o + Vector2(2.0, 0.0), 1.4, Color("#10151c", alpha))
	var font := ThemeDB.fallback_font
	var tx := at + Vector2(SKULL_STEP * 5.0 + 8.0, 4.0)
	_hud.draw_string_outline(font, tx, "%d/5" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.9 * alpha))
	_hud.draw_string(font, tx, "%d/5" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(on, alpha))


## Where the line from `from` toward `to` leaves `box`.
static func _to_edge(from: Vector2, to: Vector2, box: Rect2) -> Vector2:
	var d := to - from
	var t := 1.0
	if d.x != 0.0:
		t = minf(t, ((box.end.x if d.x > 0.0 else box.position.x) - from.x) / d.x)
	if d.y != 0.0:
		t = minf(t, ((box.end.y if d.y > 0.0 else box.position.y) - from.y) / d.y)
	return from + d * maxf(t, 0.0)
