extends Control
## The map of the Drift (M in play mode): the screen of the campaign. Click a node joined to yours by a
## lane to jump there (1 fuel, less with efficient engines: Campaign.jump_cost; Shift+click with an empty
## tank is a drift jump that costs 15 hull integrity; T waits for a passing trader). The event of the node
## opens in the event panel, a station opens its menu in the station panel (Enter or a click on your own
## node docks again). Esc or M closes the map. It owns the Campaign (campaign.gd, saved in
## user://campaign.json with the ship) and the two panels, and it carries the flow: jump, arrive, event,
## fight, loot, salvage, station.
## While open it takes every key and click; it stays shut during a fight and under the ship picker.
## All rules live in campaign.gd, events.gd and drift.gd; this node reads input and draws, in the UI
## colours of docs/ART_STYLE.md.

const Campaign = preload("res://scripts/space/campaign.gd")
const EventPanel = preload("res://scripts/ui/event_panel.gd")
const StationPanel = preload("res://scripts/ui/station_panel.gd")

const MARGIN := 40.0
const TITLE_H := 64.0
const FOOT_H := 96.0
const PAD := 18.0
const NODE_R := 13.0
const DIM := Color(0.0, 0.0, 0.0, 0.7)
const PANEL_BG := Color("#1f2630")
const SPACE_BG := Color("#0b0f16")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.1)
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const GOOD := Color("#6bd34a")
const BAD := Color("#e0413b")
const AMBER := Color("#e1a136")
const UNKNOWN := Color("#3a4350")

## Emitted when a lost fight ends the run, with the campaign as it stood (front_door.gd shows the game over screen).
signal run_over(campaign)

var sim: Node  ## the ShipSim whose player ship travels
var build: Node  ## the BuildMode (told about the new ship)
var combat: Node  ## the combat view: fights started from events run there
var campaign: Campaign
var event_panel: Control
var station_panel: Control
var hover := ""  ## the node id under the mouse
var message := ""
var message_bad := false
var new_seed := 0  ## the seed of the next new campaign; 0 picks one
var save_path := Campaign.SAVE_PATH  ## where the campaign is saved with the ship (tests point it elsewhere)
var hull := Vector2i.ZERO  ## (left, max) hull integrity, refreshed after every action
var _arrived := false  # the arrival at the start of this campaign has been played
var _fighting := false  # a fight of ours is on
var _after_win := {}  # the after_win of the event that started it
var _fight_node := ""  # the type of the node it was started at
var _queue: Array[Callable] = []  # what comes after the event panel is done


func _ready() -> void:
	sim = get_node_or_null("../../ShipSim")
	build = get_node_or_null("../../BuildMode")
	combat = get_node_or_null("../../Combat")
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_ensure_panels()
	if combat != null and combat.has_signal("finished"):
		combat.finished.connect(_on_fight_finished)


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## The player's ship (null before the scene is wired).
func ship():
	return sim.player_ship() if sim != null else null


func _ensure_panels() -> void:
	if event_panel != null:
		return
	event_panel = EventPanel.new()
	event_panel.map = self
	event_panel.finished.connect(_on_events_finished)
	event_panel.fight_requested.connect(_start_fight)
	add_child(event_panel)
	station_panel = StationPanel.new()
	station_panel.map = self
	add_child(station_panel)


# --- actions (the keys and clicks call these) -----------------------------------------------------------------

## Show the map; the first time, start a campaign and play the arrival at Rusthold.
func open() -> void:
	_ensure_panels()
	if campaign == null:
		new_game()
	visible = true
	message = ""
	refresh()
	if not _arrived:
		_arrived = true
		_arrive()


func close() -> void:
	if event_panel.visible or station_panel.visible:
		return
	visible = false


## Begin a campaign (a fresh map from `seed_value`, a random one for 0), at Rusthold.
func new_game(seed_value := 0) -> void:
	_ensure_panels()
	var s := seed_value if seed_value != 0 else (new_seed if new_seed != 0 else randi())
	campaign = Campaign.new(s)
	_arrived = false
	_queue.clear()
	event_panel.visible = false
	station_panel.visible = false
	_fighting = false
	message = ""
	refresh()


## Refresh what the screen derives from the ship (the hull integrity).
func refresh() -> void:
	var s = ship()
	if campaign != null and s != null:
		hull = Vector2i(campaign.hull_left(s), campaign.hull_max(s))


func _say(text: String, bad := false) -> void:
	message = text
	message_bad = bad


