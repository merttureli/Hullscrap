extends Control
## The station menu of the Drift: a trading screen over the map, opened when you dock at Rusthold,
## Meridian, the Prism or a Scrapper trader. Three columns. BUY: fuel and the station's stock. SELL: your
## cargo at half its value. SERVICES: pay Ma Gantry's debt (Scrapper docks), repair hull integrity,
## hire one of the recruits on offer. Click a row (left: one, right: five fuel or all of an item); Esc,
## Enter or M leaves. While open it takes every key and click. The rules and prices are in campaign.gd
## (data/drift.json); this node only reads input and draws, in the UI colours of docs/ART_STYLE.md.

## Emitted when the menu is closed.
signal closed

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Backstory = preload("res://scripts/crew/backstory.gd")
const Audio = preload("res://scripts/audio/audio.gd")

const MARGIN := 40.0
const PAD := 18.0
const HEAD_H := 96.0
const FOOT_H := 38.0
const ROW_H := 30.0
const HEADER_H := 32.0
const STORY_SIZE := 13  ## font size of the story under a recruit
const COL_GAP := 14.0
const COL_SPLIT: Array[float] = [0.36, 0.30, 0.34]
const DIM := Color(0.0, 0.0, 0.0, 0.62)
const PANEL_BG := Color("#1f2630")
const ROW_BG := Color("#2a3340")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.1)
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const GOOD := Color("#6bd34a")
const BAD := Color("#e0413b")
const AMBER := Color("#e1a136")
const COLUMNS: Array[String] = ["BUY", "SELL", "SERVICES"]

var map: Control  ## the MapView: its campaign and ship
var station := ""  ## the node id of the station
var message := ""
var message_bad := false
var hover := [-1, -1]  ## [column, row] under the mouse
var top: Array[int] = [0, 0, 0]  ## the first row shown in each column


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _campaign():
	return map.campaign


# --- the rows each column shows -------------------------------------------------------------------------------

## Open the menu of node `id`.
func open(id: String) -> void:
	station = id
	message = ""
	hover = [-1, -1]
	top = [0, 0, 0]
	visible = true
	Audio.fx(self, "open")


func close() -> void:
	if not visible:
		return
	visible = false
	Audio.fx(self, "close")
	closed.emit()


func _cfg() -> Dictionary:
	return _campaign().station_cfg(station)


func _faction() -> String:
	return str(_cfg().get("faction", ""))


## Column `col`'s rows: {kind, id, index, label, right (text), cost (credits it takes, 0 for none), header}.
func rows(col: int) -> Array:
	var c = _campaign()
	var s = map.ship()
	var cfg := _cfg()
	var out := []
	if col == 0:
		if "fuel" in cfg["services"]:
			out.append({"kind": "fuel", "id": "fuel", "label": "Fuel", "right": "%d cr" % c.price(int(c.cfg["fuel"]["price"]), _faction(), s), "cost": c.price(int(c.cfg["fuel"]["price"]), _faction(), s)})
		if "stock" in cfg["services"]:
			var ids: Array = cfg.get("stock", {}).keys()
			ids.sort_custom(func(a, b): return c.stock_price(station, a, s) < c.stock_price(station, b, s) or (c.stock_price(station, a, s) == c.stock_price(station, b, s) and a < b))
			for id in ids:
				out.append({"kind": "buy", "id": id, "label": s.crafting.name_of(id, s.components), "right": "%d cr" % c.stock_price(station, id, s), "cost": c.stock_price(station, id, s)})
	elif col == 1:
		if "sell" in cfg["services"]:
			var ids: Array = s.inventory.counts.keys()
			ids.sort()
			for id in ids:
				if id == "credits":
					continue
				var each: int = c.sell_price(s, id)
				out.append({"kind": "sell", "id": id, "label": "%s  x%d" % [s.crafting.name_of(id, s.components), s.inventory.count(id)], "right": "%d cr" % each if each > 0 else "-", "cost": 0})
	else:
		if "debt" in cfg["services"]:
			var pay := mini(int(c.cfg["debt"]["payment"]), c.debt)
			out.append({"kind": "header", "label": "MA GANTRY'S DEBT: %d" % c.debt, "right": "behind %d" % c.behind() if c.behind() > 0 else ""})
			if c.debt > 0:
				out.append({"kind": "pay", "id": "pay", "label": "Pay %d" % pay, "right": "%d cr" % pay, "cost": pay})
				out.append({"kind": "pay_all", "id": "pay_all", "label": "Pay it all", "right": "%d cr" % c.debt, "cost": c.debt})
			else:
				out.append({"kind": "note", "label": "Paid off. Ma has nothing more to say to you."})
		if "repair" in cfg["services"]:
			var each: int = c.price(int(c.cfg["prices"]["repair"]), _faction(), s)
			out.append({"kind": "header", "label": "HULL INTEGRITY: %d/%d" % [c.hull_left(s), c.hull_max(s)], "right": "%d cr a point" % each})
			if c.hull_loss > 0:
				out.append({"kind": "repair", "id": "repair", "label": "Repair 10 points", "right": "%d cr" % (mini(10, c.hull_loss) * each), "cost": mini(10, c.hull_loss) * each})
				out.append({"kind": "repair_all", "id": "repair_all", "label": "Repair all (%d points)" % c.hull_loss, "right": "%d cr" % (c.hull_loss * each), "cost": c.hull_loss * each})
			else:
				out.append({"kind": "note", "label": "The hull is sound."})
		if "recruit" in cfg["services"]:
			var price: int = c.price(int(c.cfg["prices"]["recruit"]), _faction(), s)
			out.append({"kind": "header", "label": "RECRUITS", "right": "%d cr each" % price})
			var offers: Array = c.offers.get(station, [])
			for i in offers.size():
				var def := CrewMember.species_def(str(offers[i]["species"]))
				var traits: Array = def.get("traits", [])
				out.append({"kind": "recruit", "id": "recruit", "index": i, "label": "%s  %s  hp %d" % [offers[i]["name"], str(offers[i]["species"]).capitalize(), int(def.get("hp", 100))],
					"right": "%s" % (", ".join(traits) if not traits.is_empty() else ""), "cost": price})
				out.append({"kind": "note", "story": true, "label": Backstory.of(str(offers[i]["name"]), str(offers[i]["species"]))})  # who they are, so the hire is made by story
			if offers.is_empty():
				out.append({"kind": "note", "label": "Nobody is looking for a berth."})
	return out


