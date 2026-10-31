extends Control
## The map of the Drift (M in play mode): the screen of the campaign. Click a node joined to yours by a
## lane to jump there (1 fuel, less with efficient engines: Campaign.jump_cost; Shift+click with an empty
## tank is a drift jump that costs 15 hull integrity; T waits for a passing trader). The event of the node
## opens in the event panel, a station opens its menu in the station panel (Enter or a click on your own
## node docks again). Esc or M closes the map. It owns the Campaign (campaign.gd, saved in
## user://campaign.json with the ship) and the three panels, and it carries the flow: jump, arrive, event,
## fight, loot, salvage, station, and at the region's exit beacon the region choice (region_choice.gd; Enter or a
## click on the beacon opens it again). The footer names the stage and the region ("Stage 3/8: The Kett Hives").
## While open it takes every key and click; it stays shut during a fight and under the ship picker.
## All rules live in campaign.gd, events.gd and drift.gd; this node reads input and draws, in the UI
## colours of docs/ART_STYLE.md.
## With the light-speed flow (data/drift.json instant_jump false, docs/CONTENT.md section 11) a click on a linked node
## spools the jump drive there (Campaign.start_jump; the same click again cancels it) and closes the map: the sector
## view runs the spool and the arrival. Events happen at a sector's POIs instead: open_poi() shows a POI's trigger in
## the panels with no map behind them (`panel_only`) and resolves the POI when they are done; fights from them spawn
## at the POI (Sector.fight_spawn), and a won fight leaves its wreck as a POI to salvage instead of the salvage page.

const Campaign = preload("res://scripts/space/campaign.gd")
const EventPanel = preload("res://scripts/ui/event_panel.gd")
const StationPanel = preload("res://scripts/ui/station_panel.gd")
const TideHud = preload("res://scripts/ui/tide_hud.gd")
const Tide = preload("res://scripts/space/tide.gd")
const Salvage = preload("res://scripts/space/salvage.gd")
const RegionChoice = preload("res://scripts/ui/region_choice.gd")
const HazardBar = preload("res://scripts/ui/hazard_bar.gd")
const Hazards = preload("res://scripts/combat/hazards.gd")

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
const HOLLOW := Color("#6d6679")  ## a place the Hollow tide has taken: dead violet-grey
const HOLLOW_BAND := Color(0.42, 0.34, 0.58, 0.2)  ## the faint band over the consumed part of the map
const HOLLOW_EDGE := Color(0.62, 0.52, 0.82, 0.55)

## Emitted when a lost fight ends the run, with the campaign as it stood (front_door.gd shows the game over screen).
signal run_over(campaign)
## Emitted when an ending ends the run as a win (an event's `ending` effect), with the campaign as it stood and the ending's id
## (front_door.gd shows the ending screen).
signal run_won(campaign, ending_id)

var sim: Node  ## the ShipSim whose player ship travels
var build: Node  ## the BuildMode (told about the new ship)
var combat: Node  ## the combat view: fights started from events run there
var campaign: Campaign
var profile = null  ## the player's Profile (front_door.gd sets it): the campaigns write their unlocks and landmarks to it
var event_panel: Control
var station_panel: Control
var tide_hud: Control  ## the play-mode line of the Hollow tide (tide_hud.gd), a sibling in this canvas layer
var region_choice: Control
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
var panel_only := false  ## shown only to hold the event or station panel of a sector POI: no map is drawn
var _poi := ""  # the id of the POI whose event is up (open_poi), "" when none
var _poi_sector = null  # its sector
var _dock := false  # its station menu opens when the event is done
var _exit_due := false  # the ship came to the exit beacon: the region choice opens once its events are done


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
	_make_tide_hud.call_deferred()


func _process(dt: float) -> void:
	if visible and panel_only and not event_panel.visible and not station_panel.visible and not region_choice.visible and not _fighting:
		_hide_panels()  # nothing left to show over the sector
	if visible:
		queue_redraw()
	else:
		tick_linger(minf(dt, 0.25))