## Jump to node `id` (a click). `drift_jump`: the no-fuel jump that costs hull integrity. Clicking your
## own node docks if there is a station. Returns "" or the reason it was refused.
func click_node(id: String, drift_jump := false) -> String:
	if campaign == null or id == "":
		return ""
	if id == campaign.current:
		return dock()
	var s = ship()
	var r := campaign.jump(id, s, drift_jump)
	if not r["ok"]:
		var why: String = r["why"]
		if why == Campaign.NO_FUEL:
			why += ". Shift+click drifts there (hull -%d), T waits for a trader" % int(campaign.cfg["fuel"]["drift_hull"])
		_say(why, true)
		return r["why"]
	_say(" ".join(r["notes"]), false)
	refresh()
	_arrive()
	return ""


## What the next jump costs the ship as it is now: "1 fuel", "0.5 fuel" (Campaign.jump_cost).
func jump_cost_text() -> String:
	var s = ship()
	return Campaign.fuel_text(campaign.jump_cost(s) if s != null else Campaign.FUEL_PARTS)


## Dock at the station of the current node. Returns "" or why not.
func dock() -> String:
	var why := campaign.dock_block(campaign.current)
	if why != "":
		_say(why, true)
		return why
	station_panel.open(campaign.current)
	return ""


## Wait for a passing trader (only with an empty tank).
func wait() -> String:
	var r := campaign.wait(ship())
	if not r["ok"]:
		_say(r["why"], true)
		return r["why"]
	refresh()
	if r["event"].is_empty():
		_say("Nobody comes. Time passes. " + " ".join(r["notes"]), true)
	else:
		_say(" ".join(r["notes"]))
		event_panel.open_event(r["event"])
	return ""


## The current node has been reached: refused at the dock, an event, a station menu or nothing.
func _arrive() -> void:
	var a := campaign.arrive(ship())
	refresh()
	if a["refused"] != "":
		event_panel.open_notice(campaign.label(campaign.current), a["refused"], [])
	elif not a["event"].is_empty():
		event_panel.open_event(a["event"])
	elif campaign.dock_block(campaign.current) == "" and not campaign.station_cfg(campaign.current).is_empty():
		station_panel.open(campaign.current)


## The event panel has no more to show: whatever was queued (a fight's follow-up), else the station menu.
func _on_events_finished() -> void:
	refresh()
	if not _queue.is_empty():
		_queue.pop_front().call()
		return
	if campaign.dock_block(campaign.current) == "" and not campaign.station_cfg(campaign.current).is_empty():
		station_panel.open(campaign.current)


# --- fights -------------------------------------------------------------------------------------------------------------------

## An event outcome asked for a fight: `value` is "tier" or a design id; `after_win` runs if we win.
func _start_fight(value: String, after_win: Dictionary) -> void:
	var path := campaign.fight_path(value, str(campaign.node(campaign.current)["type"]))
	var why: String = combat.enter(path) if combat != null else "no combat view"
	if why != "":
		_say("Cannot fight: " + why, true)
		return
	var session = combat.get("session") if combat != null else null
	if session != null:  # the fight starts with the integrity the campaign says is left
		var mine = session.arena.ships[0]
		mine.hull = campaign.fight_hull(mine.hull_max)
	_fighting = true
	_after_win = after_win
	_fight_node = str(campaign.node(campaign.current)["type"])
	visible = false


## The combat view is done with a fight. If it was ours: loot, after_win, the next page; a loss ends the run.
func _on_fight_finished(result: Dictionary) -> void:
	if not _fighting:
		return
	_fighting = false
	var r := campaign.fight_done(result, ship(), _after_win)
	_after_win = {}
	if r["state"] == "lost":
		run_over.emit(campaign)
		new_game()
		_say("Wrecked. A new run begins.", true)
		return
	visible = true
	refresh()
	event_panel.open_notice("The fight is over" if r["state"] == "won" else "You get away", r["text"], r["lines"])
	if r["fight"] != "":
		var next: String = r["fight"]
		_queue.append(func(): _start_fight(next, {}))
	elif r["goto"] != "" and campaign.events.has(r["goto"]):
		var page: String = r["goto"]
		_queue.append(func(): event_panel.open_event(campaign.events.get_event(page)))
	elif r["state"] == "won":
		var salvage := campaign.salvage_event(ship())
		if not salvage.is_empty():
			_queue.append(func(): event_panel.open_event(salvage))


# --- saving ---------------------------------------------------------------------------------------------------------------------

## Write the campaign next to the ship save. Returns "" or why not.
func save_campaign() -> String:
	return campaign.save(save_path) if campaign != null else ""


## Load the campaign saved with the ship. An old ship save without one starts a new campaign.
## Returns "" when it loaded, else why a new one was started.
func load_campaign() -> String:
	_ensure_panels()
	var fresh := Campaign.new(new_seed if new_seed != 0 else randi())
	var why := fresh.load_file(save_path)
	if why == "":
		campaign = fresh
		_arrived = true
		_queue.clear()
		event_panel.visible = false
		station_panel.visible = false
		_fighting = false
		refresh()
		return ""
	new_game()
	return why