## Do the row `i` of column `col`: `button` is MOUSE_BUTTON_LEFT (one) or MOUSE_BUTTON_RIGHT (five fuel, all of an item).
## Returns the message shown.
func act(col: int, i: int, button := MOUSE_BUTTON_LEFT) -> String:
	var list := rows(col)
	if i < 0 or i >= list.size():
		return ""
	var row: Dictionary = list[i]
	var c = _campaign()
	var s = map.ship()
	var more: bool = button == MOUSE_BUTTON_RIGHT
	var r := {"ok": false, "text": ""}
	match row["kind"]:
		"fuel":
			r = c.buy_fuel(s, station, 5 if more else 1)
		"buy":
			r = c.buy(s, station, row["id"], 1)
		"sell":
			r = c.sell(s, row["id"], 99999 if more else 1)
		"pay":
			r = c.pay_debt(s, int(c.cfg["debt"]["payment"]))
		"pay_all":
			r = c.pay_debt(s, c.debt)
		"repair":
			r = c.repair(s, station, 10)
		"repair_all":
			r = c.repair(s, station, c.hull_loss)
		"recruit":
			r = c.recruit(s, station, row["index"])
		_:
			return ""
	message = r["text"]
	message_bad = not r["ok"]
	Audio.fx(self, "buy" if r["ok"] else "invalid")
	map.refresh()
	return message


# --- input ----------------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey):
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	if e.pressed and not e.echo and not e.ctrl_pressed and e.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_M]:  # (Ctrl+M is the mute, audio.gd)
		close()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover = row_at(e.position)
	elif e is InputEventMouseButton and e.pressed:
		var at := row_at(e.position)
		match e.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if at[0] >= 0:
					act(at[0], at[1], e.button_index)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if at[0] >= 0:
					top[at[0]] = clampi(top[at[0]] + (1 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, maxi(rows(at[0]).size() - 1, 0))
	accept_event()


# --- layout ---------------------------------------------------------------------------------------------------

func panel_rect() -> Rect2:
	return Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN, MARGIN) * 2.0)


## The rectangle of column `col` (below its title).
func column_rect(col: int) -> Rect2:
	var p := panel_rect()
	var inner := p.size.x - 2.0 * PAD - 2.0 * COL_GAP
	var x := p.position.x + PAD
	for k in col:
		x += inner * COL_SPLIT[k] + COL_GAP
	return Rect2(Vector2(x, p.position.y + HEAD_H + HEADER_H), Vector2(inner * COL_SPLIT[col], p.size.y - HEAD_H - HEADER_H - FOOT_H))


## The rectangle of row `i` in column `col` as drawn (empty when scrolled off or past the bottom).
func row_rect(col: int, i: int) -> Rect2:
	var col_r := column_rect(col)
	var all := rows(col)
	if i < top[col] or i >= all.size():
		return Rect2()
	var y := 0.0
	for k in range(top[col], i):
		y += _row_h(col, all[k]) + 4.0
	var r := Rect2(col_r.position + Vector2(0.0, y), Vector2(col_r.size.x, _row_h(col, all[i])))
	return r if r.end.y <= col_r.end.y else Rect2()


