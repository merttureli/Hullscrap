extends Control
## The one-time question after the first finished run, won or lost: "The Ledger: keep it on?" with the three settings, Warnings only first.
## 1, 2, 3 or a click choose (Left / Right and Enter too; Esc keeps it as it is, Full); `chosen` says which setting. front_door.gd shows it once
## (profile.ledger_ask_due) and puts the answer in the profile. A modal panel: it takes every key and click while it is up.

## Emitted with the setting chosen: "warn", "full" or "off".
signal chosen(mode: String)

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Audio = preload("res://scripts/audio/audio.gd")

## The choices, in order: the one asked for first.
const CHOICES: Array = [
	{"mode": "warn", "label": "Warnings only", "note": "It speaks up only when something is about to go wrong."},
	{"mode": "full", "label": "Full", "note": "The goal card, the first-time tips and the warnings."},
	{"mode": "off", "label": "Off", "note": "Ma will take your word for it."},
]
const SIZE := Vector2(640.0, 330.0)
const BTN_H := 52.0

var selected := 0  ## the choice Enter takes
var _then := Callable()  # what to do once it is answered


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## Ask; `then` is called once it is answered.
func open(then := Callable()) -> void:
	_then = then
	selected = 0
	visible = true
	Audio.fx(self, "open")
	queue_redraw()


## Take choice `i` (0 to 2): the panel goes and `chosen` says which setting.
func choose(i: int) -> void:
	if not visible or i < 0 or i >= CHOICES.size():
		return
	visible = false
	Audio.fx(self, "confirm")
	chosen.emit(str(CHOICES[i]["mode"]))
	if _then.is_valid():
		_then.call()


func panel_rect() -> Rect2:
	return Rect2(((size - SIZE) / 2.0).round(), SIZE)


func button_rect(i: int) -> Rect2:
	var p := panel_rect()
	return Rect2(p.position + Vector2(24.0, 120.0 + i * (BTN_H + 8.0)), Vector2(p.size.x - 48.0, BTN_H))


func button_at(pt: Vector2) -> int:
	for i in CHOICES.size():
		if button_rect(i).has_point(pt):
			return i
	return -1


func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey):
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	if not e.pressed or e.echo:
		return
	match e.keycode:
		KEY_1, KEY_2, KEY_3:
			choose(e.keycode - KEY_1)
		KEY_LEFT, KEY_UP:
			selected = (selected + CHOICES.size() - 1) % CHOICES.size()
			Audio.fx(self, "hover")
		KEY_RIGHT, KEY_DOWN, KEY_TAB:
			selected = (selected + 1) % CHOICES.size()
			Audio.fx(self, "hover")
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			choose(selected)
		KEY_ESCAPE:
			choose(1)  # keep it as it is


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var i := button_at(e.position)
		if i >= 0 and i != selected:
			selected = i
			Audio.fx(self, "hover")
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		choose(button_at(e.position))
	accept_event()


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.72))
	var p := panel_rect()
	UiKit.panel(self, p)
	UiKit.text(self, "THE LEDGER", p.position + Vector2(24.0, 38.0), 12, UiKit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiKit.bold())
	UiKit.text(self, "Keep it on?", p.position + Vector2(24.0, 74.0), 26, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiKit.bold())
	UiKit.text(self, "Ma Gantry Loans put it on your ship to help it grow. It can stay out of the way.", p.position + Vector2(24.0, 100.0), 14, UiKit.DIM_TEXT)
	for i in CHOICES.size():
		var b := button_rect(i)
		UiKit.button(self, b, i == selected, i == selected)
		UiKit.text(self, "%d   %s" % [i + 1, CHOICES[i]["label"]], b.position + Vector2(16.0, 22.0), 17, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiKit.bold())
		UiKit.text(self, str(CHOICES[i]["note"]), b.position + Vector2(36.0, 42.0), 12, UiKit.DIM_TEXT)
	UiKit.text(self, "1 / 2 / 3 or click    Enter: choose    Esc: keep Full    Settings can change it any time", p.position + Vector2(24.0, p.size.y - 14.0), 12, UiKit.DIM_TEXT)