# --- input ------------------------------------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey):
		return
	if event_panel.visible or station_panel.visible:
		return  # they take the keys
	if get_viewport() != null:
		get_viewport().set_input_as_handled()
	if not e.pressed or e.echo:
		return
	match e.keycode:
		KEY_M, KEY_ESCAPE:
			close()
		KEY_ENTER, KEY_KP_ENTER:
			dock()
		KEY_T:
			wait()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover = node_at(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		click_node(node_at(e.position), e.shift_pressed)
	accept_event()


## May the map open now? Not in a fight, and not over the ship picker.
func can_open() -> bool:
	if combat != null and combat.get("active"):
		return false
	var picker := get_node_or_null("../../PickerLayer/ShipPicker")
	return picker == null or not picker.visible


# --- layout ------------------------------------------------------------------------------------------------------------------------

func panel_rect() -> Rect2:
	return Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN, MARGIN) * 2.0)


func map_rect() -> Rect2:
	var p := panel_rect()
	return Rect2(p.position + Vector2(PAD, TITLE_H), Vector2(p.size.x - 2.0 * PAD, p.size.y - TITLE_H - FOOT_H))


func _region() -> Vector2:
	var s: Array = Campaign.config()["map"]["size"]
	return Vector2(float(s[0]), float(s[1]))


## Screen position (this control's coordinates) of node `id`: the region fitted into the map area.
func node_pos(id: String) -> Vector2:
	var r := map_rect()
	var region := _region()
	var k := minf((r.size.x - 2.0 * NODE_R) / region.x, (r.size.y - 2.0 * NODE_R) / region.y)
	var origin := r.position + (r.size - region * k) / 2.0
	return origin + campaign.node(id)["pos"] * k


## The visible node at `p`, or "".
func node_at(p: Vector2) -> String:
	if campaign == null:
		return ""
	var best := ""
	var best_d := NODE_R * 1.6
	for id in campaign.drift.ids():
		if campaign.is_hidden(id):
			continue
		var d := node_pos(id).distance_to(p)
		if d < best_d:
			best_d = d
			best = id
	return best


# --- drawing --------------------------------------------------------------------------------------------------------------------------

func _draw() -> void:
	if campaign == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var p := panel_rect()
	_panel(p)
	_text("THE DRIFT", p.position + Vector2(PAD, 38.0), 26, TEXT)
	_draw_status(p)
	var m := map_rect()
	draw_rect(m, SPACE_BG)
	draw_rect(m, EDGE_DIM, false, 1.0)
	_draw_lanes()
	for id in campaign.drift.ids():
		if not campaign.is_hidden(id):
			_draw_node(id)
	if hover != "" and not campaign.is_hidden(hover):
		_draw_tip(hover)
	_draw_foot(p)


func _draw_status(p: Rect2) -> void:
	var s = ship()
	var fuel: int = s.inventory.count("fuel") if s != null else 0
	var credits: int = s.inventory.count("credits") if s != null else 0
	var x := p.position.x + 220.0
	var y := p.position.y + 36.0
	_text("Fuel %d" % fuel, Vector2(x, y), 18, GOOD if fuel > 0 else BAD)
	_text("Credits %d" % credits, Vector2(x + 100.0, y), 18, TEXT)
	_text("Jumps %d" % campaign.jumps, Vector2(x + 230.0, y), 18, TEXT)
	_text("Hull %d/%d" % [hull.x, hull.y], Vector2(x + 340.0, y), 18, TEXT if hull.x * 2 > hull.y else AMBER)
	var owed := "Debt %d" % campaign.debt
	var due := ""
	if campaign.debt > 0:
		due = "  (%d behind!)" % campaign.behind() if campaign.behind() > 0 else "  (%d due in %d)" % [int(campaign.cfg["debt"]["payment"]), campaign.next_due_in()]
	_text(owed + due, Vector2(x + 470.0, y), 18, BAD if campaign.behind() > 0 else (GOOD if campaign.debt == 0 else AMBER))
	var rx := p.end.x - PAD - 380.0
	for f in Campaign.rep_factions():
		var seg := "%s %+d" % [Campaign.faction_name(f), campaign.rep[f]]
		_text(seg, Vector2(rx, p.position.y + 38.0), 16, Campaign.faction_color(f))
		rx += 130.0


