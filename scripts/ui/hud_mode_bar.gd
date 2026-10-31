extends Control
## The mode bar at the bottom of the screen: Build (B), Play, Map (M), Shields (H), Crafting (C) and Help (F1),
## the active one lit; Build shows red while the red alert refuses it (build_mode.gd can_build()). A click switches
## (hud.gd switch_mode()). When the screen is too narrow for the labels
## between the side panels it shows only the icons and keys. Draws only.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

const MODES: Array = [
	{"id": "build", "label": "Build", "key": "B"},
	{"id": "play", "label": "Play", "key": ""},
	{"id": "map", "label": "Map", "key": "M"},
	{"id": "shields", "label": "Shields", "key": "H"},
	{"id": "crafting", "label": "Crafting", "key": "C"},
	{"id": "help", "label": "Help", "key": "F1"},
]
const BTN_W := 112.0
const BTN_W_COMPACT := 56.0
const GAP := 6.0
const PAD := 8.0
const ICON := 24.0

var hud: Control
var compact := false  ## icons and keys only
var hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): hover = -1)


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## The bar's width with labels, or icons only when `icons_only`.
static func width_for(icons_only: bool) -> float:
	var w := BTN_W_COMPACT if icons_only else BTN_W
	return MODES.size() * w + (MODES.size() - 1) * GAP + 2.0 * PAD


func full_width() -> float:
	return width_for(compact)


func button_rect(i: int) -> Rect2:
	var w := BTN_W_COMPACT if compact else BTN_W
	return Rect2(PAD + i * (w + GAP), PAD, w, size.y - 2.0 * PAD)


## The mode button under local point `p`, or -1.
func button_at(p: Vector2) -> int:
	for i in MODES.size():
		if button_rect(i).has_point(p):
			return i
	return -1


func _gui_input(e: InputEvent) -> void:
	if hud.pass_release(e):
		return
	if e is InputEventMouseMotion:
		hover = button_at(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := button_at(e.position)
		if i >= 0:
			hud.switch_mode(MODES[i]["id"])


func _draw() -> void:
	if hud == null or hud.build == null:
		return
	UiKit.bar(self, Rect2(Vector2.ZERO, size))
	var lit: String = hud.active_mode()
	for i in MODES.size():
		var m: Dictionary = MODES[i]
		var r := button_rect(i)
		var on: bool = m["id"] == lit
		UiKit.button(self, r, on, i == hover)
		if m["id"] == "build" and not on and hud.build.can_build() != "":
			draw_rect(r.grow(-1), UiKit.BAD, false, 2.0)
			draw_rect(r.grow(-2), Color(UiKit.BAD, 0.18))
		var ix := r.position.x + (8.0 if not compact else (r.size.x - ICON) / 2.0)
		UiKit.icon(self, m["id"], Rect2(ix, r.position.y + (r.size.y - ICON) / 2.0 - (5.0 if compact and m["key"] != "" else 0.0), ICON, ICON), Color.WHITE if on or i == hover else Color(1, 1, 1, 0.75))
		if compact:
			if m["key"] != "":
				UiKit.text(self, m["key"], Vector2(r.position.x, r.end.y - 4.0), 10, UiKit.AMBER if on else UiKit.DIM_TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			continue
		UiKit.text(self, m["label"], Vector2(ix + ICON + 7.0, r.get_center().y + 5.0), 13, UiKit.AMBER.lightened(0.3) if on else UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiKit.bold())
		if m["key"] != "":
			UiKit.text(self, m["key"], Vector2(r.position.x, r.get_center().y + 4.0), 10, UiKit.AMBER if on else UiKit.DIM_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 7.0)
