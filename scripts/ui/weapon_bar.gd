extends Control
## The weapon bar along the bottom of the combat screen: one slot per weapon of the player's ship with
## its key, name, fire group, a cooldown ring and its state (ready, cooling, no power, jammed, no ammo,
## out of arc ...). Above it, one slot per active ability of the ship (Abilities.slots): the key that
## triggers it (Shift engine, Space shield, Q utility), its name, a ring that shows the time left while
## it runs and the cooldown while it rests, and why it cannot start; a press that is refused flashes
## the reason in the slot. Reads a CombatSession; the only input it takes is the three ability keys.

const SLOT := Vector2(176.0, 58.0)
const ASLOT := Vector2(196.0, 66.0)  ## an ability slot: taller, for the reason
const GAP := 8.0
const BG := Color(0.04, 0.07, 0.11, 0.85)
const TEXT := Color("#cfe6ff")
const READY := Color("#4fd08a")
const COOLING := Color("#f1c40f")
const BAD := Color("#e0453a")
const GREY := Color("#6b7686")
const GOLD := Color("#ffd24a")
const KEY_OF := {KEY_SHIFT: "engine", KEY_SPACE: "shield", KEY_Q: "utility"}  ## keycode -> ability key
const KEY_LABEL := {"engine": "SHIFT", "shield": "SPACE", "utility": "Q"}
const FLASH_MS := 2200  ## how long a refusal stays in its slot
const BLOCKED_TEXT := {"unpowered": "NO POWER", "disabled": "DISABLED", "overheated": "OVERHEATED", "malfunction": "JAMMED", "wrecked": "WRECKED"}
const GROUP_COLORS := {1: Color("#5fd4ff"), 2: Color("#ff9a3c")}
const STATUS_TEXT := {
	"ready": "READY", "cooling down": "COOLING", "out of arc": "OUT OF ARC", "unpowered": "NO POWER", "no ammo": "NO AMMO",
	"malfunction": "JAMMED", "overheated": "OVERHEATED", "disabled": "DISABLED", "wrecked": "WRECKED", "no such weapon": "-",
}

var session  ## combat_session.gd
var aim: Callable = func() -> Vector2: return Vector2.ZERO  ## the world point the mouse aims at
var flashes := {}  ## ability slot id -> {text, until (Time.get_ticks_msec)}: the refusals on show


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p_session, p_aim: Callable) -> void:
	session = p_session
	aim = p_aim


func _process(_dt: float) -> void:
	if not visible or session == null:
		return
	var weapons_w := _row_width(session.weapons().size(), SLOT.x)
	var abilities_w := _row_width(session.ability_slots().size(), ASLOT.x)
	size = Vector2(maxf(weapons_w, abilities_w), SLOT.y + (ASLOT.y + GAP if abilities_w > 0.0 else 0.0))
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - size.x) / 2.0, vp.y - size.y - 14.0)
	queue_redraw()


func _row_width(n: int, slot_w: float) -> float:
	return n * (slot_w + GAP) - GAP if n > 0 else 0.0


## The ability keys: Shift, Space and Q press the engine, shield and utility abilities.
func _unhandled_input(e: InputEvent) -> void:
	if not visible or session == null or not (e is InputEventKey and e.pressed and not e.echo) or not KEY_OF.has(e.keycode):
		return
	press(KEY_OF[e.keycode])
	if is_inside_tree():
		get_viewport().set_input_as_handled()


## Press ability key `key` ("engine", "shield" or "utility"); every refusal is flashed in its slot.
## Returns the session's {"started", "refused"}.
func press(key: String) -> Dictionary:
	var r: Dictionary = session.press_ability(key)
	for slot in r["refused"]:
		flashes[slot] = {"text": r["refused"][slot], "until": Time.get_ticks_msec() + FLASH_MS}
	return r


func _draw() -> void:
	if session == null:
		return
	var slots: Array = session.ability_slots()
	var row_y := 0.0
	if not slots.is_empty():
		var x0 := (size.x - _row_width(slots.size(), ASLOT.x)) / 2.0
		for i in slots.size():
			_ability_slot(Vector2(x0 + i * (ASLOT.x + GAP), 0.0), slots[i])
		row_y = ASLOT.y + GAP
	var list: Array = session.weapons()
	var target: Vector2 = aim.call()
	var wx := (size.x - _row_width(list.size(), SLOT.x)) / 2.0
	for i in list.size():
		_slot(Vector2(wx + i * (SLOT.x + GAP), row_y), i + 1, list[i], target)


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


## One ability slot: key, name, a ring (time left while it runs, cooldown while it rests), its state and,
## for a few seconds after a refused press, the reason.
func _ability_slot(at: Vector2, s: Dictionary) -> void:
	var st: Dictionary = session.ability_state(s)
	var state: String = st["state"]
	var flash = flashes.get(s["slot"])
	if flash != null and Time.get_ticks_msec() >= flash["until"]:
		flashes.erase(s["slot"])
		flash = null
	var col := READY
	var frac := 1.0
	var label := "READY"
	match state:
		"active":
			col = GOLD
			frac = st["active_left"] / maxf(st["duration"], 0.01)
			label = "ON %.1f" % st["active_left"]
		"cooling":
			col = COOLING
			frac = 1.0 - st["cooldown_left"] / maxf(st["cooldown"], 0.01)
			label = "COOLDOWN %d" % ceili(st["cooldown_left"] - 1e-6)
		"blocked":
			col = BAD
			label = BLOCKED_TEXT.get(st["reason"], "NEEDS CREW" if st["reason"].begins_with("needs") else st["reason"].to_upper())
	draw_rect(Rect2(at, ASLOT), BG)
	draw_rect(Rect2(at, ASLOT), Color(BAD if flash != null else col, 0.9), false, 3.0 if flash != null else 2.0)
	var c := at + Vector2(30.0, ASLOT.y / 2.0)
	draw_arc(c, 19.0, 0.0, TAU, 28, Color(1, 1, 1, 0.12), 4.0, true)
	draw_arc(c, 19.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(frac, 0.0, 1.0), 28, Color(col, 0.95), 4.0, true)
	var key: String = KEY_LABEL.get(s["key"], "?")
	_text(key, c + Vector2(-19.0, 4.0 if key.length() > 1 else 6.0), 10 if key.length() > 1 else 17, TEXT, 38.0, HORIZONTAL_ALIGNMENT_CENTER)
	_text(str(s["name"]), at + Vector2(58.0, 20.0), 14, TEXT)
	if flash != null:
		draw_multiline_string(ThemeDB.fallback_font, at + Vector2(58.0, 33.0), flash["text"], HORIZONTAL_ALIGNMENT_LEFT, ASLOT.x - 64.0, 10, 3, BAD)
	else:
		_text(label, at + Vector2(58.0, 39.0), 11, col)
		_text(str(s["part"]), at + Vector2(58.0, 55.0), 10, GREY)


func _text(text: String, at: Vector2, size: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(ThemeDB.fallback_font, at, text, align, width, size, col)
