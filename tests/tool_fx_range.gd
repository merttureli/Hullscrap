extends SceneTree
## Not a test (the runner only loads test_*.gd). The weapon effects test range: the real combat view, one panel per effect,
## each firing at the same target hull, saved as PNGs and one contact sheet. Needs a window (xvfb), not --headless:
##   xvfb-run -a godot --path . --script res://tests/tool_fx_range.gd [-- <out dir> [<effect> ...]]
## Writes <out dir>/fx_<effect>.png for each effect, and fx_sheet.png (default out dir /home/user/hs/shots/fx-effects).
## Each panel: a courier (left, below) shoots the Rustfang raider (above) with a virtual gun whose entry is in PANELS, a
## moment after the hit.

const Ship = preload("res://scripts/ship/ship.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Projectiles = preload("res://scripts/combat/projectiles.gd")
const Damage = preload("res://scripts/combat/damage.gd")

const COURIER := "res://data/ships/starter_courier.json"
const STEP := 1.0 / 60.0
## effect -> [the gun's entry, seconds to run after the shot lands]. The guns are what the racial weapons will be: a slag bolt,
## a splinter flak, a sonic laser ...
const PANELS := {
	"acid": [{"kind": "bolt", "speed": 900, "damage": 1.0, "damage_type": "kinetic", "effects": {"acid": {"dps": 1.0, "seconds": 3.0}}}, 0.7],
	"spores": [{"kind": "bolt", "speed": 900, "damage": 0.5, "effects": {"spores": {"o2_drain": 0.08, "seconds": 5.0}}}, 0.6],
	"shard": [{"kind": "bolt", "speed": 900, "damage": 1.0, "damage_type": "kinetic", "effects": {"shard": {"splinters": 4, "dmg": 0.6}}}, 0.12],
	"sonic": [{"kind": "laser", "damage": 0.5, "effects": {"sonic": {"stun_s": 3.0}}}, 0.25],
	"magnetic": [{"kind": "bolt", "speed": 900, "damage": 0.5, "damage_type": "kinetic", "effects": {"magnetic": {"pull": 80.0}}}, 0.2],
	"frost": [{"kind": "laser", "damage": 0.5, "effects": {"frost": {"slow": 0.5, "seconds": 5.0}}}, 0.3],
	"corrode": [{"kind": "bolt", "speed": 900, "damage": 1.0, "damage_type": "kinetic", "effects": {"corrode": {"resist_mult": 0.5, "seconds": 8.0}}}, 0.3],
	"self_room": [{"kind": "laser", "damage": 0.5, "effects": {"self_room": {"o2_drain": 0.3, "heat": 30.0, "fire_chance": 1.0, "shock_dps": 2.0}}}, 0.3],
}

var out_dir := "/home/user/hs/shots/fx-effects"
var only: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
		only = args.slice(1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	for n in ["FrontDoor", "ToastLayer", "MenuLayer", "OverLayer", "HelpLayer", "PickerLayer", "CraftLayer"]:  # the menu is not what we shoot
		if main.has_node(n):
			main.get_node(n).queue_free()
	await process_frame
	await process_frame
	paused = false  # the front door set it while its menu was up
	var sim: Node = main.get_node("ShipSim")
	var combat: Node = main.get_node("Combat")
	sim.set_process(false)
	combat.set_process(false)
	var shots := []
	for name in PANELS:
		if not only.is_empty() and not name in only:
			continue
		sim.choose_ship(COURIER)
		var why: String = combat.enter()
		if why != "":
			printerr("cannot enter: ", why)
			quit(1)
			return
		combat.active = false  # this script drives the frames, not the view (no pilot, no input)
		await _panel(sim, combat, name)
		var img := root.get_texture().get_image()
		var path := "%s/fx_%s.png" % [out_dir, name]
		img.save_png(path)
		shots.append([name, img])
		print("saved ", path)
		combat.active = true
		combat.leave()
	_sheet(shots)
	quit()


## One panel: set the fight up, fire, run `seconds`, and leave the view drawn.
func _panel(sim: Node, combat: Node, name: String) -> void:
	var session = combat.session
	var arena = session.arena
	arena.autofire = {0: false, 1: false}
	var panel: Array = PANELS[name]
	var player = arena.ships[0]
	var foe = arena.ships[1]
	foe.flight.pos = Vector2(40.0, -720.0)
	foe.flight.angle = PI
	foe.flight.vel = Vector2.ZERO
	foe.ion_lock = 1.0e6  # the pirate's shield would stop the shots: keep it offline
	var entry: Dictionary = {"cooldown": 0.0, "range": 2400, "gimbal": 180, "damage_type": "energy"}
	entry.merge(panel[0], true)
	entry["effects"] = panel[0]["effects"]
	arena.weapons.defs["fx_range"] = entry
	# the gun sits in a room of the courier (for self_room), else just ahead of the bow
	var at: Vector2 = player.pivot + Vector2(0.0, -4.0)
	var rooms: Array = player.ship.atmosphere.rooms
	if name == "self_room" and not rooms.is_empty():
		var best: Dictionary = rooms[0]
		for r in rooms:
			if r["size"] > best["size"]:
				best = r
		at = Vector2(best["cells"][best["cells"].size() / 2]) + Vector2(0.5, 0.5)
	for u in player.mounts.keys():  # the courier's own guns would draw their aiming cones over the picture
		if not player.mounts[u]["virtual"]:
			player.mounts.erase(u)
	var uid: int = arena.add_mount(0, "fx_range", at)
	combat.aim_override = Vector2(90000.0, 90000.0)  # the crosshair off the picture
	for k in 30:  # settle the camera on both ships
		_frame(sim, combat, 0.0)
	var aim: Vector2 = _wall_in_view(arena, arena.weapons.muzzle_of(arena, 0, player.mounts[uid]))
	arena.ships[0].cooldowns.clear()
	arena.fire(0, uid, aim)
	for k in 240:  # until the shot lands (a bolt takes about 0.6 s), or the gun's own room feels it
		_frame(sim, combat, STEP)
		if arena.events.any(func(e): return e["type"] == "effect"):
			break
	for k in int(float(panel[1]) / STEP):  # then the aftermath
		_frame(sim, combat, STEP)
	var cam: Camera2D = combat.cam  # then close on the target (on the shooter for its own side effects)
	cam.position = arena.local_to_world(0, at) if name == "self_room" else aim + Vector2(0.0, -70.0)
	cam.zoom = Vector2(1.2, 1.2)
	combat._fx_node.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


## The world point of a plain wall cell near the middle of the foe (ship 1) that a shot from `from` meets first, so the panel
## shows the effect on the hull and not on a gun that sticks out of it.
func _wall_in_view(arena, from: Vector2) -> Vector2:
	var foe = arena.ships[1]
	var best := Vector2.INF
	var best_d := INF
	for c in arena.weapons.facing_cells(arena, 1, from):
		var aim: Vector2 = arena.cell_to_world(1, c)
		var segment: Array = Projectiles.cells_along(arena.world_to_local(1, from), arena.world_to_local(1, aim + (aim - from).normalized() * 32.0))
		var first := {}
		for e in segment:
			first = Damage.solid_at(foe, e["c"])
			if not first.is_empty():
				if first["kind"] == "wall" and e["c"] == c:
					var d: float = absf(aim.x - foe.flight.pos.x) + 0.2 * absf(aim.y - foe.flight.pos.y)
					if d < best_d:
						best_d = d
						best = aim
				break
	return best if best != Vector2.INF else arena.cell_to_world(1, arena.weapons.facing_cells(arena, 1, from)[0])


## One frame of the fight as combat_view.frame() does it, without the pilot or the input.
func _frame(sim: Node, combat: Node, dt: float) -> void:
	var session = combat.session
	session.arena.step(maxf(dt, STEP))
	sim.step(maxf(dt, STEP))
	combat._clock += maxf(dt, STEP)
	combat._frame += 1
	combat._consume_events()
	combat._age_fx(dt)
	combat._move_camera(maxf(dt, STEP))
	combat._update_hud()
	combat._fx_node.queue_redraw()


## All panels in one picture, two to a row, each at half size.
func _sheet(shots: Array) -> void:
	if shots.is_empty():
		return
	var w: int = shots[0][1].get_width() / 2
	var h: int = shots[0][1].get_height() / 2
	var cols := 2
	var rows := (shots.size() + cols - 1) / cols
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var img: Image = shots[i][1].duplicate()
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png("%s/fx_sheet.png" % out_dir)
	print("saved ", out_dir, "/fx_sheet.png")
