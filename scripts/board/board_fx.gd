extends Control
## The light of a shot aboard (docs/BOARDING.md, B4): bolts that fly from the muzzle to the hit point, the lights they carry, the flash and sparks where they land, the
## scorch they leave on a wall, the flares that burn where they stuck. board_view.gd feeds it the events of the session (shot, impact, flare, swing) and steps it;
## it sits in the HUD's canvas layer (so the dark does not dim a bolt) and draws with additive blending. The lights are PointLight2D in the world canvas, pooled:
## at most `bolts.max_lights` bolt, flash or flare lights at once, the oldest gives its light up (the thing keeps flying, unlit). Only `bolts.shadow_lights` of them
## cast shadows from the walls' occluders at a time (the burning flares first, then the newest bolts): a shadow costs far more than the light. The look of every bolt is data
## (bolts.gd, data/boarding.json `bolts`). Visual randomness has a seed of its own.

const BoardLight = preload("res://scripts/board/board_light.gd")
const Bolts = preload("res://scripts/board/bolts.gd")
const Site = preload("res://scripts/board/site.gd")

const CELL := 32.0
const MAX_SPARKS := 160
const MAX_SCORCH := 48
const FLASH_S := 0.16
const LIGHT_HALF_PX := 64.0  ## half the width of the round light texture

var view: Node2D  ## board_view.gd (to_screen, cam)
var lights_root: Node2D  ## where the pooled lights live (the world canvas, so the walls' occluders and the dark count)
var bolts: Array = []  ## flying bolts: {look, from, to (cells), age, travel, kind (what it hit), light, born}
var flashes: Array = []  ## {pos (cells), age, life, color, radius, light, born}
var sparks: Array = []  ## {pos (cells), vel, age, life, color, len}
var flares := {}  ## flare id -> {pos (cells), age, light, born}
var swings: Array = []  ## {from, dir, reach, age, color}
var scorch: Array = []  ## {pos (px), age, seed}: dark marks on a wall (board_view.gd draws them in the world, so they are dark where the dark is)
var _pool: Array = []  # [PointLight2D]
var _users: Array = []  # parallel to _pool: the entry (bolt, flash or flare) that holds each light, or null
var _born := 0
var _rng := RandomNumberGenerator.new()
var _clock := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 4242
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func cfg() -> Dictionary:
	return Bolts.cfg()


## Lights in use right now (what the budget counts).
func lights_in_use() -> int:
	var n := 0
	for u in _users:
		if u != null:
			n += 1
	return n


## Everything that is alive: for tests and the frame-time report.
func counts() -> Dictionary:
	return {"bolts": bolts.size(), "flashes": flashes.size(), "sparks": sparks.size(), "flares": flares.size(), "lights": lights_in_use(), "pool": _pool.size()}


# --- spawning ---------------------------------------------------------------------------------------------------------------

## A bolt of `look` leaves `from` for `to` (cells), `travel` seconds on the way; `hit` is what it ends on ("body", "wall", "prop" or "air").
func shot(look: Dictionary, from: Vector2, to: Vector2, travel: float, hit: String) -> void:
	var b := {"look": look, "from": from, "to": to, "age": 0.0, "travel": travel, "kind": hit, "light": -1, "born": _next_born(), "done": false}
	if float(look.get("energy", 0.0)) > 0.0:
		_give_light(b, Color(str(look["color"])), 0.0, float(look["light_r"]))
	bolts.append(b)
	if bolts.size() > 40:
		_drop(bolts[0])
		bolts.remove_at(0)


## A melee swing: a short arc in the air.
func swing(from: Vector2, dir: float, reach: float, color: Color) -> void:
	swings.append({"from": from, "dir": dir, "reach": reach, "age": 0.0, "color": color})


## A flash where a body was hit, in the colour `color` (the bolt's).
func hit_flash(pos: Vector2, color: Color) -> void:
	var f := {"pos": pos, "age": 0.0, "life": FLASH_S, "color": color, "radius": 2.6, "light": -1, "born": _next_born()}
	_give_light(f, color, 1.2, 2.6)
	flashes.append(f)
	_spray(pos, color, 5, "body", 0.0)


## A flare lands at `pos` and burns until flare_out().
func flare(id: int, pos: Vector2) -> void:
	var f := {"pos": pos, "age": 0.0, "light": -1, "born": _next_born()}
	_give_light(f, Color("#ff7a3a"), 1.1, float(Site.config()["flare"]["radius"]) + 0.6)
	flares[id] = f
	_spray(pos, Color("#ffb070"), 10, "spark", 0.0)


