extends Node2D
## One ship drawn at its place in the arena: the node sits on the ship's flight body (position and
## heading), so everything below is drawn in the ship's own frame, in pixels from its pivot. Tiles
## (materials by colour, shaped cells as slopes and curves), the exterior hull skin over the cells
## that face space (a ship in an arena only), breached cells as dark holes, damage, doors, systems
## through visuals.gd, crew, and the shield bubble. Drawing only; bind() it to an arena ship and it
## follows it. Reusable: with no arena it draws a plain Ship at the node's own transform (pivot = the
## hull's centre), with no skin.

const Drones = preload("res://scripts/combat/drones.gd")
const DroneView = preload("res://scripts/combat/drone_view.gd")
const LimpetView = preload("res://scripts/combat/limpet_view.gd")
const Visuals = preload("res://scripts/view/visuals.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")
const GlowLayer = preload("res://scripts/view/glow_layer.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Mortality = preload("res://scripts/crew/mortality.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const ArmFx = preload("res://scripts/view/arm_fx.gd")
const Art = preload("res://scripts/view/art.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Unlocks = preload("res://scripts/space/unlocks.gd")
const BeltArt = preload("res://scripts/view/belt_art.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const Emblem = preload("res://scripts/view/emblem.gd")
const Dressing = preload("res://scripts/view/dressing.gd")

const CELL := 32.0
const FLOOR_WASH := 0.3  ## how much of an enemy livery's floor tint is washed over its floor
const LIVERY_WASH := 0.5  ## how much of an enemy livery's tint is washed over its armour plating
const HOLE := Color("#06080c")
const HOLE_RIM := Color("#9a5428")
const BUBBLE := Color("#5fd4ff")
const ION := Color("#a07bff")
const OVERCHARGE := Color("#ffd24a")
const WRECK_TINT := Color(0.5, 0.48, 0.5)
const LOOKS := {
	"Soldier": {"suit": "#33c6d6", "hair": "#2b2320", "tool": "#d7dce4"},
	"Ada": {"suit": "#e8913a", "hair": "#c2331f", "tool": "#f1d36b"},
}
const OTHER_LOOK := {"suit": "#b8382c", "hair": "#1b1b1b", "tool": "#d7dce4"}
const MARK_COLOR := Color("#ffd24a")  ## the ring of a selected crew member (as crew_view.gd's)
const ROOM_FLASH_S := 0.7  ## seconds a clicked room is lit
const HIT_FLASH_S := 0.45  ## seconds a sector flashes after a shot hits it

var arena  ## arena.gd, or null
var skin_on := false  ## draw the exterior skin on a loose ship too (the pre-fight card, the enemy gallery)
var index := 0  ## the ship's index in the arena
var ship  ## ship.gd
var pivot := Vector2.ZERO  ## the ship's centre in cell coordinates: the node's origin
var _clock := 0.0
var _glow: Node2D  # additive layer for the glow art of the parts
var _weapons := {}  # uid -> {left, peak, shot}: a weapon's cooldown as last seen, the longest it has been, when it last fired (_clock)
var marked: Array = []  ## crew members to ring (the selected ones; the combat view sets it on the player's ship)
var flash_cells: Array = []  ## the cells of the room just clicked (flash_room), lit while flash_left > 0
var flash_left := 0.0
var _crew_anim := {}  # CrewMember -> PersonDrawer state, for drawing only
var _doors := {}  # a door piece's first cell -> TileArt.door_progress() state, for the opening animation
const BAY_RISE := [0, 9, 19, 27]  ## source px the bay's cradle has risen, by launch frame (art/components/drone_bay_mk*.json)
var _glow_quads: Array = []  # the glow art of this frame, handed to _glow at the end of _draw
var _skin := {}  # TileArt.skin_plan() of the grid, remade when _skin_sig changes
var _skin_sig := []
var _paint := {}  # Unlocks.skin_paint() of the ship's hull skin, remade when the skin changes
var _paint_skin := "?"
var _emblem_at := Vector2(-1.0e9, -1.0e9)
var _emblem_sig := []
var _dress_plan: Array = []  # Dressing.plan() of the ship, remade when its cells change outside a fight (in one, Dressing.kept drops what a lost cell held)
var _dress_sig := []
var _emblem_cells := 4.0  # the emblem decal's side, in cells
var _livery := {}  # the ship's `style` meta of this frame


## Follow ship `idx` of `p_arena`.
func bind(p_arena, idx: int) -> void:
	arena = p_arena
	index = idx
	ship = arena.ships[idx].ship
	pivot = arena.ships[idx].pivot
	_follow()


## Draw a loose ship (no arena) with its hull centre at the node's origin.
func show_ship(p_ship) -> void:
	arena = null
	ship = p_ship
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in ship.grid.hull:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x + 1.0), maxf(hi.y, c.y + 1.0))
	pivot = (lo + hi) / 2.0 if not ship.grid.hull.is_empty() else Vector2(ship.grid.size) / 2.0


func _follow() -> void:
	if arena != null:
		var co = arena.ships[index]
		position = co.flight.pos
		rotation = co.flight.angle
		modulate = WRECK_TINT if co.wrecked else Color.WHITE


func _ready() -> void:
	_glow = GlowLayer.new()
	add_child(_glow)


## Flash the cells `cells` for a moment (the room a middle-click order went to).
func flash_room(cells: Array) -> void:
	flash_cells = cells
	flash_left = ROOM_FLASH_S


func _process(dt: float) -> void:
	_clock += dt
	if ship != null:
		ArmFx.turn(ship, dt)
	flash_left = maxf(flash_left - dt / maxf(Engine.time_scale, 0.01), 0.0)  # real time, so the slow-down does not stretch it
	_follow()
	if ship != null:
		for m in ship.crew:
			var a: Dictionary = _crew_anim.get(m, PersonDrawer.new_state(m))
			PersonDrawer.animate(a, m, dt, PersonDrawer.job_aim(m))
			_crew_anim[m] = a
		for m in ship.intruders:
			var a2: Dictionary = _crew_anim.get(m, PersonDrawer.new_state(m))
			PersonDrawer.animate(a2, m, dt, PersonDrawer.job_aim(m))
			_crew_anim[m] = a2
	queue_redraw()


## The pixel position of cell coordinates `c` relative to the pivot.
func px(c: Vector2) -> Vector2:
	return (c - pivot) * CELL


func _draw() -> void:
	if ship == null:
		return
	_glow_quads = []
	_livery = ship.get_meta("style", {})
	var grid = ship.grid
	if not _livery.is_empty():  # the exterior dressing: outside the hull, under everything
		var dsig := [grid.tiles.size(), grid.shapes.size(), ship.components.instances.size(), _livery["grade"]]
		if dsig != _dress_sig and arena != null and not _dress_sig.is_empty():  # in a fight it is never planned again: a lost cell drops its pieces, the rest stay put
			_dress_plan = Dressing.kept(_dress_plan, grid)
			_dress_sig = dsig
		elif dsig != _dress_sig:
			var entries: Array = _livery["dressing"].duplicate()
			if _livery["grade"] == "patched":  # a low budget looks patched: welded scrap and a bare frame
				entries.append({"kind": "scrap", "count": [6, 10], "where": "any", "len": 1.1})
			elif _livery["grade"] == "fine":  # a high one looks kept: trim along the whole outline
				entries.append({"kind": "trim"})
			_dress_plan = Dressing.plan(ship, entries)
			_dress_sig = dsig
		Dressing.draw(self, _dress_plan, px(Vector2.ZERO), CELL, _livery["palette"], _clock)
	for c in grid.tiles:
		_draw_tile(grid, c, grid.tiles[c])
	if arena != null or skin_on:
		_draw_skin(grid)
	for c in grid.breached:
		_draw_hole(c)
	for c in grid.hp:
		_draw_damage(grid, c)
	BeltArt.draw(self, ship, px(Vector2.ZERO), CELL, _clock)  # the conveyor belts and the ammo riding them
	Visuals.draw_wrecks(self, ship.components.wrecks, px(Vector2.ZERO), CELL)
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	var all_opts := {}
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		var opts := _weapon_opts(uid)
		opts.merge({"powered": powered.get(uid, false), "time": _clock, "glow_out": _glow_quads, "thrusting": _thrusting(inst)})
		if not _livery.is_empty() and str(ship.components.def(inst["id"]).get("family", "")) == "engine":
			opts["glow_tint"] = Color.WHITE.lerp(_livery["palette"]["glow"], 0.75)  # the engine flame in the livery's colour
		opts.merge(Ammo.draw_opts(ship, uid))
		if Visuals.is_arm(ship.components.def(inst["id"])):
			opts.merge(ArmFx.opts(ship, uid))  # a healing arm: turned toward its patient
		all_opts[uid] = opts
		Visuals.draw_component(self, _rect_of(inst["cells"]), ship.components.def(inst["id"]), inst, CELL, opts)
		if opts.has("bay_out"):  # a drone bay: the loaded drone on its cradle while docked, riding it up the rail as it launches, nothing while it is out
			var age: float = float(opts["fired_ago"])
			if not opts["bay_out"] or age < Drones.SHOW_AFTER_S:
				var rise := float(BAY_RISE[mini(int(age * 10.0), 3)]) if opts["bay_out"] else 0.0
				DroneView.draw_docked(self, ship.components.def(inst["id"]), inst, _rect_of(inst["cells"]), CELL, _clock, rise)
	for uid in uids:  # the outside halves and barrels of the hull mounts, over the wall's edge
		var inst: Dictionary = ship.components.instances[uid]
		if inst["out_cells"].is_empty():
			continue
		var def: Dictionary = ship.components.def(inst["id"])
		var aim := Vector2.ZERO
		if arena != null and arena.ships[index].mounts.has(uid):
			aim = arena.ships[index].mounts[uid]["aim"]
		var out_rect := Visuals.slope_rect(def, inst, px(Vector2.ZERO), CELL) if Mounts.is_angled(inst) else _rect_of(inst["out_cells"])
		Visuals.draw_mount_out(self, def, inst, out_rect, px(Mounts.barrel_of(def, inst)["pivot"]), CELL, aim, all_opts[uid])
	draw_fire(self, ship.fires, px(Vector2.ZERO), CELL, _clock, _glow_quads)
	if arena != null:  # the room behind a stuck limpet: poison haze, hot parts
		LimpetView.draw_rooms(self, arena, index, px, CELL, _clock)
	for m in ship.crew:
		var a: Dictionary = _crew_anim.get(m, PersonDrawer.new_state(m))
		var look: Dictionary = m.look if not m.look.is_empty() else LOOKS.get(m.name, OTHER_LOOK)
		var pose := {"species": Art.crew_rig(m.rig()), "move": a["angle"], "aim": a["aim"], "phase": a["phase"], "moving": a["moving"],
			"item": PersonDrawer.item_for(m, ship.clock, arena != null), "down": m.is_down(), "work": PersonDrawer.is_working(m, ship.clock), "t": _clock, "body": PersonDrawer.gear_of(m)}
		pose.merge(PersonDrawer.drone_extras(m, ship))
		PersonDrawer.draw(self, px(m.pos), pose, look, CELL)
		PersonDrawer.draw_status(self, px(m.pos), Jobs.drone_status(ship, m), CELL)
		draw_health(self, px(m.pos), m.hp / m.max_hp, m.is_down(), CELL, Mortality.bleed_frac(m))
	for m in ship.intruders:  # boarding robots (intruders.gd): the same rig drawing as crew, in the owner's red
		var ia: Dictionary = _crew_anim.get(m, PersonDrawer.new_state(m))
		var ipose := {"species": Art.crew_rig(m.rig()), "move": ia["angle"], "aim": ia["aim"], "phase": ia["phase"], "moving": ia["moving"], "item": "", "down": m.is_down(),
			"work": false, "t": _clock, "body": "",
			"arm_pose": ["melee", "melee_2"][int(_clock * 6.0) % 2] if str(m.job.get("type", "")) == "attack" else "unarmed"}
		PersonDrawer.draw(self, px(m.pos), ipose, m.look, CELL)
		draw_health(self, px(m.pos), m.hp / m.max_hp, m.is_down(), CELL, 0.0)
	for w in ship.intruder_dead:  # a fallen robot's debris, for a moment
		var age: float = ship.clock - float(w["t"])
		if age < 2.0:
			for i in 6:
				var dir := Vector2.from_angle(float(i) * 1.047 + float(hash(w["t"]) % 7))
				draw_circle(px(w["pos"]) + dir * CELL * 0.5 * minf(age * 1.5, 1.0), 2.5 * (1.0 - age / 2.0), Color(0.55, 0.57, 0.62, 1.0 - age / 2.0))
	ArmFx.draw_beams(self, ship, func(p): return px(p), CELL, _clock)
	if flash_left > 0.0:
		for c in flash_cells:
			draw_rect(Rect2(px(Vector2(c)), Vector2(CELL, CELL)), Color(MARK_COLOR, 0.7 * flash_left / ROOM_FLASH_S))
	for m in marked:  # the selection rings, pulsing a little (the node's rotation turns them with the ship)
		if ship.crew.has(m):
			var r: float = CELL * (1.45 + 0.06 * sin(_clock * 5.0))
			draw_circle(px(m.pos), r, Color(MARK_COLOR, 0.10))
			draw_arc(px(m.pos), r, 0.0, TAU, 40, MARK_COLOR, 2.5, true)
	if _glow != null:
		_glow.show_quads(_glow_quads)
	if arena != null:
		_draw_bubble(arena.ships[index])


## The screen rectangle (in the ship's frame) of a set of grid cells.
func _rect_of(cells: Array) -> Rect2:
	var lo: Vector2i = cells[0]
	var hi: Vector2i = lo
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	return Rect2(px(Vector2(lo)), Vector2(hi - lo + Vector2i.ONE) * CELL)


## Is the engine `inst` pushing now? When the helm asks for what it gives: forward or reverse for an engine
## pushing forward, a strafe for one pushing that way. False with no arena, and for a ship that cannot fly.
func _thrusting(inst: Dictionary) -> bool:
	if arena == null or ship.components.def(inst["id"]).get("family", "") != "engine":
		return false
	var input: Dictionary = arena.ships[index].input
	var push := -Mounts.dir_of(inst)
	var throttle := float(input.get("throttle", 0.0))
	var strafe := float(input.get("strafe", 0.0))
	return (throttle != 0.0 and push.y < -0.5) or (strafe > 0.0 and push.x > 0.5) or (strafe < 0.0 and push.x < -0.5)


## What the art of weapon `uid` needs from the arena: {charge (0..1, how far the cooldown has run),
## fired_ago (seconds since the cooldown last restarted)}. A cooldown that jumps up means a shot was
## fired (the arena is only read, through cooldown_left); the longest cooldown seen since then is the
## full bar. Empty for a part that is not a weapon, or with no arena.
func _weapon_opts(uid: int) -> Dictionary:
	if arena != null and arena.ships[index].bays.has(uid):  # a drone bay: launch frames, empty cradle while its drone is out
		var d = arena.ships[index].bays[uid]["drone"]
		var ago: float = (arena.tick - int(arena.ships[index].bays[uid]["launched"])) * arena.SUBSTEP
		var homing: bool = d != null and d["state"] == "home" and Vector2(d["pos"]).distance_to(arena.local_to_world(index, arena.ships[index].bays[uid]["pos"])) < 120.0
		return {"bay_out": d != null, "bay_open": homing, "fired_ago": ago}
	if arena == null or not arena.ships[index].mounts.has(uid):
		return {}
	var left: float = arena.cooldown_left(index, uid)
	var w: Dictionary = _weapons.get(uid, {"left": left, "peak": left, "shot": -1.0e9})
	if left > float(w["left"]) + 0.001:
		w["shot"] = _clock
		w["peak"] = left
	w["left"] = left
	var out := {"charge": 1.0 if left <= 0.0 or w["peak"] <= 0.0 else 1.0 - left / w["peak"], "fired_ago": _clock - w["shot"]}
	var m: Dictionary = arena.ships[index].mounts[uid]
	var def: Dictionary = arena.weapons.def(m["id"])
	if def.has("chain"):  # the rotary barrel spins faster with each step (turns per second: SPIN_TURNS x steps)
		var steps: int = arena.weapons.chain_steps(arena, index, uid)
		w["spin"] = float(w.get("spin", 0.0)) + float(steps) * SPIN_TURNS * 4.0 * maxf(_clock - float(w.get("clk", _clock)), 0.0)
		out["chain"] = steps
		out["spin"] = float(w["spin"])
	if def.has("charge"):  # the capacitor rings: one lit per stored volley
		out["stored"] = arena.weapons.charges(arena, index, uid)
	w["clk"] = _clock
	_weapons[uid] = w
	return out


const SPIN_TURNS := 1.5  ## a chain gun's barrel turns this often a second per step


func _draw_tile(grid, c: Vector2i, id: String) -> void:
	var r := Rect2(px(Vector2(c)), Vector2(CELL, CELL))
	var col: Color = grid.defs.color(id)
	var def: Dictionary = grid.defs.get_def(id)
	if def.get("door", false):
		var piece: Array[Vector2i] = grid.door_piece(c)
		if piece[0] == c:
			_draw_door(grid, piece, col, grid.is_door_open(c))
	elif def.get("solid", false):
		TileArt.solid_cell(self, r, grid, c, id, col)
		if not _livery.is_empty() and grid.shape_of(c).is_empty():  # the livery washes the plating (the skin only covers the outermost ring)
			draw_rect(r, Color(_livery["palette"]["tint"], LIVERY_WASH) if id != "wall" else Color(_livery["palette"]["wall"], LIVERY_WASH * 0.7))
	else:
		if not TileArt.floor_tile(self, r, c):
			draw_rect(r, col)
			draw_rect(r.grow(-1), col.lightened(0.05), false, 1.0)
		if not _livery.is_empty():  # the livery's floor tint: the inside reads too
			draw_rect(r, Color(_livery["palette"]["floor"], FLOOR_WASH))


## The exterior skin over the walls that face space. The plan is remade when walls come or go (a breach, a repair).
func _draw_skin(grid) -> void:
	var sig := [grid.tiles.size(), grid.shapes.size(), grid.breached.size(), ship.components.instances.size()]
	if sig != _skin_sig:
		_skin = TileArt.skin_plan(grid, _part_lines())
		_skin_sig = sig
	var look: Dictionary = ship.get_meta("style", {})  # an enemy's livery (Shipgen.style_of): its palette over the skin, its emblem on the largest plate
	if not look.is_empty():
		var pal: Dictionary = look["palette"]
		_paint = {"tint": pal["tint"], "lamp": pal["lamp"], "patch": pal["patch"]}
		_paint_skin = "\u0001" + str(look["id"])
	elif ship.skin != _paint_skin:
		_paint = Unlocks.skin_paint(ship.skin)
		_paint_skin = ship.skin
	TileArt.draw_skin(self, _skin, px(Vector2.ZERO), CELL, _clock, _glow_quads, _paint)
	if not look.is_empty():
		if _emblem_sig != _skin_sig:
			_emblem_at = emblem_spot(_skin)
			_emblem_cells = emblem_cells(_skin)
			_emblem_sig = _skin_sig
		if _emblem_at.x > -1.0e8:
			Emblem.draw(self, look["emblem"], Rect2(px(_emblem_at) - Vector2(_emblem_cells, _emblem_cells) * CELL / 2.0, Vector2(_emblem_cells, _emblem_cells) * CELL), Color(look["palette"]["mark"], 0.95), CELL / 9.0)


## Where the emblem decal goes, in cell coordinates (the centre of the plate): the skin cell with the most skin around it, the one nearest the
## ship's middle column among those. (-1e9, -1e9) when the plan has no full plate.
## The side of the emblem decal in cells: a quarter of the hull's width (4 to 8).
static func emblem_cells(plan: Dictionary) -> float:
	var lo := 1 << 20
	var hi := -(1 << 20)
	for e in plan.get("cells", []):
		lo = mini(lo, e["c"].x)
		hi = maxi(hi, e["c"].x)
	return clampf(float(hi - lo + 1) * 0.25, 4.0, 8.0)


static func emblem_spot(plan: Dictionary) -> Vector2:
	var have := {}
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for e in plan.get("cells", []):
		if int(e["row"]) < 0:
			have[e["c"]] = true
			lo = lo.min(e["c"])
			hi = hi.max(e["c"])
	if have.is_empty():
		return Vector2(-1.0e9, -1.0e9)
	var mid := float(lo.x + hi.x + 1) / 2.0
	var best := Vector2i.ZERO
	var best_score := -1.0
	var cells: Array = have.keys()
	cells.sort()
	for c in cells:
		var n := 0
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				if have.has(c + Vector2i(dx, dy)):
					n += 1
		var score := float(n) - 0.01 * absf(float(c.x) + 0.5 - mid)
		if score > best_score + 1.0e-6:
			best_score = score
			best = c
	return Vector2(best) + Vector2(0.5, 0.5)


## Line -> cells of the ship's parts, so a ship full of neon parts wears the neon skin even on standard plates.
func _part_lines() -> Dictionary:
	var out := {}
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		var line := str(ship.components.def(inst["id"]).get("line", ""))
		if line != "":
			out[line] = int(out.get(line, 0)) + inst["cells"].size()
	return out


## A door piece: floor under it, two leaves that meet in the middle when closed and slide back into
## the walls at both ends when open (an open door lets shots through).
func _draw_door(grid, piece: Array[Vector2i], col: Color, open: bool) -> void:
	var floor_col: Color = grid.defs.color("floor") if grid.defs.has("floor") else col.darkened(0.5)
	var rects := []
	for p in piece:
		var cell_rect := Rect2(px(Vector2(p)), Vector2(CELL, CELL))
		rects.append(cell_rect)
		if not TileArt.floor_tile(self, cell_rect, p):
			draw_rect(cell_rect, floor_col)
	var horizontal: bool = piece[1].x != piece[0].x if piece.size() > 1 else true
	if TileArt.door_piece(self, rects, horizontal, TileArt.door_fraction(_doors, piece[0], open, _clock), _glow_quads):
		return
	var along := Vector2.RIGHT if horizontal else Vector2.DOWN
	var across := Vector2(along.y, along.x)
	var base := px(Vector2(piece[0]))
	var n := float(piece.size())
	var leaves := [[0.0, n * 0.25], [n * 0.75, n]] if open else [[0.0, n * 0.5], [n * 0.5, n]]
	for l in leaves:
		draw_rect(Rect2(base + along * (l[0] * CELL) + across * (CELL * 0.4), along * ((l[1] - l[0]) * CELL) + across * (CELL * 0.2)), col)
	if not open:
		draw_rect(Rect2(base + along * (n * 0.5 * CELL - 1.0) + across * (CELL * 0.4), along * 2.0 + across * (CELL * 0.2)), col.darkened(0.55))


## A shot-out cell: a dark ragged hole into space with a scorched rim.
func _draw_hole(c: Vector2i) -> void:
	var o := px(Vector2(c))
	if TileArt.breach(self, Rect2(o, Vector2(CELL, CELL)), c):
		return
	var h := hash(c)
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0
		var r := CELL * (0.42 + 0.1 * float((h >> (i * 2)) & 3) / 3.0)
		pts.append(o + Vector2(CELL, CELL) / 2.0 + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, HOLE)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, HOLE_RIM, 2.0)


