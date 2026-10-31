extends Control
## The red JUMP bar under the enemy's schematic while it flees (morale.gd): "JUMP 9.2 s" as its jump drive
## charges, and in small print why the charge is held ("JUMP held: engines out", "helm down" or "no crew"). Hidden
## otherwise. bind() it to the fight's session (null: none); it reads session.morale each frame. Drawing only.

const PANEL := Vector2(280.0, 38.0)
const BG := Color(0.04, 0.07, 0.11, 0.82)
const EDGE := Color("#3b5a78")
const FILL := Color("#e0453a")
const HELD := Color("#8a4a3a")
const TEXT := Color("#ffe9e6")

var session = null


func _init() -> void:
	custom_minimum_size = PANEL
	size = PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func bind(p_session) -> void:
	session = p_session
	visible = false


func _process(_dt: float) -> void:
	visible = session != null and session.morale.state == "fleeing" and session.state() == "fighting"  # not once it is wrecked or gone
	if visible:
		queue_redraw()


func _draw() -> void:
	if session == null:
		return
	var morale = session.morale
	var total := float(morale.cfg["spool_s"])
	var held: String = morale.hold()
	var bar := Rect2(4.0, 4.0, PANEL.x - 8.0, 20.0)
	draw_rect(Rect2(Vector2.ZERO, PANEL), BG)
	draw_rect(Rect2(Vector2.ZERO, PANEL), EDGE, false, 2.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(morale.spool / total, 0.0, 1.0), bar.size.y)), HELD if held != "" else FILL)
	draw_rect(bar, EDGE, false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, bar.position + Vector2(8.0, 15.0), "JUMP %.1f s" % maxf(total - morale.spool, 0.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT)
	if held != "":
		draw_string(font, Vector2(8.0, 35.0), "JUMP held: " + held, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffb4a8"))
