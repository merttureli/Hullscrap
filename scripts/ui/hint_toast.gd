extends Control
## A hint toast: one line in a small panel at the top of the screen that fades away after a few seconds. The first-run
## hints (front_door.gd) use it; several wait their turn. Draws only, takes no input.

const SHOW_FOR := 7.0  ## seconds a toast stays
const FADE := 0.8  ## and fades over the last of them
const PANEL_BG := Color("#1f2630")
const EDGE := Color("#cfd6df")
const TEXT := Color("#eef2f7")
const AMBER := Color("#e1a136")

var queue: Array[String] = []  ## the toasts waiting
var current := ""  ## the one on show
var left := 0.0  ## seconds it has left
var top := 6.0  ## y of the panel: lower in a fight, under the key line of the combat screen


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Show `text` for SHOW_FOR seconds, after the one on show.
func push(text: String) -> void:
	if current == "":
		current = text
		left = SHOW_FOR
	else:
		queue.append(text)
	queue_redraw()


## Time passes by `dt` seconds.
func tick(dt: float) -> void:
	if current == "":
		return
	left -= dt
	if left <= 0.0:
		current = queue.pop_front() if not queue.is_empty() else ""
		left = SHOW_FOR if current != "" else 0.0
	queue_redraw()


func _process(dt: float) -> void:
	tick(dt)


## How opaque the toast is: 1, fading to 0 over the last FADE seconds.
func alpha() -> float:
	return clampf(left / FADE, 0.0, 1.0) if current != "" else 0.0


func _draw() -> void:
	if current == "":
		return
	var a := alpha()
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(current, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var r := Rect2(Vector2((size.x - w) / 2.0 - 24.0, top), Vector2(w + 48.0, 40.0))
	draw_rect(r, Color(PANEL_BG, 0.95 * a))
	draw_rect(r, Color(AMBER, a), false, 2.0)
	draw_string(font, r.position + Vector2(24.0, 28.0), current, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(TEXT, a))
