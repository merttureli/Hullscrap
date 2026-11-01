extends Control
## The station bar (playtest 2, K1): a vertical strip on the left edge above the log, in play mode, with one small button for
## each crewable part of the ship (Posts.stations: the helm, the weapons, the shields, the medbay, the smelters and the other
## manned parts). A button shows the part's picture (the palette's Thumbs) and the initial of the crew member posted there; it
## is lit while someone really is at the post. Hovering says the part and who is posted. A left click posts the selected crew
## member there (or selects whoever is posted when nobody is selected), a right click takes the post away; both go through the
## crew view (crew_view.gd press_station / release_station), which says the result on the crew bar. A second column starts when the
## strip would be taller than the room it has. A wheel step over the bar is swallowed, so it never zooms the world.

const Posts = preload("res://scripts/crew/posts.gd")
const Thumbs = preload("res://scripts/ui/thumbs.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const BTN := 42.0  ## one button, px
const GAP := 4.0
const PAD := 6.0

var hud: Control
var hover := -1  ## index of the button under the mouse
var _uids: Array = []  # the parts of the buttons, in order
var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): hover = -1)


func _process(dt: float) -> void:
	_clock += dt
	if visible:
		refresh()
		queue_redraw()


func _ship():
	return hud.build.ship if hud != null and hud.build != null else null


func _view():
	return hud.build.crew if hud != null and hud.build != null else null


## Read the stations of the ship again (the bar's buttons).
func refresh() -> void:
	var ship = _ship()
	_uids = Posts.stations(ship) if ship != null else []


## How many buttons there are.
func count() -> int:
	refresh()
	return _uids.size()


## The uid of the part of button `i`, -1 for none.
func uid_at(i: int) -> int:
	return int(_uids[i]) if i >= 0 and i < _uids.size() else -1


## The size of the strip for `n` buttons when it has `avail_h` px of height: columns of as many buttons as fit.
static func size_for(n: int, avail_h: float) -> Vector2:
	if n <= 0:
		return Vector2.ZERO
	var rows := mini(n, maxi(1, int((avail_h - 2.0 * PAD + GAP) / (BTN + GAP))))
	var cols := ceili(float(n) / float(rows))
	return Vector2(2.0 * PAD + cols * BTN + (cols - 1) * GAP, 2.0 * PAD + rows * BTN + (rows - 1) * GAP)


## The rectangle of button `i` (in this control's coordinates) in a strip of `n` buttons that is `strip` px big: down a column, then the next.
static func button_rect(i: int, n: int, strip: Vector2) -> Rect2:
	var rows := maxi(1, int((strip.y - 2.0 * PAD + GAP + 0.5) / (BTN + GAP)))
	return Rect2(Vector2(PAD + (i / rows) * (BTN + GAP), PAD + (i % rows) * (BTN + GAP)), Vector2(BTN, BTN))


## The button under local point `p`, -1 for none.
func button_at(p: Vector2) -> int:
	for i in _uids.size():
		if button_rect(i, _uids.size(), size).has_point(p):
			return i
	return -1


## The words under the mouse: the part, and who is posted there and whether they are at it.
func tip_for(i: int) -> String:
	var ship = _ship()
	var uid := uid_at(i)
	if ship == null or uid < 0:
		return ""
	var who = Posts.holder(ship, uid)
	var line := Posts.name_of(ship, uid)
	if who == null:
		return line + "\nNo one posted.\nSelect a crew member, then click to post them here."
	return "%s\nPosted: %s (%s)\nClick: select them. Right click: take them off the post." % [line, who.name, "at the post" if ship.manned.has(uid) else "on the way"]


func _get_tooltip(at_position: Vector2) -> String:
	return tip_for(button_at(at_position))


func _gui_input(e: InputEvent) -> void:
	if UiKit.is_wheel(e):
		accept_event()
	if e is InputEventMouseMotion:
		hover = button_at(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var i := button_at(e.position)
		if i >= 0:
			click(i, e.button_index == MOUSE_BUTTON_RIGHT)
			accept_event()


## Button `i` was clicked (`right`: with the right button). Returns what was said.
func click(i: int, right := false) -> String:
	var view = _view()
	var uid := uid_at(i)
	if view == null or uid < 0:
		return ""
	var text: String = view.release_station(uid) if right else view.press_station(uid)
	view.say(text)
	return text


func _draw() -> void:
	var ship = _ship()
	if ship == null or _uids.is_empty():
		return
	var view = _view()
	UiKit.bar(self, Rect2(Vector2.ZERO, size))
	var who_sel = view.selected if view != null else null
	for i in _uids.size():
		var uid: int = _uids[i]
		var r := button_rect(i, _uids.size(), size)
		var who = Posts.holder(ship, uid)
		var at: bool = who != null and ship.manned.get(uid, "") == who.name
		UiKit.button(self, r, at, i == hover)
		var id: String = ship.components.instances[uid]["id"]
		Thumbs.draw(self, {"kind": "part", "id": id}, ship, r.grow(-5.0), _clock)
		if who != null:
			if who == who_sel:
				draw_rect(r, UiKit.AMBER, false, 2.0)
			var chip := Rect2(r.end - Vector2(17.0, 17.0), Vector2(16.0, 16.0))
			draw_rect(chip, Color(0, 0, 0, 0.8))
			draw_rect(chip, UiKit.GOOD if at else UiKit.EDGE_DIM, false, 1.0)
			UiKit.text(self, who.name.left(1).to_upper(), chip.position + Vector2(0.0, 12.5), 12, UiKit.TEXT if at else UiKit.DIM_TEXT, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, UiKit.bold())
