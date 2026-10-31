extends Control
## The Hollow tide's clock in play mode: one line at the top right, "Hollow tide: rises in 2:41" (docs/MECHANICS_REVIEW.md
## P1, tide.gd). Amber under 60 s, red under 15 s. Hidden in build mode, in fights, while the map is open, once the tide
## has crossed the whole map, and with no campaign. map_view.gd adds it to its own canvas layer and owns the rules for
## "play mode"; this node only draws and takes no input.

const Tide = preload("res://scripts/space/tide.gd")

const PANEL_BG := Color("#1f2630")
const TEXT := Color("#c9c3d6")  ## a dead violet-grey while there is time
const AMBER := Color("#e1a136")
const RED := Color("#e0413b")
const WARN_S := 60.0
const ALARM_S := 15.0
const FONT := 18
const TOP := 48.0  ## px: under the resource bar of the HUD

var map: Control  ## the MapView: campaign, play mode and fight state


## The line to show, "" when the clock is hidden.
func line() -> String:
	if map == null or not map.has_method("playing") or not map.playing() or map.campaign.tide.spent():
		return ""
	return "Hollow tide: rises in " + Tide.clock(map.campaign.tide.linger_left())


## The colour of the line: amber under 60 s left, red under 15 s.
func tint() -> Color:
	if map == null or map.campaign == null:
		return TEXT
	var left: float = map.campaign.tide.linger_left()
	return RED if left < ALARM_S else (AMBER if left < WARN_S else TEXT)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_dt: float) -> void:
	visible = line() != ""
	if visible:
		queue_redraw()


func _draw() -> void:
	var text := line()
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
	var r := Rect2(Vector2(size.x - w - 44.0, TOP), Vector2(w + 28.0, 34.0))
	var col := tint()
	draw_rect(r, Color(PANEL_BG, 0.9))
	draw_rect(r, col, false, 2.0)
	draw_string(font, r.position + Vector2(14.0, 24.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, col)
