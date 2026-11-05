extends Control
## The kit choice of a drone bay (build mode): hover a placed bay and press K, or Alt+click it. A small panel lists the drone kits the bay could launch with
## their picture, tier, hp and how many the hold has; a click loads one (it is saved with the bay), "Unload" empties the bay, Esc or a click elsewhere closes it.
## The rules are drones.gd's (kit_choices, set_kit); this only draws and asks.

const Drones = preload("res://scripts/combat/drones.gd")
const Art = preload("res://scripts/view/art.gd")

const W := 330.0
const ROW := 44.0
const PAD := 10.0
const BG := Color(0.04, 0.07, 0.11, 0.95)
const TEXT := Color("#cfe6ff")
const GREY := Color("#6b7686")
const OK := Color("#4fd08a")
const GOLD := Color("#ffd24a")

signal chosen(uid: int, kit: String)

var ship
var uid := -1
var rows: Array = []
var hover := -2


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


## Open the panel for bay `p_uid` of `p_ship` with its corner near screen point `at`.
func open(p_ship, p_uid: int, at: Vector2) -> void:
	ship = p_ship
	uid = p_uid
	rows = Drones.kit_choices(ship, uid)
	var h := PAD * 2.0 + 24.0 + (rows.size() + 1) * ROW + 16.0
	size = Vector2(W, h)
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1600, 900)
	position = Vector2(clampf(at.x, 8.0, vp.x - W - 8.0), clampf(at.y, 8.0, vp.y - h - 8.0))
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	uid = -1


func _row_at(p: Vector2) -> int:
	var y := p.y - (PAD + 24.0)
	if y < 0.0 or p.x < 0.0 or p.x > W:
		return -2
	var k := int(y / ROW)
	return k if k <= rows.size() else -2  # k == rows.size() is the Unload row


## Load row `k` (an index of `rows`, or rows.size() for Unload). The refusal, "" when it worked.
func pick(k: int) -> String:
	var why := Drones.set_kit(ship, uid, "" if k >= rows.size() else str(rows[k]["id"]))
	if why == "":
		chosen.emit(uid, "" if k >= rows.size() else str(rows[k]["id"]))
		close()
	return why


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed and not get_global_rect().has_point(e.global_position):
		close()  # (the click goes on to the world)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover = _row_at(e.position)
		queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var k := _row_at(e.position)
		if k > -2:
			pick(k)
		accept_event()


func _draw() -> void:
	if not visible or ship == null or uid < 0:
		return
	var inst: Dictionary = ship.components.instances[uid]
	var def: Dictionary = ship.components.def(inst["id"])
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(Vector2.ZERO, size), Color(OK, 0.7), false, 2.0)
	_text("%s: choose the kit" % def["name"], Vector2(PAD, PAD + 14.0), 14, TEXT)
	var loaded := str(inst.get("kit", ""))
	var y := PAD + 24.0
	for k in rows.size():
		var r: Dictionary = rows[k]
		var at := Vector2(PAD / 2.0, y + k * ROW)
		var on: bool = r["id"] == loaded
		draw_rect(Rect2(at, Vector2(W - PAD, ROW - 4.0)), Color(1, 1, 1, 0.10 if hover == k and r["ok"] else (0.05 if on else 0.0)))
		if on:
			draw_rect(Rect2(at, Vector2(W - PAD, ROW - 4.0)), Color(GOLD, 0.8), false, 2.0)
		var sheet = Art.drone(str(Drones.kit(str(r["id"]))["drone"]["art"]))
		var tint := Color(1, 1, 1, 1.0 if r["ok"] else 0.35)
		if sheet != null:
			draw_texture_rect_region(sheet.texture, Rect2(at + Vector2(4.0, 2.0), Vector2(sheet.frame) * 1.4), sheet.region(0), tint)
		_text(str(r["name"]), at + Vector2(48.0, 16.0), 13, Color(TEXT, tint.a))
		var line := "tier %d   hp %d   %s   %d part%s a launch" % [r["tier"], r["hp"], "defence" if r["role"] == "defence" else "combat", r["tier"], "" if r["tier"] == 1 else "s"]
		_text(line, at + Vector2(48.0, 31.0), 10, Color(GREY, 1.0 if r["ok"] else 0.7))
		var tag := "in the hold: %d" % r["held"] if r["ok"] else str(r["why"])
		_text(tag, at + Vector2(W - PAD - 6.0, 16.0), 10, OK if r["ok"] else Color("#e0705a"), HORIZONTAL_ALIGNMENT_RIGHT, 150.0)
	var ay := y + rows.size() * ROW
	draw_rect(Rect2(Vector2(PAD / 2.0, ay), Vector2(W - PAD, ROW - 4.0)), Color(1, 1, 1, 0.10 if hover == rows.size() else 0.0))
	_text("Unload (leave the bay empty)", Vector2(PAD + 4.0, ay + 24.0), 12, GREY)
	_text("Drones are permanent; a launch spends drone parts.  Esc closes.", Vector2(PAD, size.y - 8.0), 10, GREY)


func _text(text: String, at: Vector2, font_size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		draw_string(ThemeDB.fallback_font, at - Vector2(width, 0.0), text, align, width, font_size, col)
	else:
		draw_string(ThemeDB.fallback_font, at, text, align, width, font_size, col)
