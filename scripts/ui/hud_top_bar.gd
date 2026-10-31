extends Control
## The resource bar across the top of the screen (build and play mode): the materials, credits and fuel of the
## cargo (palette.gd BAR_IDS) with their icons, then the power supply against demand, the oxygen where the soldier
## stands and the hull integrity of the run; on the right the mode, and the pause while the world stands still
## (ShipSim.pause_line(): "PAUSED: build mode").
## The name of a figure shows under the mouse. Reads the ship through the HUD's build node; draws only.

const Palette = preload("res://scripts/build/palette.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const ICON := 20.0
const SIZE := 15  ## font size of the figures
const GAP := 18.0  ## between two figures

var hud: Control
var hover := -1  ## the figure under the mouse


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): hover = -1)


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## The figures left to right: {id (its icon), text, color, tip}.
func items() -> Array:
	var b: Node = hud.build
	var ship = b.ship
	var out := []
	for id in Palette.BAR_IDS:
		out.append({"id": id, "text": str(ship.inventory.count(id)), "color": UiKit.TEXT if ship.inventory.count(id) > 0 else UiKit.DIM_TEXT,
			"tip": ship.crafting.name_of(id, ship.components)})
	var supply := 0.0
	var demand := 0.0
	for n in ship.power_state.get("networks", []):
		supply += float(n["supply"])
		demand += float(n["demand"])
	out.append({"id": "power", "text": "%s / %s" % [Palette.num(supply), Palette.num(demand)], "color": UiKit.GOOD if supply >= demand else UiKit.BAD,
		"tip": "Power: supply / demand"})
	var o2: Dictionary = b.player_o2()
	var p: float = o2["pressure"]
	out.append({"id": "o2", "text": "--" if p < 0.0 else "%d%%%s" % [roundi(p * 100.0), " breach" if o2["breach"] else ""],
		"color": UiKit.DIM_TEXT if p < 0.0 else (UiKit.BAD if o2["breach"] or p < 0.5 else (UiKit.O2_LOW if p < 0.85 else UiKit.TEXT)),
		"tip": "Oxygen where you stand"})
	var hull := _hull()
	out.append({"id": "hull", "text": "--" if hull.y <= 0 else "%d/%d" % [hull.x, hull.y],
		"color": UiKit.DIM_TEXT if hull.y <= 0 else UiKit.BAD.lerp(UiKit.GOOD, float(hull.x) / float(hull.y)), "tip": "Hull integrity"})
	return out


## Hull integrity left and max from the run (campaign.gd), or (0, 0) before a run has begun.
func _hull() -> Vector2i:
	var d = hud.build.drift
	var c = d.get("campaign") if d != null else null
	if c == null:
		return Vector2i.ZERO
	return Vector2i(c.hull_left(hud.build.ship), c.hull_max(hud.build.ship))


## Where each figure sits (local px), in items() order.
func item_rects(list: Array) -> Array:
	var out := []
	var x := 14.0
	for i in list.size():
		if i == Palette.BAR_IDS.size():
			x += 14.0  # a gap before the ship's figures
		var w := ICON + 6.0 + UiKit.text_width(list[i]["text"], SIZE)
		out.append(Rect2(x, 0, w, size.y))
		x += w + GAP
	return out


## The words on the right: the mode, and the pause while the world stands still.
func status() -> Array[String]:
	var out: Array[String] = ["BUILD MODE" if hud.build.build_on else "PLAY MODE"]
	var sim: Node = hud.build.sim
	var pause: String = sim.pause_line() if sim != null and sim.has_method("pause_line") else ""
	if pause != "":
		out.append(pause)
	return out


func _gui_input(e: InputEvent) -> void:
	if hud.pass_release(e):
		return
	if e is InputEventMouseMotion:
		hover = -1
		var rs := item_rects(items())
		for i in rs.size():
			if rs[i].has_point(e.position):
				hover = i


func _draw() -> void:
	if hud == null or hud.build == null or hud.build.ship == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	if not UiKit.nine(self, "title_bar", r):
		draw_rect(r, Color(UiKit.PANEL_BG, 0.96))
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), UiKit.EDGE, 2.0)
		draw_line(Vector2(0, 1), Vector2(size.x, 1), UiKit.HIGHLIGHT, 1.0)
	var list := items()
	var rs := item_rects(list)
	for i in list.size():
		var q: Rect2 = rs[i]
		if i == hover:
			draw_rect(q.grow_individual(4, -5, 4, -5), Color(1, 1, 1, 0.07))
		UiKit.icon(self, list[i]["id"], Rect2(q.position.x, (size.y - ICON) / 2.0, ICON, ICON))
		UiKit.text(self, list[i]["text"], Vector2(q.position.x + ICON + 6.0, size.y / 2.0 + 6.0), SIZE, list[i]["color"])
		if i == Palette.BAR_IDS.size():
			draw_line(Vector2(q.position.x - 16.0, 9), Vector2(q.position.x - 16.0, size.y - 9), UiKit.EDGE_DIM, 1.0)
	var x := size.x - 14.0
	var st := status()
	for j in range(st.size() - 1, -1, -1):
		var paused := j > 0  # the pause, after the mode
		var w := UiKit.text_width(st[j], 13, UiKit.bold()) + (40.0 if paused else 0.0)
		var at := Vector2(x - w, size.y / 2.0 + 5.0)
		if paused:
			var pill := Rect2(x - w, 8, w, size.y - 16)
			draw_rect(pill, Color(UiKit.AMBER, 0.2))
			draw_rect(pill, UiKit.AMBER, false, 1.0)
			UiKit.icon(self, "pause", Rect2(pill.position.x + 6, pill.position.y + 3, pill.size.y - 6, pill.size.y - 6))
			at.x += 30.0
		UiKit.text(self, st[j], at, 13, UiKit.AMBER if paused else UiKit.EDGE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiKit.bold())
		x -= w + 16.0
	if hover >= 0 and hover < list.size():
		var tip: String = list[hover]["tip"]
		var tw := UiKit.text_width(tip, 12) + 14.0
		var tr := Rect2(Vector2(rs[hover].position.x, size.y + 4), Vector2(tw, 22))
		draw_rect(tr, Color(UiKit.PANEL_BG, 0.96))
		draw_rect(tr, UiKit.EDGE_DIM, false, 1.0)
		UiKit.text(self, tip, tr.position + Vector2(7, 15), 12, UiKit.TEXT)