## The light-speed flow is on (the campaign's instant jump is off).
func sector_flow() -> bool:
	return campaign != null and not campaign.instant_jump()


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
	event_panel.ending_reached.connect(_on_ending)
	add_child(event_panel)
	station_panel = StationPanel.new()
	station_panel.map = self
	station_panel.closed.connect(_on_station_closed)
	add_child(station_panel)
	region_choice = RegionChoice.new()
	region_choice.map = self
	add_child(region_choice)


## The Hollow tide's clock line, in the canvas layer this map lives in (no scene edit).
func _make_tide_hud() -> void:
	if tide_hud == null and get_parent() != null:
		tide_hud = TideHud.new()
		tide_hud.map = self
		get_parent().add_child(tide_hud)


## Is the game in play mode with the map shut and no fight on (the time the tide clock counts)?
func playing() -> bool:
	return campaign != null and not visible and can_open() and build != null and not build.build_on


## The one place linger time is counted: `dt` seconds of play pass and the tide creeps on (campaign.linger) while
## playing() and the tree is not paused. The lines it says go to the chronicle and the toast; they are returned too.
## Whatever surface the game is played on (the map's play mode, the sector view) calls this each frame.
func tick_linger(dt: float) -> Array:
	if not playing() or (is_inside_tree() and get_tree().paused):
		return []
	var lines := campaign.linger(dt)
	_tide_say(lines)
	return lines


## Tell the player what the tide did: the ship's chronicle, and a toast when the front door has one.
func _tide_say(lines: Array) -> void:
	var s = ship()
	var door = get_node_or_null("../../FrontDoor")
	var toast = door.get("toast") if door != null else null
	for l in lines:
		if s != null:
			s.log_event(str(l))
		if toast != null:
			toast.push(str(l))


# --- actions (the keys and clicks call these) -----------------------------------------------------------------

## Show the map; the first time, start a campaign and play the arrival at Rusthold.
func open() -> void:
	_ensure_panels()
	if campaign == null:
		new_game()
	visible = true
	panel_only = false
	message = ""
	refresh()
	if not _arrived:
		_arrived = true
		if not sector_flow():  # in sector space the arrival happens at the node's own POI
			_arrive()


func close() -> void:
	if event_panel.visible or station_panel.visible or region_choice.visible:
		return
	visible = false


## Begin a campaign (a fresh map from `seed_value`, a random one for 0), at Rusthold.
func new_game(seed_value := 0) -> void:
	_ensure_panels()
	var s := seed_value if seed_value != 0 else (new_seed if new_seed != 0 else randi())
	campaign = Campaign.new(s)
	campaign.profile = profile
	_arrived = false
	_queue.clear()
	_forget_poi()
	panel_only = false
	_exit_due = false
	event_panel.visible = false
	station_panel.visible = false
	region_choice.visible = false
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
	if sector_flow():
		return _spool(id, drift_jump)
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


## Light speed: spool the jump drive for node `id` (a click on the map). A click on the node it already spools for
## cancels it, one on another node changes the target. The map closes when it starts. "" or why not.
func _spool(id: String, drift_jump: bool) -> String:
	var st := campaign.jump_status()
	if st["active"]:
		campaign.cancel_jump()
		if st["to"] == id:
			_say("Jump cancelled.")
			return ""
	var sec = campaign.current_sector()
	var r := campaign.start_jump(id, ship(), sec != null and sec.hostile_near(campaign.hostile_range()), drift_jump)
	if not r["ok"]:
		var why: String = r["why"]
		if why == Campaign.NO_FUEL:
			why += ". Shift+click drifts there (hull -%d), T waits for a trader" % int(campaign.cfg["fuel"]["drift_hull"])
		_say(why, true)
		return r["why"]
	_say("Jump drive spooling for %s." % campaign.label(id))
	visible = false
	return ""


