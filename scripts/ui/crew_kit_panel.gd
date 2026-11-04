extends Control
## The crew equipment screen (I, in play mode): what every crew member carries, set while the ship flies. It is a panel on the right of the screen, so the ship stays in
## view and the game keeps running; the person under the cursor on the ship (or the one whose tab the cursor is on) gets a ring.
## - Top: a tab for every crew member (not the drones). Below: the person shown, drawn by the airlock's loadout drawing (board_loadout.gd: the same slots, the same
##   choices with their stats lines): two weapons, a body and two mods. A click on a slot lists what fits; a click on a choice takes it, "Nothing" takes it off (back to
##   the hold), "Give to <name>" moves it to another crew member. Their sidearm stays with them.
## - Bottom: the gear in the hold. A click on an item puts it in the open slot, or the first free slot it fits.
## It is not open in a fight, while boarding, in build mode, or over another screen. Rules: crew_kit.gd (and kit.gd under it); this node reads input and draws.

const CrewKit = preload("res://scripts/crew/crew_kit.gd")
const Loadout = preload("res://scripts/board/board_loadout.gd")
const Cards = preload("res://scripts/board/board_cards.gd")
const Kit = preload("res://scripts/board/kit.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Mods = preload("res://scripts/board/mods.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Art = preload("res://scripts/view/art.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Audio = preload("res://scripts/audio/audio.gd")
const BreachPrompt = preload("res://scripts/ui/breach_prompt.gd")

const PANEL_BG := Color("#1f2630")
const ROW_BG := Color("#2a3340")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const GOOD := Color("#6bd34a")
const BAD := Color("#e0584a")
const AMBER := Color("#e1a136")
const CYAN := Color("#43e6ff")
const AIRLOCK := Color("#58e08a")
const PW := 800.0
const TOP := 92.0  ## the panel starts below the top bar of the HUD
const MARGIN := 16.0
const TAB := Vector2(116, 30)
const HOLD_ROW := 44.0

var sim: Node  ## the ShipSim whose player ship is shown
var build: Node  ## the BuildMode (play mode, fights)
var crew: Node  ## the Crew view (it draws the ring)
var kit := CrewKit.new()
var _hits: Array = []  # [[Rect2, Dictionary]] what a click means (drawn fresh every frame)
var _hover: Array = []  # [[Rect2, lines, edge]] what the mouse on a rect explains
var _hold_hits: Array = []  # [[Rect2, row]] the hold's rows as drawn
var _clock := 0.0

# What the loadout drawing reads of its owner (board_loadout.gd): the same names as the boarding view.
var load_who: int:
	get:
		return kit.load_who
var load_slot: Dictionary:
	get:
		return kit.load_slot
var load_msg: String:
	get:
		return kit.load_msg
var session:
	get:
		return kit


func _init() -> void:
	visible = false


func _ready() -> void:
	if sim == null:
		sim = get_node_or_null("../../ShipSim")
	if build == null:
		build = get_node_or_null("../../BuildMode")
	if crew == null:
		crew = get_node_or_null("../../Crew")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func ship():
	return sim.player_ship() if sim != null else null


func _process(dt: float) -> void:
	if not visible:
		return
	_clock += dt
	if ship() != kit.ship:  # the ship was replaced under it
		close()
		return
	_set_ring()
	queue_redraw()


# --- opening ---------------------------------------------------------------------------------------------------------------

## May the screen open now? Not in a fight, while boarding, in build mode, over another screen, or with nobody to set.
func can_open() -> bool:
	if ship() == null:
		return false
	if build != null and (bool(build.get("combat")) or bool(build.get("build_on"))):
		return false
	var main: Node = get_node_or_null("../..")
	if main != null:
		var board := main.get_node_or_null("Board")
		if board != null and board.get("active"):
			return false
		var combat := main.get_node_or_null("Combat")
		if combat != null and combat.get("active"):
			return false
		for path in ["PickerLayer/ShipPicker", "CraftLayer/CraftingPanel"]:
			var other := main.get_node_or_null(path)
			if other != null and other.visible:
				return false
	if build != null:
		for name in ["drift", "shields"]:
			var screen = build.get(name)
			if screen != null and screen is CanvasItem and screen.visible:
				return false
		var help = build.front.get("help") if build.get("front") != null else null
		if help != null and help.visible:
			return false
	return not CrewKit.new(ship()).people().is_empty()


## Open the screen. False (and nothing happens) when it may not open.
func open() -> bool:
	if not can_open():
		return false
	kit = CrewKit.new(ship())
	for m in kit.people():
		Kit.materialize(ship(), m)  # (whoever has no kit yet is given the one they have: their sidearm)
	var first = crew.get("selected") if crew != null else null
	var people := kit.people()
	kit.load_who = maxi(people.find(first), 0)
	if not visible:
		Audio.fx(self, "open")
	visible = true
	queue_redraw()
	return true


func close() -> void:
	if visible:
		Audio.fx(self, "close")
	visible = false
	if crew != null:
		crew.set("kit_hover", null)


## The panel's rectangle (the right of the screen).
func panel_rect() -> Rect2:
	return Rect2(Vector2(size.x - PW - MARGIN, TOP), Vector2(PW, size.y - TOP - MARGIN))


func tab_rect(i: int) -> Rect2:
	var p := panel_rect()
	return Rect2(p.position + Vector2(MARGIN + float(i) * (TAB.x + 4.0), 68.0), TAB)


func person_area() -> Rect2:
	var p := panel_rect()
	return Rect2(p.position + Vector2(MARGIN, 116.0), Vector2(PW - MARGIN * 2.0, 400.0))


# --- the ring on the ship --------------------------------------------------------------------------------------------------

## The crew member to ring on the ship: the one under the cursor there, else the one whose tab the cursor is on.
func hovered_person():
	var mouse := get_local_mouse_position() if is_inside_tree() else Vector2(-1, -1)
	var people := kit.people()
	for i in people.size():
		if tab_rect(i).has_point(mouse):
			return people[i]
	if panel_rect().has_point(mouse) or crew == null or not crew.has_method("pick_at") or not crew.has_method("_world"):
		return null
	var build_node: Node = crew.get("build")
	if build_node == null:
		return null
	var cell: Vector2 = (crew.get_local_mouse_position() - crew._world(Vector2.ZERO)) / float(build_node.CELL)
	return crew.pick_at(cell)


func _set_ring() -> void:
	if crew != null:
		crew.set("kit_hover", hovered_person())


# --- input -----------------------------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if e is InputEventKey:
		var plain: bool = not (e.ctrl_pressed or e.alt_pressed or e.meta_pressed)
		if not visible:
			if e.pressed and not e.echo and e.keycode == KEY_I and plain and open():
				_handled()
			return
		if BreachPrompt.claims(e):
			return  # R and V answer the breach card, whatever window is open
		_handled()
		if not e.pressed or e.echo:
			return
		match e.keycode:
			KEY_I, KEY_ESCAPE:
				if e.keycode == KEY_ESCAPE and not kit.load_slot.is_empty():
					kit.load_slot = {}
				else:
					close()
			KEY_TAB:
				kit.focus((kit.load_who + 1) % maxi(kit.people().size(), 1))
			_:
				if e.keycode >= KEY_1 and e.keycode <= KEY_9 and not kit.load_slot.is_empty():
					choose(e.keycode - KEY_1)
	elif visible and e is InputEventMouseButton and e.pressed:
		var inside := panel_rect().has_point(e.position)
		if inside:
			_handled()
			if e.button_index == MOUSE_BUTTON_LEFT:
				click(e.position)
		elif e.button_index == MOUSE_BUTTON_LEFT and crew != null:  # a click on a person of the ship shows them here (the ship's own click selects them too)
			var who = hovered_person()
			if who != null:
				kit.focus(kit.people().find(who))


## A left click at screen point `p` on the panel: a tab, a slot, a choice or a row of the hold.
func click(p: Vector2) -> void:
	for i in range(_hold_hits.size() - 1, -1, -1):
		if _hold_hits[i][0].has_point(p):
			take_from_hold(_hold_hits[i][1])
			return
	for i in range(_hits.size() - 1, -1, -1):
		if not _hits[i][0].has_point(p):
			continue
		var hit: Dictionary = _hits[i][1]
		match str(hit.get("type", "")):
			"tab":
				kit.focus(int(hit["i"]))
			"slot":
				kit.open_slot(str(hit["slot"]), int(hit["idx"]))
			"option":
				choose(int(hit["i"]))
		return
	if not kit.load_slot.is_empty():
		kit.load_slot = {}


## Take choice `i` of the open slot (crew_kit.gd). Returns why not.
func choose(i: int) -> String:
	var why := kit.choose(i)
	Audio.fx(self, "error" if why != "" else "confirm")
	return why


## A row of the hold ({id, kind, name, count}): into the open slot when it is one of its kind, else the first free slot it fits on the person shown.
func take_from_hold(row: Dictionary) -> String:
	var m = kit.person()
	if m == null:
		return "Nobody."
	var why := ""
	if not kit.load_slot.is_empty() and str(kit.load_slot["slot"]) == str(row["kind"]):
		why = CrewKit.set_slot(ship(), m, str(kit.load_slot["slot"]), int(kit.load_slot["idx"]), str(row["id"]))
	else:
		why = CrewKit.equip_from_hold(ship(), m, str(row["id"]))
	kit.load_msg = why
	if why == "":
		kit.load_slot = {}
	Audio.fx(self, "error" if why != "" else "confirm")
	return why


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


# --- what the loadout drawing asks of its owner ------------------------------------------------------------------------------

func loadout_options() -> Array:
	return kit.loadout_options()


func weapons_note() -> String:
	return ""


func hit_add(r: Rect2, hit: Dictionary) -> void:
	_hits.append([r, hit])


func hover_add(r: Rect2, lines: Array, edge: Color) -> void:
	if not lines.is_empty():
		_hover.append([r, lines, edge])


func _font() -> Font:
	return ThemeDB.fallback_font


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


# --- drawing -----------------------------------------------------------------------------------------------------------------

func _draw() -> void:
	_hits.clear()
	_hover.clear()
	_hold_hits.clear()
	var s = ship()
	var m = kit.person()
	if s == null or m == null:
		return
	var p := panel_rect()
	draw_rect(p, Color(PANEL_BG, 0.96))
	draw_rect(p, EDGE, false, 2.0)
	_text("Crew kit", p.position + Vector2(MARGIN + 4.0, 38.0), 26, TEXT)
	_text("I or Esc closes. Click a slot to see what fits, then pick one; or click a slot, then an item of the hold. The ship keeps flying.", p.position + Vector2(MARGIN + 4.0, 58.0), 13, DIM_TEXT)
	var people := kit.people()
	for i in people.size():
		var r := tab_rect(i)
		var on: bool = i == kit.load_who
		draw_rect(r, Color(GOOD, 0.3) if on else ROW_BG)
		draw_rect(r, GOOD if on else EDGE_DIM, false, 1.5 if on else 1.0)
		_text(("%s" % people[i].name).left(11), r.position + Vector2(8, 21), 14, TEXT if on else DIM_TEXT)
		hit_add(r, {"type": "tab", "i": i})
	var area := person_area()
	Loadout._person(self, area, self, m)
	_draw_preview(m, Vector2(area.end.x - 80.0, area.position.y + 44.0))
	_text(kit.load_msg, Vector2(area.position.x, area.end.y + 4.0), 15, BAD)
	_draw_hold(s, Rect2(Vector2(area.position.x, area.end.y + 26.0), Vector2(area.size.x, p.end.y - area.end.y - 40.0)))
	_draw_hover()


## The person shown as they are drawn on the ship, so the body gear they wear can be seen.
func _draw_preview(m, at: Vector2) -> void:
	var look: Dictionary = m.look if not m.look.is_empty() else ShipView.LOOKS.get(m.name, ShipView.OTHER_LOOK)
	var pose := {"species": Art.crew_rig(m.rig()), "move": -PI / 2.0 + 0.3, "aim": -PI / 2.0 + 0.3, "phase": 0.0, "moving": false, "item": "", "down": m.is_down(),
		"t": _clock, "head": m.head, "body": PersonDrawer.gear_of(m)}
	draw_rect(Rect2(at - Vector2(50, 38), Vector2(100, 92)), Color(0.09, 0.12, 0.17))
	PersonDrawer.draw(self, at + Vector2(0, 8), pose, look, 40.0)


func _draw_hold(s, r: Rect2) -> void:
	_text("IN THE HOLD", r.position + Vector2(0, 12), 12, DIM_TEXT)
	var rounds: int = s.inventory.count(str(Arms.cfg()["ammo_item"]))
	_text("%d rounds" % rounds, r.position + Vector2(120, 12), 12, DIM_TEXT if rounds > 0 else BAD)
	var rows := CrewKit.hold_rows(s)
	if rows.is_empty():
		_text("No weapons, body gear or mods in the hold.", r.position + Vector2(0, 40), 14, DIM_TEXT)
		return
	var colw := (r.size.x - 12.0) / 2.0
	var per := maxi(int((r.size.y - 24.0) / HOLD_ROW), 1)
	for i in mini(rows.size(), per * 2):
		var row: Dictionary = rows[i]
		var rr := Rect2(r.position + Vector2(float(i / per) * (colw + 12.0), 22.0 + float(i % per) * HOLD_ROW), Vector2(colw, HOLD_ROW - 4.0))
		draw_rect(rr, ROW_BG)
		var kind := str(row["kind"])
		var ir := Rect2(rr.position + Vector2(4, 4), Vector2(34, 34))
		draw_rect(ir, Color(PANEL_BG, 0.9))
		match kind:
			"mod":
				Mods.draw_icon(self, str(row["id"]), ir)
			"body":
				Cards._body_icon(self, ir, str(row["id"]))
			_:
				Cards._art(self, str(Arms.weapon(str(row["id"])).get("art", "")), ir.grow(-2.0), 1.0)
		var col: Color = Mods.color(Mods.parse(str(row["id"]))["mod"]) if kind == "mod" else TEXT
		_text("%s   x%d" % [str(row["name"]), int(row["count"])], rr.position + Vector2(46, 17), 14, col)
		_text(Loadout.stats(kind, str(row["id"])), rr.position + Vector2(46, 34), 12, DIM_TEXT)
		_hold_hits.append([rr, row])
	if rows.size() > per * 2:
		_text("+%d more" % (rows.size() - per * 2), r.position + Vector2(r.size.x - 70, 12), 12, DIM_TEXT)


func _draw_hover() -> void:
	var mouse := get_local_mouse_position()
	for i in range(_hover.size() - 1, -1, -1):
		var h: Array = _hover[i]
		if not h[0].has_point(mouse):
			continue
		var lines := PackedStringArray()
		for t in h[1]:
			lines.append_array(UiKit.wrap(str(t), 300.0, 12))
		var w := 16.0
		for l in lines:
			w = maxf(w, UiKit.text_width(l, 12) + 16.0)
		var ht := float(lines.size()) * 16.0 + 12.0
		var at := Vector2(clampf(h[0].position.x, 4.0, size.x - w - 4.0), h[0].position.y - ht - 6.0)
		if at.y < 4.0:
			at.y = h[0].end.y + 6.0
		UiKit.note(self, lines, at, h[2])
		return
