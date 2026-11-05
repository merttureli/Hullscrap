extends Control
## The build palette, on the left in build mode: a row of category tabs (Tab and Shift+Tab cycle them) over a
## scrolling grid of picture cards, three across (scripts/build/palette.gd says what each tab holds: only what can be placed
## now). A card is pic_card.gd's: the real sprite, two or three figures, the cost or the count held, framed in its line's colour, with
## no name; the first nine carry their number key. A click on a tab opens it, a
## click on a card picks it (build_mode.gd pick()), the wheel scrolls, and the card under the mouse is what the
## selection card (hud_card.gd) shows.

const Palette = preload("res://scripts/build/palette.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const PicCard = preload("res://scripts/ui/pic_card.gd")
const Audio = preload("res://scripts/audio/audio.gd")

const PAD := 14.0
const TAB_H := 38.0
const TAB_GAP := 4.0
const HEAD_H := 30.0
const CARD_H := 124.0
const GAP := 6.0
const COLS := 3
const SCROLL_STEP := 54.0

var hud: Control
var list: Control  ## the clipped grid of cards
var scroll := 0.0  ## px the grid is scrolled down
var hover_tab := -1
var hover_key := ""  ## the card under the mouse ("" for none)
var _shown_tab := -1  # the tab drawn last frame: a new one scrolls back to the top
var _shown_key := ""  # the tool picked last frame: a new one is scrolled into view
var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		hover_tab = -1
		hover_key = "")
	list = Control.new()
	list.clip_contents = true
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.draw.connect(_draw_list)
	add_child(list)


func _process(dt: float) -> void:
	_clock += dt
	if not visible or hud == null or hud.build == null or hud.build.ship == null:
		return
	list.position = list_rect().position
	list.size = list_rect().size
	_follow()
	queue_redraw()
	list.queue_redraw()


## The cards of the open tab.
func entries() -> Array:
	var b: Node = hud.build
	return Palette.entries(b.tab, b.ship, b.session.cable_cost)


## The rect of the grid (local px).
func list_rect() -> Rect2:
	var top := PAD + TAB_H + HEAD_H + 4.0
	return Rect2(PAD + 2.0, top, size.x - 2.0 * PAD - 4.0, maxf(0.0, size.y - top - PAD - 2.0))


func tab_rect(i: int) -> Rect2:
	var n := Palette.TAB_NAMES.size()
	var w := (size.x - 2.0 * PAD - (n - 1) * TAB_GAP) / n
	return Rect2(PAD + i * (w + TAB_GAP), PAD, w, TAB_H)


func card_size() -> Vector2:
	return Vector2((list_rect().size.x - (COLS - 1) * GAP - 12.0) / COLS, CARD_H)  # 12 px for the scroll bar


## Card `i`'s rect in the grid's own px (scrolled).
func card_rect(i: int) -> Rect2:
	var s := card_size()
	return Rect2(Vector2((i % COLS) * (s.x + GAP), (i / COLS) * (s.y + GAP) - scroll), s)


func content_height(n: int) -> float:
	return ceili(float(n) / COLS) * (CARD_H + GAP) - GAP


func _max_scroll() -> float:
	return maxf(0.0, content_height(entries().size()) - list_rect().size.y)


## The card under local point `p`, or {}.
func entry_at(p: Vector2) -> Dictionary:
	var lr := list_rect()
	if not lr.has_point(p):
		return {}
	var list_e := entries()
	for i in list_e.size():
		if card_rect(i).has_point(p - lr.position):
			return list_e[i]
	return {}


## The card under the mouse, or {}.
func hovered() -> Dictionary:
	if hover_key == "" or not visible:
		return {}
	for e in entries():
		if e["key"] == hover_key:
			return e
	return {}


## A new tab starts at the top; a newly picked card (a number key, T) is scrolled into view.
func _follow() -> void:
	var b: Node = hud.build
	if b.tab != _shown_tab:
		_shown_tab = b.tab
		scroll = 0.0
	var key: String = b.tool_key()
	if key != _shown_key:
		_shown_key = key
		var list_e := entries()
		for i in list_e.size():
			if list_e[i]["key"] == key:
				var r := card_rect(i)
				if r.position.y < 0.0:
					scroll += r.position.y
				elif r.end.y > list_rect().size.y:
					scroll += r.end.y - list_rect().size.y
	scroll = clampf(scroll, 0.0, _max_scroll())


