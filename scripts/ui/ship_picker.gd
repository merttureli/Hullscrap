extends Control
## "Choose your ship": a centred panel with one card per starter design (data/ships/starter_*.json).
## Each card has the ship's name, its one-line character, a mini schematic (schematic.gd on a private
## arena) and the key numbers: power, mass, hull, shield layers and weapon names. 1 / 2 / 3 or a click
## loads the design into the player's ship (ShipSim.choose_ship); the build mode works as usual after.
## It opens when the game starts; N in play mode (build_mode.gd) asks "Discard current ship? Y/N" first.
## Esc closes it and keeps the current ship (or calls `on_escape`, which the main menu sets for a new run).
## While it is open it swallows every key and click.
## Rules are in ShipSim and Ship.from_design; this node only draws and reads input.

const Ship = preload("res://scripts/ship/ship.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Schematic = preload("res://scripts/ui/schematic.gd")

const DESIGNS: Array[String] = [
	"res://data/ships/starter_rustbucket.json",
	"res://data/ships/starter_courier.json",
	"res://data/ships/starter_prism.json",
]
const CELL_PX := 32.0  ## the build view's cell size, for fitting the camera to a ship
## Screen px the build HUD (hud.gd) covers: the top bar, the mode bar with its hints, and the palette and the card at
## the sides. A chosen ship is fitted in the space between them.
const HUD_TOP := 48.0
const HUD_BOTTOM := 120.0
const HUD_SIDE := 376.0
const CARD := Vector2(300.0, 390.0)
const GAP := 18.0
const PAD := 22.0
const TITLE_H := 74.0
const FOOT_H := 50.0
const DIM := Color(0.0, 0.0, 0.0, 0.8)
const PANEL_BG := Color(0.04, 0.065, 0.1, 0.98)
const CARD_BG := Color(0.075, 0.11, 0.16)
const EDGE := Color("#3b5a78")
const EDGE_HOT := Color("#7fd0ff")
const TEXT := Color("#e4f1ff")
const DIM_TEXT := Color("#8ea6bf")
const GOOD := Color("#4fd08a")
const BAD := Color("#e0453a")

enum Mode { CHOOSE, CONFIRM }

## Emitted after a ship was chosen and the picker closed.
signal chosen

var sim: Node  ## the ShipSim whose player ship is replaced
var build: Node  ## the BuildMode (told about the new ship)
var crew: Node  ## the crew view (its people respawn on the new ship)
var cam: Camera2D  ## fitted to the new ship
var mode: int = Mode.CHOOSE
var hover := -1  ## the card under the mouse
var cards: Array = []  ## {path, name, blurb, stats, schematic}
var on_escape := Callable()  ## called instead of just closing when Esc is pressed (once)


func _ready() -> void:
	sim = get_node_or_null("../../ShipSim")
	build = get_node_or_null("../../BuildMode")
	crew = get_node_or_null("../../Crew")
	cam = get_node_or_null("../../Camera2D")
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	load_cards()
	if get_node_or_null("../../FrontDoor") != null:
		close()  # the front door opens it from New run
	else:
		open()


## Load every design of DESIGNS that can be read into a card; one that cannot is left out.
func load_cards() -> void:
	for c in cards:
		c["schematic"].queue_free()
	cards.clear()
	for path in DESIGNS:
		var ship: Ship = Ship.from_design(path)
		if ship == null:
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		var arena := Arena.new(1)
		arena.add_ship(ship)
		var s := Schematic.new()
		s.bind(arena, 0, "%d  %s" % [cards.size() + 1, ship.name])
		s.visible = false
		add_child(s)
		cards.append({"path": path, "name": ship.name, "blurb": str(d.get("blurb", "")), "stats": stats_of(arena.ships[0]), "schematic": s})
	_layout()


## The numbers a card shows for the arena ship `co`: {supply, demand, mass, hull, layers, sectors, weapons: names}.
static func stats_of(co) -> Dictionary:
	var supply := 0.0
	var demand := 0.0
	for n in co.ship.power_state.get("networks", []):
		supply += n["supply"]
		demand += n["demand"]
	var names: Array[String] = []
	var uids: Array = co.mounts.keys()
	uids.sort()
	for uid in uids:
		var m: Dictionary = co.mounts[uid]
		names.append(str(co.ship.components.def(m["id"]).get("name", m["id"])))
	return {"supply": supply, "demand": demand, "mass": co.mass, "hull": co.hull_max,
		"layers": co.layers_cap, "sectors": co.sectors, "weapons": names}


## The camera ({zoom, pos}) that shows the whole hull of `grid` in a viewport of `view` px, centred
## in the part of the screen the HUD leaves free. The grid sits at the world origin, as build_mode.gd draws it.
static func fit(grid, view: Vector2) -> Dictionary:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in grid.hull:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x + 1.0), maxf(hi.y, c.y + 1.0))
	if grid.hull.is_empty():
		return {"zoom": 0.5, "pos": Vector2.ZERO}
	var px := (hi - lo) * CELL_PX
	var z := clampf(minf((view.x - 2.0 * HUD_SIDE) / px.x, (view.y - HUD_TOP - HUD_BOTTOM) / px.y) * 0.95, 0.1, 1.2)
	var centre := ((lo + hi) / 2.0 - Vector2(grid.size) / 2.0) * CELL_PX
	return {"zoom": z, "pos": centre - Vector2(0.0, (HUD_TOP - HUD_BOTTOM) / 2.0 / z)}


