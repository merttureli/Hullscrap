extends RefCounted
## The swappable art registry: every component is drawn through draw_component(), by id. If
## art/components/<id>.png exists (scripts/view/art.gd), its sprite is drawn at the footprint, turned
## with the part, and the animation follows the part's state (anim_state()); otherwise a flat
## placeholder is drawn (see art/README.md for how to drop art in). On top of either it overlays the
## component's state: a heat bar, an orange "!" when overheated, a yellow gear when malfunctioning
## and a row of hp pips when damaged. Drawing only, no game logic.

const Stats = preload("res://scripts/sim/stats.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Art = preload("res://scripts/view/art.gd")
const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const FIRE_WINDOW := 0.15  ## seconds a weapon shows its fire frame after a shot
const BARRELS: Array[String] = ["weapon", "radar", "tractor"]  ## the families whose outside half carries a head that turns: a gun, a dish, an emitter
const DISH_SPIN := 2.1  ## radians a second a radar dish turns while the radar works
const DAMAGED_BELOW := 0.5  ## hp fraction under which a part looks damaged
const DIM := Color(0.45, 0.45, 0.5)
const HEAT_RED := Color(1.0, 0.18, 0.1)
const SPARK_COLORS := [Color("#ffd23a"), Color("#ffffff"), Color("#ff8a1e")]
const HEAT_SHOWN := 0.3  ## the heat bar appears above this fraction of the limit
const GREY := Color("#5b5f6b")
const HEAT_COLD := Color("#f2c14e")
const HEAT_HOT := Color("#ff3b2f")
const OVERHEAT_COLOR := Color("#ff8a1f")
const MALFUNCTION_COLOR := Color("#ffe14a")
const HP_COLOR := Color("#5bd67a")
const HP_LOST_COLOR := Color("#7a2530")
## Placeholder accent per line: scrap gets a hazard-stripe corner, neon a bright outline.
const SCRAP_ACCENT := Color("#f2c14e")
const NEON_ACCENT := Color("#3ef0ff")

## What the state overlay shows for a component: {status, heat (0..1), show_heat, hp, max_hp,
## show_hp}. `inst` may be empty (a ghost): everything is then healthy and cold.
static func marks(def: Dictionary, inst: Dictionary) -> Dictionary:
	var max_hp := Stats.max_hp(def)
	var limit := maxf(1.0, float(def.get("heat_limit", Stats.DEFAULT_HEAT_LIMIT)))
	var heat := clampf(float(inst.get("heat", 0.0)) / limit, 0.0, 1.0)
	var hp := int(inst.get("hp", max_hp))
	return {
		"status": str(inst.get("status", "ok")),
		"heat": heat, "show_heat": heat > HEAT_SHOWN,
		"hp": hp, "max_hp": max_hp, "show_hp": hp < max_hp,
	}


## A 1-2 letter name for a system: "R1" for Reactor Mk1, the initials of two words ("OG"), else two letters.
static func label_of(def: Dictionary) -> String:
	var words: PackedStringArray = str(def.get("name", def.get("id", "?"))).split(" ", false)
	if words.is_empty():
		return "?"
	if words.size() > 1 and words[-1].begins_with("Mk"):
		return words[0][0] + words[-1].substr(2)
	return words[0][0] + words[1][0] if words.size() > 1 else words[0].substr(0, 2)


## Draw component `def` into `rect` (the screen rectangle of its whole, already rotated, footprint)
## on `canvas` (a CanvasItem; call this from its _draw). `inst`: the runtime state {rot, hp, heat,
## status}. `cell_px`: pixels per grid cell. `opts`: powered (default true; false marks a consumer
## without power), alpha (default 1, for ghosts), time (seconds, for the loops), charge (a weapon's
## charge 0..1, default ready), fired_ago (seconds since a weapon's last shot), glow_out (an Array that
## collects the glow quads for an additive GlowLayer instead of drawing them over the sprite).
static func draw_component(canvas, rect: Rect2, def: Dictionary, inst: Dictionary, cell_px: float, opts := {}) -> void:
	var m := marks(def, inst)
	var alpha := float(opts.get("alpha", 1.0))
	var sheet = Art.component(str(def.get("id", "")))
	if sheet != null:
		_draw_sheet(canvas, sheet, rect, def, inst, cell_px, opts)
	else:
		_draw_placeholder(canvas, rect.grow(-2), def, cell_px, m, bool(opts.get("powered", true)), alpha)
	_draw_marks(canvas, rect.grow(-2), m, alpha)
	if inst.has("n") and str(def.get("family", "")) == "ammo_rack":  # a rack's count
		_draw_text(canvas, str(int(inst["n"])), rect.end - Vector2(11.0, 9.0), 11, Color(1, 1, 1, alpha), true)


# --- hull mounts (docs/CONTENT.md 4f): the outside half, its barrel, and the debris of wrecked parts -----------

## Draw the outside half of hull mount `def` (a placed one, `inst`, or a ghost: `inst` may only have rot, out_hp
## and uid) into `rect`, the screen rectangle of its cells, and for a weapon its barrel about `pivot` (the
## barrel's turning point in the canvas' pixels) pointing along `aim` (a ship-local unit vector; the
## outward direction when left out). Art: <id>_out and <id>_barrel (art/README.md), else a flat block and a
## line. `opts` as draw_component, plus: thrusting (an engine's flame is on; it is off otherwise),
## fired_ago (seconds since the last shot, for the barrel's recoil and flash).
static func draw_mount_out(canvas, def: Dictionary, inst: Dictionary, rect: Rect2, pivot: Vector2, cell_px: float, aim := Vector2.ZERO, opts := {}) -> void:
	var mount: Dictionary = def["mount"]
	var rot := int(inst.get("rot", 0))
	var out_hp := int(inst.get("out_hp", mount["outside_hp"]))
	var d2 := def.duplicate()
	d2["size"] = mount["outside"]
	d2["hp"] = mount["outside_hp"]
	var i2 := {"rot": rot, "hp": out_hp, "heat": 0.0, "status": "disabled" if out_hp <= 0 else "ok", "uid": int(inst.get("uid", 0))}
	var angled := Mounts.is_angled(inst)
	if angled:  # on a slope: `rect` is the box about the outside half's middle and the art turns to the face
		i2["face"] = inst["angle"]
	var o2 := opts.duplicate()
	var family := str(def.get("family", ""))
	if family == "engine":
		o2["powered"] = bool(opts.get("thrusting", false)) and bool(opts.get("powered", true))
	var alpha := float(opts.get("alpha", 1.0))
	var sheet = Art.component(str(def.get("id", "")) + "_out")
	var fits: bool = sheet != null and (sheet.cells == Vector2i.ZERO or sheet.cells == Vector2i(int(mount["outside"][0]), int(mount["outside"][1])))
	if sheet != null and not fits:  # art made for another shape: the flat block, never the old art stretched
		sheet = null
	if sheet != null:
		_draw_sheet(canvas, sheet, rect, d2, i2, cell_px, o2)
	else:
		var m := marks(d2, i2)
		var flat := rect
		if angled:  # the flat block, turned about its middle
			flat = Rect2(-rect.size / 2.0, rect.size)
			canvas.draw_set_transform_matrix(Transform2D(deg_to_rad(float(inst["angle"]) - rot * 90.0), rect.get_center()))
		_draw_placeholder(canvas, flat.grow(-2), d2, cell_px, m, bool(o2.get("powered", true)), alpha)
		canvas.draw_rect(flat.grow(-2), Color(0, 0, 0, 0.25 * alpha))
		if angled:
			canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	if not family in BARRELS:
		return
	var dir := Mounts.dir_of(inst)
	if family == "radar" and aim == Vector2.ZERO and bool(opts.get("powered", true)):  # the dish turns by itself while it works
		aim = Vector2.UP.rotated(float(opts.get("time", 0.0)) * DISH_SPIN)
	var live := aim if aim != Vector2.ZERO and out_hp > 0 and str(def.get("shape", "")) != "flush_pod" else dir  # a disabled barrel hangs along the mount; a pod's hatch lids never turn
	var pivots: Array[Vector2] = [pivot]
	var art := Mounts.barrel_art(def)
	if fits and art["pivots_px"].size() > 1:  # a base with several barrels (broadside battery, gun strip): each turned the same way
		var half := Vector2(float(mount["outside"][0]), float(mount["outside"][1])) * SpriteSheet.SRC_CELL / 2.0
		var turn := deg_to_rad(float(inst["angle"])) if angled else posmod(rot, 4) * PI / 2.0
		pivots = []
		for p in art["pivots_px"]:
			pivots.append(rect.get_center() + (p - half).rotated(turn) * cell_px / SpriteSheet.SRC_CELL)
	var reach: float = Mounts.barrel(def, Mounts.NONE, rot)["reach"]
	for k in pivots.size():
		var o3 := opts
		if pivots.size() > 1 and opts.has("fired_ago"):  # staggered recoil: barrel k fires stagger_s later than barrel k - 1 (idle until then)
			o3 = opts.duplicate()
			var ago: float = float(opts["fired_ago"]) - k * float(art["stagger_s"])
			if ago < 0.0:
				o3.erase("fired_ago")
			else:
				o3["fired_ago"] = ago
		_draw_barrel(canvas, def, i2, pivots[k], cell_px, live, o3, reach)


## The screen rectangle of the outside half of a placed mount on a slope: the box of its quarter-turn size about its middle
## (the art is turned about that middle). `origin`: where grid cell (0, 0) starts in the canvas' pixels.
static func slope_rect(def: Dictionary, inst: Dictionary, origin: Vector2, cell_px: float) -> Rect2:
	var r := Mounts.out_rect(def, inst)
	return Rect2(origin + r.position * cell_px, r.size * cell_px)


## The barrel of weapon `def` about `pivot`, turned to point along `aim` (see draw_mount_out): its frame by the outside
## half's state (disabled, fire for a moment after a shot, damaged, idle), the fire flash on the glow layer.
static func _draw_barrel(canvas, def: Dictionary, i2: Dictionary, pivot: Vector2, cell_px: float, aim: Vector2, opts: Dictionary, reach: float) -> void:
	var alpha := float(opts.get("alpha", 1.0))
	var sheet = Art.component(str(def.get("id", "")) + "_barrel")
	var angle := Vector2.UP.angle_to(aim)
	if sheet == null:
		canvas.draw_line(pivot, pivot + aim * reach * cell_px, Color(0.85, 0.87, 0.9, alpha), maxf(3.0, cell_px / 6.0))
		canvas.draw_circle(pivot, cell_px * 0.25, Color(0.3, 0.32, 0.38, alpha))
		return
	var hp := int(i2["hp"])
	var max_hp := int(def["mount"]["outside_hp"])
	var t := float(opts.get("time", 0.0))
	var anim := "idle"
	var frame := 0
	if hp <= 0 and sheet.has_anim("disabled"):
		anim = "disabled"
	elif not bool(opts.get("powered", true)) and sheet.has_anim("off"):  # the lights are dead
		anim = "off"
	elif opts.has("fired_ago") and float(opts["fired_ago"]) < FIRE_WINDOW + 0.1 and sheet.has_anim("fire"):
		anim = "fire"
	elif float(hp) < float(max_hp) * DAMAGED_BELOW and sheet.has_anim("damaged"):
		anim = "damaged"
	frame = sheet.frame_once("fire", float(opts.get("fired_ago", 0.0))) if anim == "fire" else sheet.frame_at(anim, t)
	var extra := ""  # a chain gun's spin (steps > 0) and a charge gun's capacitor rings (one per stored volley) show while it idles
	var sub := 0
	if anim in ["idle", "damaged"]:
		if int(opts.get("chain", 0)) > 0 and sheet.has_anim("spin"):
			extra = "spin"
			sub = int(opts.get("spin", 0.0)) % int(sheet.anims["spin"]["count"])
		elif opts.has("stored") and sheet.has_anim("charge"):
			extra = "charge"
			sub = mini(int(opts["stored"]), int(sheet.anims["charge"]["count"]) - 1)
		if extra != "":
			frame = sheet.start_of(extra) + sub
	var k := cell_px / SpriteSheet.SRC_CELL
	var pin: Vector2 = (sheet.anchors["pivot"] + Vector2(0.5, 0.5)) if sheet.anchors.has("pivot") else Vector2(sheet.frame) / 2.0
	var xf := Transform2D(angle, pivot)
	var dest := Rect2(-pin * k, Vector2(sheet.frame) * k)
	canvas.draw_set_transform_matrix(xf)
	canvas.draw_texture_rect_region(sheet.texture, dest, sheet.region(frame), Color(1, 1, 1, alpha))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	var g = sheet.glow
	if g != null and (anim in ["fire", "damaged"] or extra != "") and g.has_anim(extra if extra != "" else anim):
		var gf: int = g.start_of(extra) + sub if extra != "" else (g.frame_once("fire", float(opts.get("fired_ago", 0.0))) if anim == "fire" else g.frame_at(anim, t))
		var quad := {"tex": g.texture, "rect": Rect2(dest.position + g.offset * k, Vector2(g.frame) * k), "src": g.region(gf), "xf": xf, "mod": Color(1, 1, 1, alpha)}
		if opts.has("glow_out"):
			opts["glow_out"].append(quad)
		else:
			canvas.draw_set_transform_matrix(xf)
			canvas.draw_texture_rect_region(quad["tex"], quad["rect"], quad["src"], quad["mod"])
			canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## The debris of wrecked parts (`wrecks`: [{id, cells}] of components.gd): art/tiles/wreck (one of its 4 variants
## by cell) on each cell, else a scorch with scraps. `origin`: where grid cell (0, 0) starts in the canvas' pixels.
static func draw_wrecks(canvas, wrecks: Array, origin: Vector2, cell_px: float) -> void:
	var sheet = Art.tiles("wreck")
	for w in wrecks:
		for c in w["cells"]:
			var r := Rect2(origin + Vector2(c) * cell_px, Vector2(cell_px, cell_px))
			if sheet != null:
				canvas.draw_texture_rect_region(sheet.texture, r, sheet.region(posmod(hash(c) >> 2, sheet.count)))
				continue
			canvas.draw_rect(r.grow(-1), Color(0.05, 0.04, 0.04, 0.6))
			var h := hash(c)
			for n in 3:
				var p := r.position + Vector2(float((h >> (n * 4)) & 15) / 15.0, float((h >> (n * 4 + 2)) & 15) / 15.0) * cell_px * 0.7
				canvas.draw_rect(Rect2(p, Vector2(cell_px * 0.22, cell_px * 0.12)), Color(0.45, 0.4, 0.36, 0.9))


## What a component's art shows now: {"anim", "frame", "glow" (glow anim name or ""), "glow_frame",
## "dim", "heat" (red pulse), "sparks", "smoke"}. Order of the animations: off when a consumer has no
## power; disabled (or dim + smoke); malfunction (or a flicker of on and off); overheated (or the heat
## pulse over the normal frame); a weapon's fire for FIRE_WINDOW s after a shot, else its charge by
## fraction; damaged under half hp (or sparks over the normal frame); on.
static func anim_state(sheet, def: Dictionary, inst: Dictionary, opts := {}) -> Dictionary:
	var max_hp := Stats.max_hp(def)
	var hp := int(inst.get("hp", max_hp))
	var status := str(inst.get("status", "ok"))
	var t := float(opts.get("time", 0.0))
	var consumer := int(def.get("power", 0)) < 0
	var powered := bool(opts.get("powered", true)) or not consumer
	var hurt := max_hp > 0 and float(hp) < float(max_hp) * DAMAGED_BELOW
	var st := {"anim": "on", "frame": 0, "glow": "", "glow_frame": 0, "dim": false, "heat": false, "sparks": false, "smoke": false}
	if status == "disabled" or hp <= 0:
		var has: bool = sheet.has_anim("disabled")
		st["anim"] = "disabled" if has else ("off" if sheet.has_anim("off") else "on")
		st["dim"] = not has
		st["smoke"] = not has
		st["frame"] = sheet.frame_at(st["anim"], t)
		return st
	var anim := "on"
	if opts.get("pulling", false) and sheet.has_anim("pulling"):  # an intake drawing a piece in (debris_view.gd)
		anim = "pulling"
	elif not powered:
		anim = "off" if sheet.has_anim("off") else "on"
		st["dim"] = not sheet.has_anim("off")
	elif status == "malfunction":
		if sheet.has_anim("malfunction"):
			anim = "malfunction"
		else:
			anim = "on" if _flicker_on(t) else ("off" if sheet.has_anim("off") else "on")
			st["dim"] = anim == "on" and not _flicker_on(t)
	elif status == "overheated" and sheet.has_anim("overheated"):
		anim = "overheated"
	else:
		st["heat"] = status == "overheated"
		if sheet.has_anim("fire") and opts.has("fired_ago") and float(opts["fired_ago"]) < FIRE_WINDOW:
			anim = "fire"
		elif sheet.has_anim("charge"):
			anim = "charge"
		elif hurt and sheet.has_anim("damaged"):
			anim = "damaged"
		elif Ammo.fill_anim(def, inst, sheet, opts) != "":  # an ammo rack shows how full it is
			anim = Ammo.fill_anim(def, inst, sheet, opts)
	st["anim"] = anim
	st["sparks"] = hurt and anim != "damaged"
	match anim:
		"charge":
			st["frame"] = sheet.frame_frac("charge", float(opts.get("charge", 1.0)))
		"fire":
			st["frame"] = sheet.frame_once("fire", float(opts.get("fired_ago", 0.0)))
		_:
			st["frame"] = sheet.frame_at(anim, t)
	var g = sheet.glow
	if g != null and powered and anim != "off":
		var gname: String = anim if g.has_anim(anim) else ("on" if g.has_anim("on") else "")
		if anim.ends_with("_0") and not g.has_anim(anim):  # an empty rack's lamps are out
			gname = ""
		st["glow"] = gname
		match gname:
			"charge":
				st["glow_frame"] = g.frame_frac("charge", float(opts.get("charge", 1.0)))
			"fire":
				st["glow_frame"] = g.frame_once("fire", float(opts.get("fired_ago", 0.0)))
			"":
				pass
			_:
				st["glow_frame"] = g.frame_at(gname, t)
	return st


## A malfunctioning part stutters: on for most of a cycle, off for a short beat, about 4 times a second.
static func _flicker_on(t: float) -> bool:
	return fmod(t * 4.3, 1.0) > 0.35


## The art sheet, turned with the part about the centre of the footprint. A sheet from a JSON is
## authored at 16 source px per cell and drawn at cell_px / 16; a bare PNG is stretched to the footprint.
static func _draw_sheet(canvas, sheet, rect: Rect2, def: Dictionary, inst: Dictionary, cell_px: float, opts: Dictionary) -> void:
	var st := anim_state(sheet, def, inst, opts)
	var alpha := float(opts.get("alpha", 1.0))
	var t := float(opts.get("time", 0.0))
	var foot := Vector2(float(def["size"][0]), float(def["size"][1])) * cell_px
	var k: Vector2 = Vector2.ONE * cell_px / SpriteSheet.SRC_CELL if sheet.cells != Vector2i.ZERO else foot / Vector2(sheet.frame)
	var tint := Color(DIM, alpha) if st["dim"] else Color(1, 1, 1, alpha)
	var turn: float = sheet.rot_total(int(inst.get("rot", 0))) * PI / 2.0
	if inst.has("face"):  # the outside half of a mount on a slope: the quarter turn, then the rest of the way to the face
		turn += deg_to_rad(float(inst["face"]) - posmod(int(inst.get("rot", 0)), 4) * 90.0)
	var xf := Transform2D(turn, rect.get_center())
	var at: Vector2 = -foot / 2.0 + sheet.offset * k  # the frame's top-left, in the turned frame
	var dest := Rect2(at, Vector2(sheet.frame) * k)
	var src: Rect2 = sheet.region(st["frame"])
	canvas.draw_set_transform_matrix(xf)
	canvas.draw_texture_rect_region(sheet.texture, dest, src, tint)
	if st["heat"]:  # the same frame again in red, pulsing
		var pulse := 0.5 + 0.5 * sin(t * 7.0)
		canvas.draw_texture_rect_region(sheet.texture, dest, src, Color(HEAT_RED, (0.22 + 0.3 * pulse) * alpha))
	if st["glow"] != "":
		var g = sheet.glow
		var quad := {"tex": g.texture, "rect": Rect2(at + g.offset * k, Vector2(g.frame) * k), "src": g.region(st["glow_frame"]),
			"xf": xf, "mod": Color(opts.get("glow_tint", Color.WHITE), alpha)}
		if opts.has("glow_out"):
			opts["glow_out"].append(quad)
		else:
			canvas.draw_texture_rect_region(quad["tex"], quad["rect"], quad["src"], quad["mod"])
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	if st["heat"]:
		draw_shimmer(canvas, rect, t, cell_px, alpha)
	if st["sparks"]:
		draw_sparks(canvas, rect, t, int(inst.get("uid", 0)), cell_px, alpha)
	if st["smoke"]:
		draw_smoke(canvas, rect, t, int(inst.get("uid", 0)), cell_px, alpha)


## Heat shimmer over every cell of `rect` (art/fx/heat_shimmer, an alpha overlay); nothing without that art.
static func draw_shimmer(canvas, rect: Rect2, t: float, cell_px: float, alpha := 1.0) -> void:
	var fx = Art.fx("heat_shimmer")
	if fx == null:
		return
	var src: Rect2 = fx.region(fx.loop_frame(t))
	for y in roundi(rect.size.y / cell_px):
		for x in roundi(rect.size.x / cell_px):
			canvas.draw_texture_rect_region(fx.texture, Rect2(rect.position + Vector2(x, y) * cell_px, Vector2(cell_px, cell_px)), src, Color(1, 1, 1, alpha))


## Sparks jumping about `rect`: art/fx/sparks frames when that art exists, else a few 2 px specks.
static func draw_sparks(canvas, rect: Rect2, t: float, seed_value: int, cell_px: float, alpha := 1.0) -> void:
	var fx = Art.fx("sparks")
	var unit := cell_px / SpriteSheet.SRC_CELL
	for i in 3:
		var n := int(t * 12.0) + i * 7919 + seed_value * 104729
		var p := rect.position + Vector2(_unit(n * 2), _unit(n * 2 + 1)) * rect.size
		if fx != null:
			var f: int = fx.loop_frame(t + i * 0.13)
			canvas.draw_texture_rect_region(fx.texture, Rect2(p - Vector2(fx.frame) * unit / 2.0, Vector2(fx.frame) * unit), fx.region(f), Color(1, 1, 1, alpha))
		else:
			canvas.draw_rect(Rect2(p, Vector2(2, 2) * unit), Color(SPARK_COLORS[i % SPARK_COLORS.size()], alpha))


## Smoke rising off `rect`: art/fx/smoke frames when that art exists, else grey puffs that grow and fade.
static func draw_smoke(canvas, rect: Rect2, t: float, seed_value: int, cell_px: float, alpha := 1.0) -> void:
	var fx = Art.fx("smoke")
	var unit := cell_px / SpriteSheet.SRC_CELL
	for i in 3:
		var age := fposmod(t * 0.6 + float(i) / 3.0 + _unit(seed_value + i) * 0.3, 1.0)
		var p := rect.get_center() + Vector2((_unit(seed_value * 3 + i) - 0.5) * rect.size.x * 0.6, -age * cell_px * 1.6)
		if fx != null:
			var f: int = fx.life_frame(age)
			canvas.draw_texture_rect_region(fx.texture, Rect2(p - Vector2(fx.frame) * unit / 2.0, Vector2(fx.frame) * unit), fx.region(f), Color(1, 1, 1, alpha * (1.0 - age)))
		else:
			canvas.draw_circle(p, (3.0 + 7.0 * age) * unit, Color(0.45, 0.46, 0.5, 0.55 * (1.0 - age) * alpha))


## A repeatable pseudo-random number in 0..1 for the integer `n` (looks only; the simulation never sees it).
static func _unit(n: int) -> float:
	return float(posmod(n * 2654435761 + 40503, 65521)) / 65521.0


static func _draw_placeholder(canvas, r: Rect2, def: Dictionary, cell_px: float, m: Dictionary, powered: bool, alpha: float) -> void:
	var col := Color(def.get("color", "#ff00ff"))
	var line := str(def.get("line", Stats.DEFAULT_LINE))
	var status: String = m["status"]
	var out_of_action := status != "ok"
	var unpowered := not powered and int(def.get("power", 0)) < 0 and not out_of_action
	var fill := col.darkened(0.4) if line == "neon" else col  # neon: a dark panel with a glowing edge
	if status == "disabled":
		fill = GREY
	elif status == "overheated":
		fill = fill.lerp(OVERHEAT_COLOR, 0.35).darkened(0.25)
	elif status == "malfunction" or unpowered:
		fill = fill.darkened(0.55)
	var label_col := Color(0, 0, 0, 0.5 if (unpowered or out_of_action) else 0.85)
	canvas.draw_rect(r, _a(fill, alpha))
	match line:
		"scrap":
			canvas.draw_rect(r, _a(col.darkened(0.4), alpha), false, 1.5)
			_draw_hazard_corner(canvas, r, cell_px * 0.75, alpha)
		"neon":
			canvas.draw_rect(r.grow(1.0), _a(Color(NEON_ACCENT, 0.3), alpha), false, 5.0)  # glow
			canvas.draw_rect(r, _a(NEON_ACCENT, alpha), false, 2.5)
		_:
			canvas.draw_rect(r, _a(col.darkened(0.4), alpha), false, 1.5)
	_draw_text(canvas, label_of(def), r.get_center(), 14, _a(label_col, alpha), true)
	if unpowered:
		_draw_no_power(canvas, r.position + Vector2(r.size.x - 8, 9))


## A right-triangle of yellow and black diagonal stripes in the bottom-left corner of `r`.
static func _draw_hazard_corner(canvas, r: Rect2, s: float, alpha: float) -> void:
	var x0 := r.position.x
	var y1 := r.end.y
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(x0, y1 - s), Vector2(x0, y1), Vector2(x0 + s, y1)]), _a(SCRAP_ACCENT, alpha))
	for k in [1.0 / 3.0, 2.0 / 3.0]:
		canvas.draw_line(Vector2(x0, y1 - s + s * k), Vector2(x0 + s - s * k, y1), _a(Color.BLACK, alpha), 3.0)