## The height of `row` of column `col`: ROW_H, or what its wrapped story needs.
func _row_h(col: int, row: Dictionary) -> float:
	if not row.has("story"):
		return ROW_H
	return ThemeDB.fallback_font.get_multiline_string_size(str(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, column_rect(col).size.x - 16.0, STORY_SIZE).y + 8.0


## [column, row] at `p`, or [-1, -1].
func row_at(p: Vector2) -> Array:
	for col in 3:
		var all := rows(col)
		for i in range(top[col], all.size()):
			if all[i]["kind"] not in ["header", "note"] and row_rect(col, i).has_point(p):
				return [col, i]
	return [-1, -1]


# --- drawing --------------------------------------------------------------------------------------------------

func _draw() -> void:
	var c = _campaign()
	if c == null or station == "":
		return
	var s = map.ship()
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var p := panel_rect()
	_panel(p)
	var n: Dictionary = c.node(station)
	_text((str(n["name"]) if str(n["name"]) != "" else "Scrapper trader").to_upper(), p.position + Vector2(PAD, 38.0), 26, TEXT)
	var f := _faction()
	if f != "":
		var disc: float = c.discount(f)
		_text("%s reputation %+d%s" % [c.faction_name(f), c.rep[f], "   prices %d%% off" % roundi(disc * 100.0) if disc > 0.0 else ""], p.position + Vector2(PAD, 64.0), 15, c.faction_color(f))
	var credits: int = s.inventory.count("credits")
	_text("Credits %d" % credits, Vector2(p.end.x - 620.0, p.position.y + 38.0), 20, AMBER)
	_text("Fuel %d" % s.inventory.count("fuel"), Vector2(p.end.x - 470.0, p.position.y + 38.0), 20, GOOD if s.inventory.count("fuel") > 0 else BAD)
	_text("Hull %d/%d" % [c.hull_left(s), c.hull_max(s)], Vector2(p.end.x - 340.0, p.position.y + 38.0), 20, TEXT)
	_text("Debt %d" % c.debt, Vector2(p.end.x - 190.0, p.position.y + 38.0), 20, BAD if c.behind() > 0 else TEXT)
	if message != "":
		_text(message, p.position + Vector2(PAD, 88.0), 16, BAD if message_bad else GOOD)
	for col in 3:
		_draw_column(col, credits)
	_text("Click: buy or sell one   Right-click: five fuel or all   Wheel: scroll   Esc: leave", Vector2(p.position.x + PAD, p.end.y - 14.0), 13, DIM_TEXT)


func _draw_column(col: int, credits: int) -> void:
	var cr := column_rect(col)
	_text(COLUMNS[col], Vector2(cr.position.x, cr.position.y - 10.0), 15, AMBER)
	draw_line(Vector2(cr.position.x, cr.position.y - 6.0), Vector2(cr.end.x, cr.position.y - 6.0), EDGE_DIM, 1.0)
	var all := rows(col)
	if all.is_empty():
		_text("Nothing here", cr.position + Vector2(8.0, 22.0), 15, DIM_TEXT)
		return
	for i in range(top[col], all.size()):
		var r := row_rect(col, i)
		if r.size == Vector2.ZERO:
			_text("v more", Vector2(cr.end.x - 60.0, cr.end.y + 14.0), 12, DIM_TEXT)
			break
		var row: Dictionary = all[i]
		if row["kind"] == "header":
			_text(str(row["label"]), r.position + Vector2(2.0, 20.0), 14, AMBER)
			_right(str(row.get("right", "")), r, 12, BAD if str(row.get("right", "")).begins_with("behind") else DIM_TEXT, 20.0)
			continue
		if row["kind"] == "note":
			if row.has("story"):
				var font := ThemeDB.fallback_font
				draw_multiline_string(font, r.position + Vector2(8.0, 4.0 + font.get_ascent(STORY_SIZE)), str(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0, STORY_SIZE, -1, DIM_TEXT)
				continue
			_text(str(row["label"]), r.position + Vector2(8.0, 20.0), 14, DIM_TEXT)
			continue
		var hot: bool = hover[0] == col and hover[1] == i
		var afford: bool = int(row.get("cost", 0)) <= credits
		draw_rect(r, ROW_BG)
		draw_rect(r, AMBER if hot else EDGE_DIM, false, 2.0 if hot else 1.0)
		_text(str(row["label"]), r.position + Vector2(10.0, 21.0), 15, TEXT if (afford or row["kind"] == "sell") else DIM_TEXT)
		_right(str(row.get("right", "")), r, 14, GOOD if row["kind"] == "sell" else (TEXT if afford else BAD), 21.0)


## Text flush with the right edge of `r`.
func _right(text: String, r: Rect2, font_size: int, col: Color, baseline: float) -> void:
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(text, Vector2(r.end.x - w - 10.0, r.position.y + baseline), font_size, col)


## A chunky panel: a slate fill, a 2 px light border and a 1 px inner highlight.
func _panel(r: Rect2, fill := PANEL_BG) -> void:
	draw_rect(r, fill)
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-3.0), HIGHLIGHT, false, 1.0)


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
