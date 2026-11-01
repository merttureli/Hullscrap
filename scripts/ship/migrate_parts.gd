extends RefCounted
## Ship save version 7 (playtest 2, P2): the tier 1-2 weapons, engines, reactors, shields and the medbay take less room inside
## the ship. A save older than 7 holds those parts at their old size, anchored by the inside half's top-left; migrate() gives each
## one its new anchor and keeps the power (and the belts) reaching it, so an old ship loads whole. Ship.load_dict calls it for
## every save below version 7; tests/tool_migrate_parts.gd runs it over the shipped designs. Pure data in, data out (no nodes).

const Mounts = preload("res://scripts/ship/mounts.gd")

## The parts whose inside half was 4x2 (weapons, engines: now 2x2) and 4x4 (reactors, shields, the medbay: now 2x4) before version 7.
const WAS_4X2: Array = [
	"artemis_mk1", "basalt_magma_spitter", "basalt_pumice_flak", "bolt_thrower_scrap", "emberkin_cinder_mortar", "emberkin_flare_turret",
	"emberkin_pyre_drive", "emberkin_pyre_lance", "engine_mk1", "engine_mk2", "engine_neon_mk1", "engine_neon_mk2", "engine_scrap_mk1",
	"engine_scrap_mk2", "fenn_haggle_engine", "fenn_market_missile", "fenn_spark_lattice", "fenn_twitch_cannon", "gauntling_arc_hammer",
	"gauntling_overclock_engine", "gauntling_scrap_shotgun", "gauntling_tesla_picket", "grundl_barge_flak", "grundl_grapple_harpoon",
	"grundl_hauler_thrusters", "heat_lance_neon", "human_flak_screen", "human_volley_rack", "ion_blast_mk1", "kett_chitin_thrower", "kett_drone_picket",
	"kett_hive_swarm_launcher", "laser_mk1", "laser_mk2", "laser_turret_mk1", "longburn_mk1", "longburn_mk2", "mire_bog_mortar", "mire_mist_projector",
	"mire_steam_lance", "prismatic_glimmer_turret", "prismatic_prism_lens", "prismatic_refractor", "pulse_mk1", "pulse_mk2", "rattle_burst_scrap",
	"shrapnel_cannon_scrap", "siren_ion_neon", "sporeling_pollen_turret", "sporeling_rot_pod", "sporeling_spore_cannon"
]
const WAS_4X4: Array = [
	"basalt_vacuum_forge", "emberkin_furnace_core", "emberkin_hearth_shield", "fenn_jury_reactor", "gauntling_arc_core", "grundl_freight_shield",
	"human_reactor_plus", "kett_hive_battery", "kett_nest_reactor", "medbay", "mire_rain_shield", "mire_wetwell_reactor", "prismatic_lattice_shield",
	"prismatic_song_reactor", "reactor_mk1", "reactor_mk2", "reactor_neon_mk1", "reactor_scrap_mk1", "shield_mk1", "shield_mk2", "shield_neon_mk1",
	"shield_scrap_mk1", "sporeling_bloom_reactor", "sporeling_mycelium_shield"
]


## The size a part of `id` had before version 7 (width, height at rotation 0), or Vector2i.ZERO when it never changed.
static func was_size(id: String) -> Vector2i:
	if WAS_4X2.has(id):
		return Vector2i(4, 2)
	if WAS_4X4.has(id):
		return Vector2i(4, 4)
	return Vector2i.ZERO


