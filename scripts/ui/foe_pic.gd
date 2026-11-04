extends Control
## The pre-fight picture of an enemy (the contact card, the event's fight choice, the warden): her real generated ship next to your own at the same
## scale, so size reads at a glance, with her emblem and name line. No skulls and no numbers. Give it `show_foe(ship, mine)`; it draws both ships
## with the real ship art (ShipView) inside its own clipped box.

const ShipView = preload("res://scripts/view/ship_view.gd")
const Emblem = preload("res://scripts/view/emblem.gd")

const BOX := Vector2(380.0, 190.0)
const PIC_H := 140.0  ## the height of the picture part
const BG := Color("#10151c")
const EDGE := Color("#3a4a5e")
const TEXT := Color("#dfe8f5")
const DIM := Color("#8696b0")

var foe  ## her Ship
var mine  ## your Ship
var line := ""  ## the name line
var look := {}  ## her livery (Shipgen.style_of), {} for an authored design
var _pic: Control
var _views: Array = []


func _init() -> void:
	custom_minimum_size = BOX
	size = BOX
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pic = Control.new()
	_pic.clip_contents = true
	_pic.position = Vector2(4.0, 4.0)
	_pic.size = Vector2(BOX.x - 8.0, PIC_H)
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pic)


## Show `p_foe` against `p_mine`. `p_line`: her name line.
func show_foe(p_foe, p_mine, p_line: String) -> void:
	foe = p_foe
	mine = p_mine
	line = p_line
	look = p_foe.get_meta("style", {}) if p_foe != null else {}
	for v in _views:
		v.queue_free()
	_views = []
	if foe == null:
		queue_redraw()
		return
	var boxes: Array = [hull_box(foe), hull_box(mine) if mine != null else Rect2()]
	var k := minf(_pic.size.y / maxf(float(boxes[0].size.y), 1.0), _pic.size.y / maxf(float(boxes[1].size.y), 1.0))
	k = minf(k, (_pic.size.x * 0.5 - 12.0) / maxf(float(boxes[0].size.x), float(boxes[1].size.x)))  # both ships at this one scale
	_add(foe, boxes[0], Vector2(_pic.size.x * 0.27, _pic.size.y * 0.5), k, true)
	if mine != null:
		_add(mine, boxes[1], Vector2(_pic.size.x * 0.77, _pic.size.y * 0.5), k, false)
	queue_redraw()


func _add(ship, box: Rect2, centre: Vector2, k: float, skin: bool) -> void:
	var v := ShipView.new()
	v.skin_on = skin
	_pic.add_child(v)
	v.scale = Vector2(k, k) / ShipView.CELL
	v.show_ship(ship)
	v.position = centre - (box.position + box.size / 2.0 - v.pivot) * k
	_views.append(v)


## The cell box of a ship's tiles and its mounts' outside halves.
static func hull_box(ship) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var cells: Array = ship.grid.tiles.keys()
	for uid in ship.components.instances:
		cells.append_array(ship.components.instances[uid]["out_cells"])
	for c in cells:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x + 1.0), maxf(hi.y, c.y + 1.0))
	return Rect2(lo, hi - lo) if lo.x < INF else Rect2()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, BOX), BG)
	var accent: Color = look["palette"]["accent"] if not look.is_empty() else EDGE
	draw_rect(Rect2(Vector2.ZERO, BOX), accent.lerp(EDGE, 0.4), false, 2.0)
	var y := PIC_H + 8.0
	if not look.is_empty():
		Emblem.draw(self, look["emblem"], Rect2(12.0, y + 6.0, 30.0, 30.0), look["palette"]["mark"], 2.5)
	draw_string(ThemeDB.fallback_font, Vector2(52.0, y + 26.0), line, HORIZONTAL_ALIGNMENT_LEFT, BOX.x - 64.0, 18, TEXT)
	draw_string(ThemeDB.fallback_font, Vector2(BOX.x * 0.77 - 28.0, BOX.y - 6.0), "your ship", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
