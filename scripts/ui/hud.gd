extends Control
## The game HUD around the ship (docs/waves/content_loop_1.md, priority 0.3): the resource bar along the top,
## the build palette (left) and the selection card (right) in build mode, the log (bottom left), the mode bar
## (bottom centre) with the last message and the key hints over it, and the note at the cursor (why a placement
## is refused, what a drag costs). build_mode.gd makes it in a canvas layer of its own; the rules stay there and in
## BuildSession, and these panels only read, draw and hand clicks back. Hidden in a fight and under the ship picker.

const TopBar = preload("res://scripts/ui/hud_top_bar.gd")
const PalettePanel = preload("res://scripts/ui/hud_palette.gd")
const InfoCard = preload("res://scripts/ui/hud_card.gd")
const ModeBar = preload("res://scripts/ui/hud_mode_bar.gd")
const LogPanel = preload("res://scripts/ui/hud_log.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const MARGIN := 8.0
const TOP_H := 40.0
const SIDE_W := 360.0
const MODE_H := 52.0
const HINT_SIZE := 12  ## font size of the key hints
const HINT_LINE := 16.0
const HINT_PAD := 10.0  ## inside the hints' frame
const MSG_SIZE := 14
const TIP_SIZE := 13

var build: Node  ## the BuildMode node: the ship, the tool, the message
var top_bar: Control
var palette: Control
var card: Control
var mode_bar: Control
var log_panel: Control
var hint_rect := Rect2()  ## where the message and the key hints are drawn
var view := Vector2(1600, 900)  ## the screen size of the last layout
var cursor_state := ""  ## the kit cursor on show: "" (the system's), place, remove or invalid
var _tip: Control  # the note at the cursor, over everything


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Make the panels for `p_build` (a BuildMode); works without a scene tree, for tests.
func setup(p_build: Node) -> void:
	build = p_build
	top_bar = _add(TopBar.new())
	log_panel = _add(LogPanel.new())
	palette = _add(PalettePanel.new())
	card = _add(InfoCard.new())
	mode_bar = _add(ModeBar.new())
	_tip = Control.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tip.draw.connect(_draw_tip)
	add_child(_tip)
	sync(view)


func _add(c: Control) -> Control:
	c.set("hud", self)
	add_child(c)
	return c


func _process(_dt: float) -> void:
	if build == null:
		return
	sync(get_viewport_rect().size)
	_set_cursor(wanted_cursor(get_viewport().get_mouse_position()))
	queue_redraw()
	_tip.queue_redraw()


## Show what the mode needs and lay it out for a screen of `p_view` px.
func sync(p_view: Vector2) -> void:
	var picker = build.picker
	visible = not build.combat and build.ship != null and (picker == null or not picker.visible)
	palette.visible = build.build_on
	card.visible = build.build_on
	layout(p_view)


## Place every panel for a screen of `p_view` px: the top bar across, the palette over the log on the left, the
## card on the right, the mode bar at the bottom centre (icons only when it would not fit between the sides) and
## the hints over it, between the side columns.
func layout(p_view: Vector2) -> void:
	view = p_view
	var side := SIDE_W + 2.0 * MARGIN
	_place(top_bar, Rect2(0, 0, view.x, TOP_H))
	var log_h: float = log_panel.wanted_height()
	_place(log_panel, Rect2(MARGIN, view.y - MARGIN - log_h, SIDE_W, log_h))
	_place(palette, Rect2(MARGIN, TOP_H + MARGIN, SIDE_W, view.y - log_h - TOP_H - 3.0 * MARGIN))
	mode_bar.compact = ModeBar.width_for(false) > view.x - 2.0 * side
	var mw: float = mode_bar.full_width()
	_place(mode_bar, Rect2(floorf((view.x - mw) / 2.0), view.y - MARGIN - MODE_H, mw, MODE_H))
	_place(card, Rect2(view.x - MARGIN - SIDE_W, TOP_H + MARGIN, SIDE_W, minf(card.wanted_height(), view.y - TOP_H - 2.0 * MARGIN)))
	var lines := hint_lines(view.x - 2.0 * side - 2.0 * HINT_PAD)
	var h := lines.size() * HINT_LINE + (2.0 * HINT_PAD if not lines.is_empty() else 0.0)
	hint_rect = Rect2(side, mode_bar.position.y - MARGIN - h, view.x - 2.0 * side, h)


func _place(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = r.size


## The rect of every panel on show (name -> Rect2, screen px), the hints included when there are any.
func panel_rects() -> Dictionary:
	var out := {}
	for n in ["top_bar", "palette", "card", "mode_bar", "log_panel"]:
		var c: Control = get(n)
		if c.visible:
			out[n] = Rect2(c.position, c.size)
	if hint_rect.size.y > 0.0:
		out["hints"] = hint_rect
	return out


## Is screen point `p` over a panel (so the ghost hides and the world takes no click)?
func over_ui(p: Vector2) -> bool:
	if not visible:
		return false
	for r in panel_rects().values():
		if r.has_point(p):
			return true
	return false


## The last message (amber) and the key hints of the mode, wrapped to `width`: [[text, colour, size]].
func hint_lines(width: float) -> Array:
	var out := []
	if build == null or build.ship == null:
		return out
	if build.message != "":
		for l in UiKit.wrap(build.message, width, MSG_SIZE):
			out.append([l, UiKit.AMBER, MSG_SIZE])
	for row in build._controls_text().split("\n"):
		for l in UiKit.wrap(row, width, HINT_SIZE, null, "   "):
			out.append([l, UiKit.DIM_TEXT, HINT_SIZE])
	return out


## A button of the mode bar or a key: "build", "play", "map", "shields", "crafting" or "help". Returns what it did ("" for nothing).
func switch_mode(id: String) -> String:
	if build == null or build.combat:
		return ""
	var main: Node = build.get_parent()
	var craft: Node = main.get_node_or_null("CraftLayer/CraftingPanel") if main != null else null
	var help = build.front.get("help") if build.front != null else null
	match id:
		"build", "play":
			build.set_build(id == "build")
		"map":
			return build.open_map()
		"shields":
			if build.shields == null:
				return ""
			build.shields.open()
		"crafting":
			if craft == null:
				return ""
			craft.open()
		"help":
			if help == null:
				return ""
			help.open()
	return id


## The mode lit on the mode bar: a screen that is open, else build or play.
func active_mode() -> String:
	if build == null:
		return ""
	var main: Node = build.get_parent()
	var craft: Node = main.get_node_or_null("CraftLayer/CraftingPanel") if main != null else null
	var help = build.front.get("help") if build.front != null else null
	if help != null and help.visible:
		return "help"
	if build.drift != null and build.drift.visible:
		return "map"
	if build.shields != null and build.shields.visible:
		return "shields"
	if craft != null and craft.visible:
		return "crafting"
	return "build" if build.build_on else "play"


## The kit cursor for the mouse at screen point `p`: in build mode over the world, place (the edit would apply),
## invalid (refused) or remove (a right-button stroke); "" elsewhere.
func wanted_cursor(p: Vector2) -> String:
	if build == null or not visible or not build.build_on or over_ui(p) or build.ghost.is_empty():
		return ""
	if build.dragging and build.drag_button == MOUSE_BUTTON_RIGHT:
		return "remove"
	return "invalid" if build.cursor_note()["bad"] else "place"


func _set_cursor(state: String) -> void:
	if state == cursor_state:
		return
	cursor_state = state
	var c = UiKit.cursor(state) if state != "" else null
	if c == null:
		Input.set_custom_mouse_cursor(null)
	else:
		Input.set_custom_mouse_cursor(c[0], Input.CURSOR_ARROW, c[1])


## A mouse release over a panel while a stroke is being drawn in the world still ends the stroke. True when it did.
func pass_release(e: InputEvent) -> bool:
	if e is InputEventMouseButton and not e.pressed and build != null and build.dragging and e.button_index == build.drag_button:
		build.finish_drag()
		return true
	return false


func _draw() -> void:
	if build == null or hint_rect.size.y <= 0.0:
		return
	var lines := hint_lines(hint_rect.size.x - 2.0 * HINT_PAD)
	UiKit.bar(self, hint_rect, 0.8)
	var y := hint_rect.position.y + HINT_PAD - 2.0
	for l in lines:
		y += HINT_LINE
		UiKit.text(self, l[0], Vector2(hint_rect.position.x + HINT_PAD, y - 4.0), l[2], l[1], HORIZONTAL_ALIGNMENT_CENTER, hint_rect.size.x - 2.0 * HINT_PAD)


## The note at the cursor: build_mode.gd cursor_note(), kept inside the world area between the panels.
func _draw_tip() -> void:
	if build == null or not build.build_on or build.combat:
		return
	var mouse := get_viewport().get_mouse_position() if is_inside_tree() else Vector2.ZERO
	if over_ui(mouse):
		return
	var note: Dictionary = build.cursor_note()
	if note["text"] == "":
		return
	var w := UiKit.text_width(note["text"], TIP_SIZE) + 30.0
	var r := Rect2(mouse + Vector2(22, 20), Vector2(w, 30))
	var lo := Vector2((SIDE_W + 2.0 * MARGIN) if palette.visible else MARGIN, TOP_H + MARGIN)
	var hi := Vector2(view.x - ((SIDE_W + 2.0 * MARGIN) if card.visible else MARGIN), hint_rect.position.y - MARGIN)
	if r.end.x > hi.x:
		r.position.x = mouse.x - 22.0 - w
	if r.end.y > hi.y:
		r.position.y = mouse.y - 46.0
	r.position = r.position.clamp(lo, (hi - r.size).max(lo))
	var col: Color = UiKit.BAD if note["bad"] else UiKit.GOOD
	UiKit.tooltip(_tip, r, col)
	_tip.draw_rect(Rect2(r.position + Vector2(6, 7), Vector2(4, r.size.y - 14)), col)
	UiKit.text(_tip, note["text"], r.position + Vector2(16, 20), TIP_SIZE, col.lerp(UiKit.TEXT, 0.55))