## A damaged wall or door darkens and cracks with the hp it has lost.
func _draw_damage(grid, c: Vector2i) -> void:
	if not grid.tiles.has(c):
		return
	var lost: float = 1.0 - grid.hp_of(c) / maxf(grid.max_hp_of(c), 0.01)
	if lost <= 0.0:
		return
	var o := px(Vector2(c))
	var shade := Color(0.05, 0.02, 0.0, 0.55 * lost)
	if grid.shapes.has(c):  # only the solid part of a slope or a curve darkens
		var pts := PackedVector2Array()
		for p in grid.polygon_at(c):
			pts.append(o + p * CELL)
		draw_colored_polygon(pts, shade)
	else:
		draw_rect(Rect2(o, Vector2(CELL, CELL)), shade)
	draw_line(o + Vector2(4, 6), o + Vector2(CELL * 0.55, CELL * 0.5), Color(0, 0, 0, 0.8), 1.5)
	if lost > 0.4:
		draw_line(o + Vector2(CELL * 0.55, CELL * 0.5), o + Vector2(CELL - 5, CELL - 8), Color(0, 0, 0, 0.8), 1.5)


# --- fire and health (placeholder art: swap these two helpers for real art) -----------------------

## Fires as flickering blobs: a red base, an orange body and a yellow core per burning cell, bigger
## with the intensity. `fires`: cell -> intensity (0..1); `origin`: where cell (0, 0) starts, in the
## canvas' pixels; `t`: seconds, for the flicker. Static, so the interior view uses it too.
static func draw_fire(canvas: CanvasItem, fires: Dictionary, origin: Vector2, cell_px: float, t: float, glow_out = null) -> void:
	for c in fires:
		var i: float = clampf(fires[c], 0.0, 1.0)
		if TileArt.fire_cell(canvas, Rect2(origin + Vector2(c) * cell_px, Vector2(cell_px, cell_px)), i, t, c, glow_out):
			continue
		var h := hash(c)
		var phase := float(h & 255) / 40.0
		var flick := 0.88 + 0.12 * sin(t * 11.0 + phase) + 0.05 * sin(t * 23.0 + phase * 2.0)
		var mid := origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell_px
		var r := cell_px * (0.35 + 0.5 * i) * flick
		canvas.draw_circle(mid, r * 1.5, Color(1.0, 0.25, 0.05, 0.14 + 0.1 * i))
		canvas.draw_circle(mid + Vector2(sin(t * 7.0 + phase), 0.0) * cell_px * 0.06, r, Color(0.95, 0.2, 0.06, 0.55 + 0.3 * i))
		canvas.draw_circle(mid + Vector2(0.0, -0.08) * cell_px, r * 0.68, Color(1.0, 0.55, 0.1, 0.75))
		canvas.draw_circle(mid + Vector2(0.0, -0.14) * cell_px, r * 0.36 * flick, Color(1.0, 0.9, 0.4, 0.9))


