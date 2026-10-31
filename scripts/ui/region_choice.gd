extends Control
## The region choice at a region's exit beacon (docs/CONTENT.md section 15). First a confirm: leave the region for good?
## (Enter or a click reads the beacon's charts, Esc stays.) Then a card for each region on offer (Campaign.region_offers,
## 2 or 3; the ending region alone at the last stage's exit): its name, the home race (drawn) or the faction's mark, the
## faction, the danger in skulls, the rarity once scanned or known, and the blurb. 1-3 or a click on a card jumps there
## (the map's cross_to), Esc goes back to the map. While open it takes every key and click, over the map. The rules live
## in campaign.gd and regions.gd; this node only reads input and draws, in the UI colours of docs/ART_STYLE.md.

const Content = preload("res://scripts/data/content.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Art = preload("res://scripts/view/art.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Skulls = preload("res://scripts/ui/skulls.gd")

const PAD := 26.0
const GAP := 20.0
const CARD_H := 430.0
const CONFIRM_W := 720.0
const CONFIRM_H := 250.0
const DIM := Color(0.0, 0.0, 0.0, 0.6)
const PANEL_BG := Color("#1f2630")
const CARD_BG := Color("#10151c")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.1)
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const GOOD := Color("#6bd34a")
const BAD := Color("#e0413b")
const RARITY_COLORS := {"common": Color("#cfd6df"), "uncommon": Color("#6bd34a"), "rare": Color("#4fa3ff"), "very_rare": Color("#c06bff"), "legendary": Color("#e1a136")}

var map: Control  ## the MapView: its campaign, its ship and cross_to()
var page := "confirm"  ## "confirm", then "choose"
var options: Array = []  ## the regions on offer: their data (Regions.get_region), in order
var known: Array = []  ## per option: is its rarity known (Campaign.rarity_known), worked out when the cards open
var hover := -1  ## the card (or, on the confirm page, the row) under the mouse
var message := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


# --- actions ---------------------------------------------------------------------------------------------------

## Open on the confirm page (the ship has reached the exit beacon).
func open() -> void:
	page = "confirm"
	options = []
	hover = -1
	message = ""
	visible = true


## Read the charts: the cards of the regions on offer.
func show_choices() -> void:
	var c = map.campaign
	options = c.region_offers().map(func(id): return Regions.get_region(str(id)))
	known = options.map(func(r): return c.rarity_known(str(r["id"]), map.ship()))
	page = "choose"
	hover = -1
	message = "" if not options.is_empty() else "The charts are blank: there is no way on from here."
	visible = true


func close() -> void:
	visible = false
	options = []


## Jump to option `i`. Returns "" or why not.
func choose(i: int) -> String:
	if page != "choose" or i < 0 or i >= options.size():
		return "no such region"
	var why: String = map.cross_to(str(options[i]["id"]))
	if why != "":
		message = why
		return why
	close()
	return ""