## What the next jump costs the ship as it is now: "1 fuel", "0.5 fuel" (Campaign.jump_cost).
func jump_cost_text() -> String:
	var s = ship()
	return Campaign.fuel_text(campaign.jump_cost(s) if s != null else Campaign.FUEL_PARTS)


## Dock at the station of the current node (at the exit beacon: open the region choice). Returns "" or why not. In
## sector space a station's menu opens by flying to its beacon.
func dock() -> String:
	if campaign.at_exit():
		region_choice.open()
		return ""
	if sector_flow():
		_say("Fly to the station's beacon to dock.", true)
		return "fly to the station"
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


## Y with no fuel: Ma tows you to the region's start (Gantry Rusthold in Clan space; debt +150, 2 fuel), then you arrive there.
func tow() -> String:
	var r := campaign.tow(ship())
	if not r["ok"]:
		_say(r["why"], true)
		return r["why"]
	refresh()
	_say(" ".join(r["notes"]))
	if sector_flow():
		visible = false  # the sector view takes the ship in at Rusthold's arrival point
	else:
		_arrive()
	return ""


## Leave the region from its exit beacon for region `id` (the region choice's pick): the next stage, then the arrival
## there. Returns "" or why not.
func cross_to(id: String) -> String:
	var r := campaign.cross(id, ship())
	if not r["ok"]:
		return r["why"]
	_say(" ".join(r["notes"]))
	refresh()
	if sector_flow():
		_hide_panels()  # the sector view takes the ship in at the new region's arrival point
	else:
		_arrive()
	return ""


## The current node has been reached: refused at the dock, an event, a station menu, the region choice (at the exit
## beacon, after any event) or nothing.
func _arrive() -> void:
	var a := campaign.arrive(ship())
	refresh()
	_exit_due = a["exit"]
	if a["refused"] != "":
		event_panel.open_notice(campaign.label(campaign.current), a["refused"], [])
	elif not a["event"].is_empty():
		event_panel.open_event(a["event"])
	elif _exit_due:
		_open_exit()
	elif campaign.dock_block(campaign.current) == "" and not campaign.station_cfg(campaign.current).is_empty():
		station_panel.open(campaign.current)


func _open_exit() -> void:
	_exit_due = false
	region_choice.open()


## The event panel has no more to show: whatever was queued (a fight's follow-up), else the region choice at the exit
## beacon, else the station menu.
func _on_events_finished() -> void:
	refresh()
	if not _queue.is_empty():
		_queue.pop_front().call()
		return
	if sector_flow():
		if _exit_due and campaign.at_exit():
			_poi_resolve()
			_open_exit()
		elif _dock and campaign.dock_block(campaign.current) == "":
			station_panel.open(campaign.current)
		else:
			_poi_done()
		_dock = false
		return
	if _exit_due and campaign.at_exit():
		_open_exit()
		return
	if campaign.dock_block(campaign.current) == "" and not campaign.station_cfg(campaign.current).is_empty():
		station_panel.open(campaign.current)


func _on_station_closed() -> void:
	if sector_flow() and panel_only:
		_poi_done()


# --- sector POIs ------------------------------------------------------------------------------------------------------------

## A POI of the sector the ship is in has triggered (`res`: Sector.trigger() of `sector`): the dock master's refusal, its
## event (then the station menu if it docks, or the region choice at the exit beacon) or the station menu, over the
## sector. When that is all done the POI is resolved (Sector.resolve).
func open_poi(res: Dictionary, sector) -> void:
	_ensure_panels()
	_poi = str(res["poi"]["id"])
	_poi_sector = sector
	_dock = bool(res.get("dock", false))
	_exit_due = bool(res.get("exit", false))
	panel_only = true
	visible = true
	refresh()
	if str(res.get("refused", "")) != "":
		_dock = false
		event_panel.open_notice(str(res["poi"]["name"]), str(res["refused"]), [])
	elif not res.get("event", {}).is_empty():
		event_panel.open_event(res["event"])
	elif _exit_due:
		_poi_resolve()
		_open_exit()
	elif _dock:
		_dock = false
		station_panel.open(campaign.current)
	else:
		_poi_done()