## A copy of the save `d` (Ship.to_dict format, version below 7) with every resized part re-anchored: a hull mount moves along
## the wall to sit centred behind its barrel (Mounts.breech_shift), any other part keeps its top-left. `defs` is Components.by_id
## (the sizes now). Cable and belt cells the part's old footprint had under it, which its new one no longer covers, are
## joined on to the new footprint by a straight run of cells inside the old one, so every network still reaches the part.
static func migrate(d: Dictionary, defs: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	var parts = out.get("components")
	if not (parts is Dictionary and parts.get("instances") is Array):
		return out
	var cables := _cell_set(out.get("cables"))
	var belts := _cell_set(out.get("belts"))
	for inst in parts["instances"]:
		if not (inst is Dictionary and inst.get("anchor") is Array and inst["anchor"].size() == 2 and inst.has("id")):
			continue
		var id := str(inst["id"])
		var was := was_size(id)
		if was == Vector2i.ZERO or not defs.has(id):
			continue
		var def: Dictionary = defs[id]
		var rot := posmod(int(inst.get("rot", 0)), 4)
		var anchor := Vector2i(int(inst["anchor"][0]), int(inst["anchor"][1]))
		var isz := Mounts.turned(def["size"], rot)
		var moved := anchor
		if Mounts.is_mount(def):
			moved += Mounts.breech_shift(Mounts.turned(def["mount"]["outside"], rot), isz, rot)
		inst["anchor"] = [moved.x, moved.y]
		var was_rect := Rect2i(anchor, Mounts.turned([was.x, was.y], rot))
		var now_rect := Rect2i(moved, isz)
		_join(cables, was_rect, now_rect)
		_join_belts(belts, was_rect, now_rect)
	if out.get("cables") is Dictionary:
		out["cables"]["cells"] = _cell_list(cables)
	if out.get("belts") is Dictionary and not belts.is_empty():
		out["belts"]["cells"] = _cell_list(belts)
	return out


## Every cell of `cells` inside `was` but outside `now` is joined to `now` by an L-shaped run of cells inside `was`.
static func _join(cells: Dictionary, was: Rect2i, now: Rect2i) -> void:
	var lost: Array[Vector2i] = []
	for c in cells:
		if was.has_point(c) and not now.has_point(c):
			lost.append(c)
	for c in lost:
		var to := Vector2i(clampi(c.x, now.position.x, now.end.x - 1), clampi(c.y, now.position.y, now.end.y - 1))
		var at := c
		while at.x != to.x:
			at.x += signi(to.x - at.x)
			cells[at] = true
		while at.y != to.y:
			at.y += signi(to.y - at.y)
			cells[at] = true


## A belt cell beside the old footprint, next to a cell the new one gave up, is carried on across those cells until it touches
## the new footprint (belts feed a part through any of its edge cells).
static func _join_belts(cells: Dictionary, was: Rect2i, now: Rect2i) -> void:
	if cells.is_empty():
		return
	var joins: Array[Vector2i] = []
	for c in cells:
		if was.has_point(c):
			continue
		for d in Mounts.OUTWARD:
			var n: Vector2i = c + d
			if was.has_point(n) and not now.has_point(n) and not joins.has(n):
				joins.append(n)
	for n in joins:
		var to := Vector2i(clampi(n.x, now.position.x, now.end.x - 1), clampi(n.y, now.position.y, now.end.y - 1))
		var at := n
		cells[at] = true
		while not _touches(at, now):
			at += Vector2i(signi(to.x - at.x), 0) if at.x != to.x else Vector2i(0, signi(to.y - at.y))
			if now.has_point(at):
				break
			cells[at] = true


## Is `c` outside `r` with one of its four neighbours inside it?
static func _touches(c: Vector2i, r: Rect2i) -> bool:
	if r.has_point(c):
		return false
	for d in Mounts.OUTWARD:
		if r.has_point(c + d):
			return true
	return false


static func _cell_set(layer) -> Dictionary:
	var out := {}
	if layer is Dictionary and layer.get("cells") is Array:
		for p in layer["cells"]:
			if p is Array and p.size() == 2:
				out[Vector2i(int(p[0]), int(p[1]))] = true
	return out


static func _cell_list(cells: Dictionary) -> Array:
	var keys := cells.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return keys.map(func(c): return [c.x, c.y])