func flare_out(id: int) -> void:
	if flares.has(id):
		_drop(flares[id])
		flares.erase(id)


## Where a burning flare is (cells), null when none burns (the burn loop plays there).
func a_flare() -> Variant:
	for id in flares:
		return flares[id]["pos"]
	return null


func _next_born() -> int:
	_born += 1
	return _born


## The bolt reaches its end: a flash and sparks by what it hit and how (`impact`), and a scorch on a wall.
func _land(b: Dictionary) -> void:
	var look: Dictionary = b["look"]
	var at: Vector2 = b["to"]
	var col := Color(str(look["color"]))
	var imp := str(look.get("impact", "spark"))
	if imp == "none" or b["kind"] == "air":
		return
	if b["kind"] != "body":  # (a body shows its own flash when the hit arrives)
		var f := {"pos": at, "age": 0.0, "life": FLASH_S, "color": col, "radius": 2.4 + float(look.get("size", 1.0)) * 0.4, "light": -1, "born": _next_born()}
		if b["light"] >= 0:  # the bolt's own light stays for the flash
			f["light"] = b["light"]
			_users[b["light"]] = f
			b["light"] = -1
		else:
			_give_light(f, col, 1.1, 2.4)
		flashes.append(f)
		_spray(at, col, {"slug": 12, "arc": 9, "flame": 9}.get(imp, 7), imp, float(look.get("size", 1.0)))
	if b["kind"] == "wall" and imp in ["spark", "slug", "arc", "flame"]:
		var dir: Vector2 = (b["to"] - b["from"]).normalized()
		scorch.append({"pos": (at + dir * 0.2) * CELL, "age": 0.0, "seed": _rng.randi()})
		if scorch.size() > MAX_SCORCH:
			scorch.remove_at(0)


func _spray(at: Vector2, col: Color, n: int, imp: String, size: float) -> void:
	for i in n:
		if sparks.size() >= MAX_SPARKS:
			sparks.remove_at(0)
		var a := _rng.randf() * TAU
		var sp := _rng.randf_range(2.0, 7.0)
		var life := _rng.randf_range(0.18, 0.4)
		var vel := Vector2.from_angle(a) * sp
		var c := col.lightened(_rng.randf_range(0.0, 0.5))
		if imp == "flame":
			vel = Vector2(vel.x * 0.4, -absf(vel.y) * 0.5 - 1.0)
			life *= 1.6
			c = Color("#ff9a3c").lerp(Color("#ffd870"), _rng.randf())
		elif imp == "arc":
			c = Color("#9fd2ff").lerp(Color.WHITE, _rng.randf())
			life *= 0.7
		sparks.append({"pos": at, "vel": vel, "age": 0.0, "life": life, "color": c, "len": 0.25 + 0.1 * size})


# --- lights -----------------------------------------------------------------------------------------------------------------

func _give_light(entry: Dictionary, color: Color, energy: float, radius: float) -> void:
	if lights_root == null:
		return
	var idx := -1
	for i in _users.size():
		if _users[i] == null:
			idx = i
			break
	if idx < 0 and _pool.size() < int(cfg()["max_lights"]):
		var l := PointLight2D.new()
		l.texture = BoardLight.round_texture()
		l.shadow_filter = Light2D.SHADOW_FILTER_NONE
		l.visible = false
		lights_root.add_child(l)
		_pool.append(l)
		_users.append(null)
		idx = _pool.size() - 1
	if idx < 0:  # the budget is spent: the oldest holder loses its light
		idx = 0
		for i in _users.size():
			if int(_users[i]["born"]) < int(_users[idx]["born"]):
				idx = i
		_users[idx]["light"] = -1
	var light: PointLight2D = _pool[idx]
	light.color = color
	light.energy = energy
	light.shadow_enabled = false  # (_assign_shadows decides each frame who casts one)
	light.texture_scale = radius * CELL / LIGHT_HALF_PX
	light.visible = true
	_users[idx] = entry
	entry["light"] = idx


func _drop(entry: Dictionary) -> void:
	var i := int(entry.get("light", -1))
	if i >= 0 and i < _users.size() and _users[i] == entry:
		_users[i] = null
		_pool[i].visible = false
	entry["light"] = -1


func _set_light(entry: Dictionary, pos: Vector2, energy: float) -> void:
	var i := int(entry.get("light", -1))
	if i >= 0:
		_pool[i].position = pos * CELL
		_pool[i].energy = energy


## Put everything away (the visit ends).
func clear() -> void:
	for l in _pool:
		if is_instance_valid(l):
			l.visible = false
	for i in _users.size():
		_users[i] = null
	bolts.clear()
	flashes.clear()
	sparks.clear()
	flares.clear()
	swings.clear()
	scorch.clear()


