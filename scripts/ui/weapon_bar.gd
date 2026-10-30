extends Control
## The weapon bar along the bottom of the combat screen: one slot per weapon of the player's ship with
## its key, name, fire group, a cooldown ring and its state (ready, cooling, no power, jammed, no ammo,
## out of arc ...), then the shield overcharge slot (Space). Reads a CombatSession; drawing only.

const Shields = preload("res://scripts/combat/shields.gd")

const SLOT := Vector2(176.0, 58.0)
const GAP := 8.0
const BG := Color(0.04, 0.07, 0.11, 0.85)
const TEXT := Color("#cfe6ff")
const READY := Color("#4fd08a")
const COOLING := Color("#f1c40f")
const BAD := Color("#e0453a")
const GREY := Color("#6b7686")
const GOLD := Color("#ffd24a")
const GROUP_COLORS := {1: Color("#5fd4ff"), 2: Color("#ff9a3c")}
const STATUS_TEXT := {
	"ready": "READY", "cooling down": "COOLING", "out of arc": "OUT OF ARC", "unpowered": "NO POWER", "no ammo": "NO AMMO",
	"malfunction": "JAMMED", "overheated": "OVERHEATED", "disabled": "DISABLED", "wrecked": "WRECKED", "no such weapon": "-",
}

var session  ## combat_session.gd
var aim: Callable = func() -> Vector2: return Vector2.ZERO  ## the world point the mouse aims at


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p_session, p_aim: Callable) -> void:
	session = p_session
	aim = p_aim


func _process(_dt: float) -> void:
	if not visible or session == null:
		return
	var n: int = session.weapons().size() + 1
	size = Vector2(n * (SLOT.x + GAP) - GAP, SLOT.y)
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - size.x) / 2.0, vp.y - SLOT.y - 14.0)
	queue_redraw()


func _draw() -> void:
	if session == null:
		return
	var list: Array = session.weapons()
	var target: Vector2 = aim.call()
	for i in list.size():
		_slot(Vector2(i * (SLOT.x + GAP), 0.0), i + 1, list[i], target)
	_overcharge_slot(Vector2(list.size() * (SLOT.x + GAP), 0.0))


func _slot(at: Vector2, number: int, w: Dictionary, target: Vector2) -> void:
	var st: Dictionary = session.slot_state(w["uid"], target)
	var status: String = st["status"]
	var col: Color = READY if status == "ready" else (COOLING if status == "cooling down" else (GREY if status == "out of arc" else BAD))
	draw_rect(Rect2(at, SLOT), BG)
	draw_rect(Rect2(at, SLOT), Color(col, 0.9), false, 2.0)
	var c := at + Vector2(30.0, SLOT.y / 2.0)
	draw_arc(c, 19.0, 0.0, TAU, 28, Color(1, 1, 1, 0.12), 4.0, true)
	var total: float = maxf(st["cooldown"], 0.01)
	var done := 1.0 - clampf(st["cooldown_left"] / total, 0.0, 1.0)
	if done > 0.0:
		draw_arc(c, 19.0, -PI / 2.0, -PI / 2.0 + TAU * done, 28, Color(col, 0.95), 4.0, true)
	_text(str(number), c + Vector2(-4.0, 6.0), 17, TEXT)
	_text(str(w["name"]), at + Vector2(58.0, 20.0), 14, TEXT)
	var group_col: Color = GROUP_COLORS.get(w["group"], GREY)
	draw_rect(Rect2(at + Vector2(58.0, 28.0), Vector2(26.0, 14.0)), Color(group_col, 0.25))
	_text("G%d" % w["group"], at + Vector2(62.0, 39.0), 11, group_col)
	var label: String = STATUS_TEXT.get(status, status.to_upper())
	if status == "cooling down":
		label += " %.1f" % st["cooldown_left"]
	_text(label, at + Vector2(90.0, 39.0), 11, col)
	var powered: bool = status not in ["unpowered", "disabled", "overheated", "malfunction", "wrecked"]
	draw_circle(at + Vector2(SLOT.x - 12.0, 12.0), 4.0, READY if powered else BAD)


func _overcharge_slot(at: Vector2) -> void:
	var co = session.arena.ships[session.PLAYER]
	var active: bool = co.overcharge_left > 0.0
	var resting: bool = co.overcharge_cd > 0.0
	var has_shield: bool = co.layers_cap - (1 if active else 0) > 0
	var col := GOLD if active else (READY if has_shield and not resting else GREY)
	draw_rect(Rect2(at, SLOT), BG)
	draw_rect(Rect2(at, SLOT), Color(col, 0.9), false, 2.0)
	var c := at + Vector2(30.0, SLOT.y / 2.0)
	var frac := 1.0
	var label := "READY"
	if active:
		frac = co.overcharge_left / Shields.OVERCHARGE_S
		label = "ON %.1f" % co.overcharge_left
	elif resting:
		frac = 1.0 - co.overcharge_cd / Shields.OVERCHARGE_COOLDOWN
		label = "RESTING %.0f" % co.overcharge_cd
	elif not has_shield:
		label = "NO SHIELD"
	draw_arc(c, 19.0, 0.0, TAU, 28, Color(1, 1, 1, 0.12), 4.0, true)
	draw_arc(c, 19.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(frac, 0.0, 1.0), 28, Color(col, 0.95), 4.0, true)
	_text("SP", c + Vector2(-8.0, 5.0), 14, TEXT)
	_text("Overcharge", at + Vector2(58.0, 20.0), 14, TEXT)
	_text(label, at + Vector2(58.0, 39.0), 11, col)


func _text(text: String, at: Vector2, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