## A small health bar over the head of a person at `centre` (pixels), only when hurt or down. A downed person
## with `bleed` above 0 (0..1, the share of their bleed-out time gone: Mortality.bleed_frac) also gets a red ring
## that empties as it grows.
static func draw_health(canvas: CanvasItem, centre: Vector2, frac: float, down: bool, cell_px: float, bleed := 0.0) -> void:
	if frac >= 1.0 and not down:
		return
	var w := cell_px * 1.8
	var r := Rect2(centre + Vector2(-w / 2.0, -cell_px * 1.9), Vector2(w, cell_px * 0.22))
	canvas.draw_rect(r.grow(1.5), Color(0, 0, 0, 0.7))
	canvas.draw_rect(r, Color("#5a1d1d"))
	canvas.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), Color("#7bd88f") if frac > 0.4 else Color("#ff5a4a"))
	if down:  # a red cross over them
		var k := cell_px * 0.7
		canvas.draw_line(centre + Vector2(-k, -k), centre + Vector2(k, k), Color(1, 0.2, 0.2, 0.8), 3.0)
		canvas.draw_line(centre + Vector2(-k, k), centre + Vector2(k, -k), Color(1, 0.2, 0.2, 0.8), 3.0)
		if bleed > 0.0:  # the bleed-out ring: full when they fall, empty (clockwise from the top) when they die
			canvas.draw_arc(centre, cell_px * 1.2, 0.0, TAU, 40, Color(0, 0, 0, 0.55), 5.0)
			canvas.draw_arc(centre, cell_px * 1.2, -PI / 2.0 + TAU * clampf(bleed, 0.0, 1.0), 1.5 * PI, 40, Color(1.0, 0.18, 0.15, 0.95), 3.5)


