extends Control
## Build mode's layout buttons (bottom right): "Save layout" stores the ship as its reference layout, and Rebuild Hull / Parts /
## Both puts back what is missing compared with it (layout.gd; the result is said in the message line). Draws and clicks only.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Audio = preload("res://scripts/audio/audio.gd")

const BUTTONS: Array = [
	{"id": "save", "label": "Save layout"},
	{"id": "hull", "label": "Hull"},
	{"id": "parts", "label": "Parts"},
	{"id": "both", "label": "Both"},
]
const PAD := 6.0
const GAP := 4.0
const ROW := 28.0
const HEIGHT := 2.0 * PAD + GAP + 2.0 * ROW + 14.0

var hud: Control
var hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): hover = -1)


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func button_rect(i: int) -> Rect2:
	var w := size.x - 2.0 * PAD
	if i == 0:
		return Rect2(PAD, PAD, w, ROW)
	var bw := (w - 2.0 * GAP) / 3.0
	return Rect2(PAD + (i - 1) * (bw + GAP), PAD + ROW + GAP + 14.0, bw, ROW)


func button_at(p: Vector2) -> int:
	for i in BUTTONS.size():
		if button_rect(i).has_point(p):
			return i
	return -1


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover = button_at(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := button_at(e.position)
		if i >= 0 and hud != null:
			hud.build.layout_action(BUTTONS[i]["id"])
			Audio.fx(self, "click")
		accept_event()
	elif e is InputEventMouseButton:
		accept_event()


## True when the ship has a saved layout to rebuild from.
func has_layout() -> bool:
	return hud == null or hud.build.ship == null or not hud.build.ship.layout.is_empty()


func _get_tooltip(at_position: Vector2) -> String:
	var i := button_at(at_position)
	return "Save a layout first" if i > 0 and not has_layout() else ""


func _draw() -> void:
	UiKit.panel(self, Rect2(Vector2.ZERO, size))
	for i in BUTTONS.size():
		var r := button_rect(i)
		UiKit.button(self, r, false, hover == i and (i == 0 or has_layout()))
		var off: bool = i > 0 and not has_layout()  # (the Rebuild buttons wait for a saved layout)
		UiKit.text(self, BUTTONS[i]["label"], Vector2(r.position.x, r.position.y + 19.0), 14, UiKit.DIM_TEXT if off else UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		if off:
			draw_rect(r, Color(0, 0, 0, 0.35))
	UiKit.text(self, "Rebuild what is missing:", Vector2(PAD + 2.0, PAD + ROW + GAP + 11.0), 11, UiKit.DIM_TEXT)
