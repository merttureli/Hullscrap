extends Control
## The Hollow tide's clock in play mode: one line at the top right, "Hollow tide: rises in 2:41" (docs/MECHANICS_REVIEW.md
## P1, tide.gd). Amber under 60 s, red under 15 s. Hidden in build mode, in fights, while the map is open, once the tide
## has crossed the whole map, and with no campaign. map_view.gd adds it to its own canvas layer and owns the rules for
## "play mode"; this node only draws and takes no input. While the place the ship is in is Hollow (and sector space runs)
## a second red line under it says "Hollow place: ghosts every 60 s", for as long as the ship lingers there.

const Tide = preload("res://scripts/space/tide.gd")
const Sector = preload("res://scripts/space/sector.gd")

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


## The warning line of a Hollow place, "" elsewhere (and when the map is not in play mode or sector space is off).
func warning() -> String:
	if map == null or not map.has_method("playing") or not map.playing() or not map.sector_flow() or not map.campaign.is_hollow(map.campaign.current):
		return ""
	return "Hollow place: ghosts every %d s" % int(Sector.config()["ambient"]["hollow"]["every"])


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
	visible = line() != "" or warning() != ""
	if visible:
		queue_redraw()


func _draw() -> void:
	var y := TOP
	for e in [[line(), tint()], [warning(), RED]]:
		if e[0] == "":
			continue
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
		var r := Rect2(Vector2(size.x - w - 44.0, y), Vector2(w + 28.0, 34.0))
		draw_rect(r, Color(PANEL_BG, 0.9))
		draw_rect(r, e[1], false, 2.0)
		draw_string(font, r.position + Vector2(14.0, 24.0), e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, e[1])
		y += 40.0
