extends "res://tests/base_test.gd"
## The build UI (docs/waves/content_loop_1.md, priority 0.3) without a screen: the palette's tabs and cards
## (scripts/build/palette.gd), picking with the keys and the mouse, the selection card, the mode bar, the log,
## the note at the cursor while dragging, the red alert, and that no two HUD panels overlap (scripts/ui/hud.gd).

const BuildMode = preload("res://scripts/build/build_mode.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const PicCard = preload("res://scripts/ui/pic_card.gd")
const Palette = preload("res://scripts/build/palette.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Describe = preload("res://scripts/ui/describe.gd")
const RedAlert = preload("res://scripts/sim/red_alert.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const ShieldPanel = preload("res://scripts/ui/shield_panel.gd")
const CraftingPanel = preload("res://scripts/ui/crafting_panel.gd")
const HelpPanel = preload("res://scripts/ui/help_panel.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const AT := Vector2i(8, 8)


## The front door's part the HUD uses: the help panel.
class FakeFront extends Node:
	var help: Control


## A build mode on a 20x20 round hull with `cargo`, the mouse on AT, and its HUD laid out for 1600x900.
func _build(cargo := {"scrap": 200, "copper": 20}) -> BuildMode:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(20, 20), defs)
	g.fill_circle_hull(9.0)
	var ship := Ship.new("T", g)
	ship.inventory.load_dict(cargo)
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	b.selected = "floor"
	b.hover = AT
	b.hud = Hud.new()
	b.hud.setup(b)
	return b


func _done(b: BuildMode) -> void:
	b.hud.free()
	b.sim.free()
	b.free()


func _key(b: BuildMode, code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	b._on_key(e)


func _keys(cards: Array) -> Array:
	return cards.map(func(e): return e["key"])


func test_the_palette_lists_every_placeable_id_by_category() -> void:
	var b := _build()
	var ship: Ship = b.ship
	for m in ship.crafting.materials:  # a rich ship holding one of every part: everything can be placed
		ship.inventory.add(m, 1000)
	for id in ship.components.ids():
		ship.inventory.add(id, 1)
	var structure := _keys(Palette.entries(Palette.Tab.STRUCTURE, ship, b.session.cable_cost))
	for id in ship.grid.defs.ids():
		check(structure.has("tile:" + id), "Structure has the tile " + id)
	check(structure.has("cable"), "and the cable")
	var shapes := _keys(Palette.entries(Palette.Tab.SHAPES, ship, b.session.cable_cost))
	for id in ship.grid.defs.ids():
		for p in Shapes.piece_ids():
			var want: bool = p != Shapes.FULL and ship.grid.tile_flag(id, "solid") and not ship.grid.tile_flag(id, "door")
			eq(shapes.has("piece:%s:%s" % [p, id]), want, "Shapes has %s in %s exactly when it is a wall shape" % [p, id])
	var seen := {}
	for tab in [Palette.Tab.SYSTEMS, Palette.Tab.WEAPONS, Palette.Tab.ENGINES, Palette.Tab.UTILITY]:
		for e in Palette.entries(tab, ship, b.session.cable_cost):
			check(not seen.has(e["id"]), e["id"] + " is on one tab only")
			seen[e["id"]] = tab
	for id in ship.components.ids():
		check(seen.has(id), "a held part is on a tab: " + id)
	for id in seen:
		var fam := str(ship.components.def(id).get("family", ""))
		eq(seen[id] == Palette.Tab.WEAPONS, fam == "weapon", id + ": Weapons holds the weapons")
		eq(seen[id] == Palette.Tab.ENGINES, fam == "engine", id + ": Engines holds the engines")
	for id in ["intake_mk1", "shield_mk1", "oxygen_gen", "bed", "robot_arm", "fabricator"]:
		eq(seen.get(id), Palette.Tab.UTILITY, id + " is a utility")
	for id in ["reactor_mk1", "helm", "medbay", "radiator"]:
		eq(seen.get(id), Palette.Tab.SYSTEMS, id + " is a system")
	_done(b)


func test_the_palette_lists_only_what_can_be_placed_now() -> void:
	var b := _build({"scrap": 2})
	var ship: Ship = b.ship
	var cable: Dictionary = b.session.cable_cost
	for tab in [Palette.Tab.STRUCTURE, Palette.Tab.SHAPES]:
		for e in Palette.entries(tab, ship, cable):
			check(e["ok"], "%s is listed only because it can be paid for" % e["key"])
	var structure := _keys(Palette.entries(Palette.Tab.STRUCTURE, ship, cable))
	check(structure.has("tile:floor") and not structure.has("tile:titanium_alloy") and not structure.has("tile:heavy_armor"), "structure without the material is not listed")
	check(not _keys(Palette.entries(Palette.Tab.SHAPES, ship, cable)).any(func(k): return k.contains("titanium_alloy")), "nor are its shapes")
	ship.crafting.unlock("laser_mk2")
	for tab in [Palette.Tab.SYSTEMS, Palette.Tab.WEAPONS, Palette.Tab.ENGINES, Palette.Tab.UTILITY]:
		for e in Palette.entries(tab, ship, cable):
			check(ship.inventory.count(e["id"]) > 0, "%s is on the palette only because it is held" % e["id"])
	check(not _keys(Palette.entries(Palette.Tab.WEAPONS, ship, cable)).has("part:laser_mk2"), "a known blueprint with none held is crafting-screen business")
	eq(Palette.empty_text(Palette.Tab.WEAPONS), "No guns in the hold: craft one (C)", "an empty tab says what to do, in one line")
	ship.inventory.add("laser_mk1", 2)
	ship.inventory.add("plasma_cell", 3)
	eq(_keys(Palette.entries(Palette.Tab.WEAPONS, ship, cable)), ["part:laser_mk1"], "held, it is listed")
	eq(_keys(Palette.entries(Palette.Tab.CARGO, ship, cable)), ["part:laser_mk1", "item:plasma_cell"], "Cargo: the parts held, then the rest off the top bar")
	_done(b)


func test_a_picture_card_has_figures_and_no_name() -> void:
	var b := _build({"scrap": 40, "laser_mk1": 1, "shield_mk1": 1, "engine_mk1": 1})
	var ship: Ship = b.ship
	b.set_tab(Palette.Tab.WEAPONS)
	var pal = b.hud.palette
	var e: Dictionary = Palette.entries(Palette.Tab.WEAPONS, ship, b.session.cable_cost)[0]
	var spec: Dictionary = pal.spec_of(e, 0)
	var words: Array = PicCard.labels(spec)
	check(not words.has(e["name"]) and not spec.has("name") and not spec.has("title"), "the card carries no name")
	eq(spec["stats"].map(func(s): return s["what"]), ["Damage", "Shots a second", "Range"], "a gun: damage, rate, range")
	eq(spec["aim"], "fixed", "and its aim mark (read from the gun's data)")
	eq(spec["key"], 1, "the first card has its number key")
	eq(spec["held"], 1, "a held part shows its count")
	var shield: Dictionary = Describe.glance("shield_mk1", ship)
	eq(shield["stats"].map(func(s): return s["what"]), ["Layers", "Recharge", "HP"], "a shield: layers and recharge")
	eq(Describe.glance("engine_mk1", ship)["stats"][0]["what"], "Thrust", "an engine: thrust")
	var wall: Dictionary = Palette.glance(Palette.tile_entry(ship, "wall"), ship)
	eq(wall["stats"].map(func(s): return s["what"]), ["HP", "Mass"], "structure: hp and mass")
	var card := Palette.info(e, ship)
	check(card["title"] == e["name"] and card["what"] != "" and not card["stats"].is_empty(), "the hover card has the name, the description and the full stats")
	_done(b)


func test_cards_follow_the_cargo_and_what_it_can_pay() -> void:
	var b := _build({"scrap": 1, "laser_mk1": 2})
	var ship: Ship = b.ship
	var floor_card := Palette.tile_entry(ship, "floor")
	check(floor_card["ok"], "1 scrap pays for a floor")
	var wall := Palette.tile_entry(ship, "wall")
	check(not wall["ok"], "but not for a steel wall (2 scrap)")
	eq(wall["why"], "short of 1 scrap", "and it says what is short")
	eq(Palette.tile_entry(ship, "door")["cost"], {"scrap": 6, "copper": 2}, "a door costs its two cells")
	var laser := Palette.part_entry(ship, "laser_mk1")
	check(laser["ok"] and laser["count"] == 2, "a held part: ok, x2")
	eq(laser["out_size"], Vector2i(4, 2), "with its outside half")
	eq(laser["power"], -2, "and its power draw")
	var not_held := Palette.part_entry(ship, "laser_mk2")
	check(not not_held["ok"] and str(not_held["why"]) == "Blueprint not known", "a part not held is greyed: " + str(not_held["why"]))
	ship.crafting.unlock("laser_mk2")
	eq(Palette.part_entry(ship, "laser_mk2")["why"], "Craft at Fabricator (C)", "a known blueprint says where to craft it")
	var scrap_pw: float = float(ship.components.def("reactor_scrap_mk1")["power"]) * 0.9
	check(is_equal_approx(float(Palette.part_entry(ship, "reactor_scrap_mk1")["power"]), scrap_pw), "power is line-adjusted (the scrap line's x0.9 of its %s)" % str(scrap_pw))
	eq(Palette.part_entry(ship, "leech_laser")["line"], "unique", "a unique part has the gold border")
	eq(Palette.piece_entry(ship, "slope2", "wall")["cost"], {"scrap": 3}, "a piece costs by area, rounded up per cell")
	ship.inventory.add("scrap", 1)
	check(Palette.tile_entry(ship, "wall")["ok"], "more scrap and the wall is affordable")
	var titan := Palette.tile_entry(ship, "titanium_alloy")
	check(not titan["ok"], "no titanium, no titanium alloy")
	ship.inventory.add("titanium", 2)
	check(Palette.tile_entry(ship, "titanium_alloy")["ok"], "until titanium arrives")
	_done(b)


func test_number_keys_tab_and_t_move_through_the_palette() -> void:
	var b := _build({"scrap": 200, "engine_mk1": 1})
	eq(b.tab, Palette.Tab.STRUCTURE, "the palette opens on Structure")
	_key(b, KEY_2)
	eq([b.group, b.selected], [BuildMode.Group.TILES, "wall"], "2 picks the second card: the Steel Wall")
	_key(b, KEY_T)
	eq(b.tab, Palette.Tab.SHAPES, "T shapes the wall and the palette shows Shapes")
	eq(b.tool_key(), "piece:slope45:wall", "with the slope picked")
	for i in 3:
		_key(b, KEY_T)
	eq([b.tab, b.tool_key()], [Palette.Tab.STRUCTURE, "tile:wall"], "round to full: back on Structure")
	_key(b, KEY_TAB)
	_key(b, KEY_TAB)
	eq(b.tab, Palette.Tab.SYSTEMS, "Tab cycles the tabs")
	_key(b, KEY_TAB)
	_key(b, KEY_TAB)
	eq(b.tab, Palette.Tab.ENGINES, "to Engines")
	eq([b.group, b.sel_component], [BuildMode.Group.SYSTEMS, "engine_mk1"], "which puts its first engine in hand")
	_key(b, KEY_TAB, true)
	eq(b.tab, Palette.Tab.WEAPONS, "Shift+Tab goes back")
	_key(b, KEY_TAB)
	eq(b.sel_component, "engine_mk1", "and coming back picks what was picked there")
	b.set_tab(Palette.Tab.STRUCTURE)
	eq(b.tool_key(), "tile:wall", "Structure remembers the wall")
	var cable: Dictionary = Palette.cable_entry(b.ship, b.session.cable_cost)
	b.pick(cable)
	eq(b.group, BuildMode.Group.CABLES, "the cable card picks the cable tool")
	b.pick(Palette.item_entry(b.ship, "scrap"))
	eq(b.group, BuildMode.Group.CABLES, "a cargo item picks nothing")
	_done(b)


func test_a_click_on_a_tab_or_a_card_picks_it() -> void:
	var b := _build({"scrap": 200, "laser_mk1": 1, "pulse_mk1": 1})
	var pal: Control = b.hud.palette
	pal.click(pal.tab_rect(Palette.Tab.WEAPONS).get_center())
	eq(b.tab, Palette.Tab.WEAPONS, "a click on a tab opens it")
	pal.click(pal.list_rect().position + pal.card_rect(1).get_center())
	eq(b.sel_component, Palette.entries(Palette.Tab.WEAPONS, b.ship, b.session.cable_cost)[1]["id"], "a click on a card picks it")
	pal.hover_key = "part:laser_mk1"
	eq(b.hud.card.entry()["id"], "laser_mk1", "the card under the mouse is what the selection card shows")
	pal.hover_key = ""
	eq(b.hud.card.entry()["id"], "laser_mk1", "and stays a moment after the mouse left, so it can reach a chip")
	b.hud.card._clock += 1.0
	eq(b.hud.card.entry()["key"], b.tool_key(), "else the tool in hand")
	_done(b)


## Every card of every tab, laid out for 1600x900: the tallest card and what it says.
func _card_heights(b: BuildMode) -> Dictionary:
	var view := Vector2(1600, 900)
	var tall := {"h": 0.0, "key": ""}
	b.hud.sync(view)
	for tab in Palette.TAB_NAMES.size():
		b.tab = tab
		for e in b.hud.palette.entries():
			b.hud.palette.hover_key = e["key"]
			b.hud.sync(view)
			b.hud.sync(view)
			var h: float = b.hud.card.wanted_height()
			if h > tall["h"]:
				tall = {"h": h, "key": e["key"]}
	b.hud.palette.hover_key = ""
	return tall


func test_the_card_is_short_for_every_part() -> void:
	var cargo := {"scrap": 500, "copper": 500, "polymer": 50}
	var b := _build(cargo)
	for id in b.ship.components.ids():
		b.ship.inventory.add(id, 1)  # every part held: each has a card
		b.ship.crafting.unlock(id)
	b.build_on = true
	var tall := _card_heights(b)
	print("tallest card at 1600x900: %d px (%s), %d%% of the screen" % [tall["h"], tall["key"], roundi(tall["h"] / 9.0)])
	check(tall["h"] < 0.6 * 900.0, "the tallest card (%s, %d px) is under 60%% of the screen" % [tall["key"], tall["h"]])
	_done(b)


func test_the_card_shows_keyword_chips_and_explains_one_under_the_mouse() -> void:
	var b := _build({"scrap": 200, "laser_turret_mk1": 1})
	b.build_on = true
	b.pick(Palette.part_entry(b.ship, "laser_turret_mk1"))
	b.hud.sync(Vector2(1600, 900))
	b.hud.sync(Vector2(1600, 900))
	var card: Control = b.hud.card
	var chips: Array = card.chips()
	check(chips.size() >= 3, "the keyword chips: %d" % chips.size())
	var labels: Array = chips.map(func(c): return c[1]["label"])
	check(labels.has("LASER") and labels.has("AUTO") and labels.has("RAPID"), "LASER, AUTO and RAPID: " + str(labels))
	var auto: Array = chips.filter(func(c): return c[1]["label"] == "AUTO")[0]
	card.point_at(auto[0].get_center())
	eq(card.hover_kw.get("hover"), "Aims and fires by itself. T toggles.", "the mouse on a chip says what it does")
	card.point_at(Vector2(2.0, 2.0))
	check(card.hover_kw.is_empty(), "and off it, nothing")
	var rects: Dictionary = b.hud.panel_rects()
	check(rects["card"].size.y < 0.6 * 900.0, "the card is short: %d px" % rects["card"].size.y)
	_done(b)


func test_a_weapon_cards_kind_shows_under_its_name_in_the_palette() -> void:
	var b := _build({"scrap": 200, "laser_turret_mk1": 1, "artemis_mk1": 1})
	var tags: Array = Describe.weapon_tags("laser_turret_mk1")
	eq(tags.map(func(k): return k["label"]), ["LASER", "AUTO"], "a turret card: its kind, then AUTO")
	eq(Describe.weapon_tags("artemis_mk1").map(func(k): return k["label"]), ["MISSILE"], "a missile card: its kind")
	check(tags[0]["color"] != Describe.weapon_tags("artemis_mk1")[0]["color"], "each kind has its own colour")
	_done(b)


func test_the_selection_card_shows_the_stats_of_the_selected_def() -> void:
	var b := _build({"scrap": 200, "engine_mk1": 1})
	b.pick(Palette.part_entry(b.ship, "engine_mk1"))
	var inf: Dictionary = b.hud.card.info()
	eq(inf["title"], "Concord Thruster Mk1", "the name")
	eq([inf["line"], inf["tier"]], ["Standard", 1], "the line and tier")
	var rows := {}
	for r in inf["stats"]:
		rows[r[0]] = r[1]
	eq(rows.get("Size"), "2\u00d72 (out 4\u00d72)", "the size of both halves")
	eq(rows.get("Power"), "\u22122", "the power")
	eq(rows.get("HP"), "6 (out 5)", "hp of both halves")
	eq(rows.get("Thrust"), "10", "and the key stat")
	eq(rows.get("Push"), "brakes: turn it (R)", "and where it pushes: held pointing up, it only brakes")
	check(inf["lore"] != "" and inf["what"] != "", "what it does, and one line of lore")
	check(inf["cost"] == {"scrap": 20, "copper": 10}, "the cost: " + str(inf["cost"]))
	b.rot = 2
	eq(b.hud.card.info()["stats"].filter(func(r): return r[0] == "Push")[0][1], "10 fwd, 3 side", "turned to point back, it pushes forward")
	b.pick(Palette.part_entry(b.ship, "laser_mk1"))
	rows = {}
	for r in b.hud.card.info()["stats"]:
		rows[r[0]] = r[1]
	eq([rows.get("Damage"), rows.get("Every"), rows.get("Range")], ["3", "2.1 s", "1260"], "a weapon's damage, fire rate and range")
	check(rows.get("Gimbal") == "5\u00b0", "and its aim: " + str(rows.get("Gimbal")))
	var labels: Array = b.hud.card.info()["keywords"].map(func(k): return k["label"])
	check(labels.has("LASER") and labels.has("ENERGY"), "a part's kind and damage type are chips: " + str(labels))
	b.pick(Palette.part_entry(b.ship, "shield_mk1"))
	inf = b.hud.card.info()
	check(inf["stats"].has(["Layers", "1"]), "a shield's layers")
	check(inf["keywords"].any(func(k): return k["label"] == "OVERCHARGE" and k["hover"].begins_with("Space:")), "and its ability: " + str(inf["keywords"]))
	b.pick(Palette.tile_entry(b.ship, "ablative_plating"))
	inf = b.hud.card.info()
	check(inf["keywords"].any(func(k): return k["label"] == "ABLATIVE"), "a wall's quirk is a chip")
	check(inf["stats"].has(["Resists", "energy x0.5"]), "and its resistances")
	_done(b)


func test_the_mode_bar_switches_modes() -> void:
	var b := _build()
	var main := Node.new()
	main.add_child(b)
	var craft_layer := Node.new()
	craft_layer.name = "CraftLayer"
	var craft := CraftingPanel.new()
	craft.name = "CraftingPanel"
	craft.sim = b.sim
	craft_layer.add_child(craft)
	main.add_child(craft_layer)
	b.shields = ShieldPanel.new()
	b.shields.sim = b.sim
	var front := FakeFront.new()
	front.help = HelpPanel.new()
	b.front = front
	var map := MapView.new()
	map.sim = b.sim
	map.size = Vector2(1600.0, 900.0)
	b.drift = map
	for panel in [craft, b.shields, front.help, map]:
		panel.visible = false  # as their _ready leaves them in the game
	var bar: Control = b.hud.mode_bar
	eq(b.hud.active_mode(), "build", "build mode is lit")
	bar.size = Vector2(bar.full_width(), 52.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = bar.button_rect(1).get_center()
	bar._gui_input(click)
	check(not b.build_on, "a click on Play leaves build mode")
	eq(b.hud.active_mode(), "play", "and Play is lit")
	eq(b.hud.switch_mode("build"), "build", "Build")
	check(b.build_on, "goes back")
	eq(b.hud.switch_mode("shields"), "shields", "Shields")
	check(b.shields.visible and b.hud.active_mode() == "shields", "opens the Shields tab, lit")
	b.shields.close()
	eq(b.hud.switch_mode("crafting"), "crafting", "Crafting")
	check(craft.visible and b.hud.active_mode() == "crafting", "opens the crafting panel, lit")
	craft.close()
	eq(b.hud.switch_mode("help"), "help", "Help")
	check(front.help.visible and b.hud.active_mode() == "help", "opens How to play, lit")
	front.help.close()
	eq(b.hud.switch_mode("map"), "map", "Map")
	check(map.visible and not b.build_on, "opens the map, out of build mode")
	eq(b.hud.active_mode(), "map", "lit")
	b.combat = true
	eq(b.hud.switch_mode("build"), "", "nothing switches in a fight")
	b.combat = false
	main.remove_child(b)
	for n in [map, front.help, front, b.shields, main]:
		n.free()
	_done(b)


func test_no_hud_panels_overlap() -> void:
	var b := _build({"scrap": 200, "laser_mk1": 1, "pulse_mk1": 1})
	for i in 12:
		b.ship.log_event("a long chronicle line about something that happened on the ship, number %d" % i)
	for view in [Vector2(1600, 900), Vector2(1280, 720)]:
		for on in [true, false]:
			for folded in [false, true]:
				b.build_on = on
				b.hud.log_panel.collapsed = folded
				b.pick(Palette.part_entry(b.ship, "laser_mk1"))
				b.message = "a message long enough to wrap over the hints: " + "words ".repeat(40)
				b.hud.sync(view)
				var rects: Dictionary = b.hud.panel_rects()
				var tag := "%s %s%s" % [str(view), "build" if on else "play", " folded" if folded else ""]
				eq(rects.has("palette"), on, tag + ": the palette only in build mode")
				eq(rects.has("card"), on, tag + ": the card only in build mode")
				for n in ["top_bar", "mode_bar", "log_panel", "hints"]:
					check(rects.has(n), tag + ": shows " + n)
				var names: Array = rects.keys()
				for i in names.size():
					var r: Rect2 = rects[names[i]]
					check(Rect2(Vector2.ZERO, view).encloses(r), "%s: %s is on screen" % [tag, names[i]])
					check(r.size.x > 0.0 and r.size.y > 0.0, "%s: %s has room" % [tag, names[i]])
					for j in range(i + 1, names.size()):
						check(not r.intersects(rects[names[j]]), "%s: %s and %s do not overlap" % [tag, names[i], names[j]])
	_done(b)


func test_a_wall_drag_shows_its_count_and_cost_at_the_cursor() -> void:
	var b := _build({"scrap": 9})
	_key(b, KEY_2)  # the Steel Wall, 2 scrap
	b.dragging = true
	b.drag_button = MOUSE_BUTTON_LEFT
	b.drag_mode = BuildSession.Mode.LINE
	b.drag_start = Vector2i(4, 8)
	b.hover = Vector2i(7, 8)
	b._refresh_ghost()
	eq(b.cursor_note(), {"text": "4 cells, costs 8 scrap", "bad": false}, "four walls, before the release")
	b.hover = Vector2i(8, 8)
	b._refresh_ghost()
	eq(b.cursor_note(), {"text": "4 cells, costs 8 scrap, 1 refused: not enough scrap", "bad": true}, "a fifth is more than the cargo holds")
	b.dragging = false
	b.hover = Vector2i(0, 0)
	b._refresh_ghost()
	eq(b.cursor_note(), {"text": "can't: outside the hull", "bad": true}, "a hover that can't be built says why")
	b.hover = AT
	b._refresh_ghost()
	eq(b.cursor_note(), {"text": "", "bad": false}, "a hover that can says nothing")
	eq(b.hud.wanted_cursor(Vector2(800, 400)), "place", "and the cursor is the place reticle")
	b.hover = Vector2i(0, 0)
	b._refresh_ghost()
	eq(b.hud.wanted_cursor(Vector2(800, 400)), "invalid", "a refused one shows the no-entry cursor")
	eq(b.hud.wanted_cursor(Vector2(100, 400)), "", "over the palette the system cursor is back")
	_done(b)


func test_preview_cost_is_what_the_cargo_would_pay() -> void:
	var b := _build({"scrap": 20})
	var s: BuildSession = b.session
	s.apply(s.plan(BuildSession.Mode.LINE, "floor", false, Vector2i(5, 5), Vector2i(7, 5))["changes"])
	s.preview(s.plan(BuildSession.Mode.LINE, "wall", false, Vector2i(5, 5), Vector2i(8, 5))["changes"])
	eq(s.last_preview_cost, {"scrap": 5}, "three floors become walls (1 more each) and one new wall (2)")
	s.preview(s.plan(BuildSession.Mode.LINE, "floor", true, Vector2i(5, 5), Vector2i(6, 5))["changes"])
	eq(s.last_preview_cost, {"scrap": -2}, "removing two floors gives 2 back")
	eq(b.ship.inventory.count("scrap"), 17, "and the cargo is as it was")
	_done(b)


func test_red_alert_refuses_build_mode_near_a_hostile() -> void:
	eq(RedAlert.alert_range(), 2500.0, "2,500 px, from data/build.json")
	eq(RedAlert.can_build({"at": Vector2.ZERO, "hostiles": []}), "", "no hostiles: build away")
	eq(RedAlert.can_build({"at": Vector2(100, 100), "hostiles": [Vector2(100, 2601)]}), "", "one 2,501 px off is far enough")
	eq(RedAlert.can_build({"at": Vector2(100, 100), "hostiles": [Vector2(9000, 0), Vector2(100, 2500)]}), RedAlert.REASON, "one at 2,400 px is not")
	var b := _build()
	b.set_build(false)
	var near := [Vector2(1200, 0)]
	b.hostiles_source = func() -> Array: return near
	eq(b.can_build(), "Red alert: hostiles too close to build", "a hostile from sector space")
	_key(b, KEY_B)
	check(not b.build_on, "B is refused")
	eq(b.message, RedAlert.REASON, "and says why")
	eq(b.hud.switch_mode("build"), "build", "the mode bar's Build")
	check(not b.build_on, "is refused too")
	near[0] = Vector2(4000, 0)
	_key(b, KEY_B)
	check(b.build_on, "once it is far off, B works")
	near[0] = Vector2(10, 0)
	_key(b, KEY_B)
	check(not b.build_on, "and leaving build mode is never refused")
	_done(b)


func test_the_log_folds_and_shows_the_crew() -> void:
	var b := _build()
	var log: Control = b.hud.log_panel
	check(log.lines()[0][0].begins_with("Crew: "), "the crew line comes first")
	b.ship.log_event("Hull breached")
	check(log.lines().back()[0].ends_with("Hull breached"), "the newest chronicle line last")
	var open_h: float = log.wanted_height()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(20, 10)
	log._gui_input(click)
	check(log.collapsed and log.wanted_height() < open_h, "a click on the title folds it")
	log._gui_input(click)
	check(not log.collapsed, "and opens it again")
	_done(b)


func test_the_top_bar_shows_the_cargo_and_the_pause() -> void:
	var b := _build({"scrap": 120, "copper": 7, "credits": 300, "fuel": 4})
	var items: Array = b.hud.top_bar.items()
	var ids: Array = items.map(func(it): return it["id"])
	eq(ids, Palette.BAR_IDS + ["power", "o2"], "the materials, credits and fuel, then power and O2: no hull figure, and no wrench while nothing is damaged")
	eq([items[0]["text"], items[1]["text"], items[6]["text"], items[7]["text"]], ["120", "7", "300", "4"], "with the cargo's counts")
	eq(b.hud.top_bar.status(), ["BUILD MODE", "PAUSED: build mode"] as Array[String], "build mode pauses the world and the top bar says so")
	b.set_build(false)
	eq(b.hud.top_bar.status(), ["PLAY MODE"] as Array[String], "play mode runs it")
	_done(b)


# --- the fabricator's upgrade card -----------------------------------------------------------------------------------

## A build mode on the test room's ship with its fabricator at (15, 10) and `stock` in the hold.
func _fab_mode(stock: Dictionary) -> Array:
	var ship := Fixture.room_ship()
	var fab := Fixture.put(ship, "fabricator", 15, 10)
	ship.inventory.load_dict(stock)
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	b.hover = Vector2i(16, 10)
	b.hud = Hud.new()
	b.hud.setup(b)
	return [b, fab]


func test_a_click_on_the_fabricator_opens_its_card_and_a_second_one_upgrades() -> void:
	var r := _fab_mode({"scrap": 200, "copper": 40, "titanium": 12})
	var b: BuildMode = r[0]
	var fab: int = r[1]
	b.group = BuildMode.Group.SYSTEMS
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	eq(b.upgrade_uid, -1, "no card at first")
	check(b._fab_click(click), "the click on the fabricator is used up")
	eq(b.upgrade_uid, fab, "its card is open")
	eq(int(b.ship.components.instances[fab]["fab_level"]), 1, "nothing is paid by the first click")
	check(b._fab_click(click), "the second click too")
	eq(int(b.ship.components.instances[fab]["fab_level"]), 2, "paid and upgraded")
	check(b.upgrade_flash > 0.0, "with a flash")
	eq(b.ship.inventory.count("scrap"), 120, "80 scrap paid")
	b.hover = Vector2i(3, 3)  # elsewhere
	check(not b._fab_click(click), "a click elsewhere is not used up")
	eq(b.upgrade_uid, -1, "and closes the card")
	_done(b)


func test_a_click_on_the_fabricator_works_on_every_palette_tab() -> void:
	# (the default tab is Tiles: the owner's click used to fall through to a tile drag there and do nothing)
	for g in [BuildMode.Group.TILES, BuildMode.Group.CABLES, BuildMode.Group.BELTS, BuildMode.Group.SYSTEMS]:
		var r := _fab_mode({"scrap": 200, "copper": 40, "titanium": 12})
		var b: BuildMode = r[0]
		b.group = g
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		check(b._fab_click(click), "the click is used up on tab %d" % g)
		eq(b.upgrade_uid, r[1], "and opens the card on tab %d" % g)
		_done(b)


func test_u_over_the_fabricator_works_like_the_click_and_a_short_hold_refuses() -> void:
	var r := _fab_mode({"scrap": 200, "copper": 40, "titanium": 7})
	var b: BuildMode = r[0]
	var fab: int = r[1]
	_key(b, KEY_U)
	eq(b.upgrade_uid, fab, "U opens the card")
	_key(b, KEY_U)
	eq(int(b.ship.components.instances[fab]["fab_level"]), 1, "short of titanium: not upgraded")
	check(b.message != "", "with a reason: " + b.message)
	eq(b.ship.inventory.count("scrap"), 200, "nothing paid")
	b.ship.inventory.add("titanium", 1)
	_key(b, KEY_U)
	eq(int(b.ship.components.instances[fab]["fab_level"]), 2, "with enough, it goes")
	_done(b)


func test_the_crafting_panels_fabricator_line() -> void:
	eq(CraftingPanel.fab_line({"level": 2, "tools": ["laser_cutter"], "speed": 1.25}), "Level 2 · Tools: laser cutter · Speed +25%", "level, tools, speed")
	eq(CraftingPanel.fab_line({"level": 1, "tools": [], "speed": 1.0}), "Level 1 · Tools: none · Speed +0%", "bare")