# --- stepping -----------------------------------------------------------------------------------------------------------------

func step(dt: float) -> void:
	_clock += dt
	var keep := []
	for b in bolts:
		b["age"] = float(b["age"]) + dt
		var look: Dictionary = b["look"]
		var travel := float(b["travel"])
		var p := 1.0 if travel <= 0.0 else clampf(float(b["age"]) / travel, 0.0, 1.0)
		var head: Vector2 = b["from"].lerp(b["to"], p)
		if str(look["kind"]) == "beam":
			head = b["from"].lerp(b["to"], 0.6)
		var fl := 0.85 + 0.3 * sin(_clock * 60.0 + float(b["born"]))
		if str(look["kind"]) == "beam":  # a beam's light holds, then goes with it
			fl *= 1.0 - clampf((float(b["age"]) - travel) / maxf(float(look.get("hold", 0.15)), 0.01), 0.0, 1.0)
		_set_light(b, head, float(look["energy"]) * fl)
		var over := float(b["age"]) >= travel
		if over and not bool(b["done"]):
			b["done"] = true
			_land(b)
		var life := travel + (float(look.get("hold", 0.0)) if str(look["kind"]) == "beam" else float(look["len"]) / maxf(float(look["speed"]), 1.0))
		if float(b["age"]) < life:
			keep.append(b)
		else:
			_drop(b)
	bolts = keep
	keep = []
	for f in flashes:
		f["age"] = float(f["age"]) + dt
		var k := 1.0 - float(f["age"]) / float(f["life"])
		if k > 0.0:
			_set_light(f, f["pos"], 1.2 * k)
			keep.append(f)
		else:
			_drop(f)
	flashes = keep
	keep = []
	for s in sparks:
		s["age"] = float(s["age"]) + dt
		s["pos"] += s["vel"] * dt
		s["vel"] *= maxf(1.0 - dt * 4.0, 0.0)
		if float(s["age"]) < float(s["life"]):
			keep.append(s)
	sparks = keep
	for id in flares:
		var f: Dictionary = flares[id]
		f["age"] = float(f["age"]) + dt
		_set_light(f, f["pos"], 1.1 * (0.85 + 0.25 * sin(_clock * 23.0 + float(id)) * sin(_clock * 9.0)))
		if _rng.randf() < dt * 14.0:
			_spray(f["pos"], Color("#ffb070"), 1, "spark", 0.0)
	keep = []
	for w in swings:
		w["age"] = float(w["age"]) + dt
		if float(w["age"]) < 0.14:
			keep.append(w)
	swings = keep
	var fade := float(cfg()["scorch_s"])
	keep = []
	for sc in scorch:
		sc["age"] = float(sc["age"]) + dt
		if float(sc["age"]) < fade:
			keep.append(sc)
	scorch = keep
	_assign_shadows()
	queue_redraw()


## The burning flares and then the newest bolts cast shadows, up to the budget; every other light is flat.
func _assign_shadows() -> void:
	var budget := int(cfg()["shadow_lights"])
	var order: Array = flares.values().duplicate()
	for i in range(bolts.size() - 1, -1, -1):
		order.append(bolts[i])
	var casts := {}
	for e in order:
		var i := int(e["light"])
		if i >= 0 and casts.size() < budget:
			casts[i] = true
	for i in _pool.size():
		var want: bool = casts.has(i)
		if _pool[i].shadow_enabled != want:
			_pool[i].shadow_enabled = want


# --- drawing ------------------------------------------------------------------------------------------------------------------

func _zoom() -> float:
	return view.cam.zoom.x if view != null and view.cam != null else 1.0