## The POI's chain is over: it is resolved, and the panels make way for the sector.
func _poi_done() -> void:
	_poi_resolve()
	if panel_only and not event_panel.visible and not station_panel.visible and not region_choice.visible:
		_hide_panels()


func _poi_resolve() -> void:
	if _poi_sector != null and _poi != "":
		_poi_sector.resolve(_poi)
	_forget_poi()


func _forget_poi() -> void:
	_poi = ""
	_poi_sector = null
	_dock = false


func _hide_panels() -> void:
	panel_only = false
	visible = false


# --- fights -------------------------------------------------------------------------------------------------------------------

## The design a fight of `value` ("tier" or a design id) would start now, as _start_fight picks it: the POI's in sector
## space, else the node's. The event panel rates it for its threat tags.
func fight_design(value: String) -> String:
	var design: String = _poi_sector.fight_design(campaign, _poi, value) if sector_flow() and _poi_sector != null and _poi != "" else ""
	return design if design != "" else campaign.fight_path(value, str(campaign.node(campaign.current)["type"]))


## An event outcome asked for a fight: `value` is "tier" or a design id; `after_win` runs if we win.
func _start_fight(value: String, after_win: Dictionary) -> void:
	var spot: Dictionary = _poi_sector.fight_spawn(campaign, _poi, value) if sector_flow() and _poi_sector != null and _poi != "" else {}
	var path: String = spot["design"] if not spot.is_empty() else campaign.fight_path(value, str(campaign.node(campaign.current)["type"]))
	var why := "no combat view"
	if combat != null:
		why = combat.enter(path, {"enemy_pos": spot["pos"]}) if not spot.is_empty() else combat.enter(path)
	if why != "":
		_say("Cannot fight: " + why, true)
		if sector_flow():
			_poi_done()
		return
	var session = combat.get("session") if combat != null else null
	if session != null:  # the fight starts with the integrity the campaign says is left
		var mine = session.arena.ships[0]
		mine.hull = campaign.fight_hull(mine.hull_max)
		session.arena.hazard = campaign.hazard_at(campaign.current)  # the node's sector hazard, if any (hazards.gd)
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
	panel_only = sector_flow()
	refresh()
	var title := "Salvage" if r["state"] in ["won", "captured", "spared"] else ("The fight is over" if r["state"] == "escaped" else "You get away")
	event_panel.open_notice(title, r["text"], r["lines"])
	if r["ending"] != "":
		var done: String = r["ending"]
		_queue.append(func(): _on_ending(done))
	elif r["fight"] != "":
		var next: String = r["fight"]
		_queue.append(func(): _start_fight(next, {}))
	elif r["goto"] != "" and campaign.events.has(r["goto"]):
		var page: String = r["goto"]
		_queue.append(func(): event_panel.open_event(campaign.events.get_event(page)))
	elif r["state"] in ["won", "captured"]:
		var salvage := Salvage.event_for(result.get("enemy"), r["state"], campaign, ship(), null, int(r["threat"]))
		if not salvage.is_empty():
			_queue.append(func(): event_panel.open_event(salvage))


## An outcome ended the run with ending `id`: it is won. The front door shows the ending screen and a new campaign waits behind it.
func _on_ending(id: String) -> void:
	visible = false
	run_won.emit(campaign, id)
	new_game()


# --- saving ---------------------------------------------------------------------------------------------------------------------

## Write the campaign next to the ship save. Returns "" or why not.
func save_campaign() -> String:
	return campaign.save(save_path) if campaign != null else ""


## Load the campaign saved with the ship. An old ship save without one starts a new campaign.
## Returns "" when it loaded, else why a new one was started.
func load_campaign() -> String:
	_ensure_panels()
	var fresh := Campaign.new(new_seed if new_seed != 0 else randi())
	fresh.profile = profile
	var why := fresh.load_file(save_path)
	if why == "":
		campaign = fresh
		_arrived = true
		_queue.clear()
		_forget_poi()
		panel_only = false
		_exit_due = false
		event_panel.visible = false
		station_panel.visible = false
		region_choice.visible = false
		_fighting = false
		refresh()
		return ""
	new_game()
	return why


