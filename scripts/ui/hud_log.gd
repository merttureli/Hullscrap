extends Control
## The log, bottom left: what the crew are doing, what the trip has salvaged (play mode) and the last lines of the
## ship's chronicle with their time. A click on its title bar folds it to the newest line
## and opens it again. Draws only.

const Jobs = preload("res://scripts/crew/jobs.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const EVENTS := 3  ## chronicle lines shown
const HEAD_H := 26.0
const SIZE := 12
const LINE := 15.0
const PAD := 10.0
const MAX_LINES := 9

var hud: Control
var collapsed := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## The lines it shows open: [text, colour], the newest chronicle line last.
func lines() -> Array:
	var b: Node = hud.build
	var ship = b.ship
	if ship == null:
		return []
	var out := []
	out.append([Jobs.crew_line(ship), UiKit.TEXT])
	var deb = b.get_parent().get_node_or_null("Debris") if b.get_parent() != null else null
	if deb != null and deb.has_method("active") and deb.active() and deb.get("debris") != null:
		out.append([deb.debris.hud_line(), UiKit.AMBER])
	for e in ship.events.slice(-EVENTS):
		out.append([event_text(e), UiKit.DIM_TEXT])
	return out


## A chronicle entry as the log shows it: "[1:15] Prism Core overheated".
static func event_text(e: Dictionary) -> String:
	return "[%d:%02d] %s" % [floori(e["t"] / 60.0), floori(e["t"]) % 60, e["text"]]


## The lines wrapped to the panel: [text, colour], at most MAX_LINES (the oldest are dropped).
func wrapped() -> Array:
	var out := []
	for l in lines():
		for w in UiKit.wrap(l[0], size.x - 2.0 * PAD, SIZE):
			out.append([w, l[1]])
	return out.slice(-MAX_LINES)


func wanted_height() -> float:
	if collapsed or hud == null or hud.build == null:
		return HEAD_H + 4.0
	return HEAD_H + wrapped().size() * LINE + 10.0


func _gui_input(e: InputEvent) -> void:
	if hud.pass_release(e):
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and e.position.y < HEAD_H:
		collapsed = not collapsed


func _draw() -> void:
	if hud == null or hud.build == null or hud.build.ship == null:
		return
	UiKit.panel(self, Rect2(Vector2.ZERO, size), 0.9)
	var tri := PackedVector2Array([Vector2(PAD, 9), Vector2(PAD + 10, 9), Vector2(PAD + 5, 17)]) if not collapsed \
		else PackedVector2Array([Vector2(PAD + 2, 7), Vector2(PAD + 9, 12), Vector2(PAD + 2, 18)])
	draw_colored_polygon(tri, UiKit.EDGE)
	UiKit.text(self, "LOG", Vector2(PAD + 16.0, 18.0), 12, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiKit.bold())
	var all := lines()
	if collapsed:
		if not all.is_empty():
			UiKit.text(self, all[-1][0], Vector2(PAD + 52.0, 18.0), SIZE, UiKit.DIM_TEXT, HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2.0 - 52.0)
		return
	UiKit.text(self, "click to fold", Vector2(PAD, 18.0), 10, UiKit.EDGE_DIM.lightened(0.2), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 2.0 * PAD)
	draw_line(Vector2(PAD, HEAD_H), Vector2(size.x - PAD, HEAD_H), UiKit.EDGE_DIM, 1.0)
	var y := HEAD_H + 2.0
	for l in wrapped():
		y += LINE
		UiKit.text(self, l[0], Vector2(PAD, y), SIZE, l[1])