func _gui_input(e: InputEvent) -> void:
	if hud.pass_release(e):
		return
	if UiKit.is_wheel(e):
		accept_event()  # the wheel scrolls the palette below, and never zooms the world
	if e is InputEventMouseMotion:
		hover_tab = -1
		for i in Palette.TAB_NAMES.size():
			if tab_rect(i).has_point(e.position):
				hover_tab = i
		hover_key = entry_at(e.position).get("key", "")
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				scroll = clampf(scroll - SCROLL_STEP, 0.0, _max_scroll())
			MOUSE_BUTTON_WHEEL_DOWN:
				scroll = clampf(scroll + SCROLL_STEP, 0.0, _max_scroll())
			MOUSE_BUTTON_LEFT:
				click(e.position)


## A left click at local point `p`: a tab opens, a card is picked.
func click(p: Vector2) -> void:
	var b: Node = hud.build
	for i in Palette.TAB_NAMES.size():
		if tab_rect(i).has_point(p):
			b.set_tab(i)
			Audio.fx(self, "click")
			return
	var en := entry_at(p)
	if not en.is_empty():
		b.pick(en)
		Audio.fx(self, "click")


func _draw() -> void:
	if hud == null or hud.build == null or hud.build.ship == null:
		return
	var b: Node = hud.build
	UiKit.panel(self, Rect2(Vector2.ZERO, size))
	for i in Palette.TAB_NAMES.size():
		var r := tab_rect(i)
		UiKit.tab(self, r, i == b.tab, i == hover_tab)
		var s := minf(22.0, r.size.y - 12.0)
		UiKit.icon(self, Palette.TAB_ICONS[i], Rect2(r.get_center() - Vector2(s, s) / 2.0, Vector2(s, s)), Color.WHITE if i == b.tab else Color(1, 1, 1, 0.7))
	var shown: int = hover_tab if hover_tab >= 0 else b.tab
	var head := Rect2(PAD, PAD + TAB_H + 2.0, size.x - 2.0 * PAD, HEAD_H - 6.0)
	UiKit.title_bar(self, head, Palette.TAB_NAMES[shown].to_upper(), 13)
	var list_e := entries()
	var note := "Tab: next   1-9: pick"
	UiKit.text(self, note, Vector2(head.position.x, head.get_center().y + 4.0), 10, UiKit.DIM_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, head.size.x - 22.0)
	var lr := list_rect()
	UiKit.inset(self, lr.grow(4))
	var total := content_height(list_e.size())
	if list_e.is_empty():
		var lines := UiKit.wrap(Palette.empty_text(b.tab), lr.size.x - 16.0, 13)
		for i in lines.size():
			UiKit.text(self, lines[i], lr.position + Vector2(10.0, 26.0 + i * 18.0), 13, UiKit.DIM_TEXT)
	if total > lr.size.y:
		UiKit.scrollbar(self, Rect2(lr.end.x - 8.0, lr.position.y, 8.0, lr.size.y), lr.size.y / total, scroll / maxf(1.0, total - lr.size.y))


func _draw_list() -> void:
	if hud == null or hud.build == null or hud.build.ship == null:
		return
	var b: Node = hud.build
	var key: String = b.tool_key()
	var list_e := entries()
	for i in list_e.size():
		var r := card_rect(i)
		if r.end.y < 0.0 or r.position.y > list.size.y:
			continue
		draw_card(list, list_e[i], r, list_e[i]["key"] == key, list_e[i]["key"] == hover_key, i)


## The picture card of entry `e` (pic_card.gd's spec): no name, its figures, its cost or how many are held, its number key (the first nine).
func spec_of(e: Dictionary, index: int) -> Dictionary:
	var ship = hud.build.ship
	var g: Dictionary = Palette.glance(e, ship)
	var held := -1
	if e["kind"] in ["part", "item"]:
		held = int(e["count"])
	return {"entry": e, "line": e["line"], "stats": g["stats"], "aim": g["aim"], "cost": e["cost"], "short": ship.inventory.missing(e["cost"]),
		"held": held, "tags": [], "key": index + 1 if index < 9 else 0, "meta": "", "meta_bad": false}


## One card: PicCard draws it from spec_of().
func draw_card(cv: CanvasItem, e: Dictionary, r: Rect2, selected: bool, hot: bool, index: int) -> void:
	PicCard.draw(cv, r, hud.build.ship, spec_of(e, index), selected, hot, _clock)