# --- input -----------------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey):
		return
	if get_viewport() != null:
		get_viewport().set_input_as_handled()
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_ESCAPE:
		close()
	elif page == "confirm" and e.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		show_choices()
	elif page == "choose" and e.keycode >= KEY_1 and e.keycode <= KEY_9:
		choose(e.keycode - KEY_1)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover = _row_at(e.position) if page == "confirm" else card_at(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if page == "confirm":
			match _row_at(e.position):
				0:
					show_choices()
				1:
					close()
		else:
			choose(card_at(e.position))
	accept_event()


# --- layout ----------------------------------------------------------------------------------------------------

func confirm_rect() -> Rect2:
	return Rect2((size - Vector2(CONFIRM_W, CONFIRM_H)) / 2.0, Vector2(CONFIRM_W, CONFIRM_H))


## The confirm page's two rows: read the charts, not yet.
func row_rect(i: int) -> Rect2:
	var r := confirm_rect()
	return Rect2(r.position + Vector2(PAD, 140.0 + 44.0 * i), Vector2(r.size.x - 2.0 * PAD, 36.0))


func _row_at(p: Vector2) -> int:
	for i in 2:
		if row_rect(i).has_point(p):
			return i
	return -1


## The panel of the choose page.
func panel_rect() -> Rect2:
	var w := minf(size.x - 80.0, 1180.0)
	var h := CARD_H + 150.0
	return Rect2(Vector2((size.x - w) / 2.0, maxf((size.y - h) / 2.0, 20.0)), Vector2(w, h))


## Card `i` of the `options` shown.
func card_rect(i: int) -> Rect2:
	var p := panel_rect()
	var n := maxi(options.size(), 1)
	var w := minf((p.size.x - 2.0 * PAD - GAP * (n - 1)) / n, 360.0)
	var left := p.position.x + (p.size.x - (w * n + GAP * (n - 1))) / 2.0
	return Rect2(Vector2(left + (w + GAP) * i, p.position.y + 92.0), Vector2(w, CARD_H))


## The card at `p`, or -1.
func card_at(p: Vector2) -> int:
	for i in options.size():
		if card_rect(i).has_point(p):
			return i
	return -1


# --- drawing ---------------------------------------------------------------------------------------------------

func _draw() -> void:
	if map == null or map.campaign == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	if page == "confirm":
		_draw_confirm()
	else:
		_draw_choose()


func _draw_confirm() -> void:
	var c = map.campaign
	var r := confirm_rect()
	_panel(r)
	_text("EXIT BEACON", r.position + Vector2(PAD, 42.0), 24, TEXT)
	var body := "The beacon's charts show the lanes out of %s. Jump through and there is no coming back." % c.region_name()
	if c.stage >= c.stages():
		body = "The beacon's charts show one lane only, out of %s: the last one. Jump through and there is no coming back." % c.region_name()
	draw_multiline_string(ThemeDB.fallback_font, r.position + Vector2(PAD, 78.0), body, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 2.0 * PAD, 17, -1, DIM_TEXT)
	var rows := ["Enter: read the charts", "Esc: not yet"]
	for i in 2:
		var rr := row_rect(i)
		draw_rect(rr, Color("#2a3340") if hover != i else Color("#36414f"))
		draw_rect(rr, EDGE_DIM, false, 1.0)
		_text(rows[i], rr.position + Vector2(12.0, 24.0), 17, GOOD if i == 0 else TEXT)


func _draw_choose() -> void:
	var c = map.campaign
	var p := panel_rect()
	_panel(p)
	var next: String = "Stage %d/%d" % [c.stage + 1, c.stages()] if c.stage < c.stages() else "The last jump"
	_text("CHOOSE THE NEXT REGION", p.position + Vector2(PAD, 42.0), 24, TEXT)
	_text("Leaving %s.  %s" % [c.region_name(), next], p.position + Vector2(PAD, 70.0), 16, DIM_TEXT)
	for i in options.size():
		_draw_card(i, options[i])
	var y := p.end.y - 22.0
	if message != "":
		_text(message, Vector2(p.position.x + PAD, y - 24.0), 16, BAD)
	var keys := "1-%d or click: jump there (no coming back)    Esc: back to the map" % options.size() if not options.is_empty() else "Esc: back to the map"
	_text(keys, Vector2(p.position.x + PAD, y), 14, DIM_TEXT)


func _draw_card(i: int, r: Dictionary) -> void:
	var box := card_rect(i)
	var tint := Color(str(r.get("palette", {}).get("tint", "#cfd6df")))
	draw_rect(box, CARD_BG)
	draw_rect(Rect2(box.position, Vector2(box.size.x, 6.0)), tint)
	draw_rect(box, TEXT if i == hover else EDGE_DIM, false, 2.0 if i == hover else 1.0)
	var x := box.position.x + 16.0
	var w := box.size.x - 32.0
	_text("%d" % (i + 1), box.position + Vector2(box.size.x - 28.0, 32.0), 18, DIM_TEXT)
	_text(str(r.get("name", r.get("id", "?"))), Vector2(x, box.position.y + 34.0), 20, TEXT)
	# the home race, drawn, or the faction's mark
	var icon := Vector2(box.position.x + box.size.x / 2.0, box.position.y + 100.0)
	var faction := str(r.get("faction", ""))
	var fcol: Color = Campaign.faction_color(faction) if faction != "" else DIM_TEXT
	draw_circle(icon, 40.0, Color(tint, 0.18))
	draw_arc(icon, 40.0, 0.0, TAU, 40, Color(tint, 0.6), 2.0, true)
	var home := str(r.get("home_species", ""))
	if home != "":
		var rig := str(Content.entry("species", home).get("rig", home))
		PersonDrawer.draw(self, icon, {"species": Art.crew_rig(rig), "aim": -PI / 2.0, "move": -PI / 2.0}, {"suit": tint}, 24.0)
	else:
		draw_circle(icon, 18.0, fcol)
		draw_circle(icon, 9.0, CARD_BG)
	var y := box.position.y + 170.0
	var who := "Home of the %s" % str(Content.entry("species", home).get("name", home.capitalize())) if home != "" else "No home race"
	_text(who, Vector2(x, y), 15, TEXT if home != "" else DIM_TEXT)
	y += 24.0
	_text(Campaign.faction_name(faction) if faction != "" else "No faction", Vector2(x, y), 15, fcol)
	y += 26.0
	_text("Danger", Vector2(x, y), 15, DIM_TEXT)
	Skulls.draw(self, Vector2(x + 72.0, y - 6.0), Regions.skulls(r))
	y += 26.0
	var seen: bool = known[i]
	var rarity := str(r.get("rarity", "common"))
	_text("Rarity", Vector2(x, y), 15, DIM_TEXT)
	_text(rarity.replace("_", " ").capitalize() if seen else "? (scan with a radar)", Vector2(x + 72.0, y), 15, RARITY_COLORS.get(rarity, TEXT) if seen else DIM_TEXT)
	y += 18.0
	draw_line(Vector2(x, y), Vector2(x + w, y), EDGE_DIM, 1.0)
	draw_multiline_string(ThemeDB.fallback_font, Vector2(x, y + 24.0), str(r.get("blurb", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 14, 9, DIM_TEXT)


## A chunky panel: a slate fill, a 2 px light border and a 1 px inner highlight.
func _panel(r: Rect2, fill := PANEL_BG) -> void:
	draw_rect(r, fill)
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-3.0), HIGHLIGHT, false, 1.0)


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