## The state overlay: heat bar along the bottom, hp pips at the top left, a mark at the top right.
static func _draw_marks(canvas, r: Rect2, m: Dictionary, alpha: float) -> void:
	if m["show_heat"]:
		var bar := Rect2(r.position.x + 4, r.end.y - 8, r.size.x - 8, 4)
		canvas.draw_rect(bar, _a(Color(0, 0, 0, 0.6), alpha))
		var t: float = m["heat"]
		var hot := HEAT_COLD.lerp(HEAT_HOT, clampf((t - HEAT_SHOWN) / (1.0 - HEAT_SHOWN), 0.0, 1.0))
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), _a(hot, alpha))
	if m["show_hp"]:
		var n: int = m["max_hp"]
		var pip := minf(5.0, (r.size.x - 8.0) / maxf(1.0, float(n)))
		for i in n:
			var p := Rect2(r.position + Vector2(4.0 + i * pip, 4.0), Vector2(pip - 1.0, 4.0))
			canvas.draw_rect(p, _a(HP_COLOR if i < int(m["hp"]) else HP_LOST_COLOR, alpha))
	var at := Vector2(r.end.x - 12, r.position.y + 13)
	match m["status"]:
		"overheated":
			canvas.draw_circle(at, 10.0, _a(Color(0, 0, 0, 0.7), alpha))
			_draw_text(canvas, "!", at, 20, _a(OVERHEAT_COLOR, alpha), true)
		"malfunction":
			canvas.draw_circle(at, 10.0, _a(Color(0, 0, 0, 0.7), alpha))
			_draw_text(canvas, "⚙" if ThemeDB.fallback_font.has_char(0x2699) else "M", at, 16, _a(MALFUNCTION_COLOR, alpha), true)


## The "no power" mark: a red lightning bolt, or a red dot when the font has no such glyph.
static func _draw_no_power(canvas, at: Vector2) -> void:
	if ThemeDB.fallback_font.has_char(0x26A1):
		canvas.draw_string(ThemeDB.fallback_font, at + Vector2(-6, 5), "⚡", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.RED)
	else:
		canvas.draw_circle(at, 3.5, Color.RED)


## Text centred on `centre`, with a dark outline when `outlined`.
static func _draw_text(canvas, text: String, centre: Vector2, size: int, col: Color, outlined := false) -> void:
	var font := ThemeDB.fallback_font
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var at := centre - Vector2(extent.x / 2.0, extent.y / 2.0 - font.get_ascent(size))
	if outlined and col.get_luminance() > 0.5:
		canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, col.a * 0.9))
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func _a(col: Color, alpha: float) -> Color:
	return Color(col, col.a * alpha)
