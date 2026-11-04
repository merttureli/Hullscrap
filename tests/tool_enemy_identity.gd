extends SceneTree
## Not a test. The enemy identity prototype's two pictures (needs a window: xvfb-run -a, not --headless):
##  enemy_identity_lineup.png: one medium stage 3 ship of each race / faction side by side, emblem and name line under each;
##  enemy_identity_card_<id>.png: a mock of the pre-fight contact card: the enemy ship, your ship's silhouette at the same scale, the emblem and the name line.
##   xvfb-run -a godot --path . --script res://tests/tool_enemy_identity.gd [-- out=/home/user/hs/shots cards=kett,rustfangs]

const Shipgen = preload("res://scripts/space/shipgen.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")
const Emblem = preload("res://scripts/view/emblem.gd")
const Gallery = preload("res://tests/tool_enemy_gallery.gd")
const Session = preload("res://scripts/combat/combat_session.gd")

const IDS := ["kett", "prismatic", "grundl", "rustfangs", "clans", "lumen", "wardens"]
const PLAYER := "res://data/ships/starter_courier.json"


class Labels extends Node2D:
	var items: Array = []  # {kind: "text"|"emblem"|"hull"|"rect", ...}
	func _draw() -> void:
		for it in items:
			match it["kind"]:
				"rect":
					draw_rect(it["r"], it["col"], it.get("fill", true), it.get("w", 1.0))
				"text":
					draw_string(ThemeDB.fallback_font, it["at"], it["s"], HORIZONTAL_ALIGNMENT_LEFT, it.get("w", -1.0), it.get("size", 14), it["col"])
				"emblem":
					Emblem.draw(self, it["e"], it["r"], it["col"], it.get("lw", 0.0))
				"hull":  # a flat silhouette of a ship's tiles
					for c in it["cells"]:
						draw_rect(Rect2(it["o"] + Vector2(c) * it["k"], Vector2(it["k"], it["k"])), it["col"])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "/home/user/hs/shots"
	var cards: Array = ["kett", "rustfangs"]
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("out="):
			out = str(a).substr(4)
		if str(a).begins_with("cards="):
			cards = str(a).substr(6).split(",")
	await lineup(out + "/enemy_identity_lineup.png")
	await lineup_all(out + "/enemy_identity_all.png")
	for id in cards:
		await card(id, "%s/enemy_identity_card_%s.png" % [out, id])
	quit(0)


func _ship(id: String, size := "medium", seed_value := 7):
	return Shipgen.build(id, size, seed_value, Gallery.budget_of(id, 3), {"stage": 3})


func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color("#0b0e14")
	bg.size = Vector2(size)
	vp.add_child(bg)
	return vp


func _view(vp: SubViewport, ship, at: Vector2, k: float) -> void:
	var v := ShipView.new()
	v.skin_on = true
	v.scale = Vector2(k / ShipView.CELL, k / ShipView.CELL)
	vp.add_child(v)
	v.show_ship(ship)
	var hb: Rect2 = Gallery.hull_box(ship)
	v.position = at - (hb.position + Vector2(hb.size.x / 2.0, 0.0) - v.pivot) * k


func _save(vp: SubViewport, path: String) -> void:
	for i in 6:
		await process_frame
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	vp.get_texture().get_image().save_png(path)
	print("wrote ", path)
	vp.queue_free()
	await process_frame


func lineup(path: String) -> void:
	var k := 7.0
	var cw := 310
	var vp := _viewport(Vector2i(cw * IDS.size(), 400))
	var lab := Labels.new()
	vp.add_child(lab)
	for i in IDS.size():
		var ship = _ship(IDS[i])
		var look: Dictionary = ship.get_meta("style")
		_view(vp, ship, Vector2(i * cw + cw / 2.0, 40.0), k)
		lab.items.append({"kind": "emblem", "e": look["emblem"], "r": Rect2(i * cw + cw / 2.0 - 22.0, 305.0, 44.0, 44.0), "col": look["palette"]["mark"], "lw": 3.0})
		lab.items.append({"kind": "text", "at": Vector2(i * cw + 10.0, 380.0), "s": look["line"], "col": Color("#dfe8f5"), "size": 16, "w": cw - 20.0})
	await _save(vp, path)


func card(id: String, path: String) -> void:
	var k := 7.0
	var vp := _viewport(Vector2i(760, 460))
	var lab := Labels.new()
	vp.add_child(lab)
	var enemy = _ship(id, "medium", 7)
	var look: Dictionary = enemy.get_meta("style")
	var mine = Session.load_ship(PLAYER)
	lab.items.append({"kind": "rect", "r": Rect2(6, 6, 748, 448), "col": Color("#141a24")})
	lab.items.append({"kind": "rect", "r": Rect2(6, 6, 748, 448), "col": look["palette"]["mark"], "fill": false, "w": 2.0})
	lab.items.append({"kind": "emblem", "e": look["emblem"], "r": Rect2(22.0, 18.0, 44.0, 44.0), "col": look["palette"]["mark"], "lw": 3.0})
	lab.items.append({"kind": "text", "at": Vector2(78.0, 40.0), "s": look["line"], "col": Color("#eef3fb"), "size": 22})
	lab.items.append({"kind": "text", "at": Vector2(78.0, 60.0), "s": "contact: %s" % ("home race" if look["race"] != "" else "gang"), "col": Color("#8696b0"), "size": 12})
	_view(vp, enemy, Vector2(230.0, 100.0), k)
	_view(vp, mine, Vector2(560.0, 100.0), k)  # your ship at the same scale, its own art
	lab.items.append({"kind": "text", "at": Vector2(530.0, 440.0), "s": "your ship", "col": Color("#8696b0"), "size": 12})
	await _save(vp, path)


## Every style (the 30 races and the 8 factions) on one sheet: a medium stage 3 ship each, 8 to a row, its emblem and name line under it.
func lineup_all(path: String) -> void:
	var ids: Array = []
	for id in Shipgen.factions():
		if Shipgen.tables()["factions"][id].has("style"):
			ids.append(id)
	var k := 5.0
	var cw := 260
	var ch := 330
	var cols := 8
	var rows := int(ceil(float(ids.size()) / cols))
	var vp := _viewport(Vector2i(cw * cols, ch * rows))
	var lab := Labels.new()
	vp.add_child(lab)
	for i in ids.size():
		var ship = _ship(ids[i])
		if ship == null:
			continue
		var look: Dictionary = ship.get_meta("style")
		var ox := (i % cols) * cw
		var oy := (i / cols) * ch
		_view(vp, ship, Vector2(ox + cw / 2.0, oy + 24.0), k)
		lab.items.append({"kind": "emblem", "e": look["emblem"], "r": Rect2(ox + 10.0, oy + ch - 58.0, 34.0, 34.0), "col": look["palette"]["mark"], "lw": 2.5})
		lab.items.append({"kind": "text", "at": Vector2(ox + 50.0, oy + ch - 36.0), "s": look["line"], "col": Color("#dfe8f5"), "size": 14, "w": cw - 56.0})
	await _save(vp, path)