# --- shield bubble ----------------------------------------------------------------------------

## The part of the polyline `pts` between the fractions `t0` and `t1` of its length (0..1).
static func sub_line(pts: PackedVector2Array, t0: float, t1: float) -> PackedVector2Array:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var out := PackedVector2Array()
	var done := 0.0
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		var a := maxf(t0 * total - done, 0.0)
		var b := minf(t1 * total - done, seg)
		if b > a and seg > 0.0:
			if out.is_empty():
				out.append(pts[i].lerp(pts[i + 1], a / seg))
			out.append(pts[i].lerp(pts[i + 1], b / seg))
		done += seg
	return out


## Dashes of `dash` px with `gap` px between along the polyline `pts` on the canvas `cv`, starting `phase` px in.
static func dashed(cv: CanvasItem, pts: PackedVector2Array, col: Color, width: float, dash := 12.0, gap := 9.0, phase := 0.0) -> void:
	var pos := -phase
	for i in pts.size() - 1:
		var a := pts[i]
		var seg := pts[i].distance_to(pts[i + 1])
		var dir := (pts[i + 1] - a) / maxf(seg, 1e-6)
		var at := 0.0
		while at < seg:
			var cycle := fposmod(pos + at, dash + gap)
			if cycle < dash:
				var run := minf(dash - cycle, seg - at)
				cv.draw_line(a + dir * at, a + dir * (at + run), col, width)
				at += maxf(run, 0.01)
			else:
				at += maxf(dash + gap - cycle, 0.01)
		pos += seg


