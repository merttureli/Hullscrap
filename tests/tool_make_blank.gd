extends SceneTree
## Not a test (the runner only loads test_*.gd). Rebuilds the Blank frame, the hangar's build-your-own start:
##   godot --headless --path . --script res://tests/tool_make_blank.gd
## The ship is a seed, the smallest pod a crew can stand in: a 4x2 room (the helm takes the left half, the soldier stands on
## the right) in a ring of steel wall, one door in the starboard wall, and nothing else. The hull is the starters' big round
## build area (a disc of DISC_R cells round the middle of the 83x83 grid). The hold is the kit: the parts a starter has installed
## (reactor, two engines, air, a gun, a shield, a bed, a fabricator) and the materials of a hull of a starter's size.
## tests/test_blank_start.gd holds the kit to the open starters' value (docs/CONTENT.md 19).

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")

const PATH := "res://data/ships/starter_blank.json"
const COURIER := "res://data/ships/starter_courier.json"  ## its blueprints are the ones every starter knows
const GRID := Vector2i(83, 83)
const DISC_R := 38.0
const MID := Vector2i(41, 41)
const BLURB := "Ma Gantry's finest: a pod, a helm and a crate of parts. The pod is all the hull there is, a door in its side shows where the rest could go, and the bill is the same as ever. Build the ship you want, then launch."
const CREW := [{"name": "Soldier", "species": "human"}]
## The kit. Parts: the Courier's installed set. Materials: a hull of about 250 cells (steel walls, floor, titanium plates), its doors and cables.
const CARGO := {"reactor_mk2": 1, "engine_mk1": 2, "oxygen_gen": 1, "bed": 1, "pulse_mk1": 1, "shield_mk1": 1, "fabricator": 1,
	"scrap": 330, "copper": 50, "titanium": 100, "polymer": 30, "credits": 400, "fuel": 6, "hand_ammo": 10}


func _init() -> void:
	var defs := TileDefs.new()
	defs.load_file(Ship.TILES_PATH)
	var ship := Ship.new("Ship", ShipGrid.new(GRID, defs))
	ship.inventory.load_dict({"scrap": 200, "copper": 50, "helm": 1})
	var g = ship.grid
	g.fill_circle_hull(DISC_R)
	var session := BuildSession.new(ship)
	var changes := []
	for y in range(MID.y - 2, MID.y + 2):  # the ring: x 39..44, y 39..42
		for x in range(MID.x - 2, MID.x + 4):
			var ring: bool = x == MID.x - 2 or x == MID.x + 3 or y == MID.y - 2 or y == MID.y + 1
			changes.append({"layer": "tile", "cell": Vector2i(x, y), "to": "wall" if ring else "floor"})
	_apply(session, changes, "pod")
	_apply(session, [{"layer": "tile", "cell": Vector2i(MID.x + 3, MID.y - 1), "to": "door", "axis": Vector2i.DOWN}], "door")
	_apply(session, [{"layer": "component", "id": "helm", "anchor": Vector2i(MID.x - 1, MID.y - 1), "rot": 0}], "helm")
	ship.inventory.load_dict(CARGO)
	ship.refresh()
	var saved := ship.to_dict()
	saved["crafting"] = JSON.parse_string(FileAccess.get_file_as_string(COURIER))["crafting"]
	saved["name"] = "Blank Frame"
	saved["blurb"] = BLURB
	saved["crew"] = CREW
	saved["build_first"] = true  # the run opens in build mode and cannot leave its first node until the ship can fly (docs/CONTENT.md 19)
	saved["hangar"] = {"group": "Your own", "layout": "A", "unlock": ""}
	var keys := saved.keys()
	keys.sort()
	var lines := []
	for k in keys:
		if k == "tiles":
			lines.append("\"tiles\": [\n" + ",\n".join(saved[k].map(func(t): return "\t" + JSON.stringify(t))) + "\n]")
		else:
			lines.append("%s: %s" % [JSON.stringify(k), JSON.stringify(saved[k], "", true)])
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{\n" + ",\n".join(lines) + "\n}\n")
	f.close()
	print("wrote ", PATH, ": ", g.tiles.size(), " tiles, hull ", g.hull.size())
	quit()


func _apply(session: BuildSession, changes: Array, what: String) -> void:
	var r := session.apply(changes)
	if r["skipped"] > 0:
		push_error("%s: %d of %d changes refused: %s" % [what, r["skipped"], changes.size(), r["reason"]])
