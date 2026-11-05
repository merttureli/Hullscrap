extends Control
## The Ledger's card (the guidance program of scripts/sim/advisor.gd; Ma Gantry Loans installs it on every ship it finances): a small card under
## the top bar in play mode, build mode and on the map, showing the next goal of the stage (title, one line why, progress "Guns 2/3"); one amber line
## when a warning is up; a click or L unfolds the whole checklist (ticks for the done ones). A goal met ticks with a soft sound and a green line.
## Where it sits: top left in play mode (nothing is there), the right column under the part card in build mode (the middle is the ship's), the bottom
## right of the map (a compact two-line card in the footer, which has room; the nodes are everywhere else). Tips ("the first time ...") are a small note with a "Got it" button under
## the card: never modal, and they never pause a fight. In a fight and aboard another vessel there is no card, only the note, under the combat
## schematic (a warning there too, in amber, above it); over a screen (the station, the fabricator) and on the map it is a strip along the bottom edge. Mechanic keywords are coloured, with their hover line (data/advisor.json `keywords`). The setting
## (profile.ledger: Full, Warnings only, Off) decides what shows. front_door.gd makes it in a canvas layer of its own and sets `door`.
## One Control: its rect is the card with the note under it, so the mouse over it is its own and the wheel never zooms the world behind.