## The bubble: the hull-hugging outline (Shields.shape_of) cut into the ship's sectors. Each sector's line is
## brighter and thicker for every layer it holds, a faint dashed line at 0, shimmers while its layers fill
## and flashes when a shot hits it. An open sector (it just fired) is dim and broken; an ion-locked bubble
## flickers violet; an overcharged one has a gold second skin.
func _draw_bubble(co) -> void:
	if co.wrecked or co.layers_cap <= 0:
		return
	var shape = Shields.shape_of(co)
	var n: int = co.sectors
	var lines: Array = shape.sector_lines(n)
	var ion: bool = co.ion_lock > 0.0
	var tint := ION if ion else (OVERCHARGE if co.overcharge_left > 0.0 else BUBBLE)
	var flick := 0.35 + 0.25 * sin(_clock * 38.0)
	for k in n:
		var st: Dictionary = Shields.sector_state(co, k, arena.tick)
		var pts := PackedVector2Array()
		for p in lines[k]:
			pts.append(px(p))
		var up: float = 0.0 if ion or float(st["layers"]) <= Shields.EPS else 1.0 + 2.0 * clampf(float(st["layers"]) / maxf(float(st["cap"]), 0.001), 0.0, 1.0)  # (by its share of HP)
		var hit := clampf(1.0 - float(arena.tick - int(co.sector_hit[k])) / 60.0 / HIT_FLASH_S, 0.0, 1.0)
		var fill := 0.03 + 0.03 * up + 0.14 * hit
		var alpha := minf(0.22 + 0.17 * up, 0.9)
		var width := 2.0 + 1.0 * up
		var wedge := PackedVector2Array([Vector2.ZERO]) + pts if n > 1 else pts
		if st["open"]:  # it just fired through here: dim and broken
			draw_colored_polygon(wedge, Color(tint, fill * flick))
			var shift := int(_clock * 24.0)
			for i in pts.size() - 1:
				if (i + shift) % 3 != 0:
					draw_line(pts[i], pts[i + 1], Color(tint, 0.35 * flick), 1.5)
			continue
		draw_colored_polygon(wedge, Color(tint, fill))
		if ion:
			draw_polyline(pts, Color(tint, 0.2 + 0.3 * absf(sin(_clock * 25.0))), 2.0, true)
		elif up < 1.0:  # no whole layer: a faint dashed line
			dashed(self, pts, Color(tint, 0.22), 1.5, 12.0, 9.0, _clock * 6.0 if st["filling"] else 0.0)
		else:
			draw_polyline(pts, Color(tint, alpha), width, true)
		if hit > 0.0:
			draw_polyline(pts, Color(1, 1, 1, 0.8 * hit), width + 3.0 * hit, true)
		if st["filling"] and not ion:  # layers on their way back: a bright run travels along the line
			var at := fposmod(_clock * 0.45 + 0.17 * k, 1.0)
			var run := sub_line(pts, at, minf(at + 0.12, 1.0))
			if run.size() > 1:
				draw_polyline(run, Color(tint.lightened(0.5), 0.75), width + 1.5, true)
	if n > 1:
		for k in n:
			draw_line(Vector2.ZERO, px(shape.boundary_toward(Vector2.from_angle((float(k) - 0.5) * TAU / n - PI / 2.0))), Color(tint, 0.10), 1.0)
	if co.overcharge_left > 0.0:
		var outer := PackedVector2Array()
		for p in shape.grown(0.35).outline():
			outer.append(px(p))
		outer.append(outer[0])
		draw_polyline(outer, Color(OVERCHARGE, 0.35 + 0.2 * sin(_clock * 6.0)), 2.0, true)