# --- opening and closing -----------------------------------------------------------------------------

## Show the cards.
func open() -> void:
	mode = Mode.CHOOSE
	visible = true
	_show_cards(true)
	queue_redraw()


## Ask "Discard current ship? Y/N"; Y shows the cards.
func ask() -> void:
	mode = Mode.CONFIRM
	visible = true
	_show_cards(false)
	queue_redraw()


## Hide the picker and keep whatever ship the player has.
func close() -> void:
	visible = false
	_show_cards(false)


func _show_cards(on: bool) -> void:
	for c in cards:
		c["schematic"].visible = on


## Load card `i` into the player's ship. "" when it worked, else why not.
func choose(i: int) -> String:
	if sim == null or i < 0 or i >= cards.size():
		return "no such ship"
	var why: String = sim.choose_ship(cards[i]["path"])
	if why != "":
		if build != null:
			build.message = why
		return why
	_prepare(sim.player_ship())
	if crew != null:
		crew.set("player", null)  # they respawn on the new ship
		crew.set("ada", null)
	var ship = sim.player_ship()
	if cam != null:
		var f := fit(ship.grid, get_viewport_rect().size if is_inside_tree() else size)
		cam.zoom = Vector2(f["zoom"], f["zoom"])
		cam.position = f["pos"]
	if build != null:
		build.ship_replaced("%s: B for play mode, then K to fight. Everything can be rebuilt" % ship.name)
	close()
	on_escape = Callable()
	chosen.emit()
	return ""


## The chosen ship, just loaded and before its run starts (the hangar puts the unlocks of the new-run row on it).
func _prepare(_ship) -> void:
	pass


# --- input -------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed:
		return
	_handled()
	if e.echo:
		return
	if mode == Mode.CONFIRM:
		match e.keycode:
			KEY_Y:
				open()
			KEY_N, KEY_ESCAPE:
				close()
		return
	match e.keycode:
		KEY_1, KEY_2, KEY_3:
			choose(e.keycode - KEY_1)
		KEY_ESCAPE:
			var back := on_escape
			on_escape = Callable()
			close()
			if back.is_valid():
				back.call()


func _gui_input(e: InputEvent) -> void:
	if mode != Mode.CHOOSE:
		return
	if e is InputEventMouseMotion:
		hover = card_at(e.position)
		queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		choose(card_at(e.position))


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


# --- layout and drawing --------------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


## The index of the card at the point `p` (this control's coordinates), or -1.
func card_at(p: Vector2) -> int:
	for i in cards.size():
		if card_rect(i).has_point(p):
			return i
	return -1