func _draw_lanes() -> void:
	var here := campaign.current
	for l in campaign.drift.lanes:
		if campaign.is_hidden(l[0]) or campaign.is_hidden(l[1]):
			continue
		var near: bool = l[0] == here or l[1] == here
		var seen: bool = campaign.is_known(l[0]) or campaign.is_known(l[1])
		var col := EDGE if near else (EDGE_DIM if seen else Color(EDGE_DIM, 0.45))
		draw_line(node_pos(l[0]), node_pos(l[1]), col, 3.0 if near else 1.5, true)


func _node_color(id: String) -> Color:
	if not campaign.is_known(id):
		return UNKNOWN
	var n := campaign.node(id)
	if n["faction"] != "":
		return Campaign.faction_color(str(n["faction"]))
	return Color(str(Campaign.type_info(str(n["type"]))["color"]))


func _draw_node(id: String) -> void:
	var at := node_pos(id)
	var n := campaign.node(id)
	var known := campaign.is_known(id)
	var here := id == campaign.current
	var reach: bool = campaign.drift.linked(campaign.current, id) and n["type"] != "gate"
	var col := _node_color(id)
	if n["type"] == "gate" and known:
		col = Color("#2b3340")
	draw_circle(at, NODE_R, col.darkened(0.45))
	draw_circle(at, NODE_R - 3.0, col)
	var glyph := str(Campaign.type_info(str(n["type"]))["glyph"]) if known else "?"
	_text(glyph, at + Vector2(-5.0, 6.0), 16, Color("#10151c") if known and n["type"] != "gate" else TEXT)
	if campaign.visited.has(id):
		draw_arc(at, NODE_R + 3.0, 0.0, TAU, 28, EDGE_DIM, 1.5, true)
	if reach:
		draw_arc(at, NODE_R + 5.0, 0.0, TAU, 28, GOOD if id != hover else TEXT, 2.5, true)
	if here:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0)
		draw_arc(at, NODE_R + 6.0 + 2.0 * pulse, 0.0, TAU, 32, AMBER, 3.0, true)
	if known and (n["place"] != "" or n.get("clan", false)):
		var name_text: String = str(n["name"]) if n["place"] != "" else "Scrapper trader"
		_text(name_text, at + Vector2(-ThemeDB.fallback_font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x / 2.0, NODE_R + 20.0), 13, TEXT if n["place"] != "" else AMBER)


func _draw_tip(id: String) -> void:
	var n := campaign.node(id)
	var lines: Array[String] = []
	if id == campaign.current:
		lines.append("You are here")
		if campaign.dock_block(id) == "" and not campaign.station_cfg(id).is_empty():
			lines.append("Enter or click: dock")
	elif not campaign.is_known(id):
		lines.append("Unknown")
		lines.append("Jump to find out" if campaign.drift.linked(campaign.current, id) else "Out of reach")
	else:
		var type_label := str(Campaign.type_info(str(n["type"]))["label"])
		lines.append(campaign.label(id) + (" (Scrapper trader)" if n.get("clan", false) else ""))
		if n["place"] != "" or n.get("clan", false):
			lines.append(type_label)
		if n["type"] == "gate":
			lines.append(Campaign.DARK_TEXT)
		elif campaign.drift.linked(campaign.current, id):
			lines.append(jump_cost_text())
	var w := 0.0
	for l in lines:
		w = maxf(w, ThemeDB.fallback_font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	var box := Rect2(node_pos(id) + Vector2(18.0, -18.0), Vector2(w + 20.0, 12.0 + 20.0 * lines.size()))
	if box.end.x > size.x - 10.0:
		box.position.x -= box.size.x + 36.0
	_panel(box, Color("#10151c"))
	for i in lines.size():
		_text(lines[i], box.position + Vector2(10.0, 22.0 + 20.0 * i), 14, TEXT if i == 0 else DIM_TEXT)


func _draw_foot(p: Rect2) -> void:
	var y := p.end.y - FOOT_H + 28.0  # the message, then the fuel warning, then the hint line, each on its own row
	if message != "":
		_text(message, Vector2(p.position.x + PAD, y), 16, BAD if message_bad else GOOD)
	_text("Click a lane-linked node to jump (%s)    Enter: dock    T: wait for a trader (no fuel)    Shift+click: drift jump (no fuel, hull -%d)    M / Esc: close" % [jump_cost_text(), int(campaign.cfg["fuel"]["drift_hull"])],
		Vector2(p.position.x + PAD, p.end.y - 22.0), 13, DIM_TEXT)
	var s = ship()
	if s != null and campaign.fuel_short(s):
		_text("Out of fuel!", Vector2(p.position.x + PAD, y + 20.0), 16, BAD)


## A chunky panel: a slate fill, a 2 px light border and a 1 px inner highlight.
func _panel(r: Rect2, fill := PANEL_BG) -> void:
	draw_rect(r, fill)
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-3.0), HIGHLIGHT, false, 1.0)


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