func _draw() -> void:
	if view == null or view.session == null:
		return
	var z := _zoom()
	for b in bolts:
		_draw_bolt(b, z)
	for w in swings:
		var a: float = 1.0 - float(w["age"]) / 0.14
		var c: Vector2 = view.to_screen(w["from"])
		var half := deg_to_rad(float(Site.config()["combat"]["swing_arc_deg"])) / 2.0
		var r: float = float(w["reach"]) * CELL * z * (0.6 + 0.4 * (1.0 - a))
		draw_arc(c, r, float(w["dir"]) - half, float(w["dir"]) + half, 14, Color(w["color"], 0.55 * a), 5.0 * z, true)
		draw_arc(c, r * 0.94, float(w["dir"]) - half, float(w["dir"]) + half, 14, Color(1, 1, 1, 0.45 * a), 2.0 * z, true)
	for f in flashes:
		var k := 1.0 - float(f["age"]) / float(f["life"])
		var at: Vector2 = view.to_screen(f["pos"])
		var rad: float = float(f["radius"]) * CELL * z * 0.3 * (0.5 + 0.5 * k)
		draw_circle(at, rad * 1.8, Color(f["color"], 0.18 * k))
		draw_circle(at, rad, Color(f["color"], 0.5 * k))
		draw_circle(at, rad * 0.5, Color(1, 1, 1, 0.9 * k))
	for s in sparks:
		var k2 := 1.0 - float(s["age"]) / float(s["life"])
		var p0: Vector2 = view.to_screen(s["pos"])
		var p1: Vector2 = view.to_screen(s["pos"] - s["vel"].normalized() * float(s["len"]) * k2) if s["vel"].length() > 0.01 else p0
		draw_line(p0, p1, Color(s["color"], k2), 2.0 * z, true)
	for id in flares:
		var f2: Dictionary = flares[id]
		var at2: Vector2 = view.to_screen(f2["pos"])
		var fl := 0.8 + 0.2 * sin(_clock * 30.0 + float(id))
		draw_circle(at2, 22.0 * z * fl, Color("#ff7a3a", 0.12))
		draw_circle(at2, 10.0 * z * fl, Color("#ffa060", 0.35))
		draw_circle(at2, 4.0 * z, Color("#fff0c0", 0.95))


func _draw_bolt(b: Dictionary, z: float) -> void:
	var look: Dictionary = b["look"]
	var col := Color(str(look["color"]))
	var core := Color(str(look["core"]))
	var w := float(look["width"]) * z
	var travel := float(b["travel"])
	var age := float(b["age"])
	var p := 1.0 if travel <= 0.0 else clampf(age / travel, 0.0, 1.0)
	var from: Vector2 = b["from"]
	var to: Vector2 = b["to"]
	var dir: Vector2 = (to - from).normalized() if to != from else Vector2.RIGHT
	var head: Vector2 = from.lerp(to, p)
	var length := float(look["len"])
	var tail: Vector2 = head - dir * minf(length, from.distance_to(head))
	match str(look["kind"]):
		"beam":
			var hold := maxf(float(look.get("hold", 0.15)), 0.01)
			var a := clampf(1.0 - maxf(age - travel, 0.0) / hold, 0.0, 1.0)
			_glow(view.to_screen(from), view.to_screen(to), col, core, w * (0.5 + 0.5 * a), a)
		"arc":
			var pts := PackedVector2Array([view.to_screen(tail)])
			var n := 7
			for i in range(1, n):
				var q: Vector2 = tail.lerp(head, float(i) / float(n))
				pts.append(view.to_screen(q + dir.orthogonal() * _rng.randf_range(-1.0, 1.0) * float(look.get("jitter", 0.3))))
			pts.append(view.to_screen(head))
			draw_polyline(pts, Color(col, 0.35), w * 3.0, true)
			draw_polyline(pts, Color(core, 0.95), w * 0.8, true)
		"flame":
			var side := dir.orthogonal()
			var spread := (0.18 + 0.1 * _rng.randf()) * length
			var a1: Vector2 = view.to_screen(head)
			var a2: Vector2 = view.to_screen(tail + side * spread)
			var a3: Vector2 = view.to_screen(tail - side * spread)
			draw_colored_polygon(PackedVector2Array([a1, a2, a3]), Color("#ff6a1a", 0.35 + 0.15 * _rng.randf()))
			var m1: Vector2 = view.to_screen(head - dir * length * 0.15)
			draw_colored_polygon(PackedVector2Array([m1, view.to_screen(tail.lerp(head, 0.35) + side * spread * 0.5), view.to_screen(tail.lerp(head, 0.35) - side * spread * 0.5)]), Color("#ffd870", 0.45 + 0.2 * _rng.randf()))
		"flare":
			_glow(view.to_screen(tail), view.to_screen(head), col, core, w, 1.0)
			draw_circle(view.to_screen(head), w * 1.1, Color(core, 0.9))
		_:
			_glow(view.to_screen(tail), view.to_screen(head), col, core, w, 1.0)


func _glow(a: Vector2, b: Vector2, col: Color, core: Color, w: float, alpha: float) -> void:
	draw_line(a, b, Color(col, 0.16 * alpha), w * 3.4, true)
	draw_line(a, b, Color(col, 0.4 * alpha), w * 1.8, true)
	draw_line(a, b, Color(core, 0.95 * alpha), w * 0.75, true)
	draw_circle(b, w * 0.95, Color(core, 0.85 * alpha))