func panel_rect() -> Rect2:
	var w := cards.size() * CARD.x + maxf(cards.size() - 1.0, 0.0) * GAP + 2.0 * PAD
	var h := PAD + TITLE_H + CARD.y + FOOT_H + PAD
	return Rect2((size - Vector2(w, h)) / 2.0, Vector2(w, h))


func card_rect(i: int) -> Rect2:
	var p := panel_rect()
	return Rect2(p.position + Vector2(PAD + i * (CARD.x + GAP), PAD + TITLE_H), CARD)


func _layout() -> void:
	for i in cards.size():
		cards[i]["schematic"].position = card_rect(i).position + Vector2(10.0, 10.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	if mode == Mode.CONFIRM:
		_draw_confirm()
		return
	var p := panel_rect()
	draw_rect(p, PANEL_BG)
	draw_rect(p, EDGE, false, 2.0)
	_text("Choose your ship", p.position + Vector2(PAD, PAD + 30.0), 28, TEXT)
	_text("Pick one to start with. You can rebuild all of it afterwards.", p.position + Vector2(PAD, PAD + 54.0), 14, DIM_TEXT)
	for i in cards.size():
		_draw_card(i)
	_text("1 / 2 / 3 or click to choose      Esc: keep the current ship      then B for play mode and K to fight",
		p.position + Vector2(PAD, p.size.y - PAD - 8.0), 14, DIM_TEXT)


func _draw_card(i: int) -> void:
	var r := card_rect(i)
	var c: Dictionary = cards[i]
	draw_rect(r, CARD_BG)
	draw_rect(r, EDGE_HOT if i == hover else EDGE, false, 3.0 if i == hover else 2.0)
	var x := r.position.x + 12.0
	var y := r.position.y + 10.0 + Schematic.PANEL.y + 18.0
	draw_multiline_string(ThemeDB.fallback_font, Vector2(x, y), c["blurb"], HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 24.0, 13, 3, DIM_TEXT)
	var st: Dictionary = c["stats"]
	y += 66.0
	var ok: bool = st["supply"] + 0.0001 >= st["demand"]
	_stat(x, y, "Power", "%s supply / %s demand" % [_num(st["supply"]), _num(st["demand"])], GOOD if ok else BAD)
	_stat(x, y + 19.0, "Mass", "%d" % roundi(st["mass"]))
	_stat(x + 130.0, y + 19.0, "Hull", "%d" % roundi(st["hull"]))
	var layers: int = st["layers"]
	var shield := "none" if layers == 0 else "%d layer%s%s" % [layers, "" if layers == 1 else "s", ", %d sectors" % st["sectors"] if st["sectors"] > 1 else ""]
	_stat(x, y + 38.0, "Shield", shield)
	_text("Weapons", Vector2(x, y + 57.0), 13, DIM_TEXT)
	draw_multiline_string(ThemeDB.fallback_font, Vector2(x + 62.0, y + 57.0), ", ".join(st["weapons"]), HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 24.0 - 62.0, 13, 2, TEXT)


func _draw_confirm() -> void:
	var box := Rect2((size - Vector2(460.0, 120.0)) / 2.0, Vector2(460.0, 120.0))
	draw_rect(box, PANEL_BG)
	draw_rect(box, EDGE, false, 2.0)
	_text("Discard current ship?", box.position + Vector2(24.0, 50.0), 26, TEXT)
	_text("Y: yes, choose another      N: keep this ship", box.position + Vector2(24.0, 90.0), 15, DIM_TEXT)


func _stat(x: float, y: float, label: String, value: String, col := TEXT) -> void:
	_text(label, Vector2(x, y), 13, DIM_TEXT)
	_text(value, Vector2(x + 62.0, y), 13, col)


## A figure: whole numbers plain, others with one decimal.
static func _num(v: float) -> String:
	return "%d" % roundi(v) if is_equal_approx(v, roundf(v)) else "%.1f" % v


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