# --- input ------------------------------------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not visible or panel_only or not (e is InputEventKey):
		return
	if event_panel.visible or station_panel.visible or region_choice.visible:
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
		KEY_Y:
			tow()


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
	var s: Array = campaign.cfg["map"]["size"]
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
	if campaign == null or panel_only:
		return
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var p := panel_rect()
	_panel(p)
	_text("THE DRIFT", p.position + Vector2(PAD, 38.0), 26, TEXT)
	_draw_status(p)
	var m := map_rect()
	draw_rect(m, SPACE_BG.lerp(_tint(), 0.07))
	draw_rect(m, EDGE_DIM, false, 1.0)
	_draw_tide(m)
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
	if campaign.debt > 0 and not campaign.debt_running():
		due = "  (clock stopped)"
	elif campaign.debt > 0:
		due = "  (%d behind!)" % campaign.behind() if campaign.behind() > 0 else "  (%d due in %d)" % [int(campaign.cfg["debt"]["payment"]), campaign.next_due_in()]
	_text(owed + due, Vector2(x + 470.0, y), 18, BAD if campaign.behind() > 0 else (GOOD if campaign.debt == 0 else AMBER))
	var rx := p.end.x - PAD - 380.0
	_text(tide_status(), Vector2(x + 705.0, y), 16, HOLLOW if campaign.is_hollow(campaign.current) else DIM_TEXT)
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
	var hollow := campaign.is_hollow(id)
	if hollow:
		col = HOLLOW
	draw_circle(at, NODE_R, col.darkened(0.45))
	draw_circle(at, NODE_R - 3.0, col)
	var glyph := str(Campaign.type_info(str(n["type"]))["glyph"]) if known else "?"
	_text(glyph, at + Vector2(-5.0, 6.0), 16, Color("#10151c") if known and n["type"] != "gate" else TEXT)
	if known:  # a place with a sector hazard wears its badge (hazards.gd)
		HazardBar.badge(self, at + Vector2(-NODE_R * 0.8, -NODE_R * 0.8), campaign.hazard_at(id))
	if hollow:  # a broken ring: three arcs with gaps
		for i in 3:
			draw_arc(at, NODE_R + 4.0, TAU * i / 3.0 + 0.3, TAU * (i + 1) / 3.0 - 0.3, 10, HOLLOW.lightened(0.25), 2.0, true)
	elif campaign.visited.has(id):
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
		if campaign.at_exit():
			lines.append("Enter or click: choose the next region")
		elif campaign.dock_block(id) == "" and not campaign.station_cfg(id).is_empty():
			lines.append("Enter or click: dock")
	elif not campaign.is_known(id):
		lines.append("Unknown")
		lines.append("Jump to find out" if campaign.drift.linked(campaign.current, id) else "Out of reach")
	else:
		var type_label := str(Campaign.type_info(str(n["type"]))["label"])
		lines.append(campaign.label(id) + (" (Scrapper trader)" if n.get("clan", false) else ""))
		if (n["place"] != "" or n.get("clan", false)) and type_label != campaign.label(id):
			lines.append(type_label)
		if n["type"] == "gate":
			lines.append(Campaign.DARK_TEXT)
		elif n["type"] == "exit":
			lines.append("The way to the next region")
		if n["type"] != "gate" and campaign.drift.linked(campaign.current, id):
			lines.append(jump_cost_text())
	if campaign.is_known(id):
		lines.append_array(Hazards.map_lines(campaign.hazard_at(id)))
	if n["type"] != "gate":
		lines.append_array(tide_tip(id))
	var w := 0.0
	for l in lines:
		w = maxf(w, ThemeDB.fallback_font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	var box := Rect2(node_pos(id) + Vector2(18.0, -18.0), Vector2(w + 20.0, 12.0 + 20.0 * lines.size()))
	if box.end.x > size.x - 10.0:
		box.position.x -= box.size.x + 36.0
	_panel(box, Color("#10151c"))
	for i in lines.size():
		_text(lines[i], box.position + Vector2(10.0, 22.0 + 20.0 * i), 14, TEXT if i == 0 else (AMBER if lines[i].begins_with("Hazard:") else DIM_TEXT))


## The tooltip lines about the tide for node `id`: Hollow, or when it will be, or that it holds.
func tide_tip(id: String) -> Array[String]:
	var t = campaign.tide
	if t.is_hollow(id):
		return ["Hollow: ghost ships, no trade"]
	var n: int = t.jumps_until(id)
	if n < 0:
		return ["Holds against the tide"]
	return ["The tide reaches here in %d jump%s" % [n, "" if n == 1 else "s"]]


## The status bar's tide: "Tide: 5 jumps / 2:41" (jumps until it reaches the ship's place, time until it rises by itself).
func tide_status() -> String:
	var t = campaign.tide
	var n: int = t.jumps_until(campaign.current)
	var where := "Hollow" if t.is_hollow(campaign.current) else ("holds" if n < 0 else "%d jump%s" % [n, "" if n == 1 else "s"])
	return "Tide: %s / %s" % [where, "--" if t.spent() else Tide.clock(t.linger_left())]


## The faint band over the part of the map the tide has taken, edged at the front. The front sits between the entry
## node and the farthest one on the screen, as it does on the map.
func _draw_tide(m: Rect2) -> void:
	var t = campaign.tide
	if t.front() <= 0.0 or t.axis_len <= 0.0:
		return
	var x0 := node_pos(t.entry_id).x
	var fx := clampf(x0 + (node_pos(t.far_id).x - x0) * t.front() / t.axis_len, m.position.x, m.end.x)
	draw_rect(Rect2(m.position, Vector2(fx - m.position.x, m.size.y)), HOLLOW_BAND)
	var y := m.position.y
	while y < m.end.y:  # a ragged, dashed edge
		var a := Vector2(fx + 3.0 * sin(y * 0.09 + Time.get_ticks_msec() / 700.0), y)
		draw_line(a, a + Vector2(0.0, 9.0), HOLLOW_EDGE, 2.0)
		y += 14.0


func _draw_foot(p: Rect2) -> void:
	var y := p.end.y - FOOT_H + 28.0  # the message, then the fuel warning, then the hint line, each on its own row
	var where := campaign.stage_text()
	var where_w := ThemeDB.fallback_font.get_string_size(where, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_text(where, Vector2(p.end.x - PAD - where_w, y), 18, _tint().lightened(0.25))
	if message != "":
		_text(message, Vector2(p.position.x + PAD, y), 16, BAD if message_bad else GOOD)
	var how := "spool the jump drive there, 8 s" if sector_flow() else "jump"
	_text("Click a lane-linked node to %s (%s)    Enter: dock    T: wait for a trader (no fuel)    Y: Ma tows you home (no fuel, debt +150)    Shift+click: drift jump (no fuel, hull -%d)    M / Esc: close" % [how, jump_cost_text(), int(campaign.cfg["fuel"]["drift_hull"])],
		Vector2(p.position.x + PAD, p.end.y - 22.0), 13, DIM_TEXT)
	var s = ship()
	if s != null and campaign.fuel_short(s):
		_text("Out of fuel!", Vector2(p.position.x + PAD, y + 20.0), 16, BAD)


## The region's tint (its palette), for the map's background and the stage line.
func _tint() -> Color:
	return Color(str(campaign.region_data.get("palette", {}).get("tint", "#cfd6df")))


## A chunky panel: a slate fill, a 2 px light border and a 1 px inner highlight.
func _panel(r: Rect2, fill := PANEL_BG) -> void:
	draw_rect(r, fill)
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-3.0), HIGHLIGHT, false, 1.0)


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