const Advisor = preload("res://scripts/sim/advisor.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Audio = preload("res://scripts/audio/audio.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const Threat = preload("res://scripts/space/threat.gd")

const CARD_W := 440.0
const MAP_W := 420.0  ## the compact card on the map: two lines, in the footer of the map's panel
const OPEN_W := 540.0  ## the card wider, with the checklist unfolded (not in build mode: the column is Hud.SIDE_W)
const PAD := 12.0
const HEAD_H := 24.0
const TITLE := 15
const BODY := 13
const SMALL := 11
const LINE := 17.0
const ROW_H := 24.0
const GAP := 6.0
const NOTE_W := 290.0  ## the note under the schematic in a fight
const NOTE_AT := Vector2(10.0, 222.0)
const TIP_S := 45.0  ## seconds a tip waits for "Got it" before it goes (it is in the journal either way)
const DONE_S := 3.0  ## seconds the "done" line shows
const BUTTON := Vector2(66.0, 22.0)
const GREEN := Color("#6bd34a")
const WARN_BG := Color("#3a2a10")

var door: Node  ## the front door: the screens, the profile, the map (and through it the campaign)
var advisor: Advisor
var expanded := false  ## the checklist is unfolded (L, or a click)
var tip := {}  ## the tip on show: {id, title, text, left}
var done := {}  ## the goal just met: {text, left}
var where := "hidden"  ## "play", "build", "map", "fight", "board", "modal" or "hidden": what is on the screen (where())
var card_rect := Rect2()  ## screen px; empty when there is no card
var tip_rect := Rect2()  ## screen px; empty when there is no tip
var hover := {}  ## the keyword under the mouse: {kw, rect (local px)}
var _card_dl: Array = []  # what the card draws: [{k, ...}] in the card's own px
var _tip_dl: Array = []
var _hot: Array = []  # [{rect (this control's px), kw}] every keyword on show
var _warn_rect := Rect2()  # the warning band (this control's px), to dismiss it by a click
var _button := Rect2()  # the tip's Got it (this control's px)
var _mouse := Vector2(-1.0, -1.0)
var _foe_for := -1  # the combat session the foe ratio below was rated for
var _foe_ratio := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_exited.connect(func(): hover = {})


# --- what is on the screen --------------------------------------------------------------------------------------

## Where the Ledger is looking: the screen the player is on. "hidden" for a menu, the ship picker, the game over screen and anything that stops the game.
func locate() -> String:
	var d := door
	if d == null or d.menu == null or d.map == null:
		return "hidden"
	if d.menu.visible or d.over.visible or d.ending.visible or d.help.visible or (d.picker != null and d.picker.visible) or d.prompt_up():
		return "hidden"
	var b = d.build
	if b == null or b.ship == null or d.map.campaign == null:
		return "hidden"
	if d.combat != null and d.combat.active:
		return "fight"
	var board = d.get_node_or_null("../Board")
	if board != null and board.active:
		return "board"
	var m = d.map
	if m.visible:
		if m.panel_only or m.event_panel.visible or m.station_panel.visible or m.team_picker.visible or m.region_choice.visible or m.journal_panel.visible:
			return "modal"
		return "map"
	if (d.craft != null and d.craft.visible) or (b.shields != null and b.shields.visible):
		return "modal"
	return "build" if b.build_on else "play"


## What the screens say, for the tips: the state of the panels the Ledger cannot see through the ship and the campaign.
func context() -> Dictionary:
	var d := door
	var b = d.build
	var board = d.get_node_or_null("../Board")
	var crew = d.get_node_or_null("../Crew")
	var fighting: bool = d.combat != null and d.combat.active
	var ctx := {
		"build_on": b.build_on and where in ["play", "build"],
		"fighting": fighting,
		"boarding": board != null and board.active,
		"loadout": board != null and board.picking,
		"breach": crew != null and crew.get("prompt") != null and crew.prompt.visible,
		"station": d.map.station_panel.visible,
		"craft": d.craft != null and d.craft.visible,
		"shields": b.shields != null and b.shields.visible,
		"rig_bonus": board != null and board.active and board.session != null and board.session.left.values().any(func(c): return not c.get("bonus", {}).is_empty()),
		"foe_ratio": _foe(d) if fighting else 0.0,
	}
	return ctx


## The enemy's power over the player's in the fight on now (once per fight).
func _foe(d: Node) -> float:
	var s = d.combat.get("session")
	if s == null:
		return 0.0
	if _foe_for != s.get_instance_id():
		_foe_for = s.get_instance_id()
		_foe_ratio = 0.0
		var ships: Array = s.arena.ships
		if ships.size() > 1:
			_foe_ratio = float(Threat.rate(ships[1].ship, ships[0].ship)["ratio"])
	return _foe_ratio


# --- the frame -----------------------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if door == null:
		return
	if advisor == null:
		advisor = Advisor.new()
	advisor.profile = door.profile
	where = locate()
	var ship = door.sim.player_ship() if door.sim != null else null
	if where == "hidden" or ship == null:
		_hide()
		return
	var campaign = door.map.campaign
	advisor.tick(dt, ship, campaign, context())
	if advisor.dirty and door.profile != null:
		advisor.dirty = false
		door.profile.ledger_run = advisor.state()
		door.profile.save()
	_events()
	_age(dt)
	_next_tip()
	layout()
	visible = card_rect.size.x > 0.0 or tip_rect.size.x > 0.0
	queue_redraw()


func _hide() -> void:
	visible = false
	card_rect = Rect2()
	tip_rect = Rect2()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Sounds and the "done" line for what the Advisor says happened.
func _events() -> void:
	for e in advisor.take_events():
		match e["type"]:
			"goal":
				done = {"text": Advisor.plain(str(e["title"])), "left": DONE_S}
				Audio.fx(self, "tab_switch")
			"warning":
				Audio.fx(self, "toast")
			"tip":
				Audio.fx(self, "toast")


func _age(dt: float) -> void:
	if not done.is_empty():
		done["left"] = float(done["left"]) - dt
		if float(done["left"]) <= 0.0:
			done = {}
	if not tip.is_empty():
		tip["left"] = float(tip["left"]) - dt
		if float(tip["left"]) <= 0.0 or not advisor.shows("tips"):
			tip = {}


## The next waiting tip comes on when none is on show.
func _next_tip() -> void:
	if not tip.is_empty() or where == "hidden":
		return
	var id := advisor.next_tip()
	if id == "":
		return
	var w := advisor.tip_words(id)
	tip = {"id": id, "title": w.get("title", ""), "text": w.get("text", ""), "left": TIP_S}
	advisor.tip_shown(id)


## "Got it": the tip goes.
func dismiss_tip() -> void:
	tip = {}


func toggle() -> void:
	expanded = not expanded
	Audio.fx(self, "tab_switch")


# --- layout --------------------------------------------------------------------------------------------------------

## The width of the card on the screen the player is on.
func card_width() -> float:
	if where == "build":
		return Hud.SIDE_W
	return OPEN_W if expanded else (MAP_W if where == "map" else CARD_W)


## Build the card and the note, place them, and give this control their rect.
func layout() -> void:
	var view := get_viewport_rect().size if is_inside_tree() else Vector2(1600.0, 900.0)
	var card := advisor.card()
	_card_dl = []
	_tip_dl = []
	_hot = []
	_warn_rect = Rect2()
	_button = Rect2()
	card_rect = Rect2()
	tip_rect = Rect2()
	var w := card_width()
	var with_card := where in ["play", "build", "map"] and not card.is_empty()
	var ch := _build_card(card, w, where == "map" and not expanded) if with_card else 0.0
	var fight_warning: bool = where == "fight" and card.has("warning")  # in a fight the card is not up, but a warning still is (a four skull enemy)
	if fight_warning:
		w = NOTE_W
		ch = _build_warning(card["warning"], w)
		with_card = true
	var th := 0.0
	var tw := w
	if not tip.is_empty():
		match where:
			"fight":
				tw = NOTE_W
				th = _build_note(tw, false)
			"modal", "board", "map":  # a strip along the bottom edge
				tw = minf(UiKit.text_width(str(tip["text"]), BODY) + UiKit.text_width(str(tip["title"]), BODY, UiKit.bold()) + BUTTON.x + 110.0, view.x - 80.0)
				th = _build_note(tw, true)
			_:
				th = _build_note(w, false)
	var stacked := not tip.is_empty() and where in ["play", "build"]
	match where:
		"build":  # the right column, at the bottom, under the part card when that is tall
			var y := view.y - Hud.MARGIN - ch - (GAP + th if stacked else 0.0)
			var info = door.build.hud.card if door.build.hud != null else null
			if info != null and info.visible:
				y = maxf(y, info.position.y + info.size.y + Hud.MARGIN)
			card_rect = Rect2(Vector2(view.x - Hud.MARGIN - w, y), Vector2(w, ch)) if with_card else Rect2()
		"map":  # the bottom right of the map's panel: the two lines in its footer; unfolded, over the corner of the map (the footer's words stay clear)
			var bottom := view.y - MapView.MARGIN - 6.0 if not expanded else view.y - MapView.MARGIN - MapView.FOOT_H - 4.0
			card_rect = Rect2(Vector2(view.x - MapView.MARGIN - MapView.PAD - w, bottom - ch), Vector2(w, ch)) if with_card else Rect2()
		"fight":
			card_rect = Rect2(NOTE_AT, Vector2(w, ch)) if fight_warning else Rect2()
		_:
			card_rect = Rect2(Vector2(8.0, Hud.TOP_H + 8.0), Vector2(w, ch)) if with_card else Rect2()
	if th > 0.0:
		match where:
			"fight":
				tip_rect = Rect2(NOTE_AT + (Vector2(0.0, ch + GAP) if fight_warning else Vector2.ZERO), Vector2(tw, th))
			"modal", "board", "map":
				tip_rect = Rect2(Vector2((view.x - tw) / 2.0, view.y - 6.0 - th), Vector2(tw, th))
			_:
				var at := Vector2(card_rect.position.x, card_rect.end.y + GAP) if with_card else Vector2(8.0, Hud.TOP_H + 8.0)
				tip_rect = Rect2(at, Vector2(tw, th))
	var all := Rect2()
	if card_rect.size.x > 0.0:
		all = card_rect
	if tip_rect.size.x > 0.0:
		all = tip_rect if all.size.x == 0.0 else all.merge(tip_rect)
	position = all.position
	size = all.size
	mouse_filter = Control.MOUSE_FILTER_STOP if all.size.x > 0.0 else Control.MOUSE_FILTER_IGNORE
	# the keywords' places, from the lists' own px to this control's
	for item in _card_dl:
		_localise(item, card_rect.position - position)
	for item in _tip_dl:
		_localise(item, tip_rect.position - position)


func _localise(item: Dictionary, off: Vector2) -> void:
	if item["k"] == "hot":
		_hot.append({"rect": Rect2(item["rect"].position + off, item["rect"].size), "kw": item["kw"]})
	elif item["k"] == "warn":
		_warn_rect = Rect2(item["rect"].position + off, item["rect"].size)
	elif item["k"] == "button":
		_button = Rect2(item["rect"].position + off, item["rect"].size)


## `text` laid out in `width` px from `at`: {items (text runs), hot (keyword rects), h}. Marks {id} and {id:words} are keywords: coloured, with a hover line.
## `bold`: all of it in the bold font (keywords always are).
func flow(text: String, at: Vector2, width: float, size: int, col: Color, bold := false) -> Dictionary:
	var items := []
	var hot := []
	var x := 0.0
	var y := 0.0
	var space := UiKit.text_width(" ", size)
	var lh := float(size) + 4.0
	for seg in Advisor.segments(text):
		var kw: Dictionary = advisor.keyword(seg["kw"]) if seg["kw"] != "" else {}
		var f: Font = UiKit.bold() if bold or not kw.is_empty() else UiKit.font()
		var s: String = seg["text"]
		var i := 0
		while i < s.length():
			var j := s.find(" ", i)
			var word := s.substr(i, (j if j >= 0 else s.length()) - i)
			var gap := space if j >= 0 else 0.0
			if word != "":
				var ww := UiKit.text_width(word, size, f)
				if x > 0.0 and x + ww > width:
					x = 0.0
					y += lh
				items.append({"k": "text", "p": at + Vector2(x, y + float(size)), "s": word, "size": size, "c": kw["color"] if not kw.is_empty() else col, "f": f})
				if not kw.is_empty():
					hot.append({"k": "hot", "rect": Rect2(at + Vector2(x, y), Vector2(ww, lh)), "kw": seg["kw"]})
				x += ww
			x += gap
			i = (j + 1) if j >= 0 else s.length()
	return {"items": items, "hot": hot, "h": y + lh}


## The map's card in two lines: the goal (or the line just done) and its progress; a warning takes the place of both while it is up. Returns the height.
func _build_compact(card: Dictionary, w: float) -> float:
	var inner := w - 2.0 * PAD
	var fold := "L unfolds"
	if card.has("warning"):
		var wf := flow(str(card["warning"]["text"]), Vector2(PAD + 22.0, 8.0), inner - 22.0, BODY, Color("#f3c26b"))
		var wh := float(wf["h"]) + 12.0
		var r := Rect2(Vector2(4.0, 3.0), Vector2(w - 8.0, wh))
		_card_dl.append({"k": "rect", "rect": r, "c": WARN_BG, "edge": UiKit.AMBER})
		_card_dl.append({"k": "text", "p": Vector2(PAD, 8.0 + float(BODY)), "s": "!", "size": TITLE, "c": UiKit.AMBER, "f": UiKit.bold()})
		_card_dl.append_array(wf["items"])
		_card_dl.append({"k": "warn", "rect": r})
		return wh + 6.0
	var y := 7.0
	if not done.is_empty():
		_card_dl.append({"k": "text", "p": Vector2(PAD, y + 13.0), "s": "Done: " + str(done["text"]), "size": TITLE - 1, "c": GREEN, "f": UiKit.bold()})
		y += 20.0
	elif card["done"]:
		var df := flow(str(advisor.words.get("card", {}).get("done", "")), Vector2(PAD, y), inner, BODY, UiKit.DIM_TEXT)
		_card_dl.append_array(df["items"])
		return float(df["h"]) + 14.0
	else:
		var tf := flow(str(card["goal"]["title"]), Vector2(PAD, y), inner, TITLE - 1, UiKit.TEXT, true)
		_card_dl.append_array(tf["items"])
		_card_dl.append_array(tf["hot"])
		y += float(tf["h"]) + 2.0
	if not card["done"]:
		y = _progress(card["goal"]["progress"], Vector2(PAD, y), inner - UiKit.text_width(fold, SMALL) - 8.0)
		_card_dl.append({"k": "text", "p": Vector2(w - PAD - UiKit.text_width(fold, SMALL), y - 5.0), "s": fold, "size": SMALL, "c": UiKit.DIM_TEXT, "f": UiKit.font()})
	return y + 6.0


## Fill _card_dl for `card` (advisor.card()) `w` px wide; returns the height. `compact`: the map's two lines (_build_compact).
func _build_card(card: Dictionary, w: float, compact := false) -> float:
	if compact:
		return _build_compact(card, w)
	var inner := w - 2.0 * PAD
	var y := HEAD_H + 8.0
	var fold := "L %s" % ("folds" if expanded else "unfolds")
	_card_dl.append({"k": "text", "p": Vector2(PAD, 17.0), "s": str(advisor.words.get("card", {}).get("title", "THE LEDGER")), "size": SMALL + 1, "c": UiKit.AMBER, "f": UiKit.bold()})
	var tag := "stage %d  |  %s" % [advisor.stage, fold] if card.has("goal") else fold
	_card_dl.append({"k": "text", "p": Vector2(w - PAD - UiKit.text_width(tag, SMALL), 17.0), "s": tag, "size": SMALL, "c": UiKit.DIM_TEXT, "f": UiKit.font()})
	_card_dl.append({"k": "line", "a": Vector2(PAD, HEAD_H), "b": Vector2(w - PAD, HEAD_H), "c": Color(UiKit.EDGE_DIM, 0.7)})
	if not done.is_empty():
		_card_dl.append({"k": "text", "p": Vector2(PAD, y + 12.0), "s": "Done: " + str(done["text"]), "size": BODY, "c": GREEN, "f": UiKit.bold()})
		y += LINE + 4.0
	if card.has("goal"):
		if expanded:
			y = _build_list(w, y)
		elif card["done"]:
			var f := flow(str(advisor.words.get("card", {}).get("done", "")), Vector2(PAD, y), inner, BODY, UiKit.DIM_TEXT)
			_card_dl.append_array(f["items"])
			y += float(f["h"]) + 4.0
		else:
			var g: Dictionary = card["goal"]
			var tf := flow(str(g["title"]), Vector2(PAD, y), inner, TITLE, UiKit.TEXT, true)
			_card_dl.append_array(tf["items"])
			_card_dl.append_array(tf["hot"])
			y += float(tf["h"]) + 3.0
			if str(g["why"]) != "":
				var wf := flow(str(g["why"]), Vector2(PAD, y), inner, BODY, UiKit.DIM_TEXT)
				_card_dl.append_array(wf["items"])
				_card_dl.append_array(wf["hot"])
				y += float(wf["h"]) + 4.0
			y = _progress(g["progress"], Vector2(PAD, y), inner) + 4.0
	if card.has("warning"):
		var wf2 := flow(str(card["warning"]["text"]), Vector2(PAD + 22.0, y + 7.0), inner - 22.0, BODY, Color("#f3c26b"))
		var wh := float(wf2["h"]) + 12.0
		var r := Rect2(Vector2(PAD - 6.0, y), Vector2(w - 2.0 * (PAD - 6.0), wh))
		_card_dl.append({"k": "rect", "rect": r, "c": WARN_BG, "edge": UiKit.AMBER})
		_card_dl.append({"k": "text", "p": Vector2(PAD, y + 7.0 + float(BODY)), "s": "!", "size": TITLE, "c": UiKit.AMBER, "f": UiKit.bold()})
		_card_dl.append_array(wf2["items"])
		_card_dl.append({"k": "warn", "rect": r})
		y += wh + 6.0
	return y + 4.0


## A warning on its own (a fight has no card): the amber band. Returns the height.
func _build_warning(warn: Dictionary, w: float) -> float:
	var wf := flow(str(warn["text"]), Vector2(PAD + 18.0, 9.0), w - 2.0 * PAD - 18.0, BODY, Color("#f3c26b"))
	var wh := float(wf["h"]) + 14.0
	var r := Rect2(Vector2(0.0, 0.0), Vector2(w, wh))
	_card_dl.append({"k": "rect", "rect": r, "c": WARN_BG, "edge": UiKit.AMBER})
	_card_dl.append({"k": "text", "p": Vector2(PAD - 2.0, 9.0 + float(BODY)), "s": "!", "size": TITLE, "c": UiKit.AMBER, "f": UiKit.bold()})
	_card_dl.append_array(wf["items"])
	_card_dl.append({"k": "warn", "rect": r})
	return wh


## The progress line: "Guns 2/3" and a bar. Returns the y under it.
func _progress(p: Dictionary, at: Vector2, width: float) -> float:
	_card_dl.append({"k": "text", "p": at + Vector2(0.0, 12.0), "s": str(p["text"]), "size": BODY, "c": UiKit.TEXT, "f": UiKit.font()})
	var tw := UiKit.text_width(str(p["text"]), BODY) + 12.0
	var frac := clampf(float(p["have"]) / maxf(float(p["need"]), 0.001), 0.0, 1.0) if float(p["need"]) > 0.0 else 0.0
	var bar := Rect2(at + Vector2(tw, 3.0), Vector2(minf(width - tw, 180.0), 8.0))
	_card_dl.append({"k": "bar", "rect": bar, "frac": frac})
	return at.y + 17.0


## The unfolded checklist: a row a goal (as tall as its words), the next one lit with its why under it. Returns the y under it.
func _build_list(w: float, y0: float) -> float:
	var y := y0
	var rows := advisor.checklist()
	var next := advisor.next_goal()
	for row in rows:
		var lit: bool = not next.is_empty() and row["id"] == next["id"]
		var status := "done" if row["met"] else str(row["progress"]["text"])
		var sw := UiKit.text_width(status, SMALL) + 10.0
		var f := flow(str(row["title"]), Vector2(PAD + 22.0, y + 4.0), w - 2.0 * PAD - 22.0 - sw, BODY, UiKit.DIM_TEXT if row["met"] else UiKit.TEXT)
		var rh := maxf(ROW_H, float(f["h"]) + 8.0)
		if lit:
			_card_dl.append({"k": "rect", "rect": Rect2(Vector2(PAD - 4.0, y), Vector2(w - 2.0 * (PAD - 4.0), rh - 2.0)), "c": Color(1, 1, 1, 0.06), "edge": Color(UiKit.AMBER, 0.5)})
		_card_dl.append({"k": "tick", "rect": Rect2(Vector2(PAD, y + 5.0), Vector2(13.0, 13.0)), "met": row["met"]})
		_card_dl.append_array(f["items"])
		_card_dl.append_array(f["hot"])
		_card_dl.append({"k": "text", "p": Vector2(w - PAD - sw + 10.0, y + 16.0), "s": status, "size": SMALL, "c": GREEN if row["met"] else UiKit.DIM_TEXT, "f": UiKit.font()})
		y += rh
		if lit and str(row["why"]) != "":
			var wf := flow(str(row["why"]), Vector2(PAD + 22.0, y), w - 2.0 * PAD - 22.0, BODY, UiKit.DIM_TEXT)
			_card_dl.append_array(wf["items"])
			_card_dl.append_array(wf["hot"])
			y += float(wf["h"]) + 5.0
	return y + 2.0


## Fill _tip_dl for the tip `w` px wide: stacked (title, text, the button under) or, for a strip, in one row. Returns the height.
func _build_note(w: float, strip: bool) -> float:
	var title := str(tip["title"])
	if strip:
		_tip_dl.append({"k": "chip", "p": Vector2(10.0, 7.0), "s": "TIP"})
		var tx := 10.0 + 38.0
		_tip_dl.append({"k": "text", "p": Vector2(tx, 21.0), "s": title, "size": BODY, "c": UiKit.AMBER, "f": UiKit.bold()})
		tx += UiKit.text_width(title, BODY, UiKit.bold()) + 12.0
		var f := flow(str(tip["text"]), Vector2(tx, 5.0), w - tx - BUTTON.x - 20.0, BODY, UiKit.TEXT)
		_tip_dl.append_array(f["items"])
		_tip_dl.append_array(f["hot"])
		_tip_dl.append({"k": "button", "rect": Rect2(Vector2(w - BUTTON.x - 8.0, 5.0), BUTTON)})
		return 32.0
	var y := 8.0
	_tip_dl.append({"k": "chip", "p": Vector2(10.0, y), "s": "TIP"})
	_tip_dl.append({"k": "text", "p": Vector2(10.0 + 38.0, y + 14.0), "s": title, "size": BODY, "c": UiKit.AMBER, "f": UiKit.bold()})
	y += 24.0
	var f2 := flow(str(tip["text"]), Vector2(10.0, y), w - 20.0, BODY, UiKit.TEXT)
	_tip_dl.append_array(f2["items"])
	_tip_dl.append_array(f2["hot"])
	y += float(f2["h"]) + 6.0
	_tip_dl.append({"k": "button", "rect": Rect2(Vector2(w - BUTTON.x - 8.0, y), BUTTON)})
	return y + BUTTON.y + 8.0


# --- input -----------------------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_L and not (e.ctrl_pressed or e.alt_pressed or e.shift_pressed or e.meta_pressed):
		if where in ["play", "build", "map"] and card_rect.size.x > 0.0:
			toggle()
			if is_inside_tree():
				get_viewport().set_input_as_handled()


func _gui_input(e: InputEvent) -> void:
	if UiKit.is_wheel(e):
		accept_event()  # the world behind must not zoom
		return
	if e is InputEventMouseMotion:
		_mouse = e.position
		hover = {}
		for h in _hot:
			if h["rect"].has_point(e.position):
				hover = h
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		click(e.position)
		accept_event()


## A left click at `p` (this control's px): Got it, the warning (it goes), or the card (it folds or unfolds).
func click(p: Vector2) -> void:
	if tip_rect.size.x > 0.0 and _button.has_point(p):
		dismiss_tip()
		Audio.fx(self, "click")
	elif card_rect.size.x > 0.0 and _warn_rect.size.x > 0.0 and _warn_rect.has_point(p):
		advisor.warning = {}
		Audio.fx(self, "click")
	elif card_rect.size.x > 0.0 and Rect2(card_rect.position - position, card_rect.size).has_point(p):
		toggle()


# --- drawing ---------------------------------------------------------------------------------------------------------

func _draw() -> void:
	if card_rect.size.x > 0.0:
		var r := Rect2(card_rect.position - position, card_rect.size)
		UiKit.bar(self, r, 0.96)
		_replay(_card_dl, r.position)
	if tip_rect.size.x > 0.0:
		var t := Rect2(tip_rect.position - position, tip_rect.size)
		UiKit.bar(self, t, 0.97)
		draw_rect(Rect2(t.position + Vector2(2.0, 2.0), Vector2(3.0, t.size.y - 4.0)), UiKit.AMBER)
		_replay(_tip_dl, t.position)
	_draw_hover()


func _replay(dl: Array, off: Vector2) -> void:
	for it in dl:
		match it["k"]:
			"text":
				UiKit.text(self, it["s"], off + it["p"], it["size"], it["c"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, it["f"])
			"line":
				draw_line(off + it["a"], off + it["b"], it["c"], 1.0)
			"rect":
				var rr := Rect2(off + it["rect"].position, it["rect"].size)
				draw_rect(rr, it["c"])
				draw_rect(rr, it["edge"], false, 1.0)
			"bar":
				var br := Rect2(off + it["rect"].position, it["rect"].size)
				draw_rect(br, UiKit.INSET_BG)
				draw_rect(Rect2(br.position, Vector2(br.size.x * float(it["frac"]), br.size.y)), UiKit.AMBER)
				draw_rect(br, UiKit.EDGE_DIM, false, 1.0)
			"tick":
				var tr := Rect2(off + it["rect"].position, it["rect"].size)
				draw_rect(tr, UiKit.INSET_BG)
				draw_rect(tr, GREEN if it["met"] else UiKit.EDGE_DIM, false, 1.0)
				if it["met"]:
					draw_polyline(PackedVector2Array([tr.position + Vector2(2.5, 6.5), tr.position + Vector2(5.5, 10.0), tr.position + Vector2(11.0, 3.0)]), GREEN, 2.0)
			"chip":
				UiKit.chip(self, it["s"], off + it["p"], UiKit.AMBER, SMALL)
			"button":
				var bb := Rect2(off + it["rect"].position, it["rect"].size)
				UiKit.button(self, bb, false, bb.has_point(_mouse))
				UiKit.text(self, "Got it", bb.position + Vector2(0.0, 16.0), BODY - 1, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, bb.size.x)


## The hover line of the keyword under the mouse, in a small note by it, kept on the screen.
func _draw_hover() -> void:
	if hover.is_empty() or advisor == null:
		return
	var k := advisor.keyword(str(hover["kw"]))
	if k.is_empty():
		return
	var lines := UiKit.wrap(str(k["hover"]), 240.0, 12)
	var w := 16.0
	for l in lines:
		w = maxf(w, UiKit.text_width(l, 12) + 16.0)
	var h := lines.size() * 16.0 + 12.0
	var r: Rect2 = hover["rect"]
	var view := get_viewport_rect().size if is_inside_tree() else Vector2(1600.0, 900.0)
	var at := Vector2(minf(r.position.x, view.x - 6.0 - w - position.x), r.end.y + 6.0)
	if position.y + at.y + h > view.y - 4.0:
		at.y = r.position.y - h - 6.0
	UiKit.note(self, lines, at, k["color"], 12)
