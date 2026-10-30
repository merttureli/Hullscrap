extends RefCounted
## The swappable art registry: every component is drawn through draw_component(), by id. If
## art/components/<id>.png exists (scripts/view/art.gd), its sprite is drawn at the footprint, turned
## with the part, and the animation follows the part's state (anim_state()); otherwise a flat
## placeholder is drawn (see art/README.md for how to drop art in). On top of either it overlays the
## component's state: a heat bar, an orange "!" when overheated, a yellow gear when malfunctioning
## and a row of hp pips when damaged. Drawing only, no game logic.

const Stats = preload("res://scripts/sim/stats.gd")
const Art = preload("res://scripts/view/art.gd")
const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const FIRE_WINDOW := 0.15  ## seconds a weapon shows its fire frame after a shot
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
	if not powered:
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
	var k := Vector2.ONE * cell_px / SpriteSheet.SRC_CELL if sheet.cells != Vector2i.ZERO else foot / Vector2(sheet.frame)
	var tint := Color(DIM, alpha) if st["dim"] else Color(1, 1, 1, alpha)
	var xf := Transform2D(sheet.rot_total(int(inst.get("rot", 0))) * PI / 2.0, rect.get_center())
	var at := -foot / 2.0 + sheet.offset * k  # the frame's top-left, in the turned frame
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
			"xf": xf, "mod": Color(1, 1, 1, alpha)}
		if opts.has("glow_out"):
			opts["glow_out"].append(quad)
		else:
			canvas.draw_texture_rect_region(quad["tex"], quad["rect"], quad["src"], quad["mod"])
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	if st["sparks"]:
		draw_sparks(canvas, rect, t, int(inst.get("uid", 0)), cell_px, alpha)
	if st["smoke"]:
		draw_smoke(canvas, rect, t, int(inst.get("uid", 0)), cell_px, alpha)


## Sparks jumping about `rect`: art/fx/sparks frames when that art exists, else a few 2 px specks.
static func draw_sparks(canvas, rect: Rect2, t: float, seed_value: int, cell_px: float, alpha := 1.0) -> void:
	var fx = Art.fx("sparks")
	var unit := cell_px / SpriteSheet.SRC_CELL
	for i in 3:
		var n := int(t * 12.0) + i * 7919 + seed_value * 104729
		var p := rect.position + Vector2(_unit(n * 2), _unit(n * 2 + 1)) * rect.size
		if fx != null:
			var f: int = fx.frame_at("on", t + i * 0.13)
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
			var f: int = fx.frame_life("on", age)
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
