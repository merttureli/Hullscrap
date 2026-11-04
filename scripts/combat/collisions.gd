extends RefCounted
## Ships are rigid bodies made of their cells (docs/CONTENT.md 4e); when they touch they push each
## other apart, spin, and hurt each other. Works on the arena (arena.gd), once per substep after the
## ships have moved, so the same inputs replay exactly: no randomness here.
## - Broad phase: the ships' bounding circles. Narrow phase: the outer solid cells (solid, with a
##   non-solid 4-neighbour) of one ship are looked up in the other's cell map, and each pair of
##   polygons (a full cell is its square, a shaped cell its real polygon) goes through SAT for the
##   overlap, the normal and the depth. Edges that sit on a face shared with another solid cell are
##   never picked as the normal, so a flat wall made of many cells pushes straight out.
## - The contacts of a pair become one: the normal and point averaged by depth. The impulse
##   j = (1 + e) * closing / (1/mA + 1/mB + angular terms) acts on both velocities and spins, about
##   each ship's centre of mass with the moment of inertia of its cells (Flight.mass_props); the
##   overlap beyond `separation_slop` is then pushed out in proportion to the inverse masses.
## - Damage above `min_speed`: E = 1/2 * reduced mass * closing^2; each ship takes E * damage_k as
##   kinetic damage, spread over its contact cells by depth, times the other side's ram multiplier
##   (ram plating 2, a battering bow 3), its own take (ram plating 0.5; the powered inertial dampener
##   0.5 for its other cells), the slope rule at the contact and the material's resist (Damage.apply).
##   Crew in rooms touching the impact take a knock; a battering bow latches on for a few seconds.
## Tuning is data/collision.json (loaded into `arena.collision`).

const Damage = preload("res://scripts/combat/damage.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")

const PATH := "res://data/collision.json"
const CELL := 32.0  ## pixels per grid cell (arena.gd)
const DEFAULTS := {"restitution": 0.2, "min_speed": 40.0, "damage_k": 6e-7, "crew_knock": 5.0, "separation_slop": 0.5, "correction": 0.8, "tether_pull": 0.2}
const NEAR := 1.4143 * CELL  ## cells whose centres are further apart than this cannot overlap
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const EDGE_EPS := 1e-6
const EVENT_POINTS := 6  ## contact points a "ram" event carries, for the effects


## The tuning of data/collision.json over the built-in defaults (all numbers).
static func load_config(path := PATH) -> Dictionary:
	var cfg := DEFAULTS.duplicate()
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			for k in DEFAULTS:
				if d.get(k) is float or d.get(k) is int:
					cfg[k] = float(d[k])
	return cfg


## Resolve every touching pair of ships for one substep, then the bow tethers.
static func step(arena, dt: float) -> void:
	var n: int = arena.ships.size()
	for i in n:
		for j in range(i + 1, n):
			_pair(arena, i, j)
	_tethers(arena, dt)


# --- hit cells ------------------------------------------------------------------------------------

## The collision cells of ship `idx`, rebuilt when its grid changed: {sig, cells (outer solid cells in
## (y, x) order), info (cell -> {p: polygon in grid coordinates, n: outward edge normals, e: per edge,
## is it exposed (not a face shared with a solid neighbour), ctr: the cell's middle from the pivot in px}), radius (px from the pivot)}.
static func hit_cells(arena, idx: int) -> Dictionary:
	var co = arena.ships[idx]
	var g = co.ship.grid
	var sig := [g.tiles.size(), g.shapes.size(), g.door_open.size(), g.breached.size(), co.ship.components.instances.size(), co.ship.components.wrecks.size()]
	if co.hit_cache.get("sig") == sig:
		return co.hit_cache
	var solid := {}
	var all: Array = g.tiles.keys()
	for uid in co.ship.components.instances:
		all.append_array(co.ship.components.instances[uid]["cells"])
		all.append_array(co.ship.components.instances[uid]["out_cells"])  # the outside half of a mount sticks out: rams hit guns first
	for c in all:
		if not Damage.solid_at(co, c, true).is_empty():  # a disabled outside half is still there
			solid[c] = true
	var cells: Array = []
	for c in solid:
		for d in SIDES:
			if not solid.has(c + d):
				cells.append(c)
				break
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var info := {}
	var far := 0.0
	for c in cells:
		var sh: Dictionary = g.shape_of(c)
		var shape := str(sh["shape"]) if not sh.is_empty() else "full"
		var rot := int(sh["rot"]) if not sh.is_empty() else 0
		var mirror := bool(sh["mirror"]) if not sh.is_empty() else false
		var local := Shapes.cell_polygon(shape, rot, mirror)
		var nrm := Shapes.edge_normals(shape, rot, mirror)
		var poly := PackedVector2Array()
		var exposed: Array = []
		for k in local.size():
			poly.append(local[k] + Vector2(c))
			far = maxf(far, (poly[k] - co.pivot).length())
			exposed.append(_exposed(g, solid, c, local[k], local[(k + 1) % local.size()]))
		info[c] = {"p": poly, "n": nrm, "e": exposed, "ctr": (Vector2(c) + Vector2(0.5, 0.5) - co.pivot) * CELL}
	co.hit_cache = {"sig": sig, "cells": cells, "info": info, "radius": far * CELL + 1.0}
	return co.hit_cache


## Is the polygon edge p -> q of cell `c` (cell-local) a free face? An edge on the cell's boundary is
## not when the neighbour across it is solid and its own polygon covers that boundary there.
static func _exposed(g, solid: Dictionary, c: Vector2i, p: Vector2, q: Vector2) -> bool:
	for s in 4:
		var line := 0.0 if s % 2 == 0 else 1.0  # SIDES order: left x=0, right x=1, up y=0, down y=1
		var on_x := s < 2
		var pa: float = p.x if on_x else p.y
		var qa: float = q.x if on_x else q.y
		if absf(pa - line) > EDGE_EPS or absf(qa - line) > EDGE_EPS:
			continue
		var nb: Vector2i = c + SIDES[s]
		if not solid.has(nb):
			return true
		var span := Vector2(minf(p.y, q.y), maxf(p.y, q.y)) if on_x else Vector2(minf(p.x, q.x), maxf(p.x, q.x))
		var lo := INF
		var hi := -INF
		for v in g.polygon_at(nb):  # the neighbour's vertices on the opposite boundary
			if absf((v.x if on_x else v.y) - (1.0 - line)) <= EDGE_EPS:
				var along: float = v.y if on_x else v.x
				lo = minf(lo, along)
				hi = maxf(hi, along)
		return not (lo <= span.x + EDGE_EPS and hi >= span.y - EDGE_EPS)
	return true


# --- narrow phase ---------------------------------------------------------------------------------

static func _pair(arena, i: int, j: int) -> void:
	var a = arena.ships[i]
	var b = arena.ships[j]
	var ha := hit_cells(arena, i)
	var hb := hit_cells(arena, j)
	if ha["cells"].is_empty() or hb["cells"].is_empty():
		return
	if a.flight.pos.distance_to(b.flight.pos) > ha["radius"] + hb["radius"]:
		return
	var contacts := _contacts(arena, i, j, ha, hb)
	if contacts.is_empty():
		return
	arena.contact_tick[i] = arena.tick
	arena.contact_tick[j] = arena.tick
	_resolve(arena, i, j, contacts)


## Every pair of overlapping cells of ships `i` and `j`: [{a, b (cells), n (world unit normal from
## a toward b), depth (px), p (world point in the overlap)}].
static func _contacts(arena, i: int, j: int, ha: Dictionary, hb: Dictionary) -> Array:
	var a = arena.ships[i]
	var b = arena.ships[j]
	var xa := Transform2D(a.flight.angle, a.flight.pos)
	var xb := Transform2D(b.flight.angle, b.flight.pos)
	var inv_b := xb.affine_inverse()
	var reach: float = hb["radius"] + NEAR
	var wa := {}
	var wb := {}
	var out: Array = []
	for ca in ha["cells"]:
		var q: Vector2 = xa * ha["info"][ca]["ctr"]
		if q.distance_squared_to(b.flight.pos) > reach * reach:
			continue
		var at: Vector2 = inv_b * q / CELL + b.pivot
		var base := Vector2i(floori(at.x), floori(at.y))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var cb: Vector2i = base + Vector2i(dx, dy)
				if not hb["info"].has(cb):
					continue
				var qb: Vector2 = xb * hb["info"][cb]["ctr"]
				if q.distance_to(qb) > NEAR:
					continue
				if not wa.has(ca):
					wa[ca] = _world(ha["info"][ca], xa, a)
				if not wb.has(cb):
					wb[cb] = _world(hb["info"][cb], xb, b)
				var s := _sat(wa[ca], wb[cb])
				if s.is_empty():
					continue
				out.append({"a": ca, "b": cb, "n": s["n"], "depth": s["depth"], "p": _overlap_point(wa[ca]["p"], wb[cb])})
	return out


## A hit-cell record in world coordinates: {p: polygon, n: normals (turned with the ship), e: exposed}.
static func _world(info: Dictionary, xf: Transform2D, co) -> Dictionary:
	var p := PackedVector2Array()
	for v in info["p"]:
		p.append(xf * ((v - co.pivot) * CELL))
	var n := PackedVector2Array()
	for v in info["n"]:
		n.append(xf.basis_xform(v))
	return {"p": p, "n": n, "e": info["e"]}


## Separating axis test of two convex polygon records (see _world): {} when they do not overlap, else
## {n: unit normal from `a` toward `b`, depth: px to move one of them along it to part them}. Only
## exposed edges can give the normal (any edge when none is exposed), the smallest depth wins.
static func _sat(a: Dictionary, b: Dictionary) -> Dictionary:
	var best := INF
	var best_n := Vector2.ZERO
	var any := INF
	var any_n := Vector2.ZERO
	for pass_no in 2:
		var src: Dictionary = a if pass_no == 0 else b
		for k in src["n"].size():
			var ax: Vector2 = src["n"][k]
			if ax == Vector2.ZERO:
				continue
			var ra := _project(a["p"], ax)
			var rb := _project(b["p"], ax)
			var o1 := ra.y - rb.x  # a ends past where b begins
			var o2 := rb.y - ra.x  # b ends past where a begins
			if o1 <= 0.0 or o2 <= 0.0:
				return {}
			var depth := minf(o1, o2)
			var n := ax if o1 < o2 else -ax
			if depth < any:
				any = depth
				any_n = n
			if src["e"][k] and depth < best:
				best = depth
				best_n = n
	if any_n == Vector2.ZERO:
		return {}
	return {"n": best_n, "depth": best} if best_n != Vector2.ZERO else {"n": any_n, "depth": any}


static func _project(p: PackedVector2Array, ax: Vector2) -> Vector2:
	var lo := INF
	var hi := -INF
	for v in p:
		var d := v.dot(ax)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)


## The middle of the overlap of polygon `pa` with the polygon record `b`: `pa` clipped by b's edges.
static func _overlap_point(pa: PackedVector2Array, b: Dictionary) -> Vector2:
	var out := pa
	for k in b["p"].size():
		var inp := out
		out = PackedVector2Array()
		if inp.is_empty():
			break
		var nrm: Vector2 = b["n"][k]
		var origin: Vector2 = b["p"][k]
		var s: Vector2 = inp[inp.size() - 1]
		var ds := nrm.dot(s - origin)
		for e in inp:
			var de := nrm.dot(e - origin)
			if de <= 0.0:
				if ds > 0.0:
					out.append(s + (e - s) * (ds / (ds - de)))
				out.append(e)
			elif ds <= 0.0:
				out.append(s + (e - s) * (ds / (ds - de)))
			s = e
			ds = de
	var sum := Vector2.ZERO
	var src := out if not out.is_empty() else pa
	for v in src:
		sum += v
	return sum / float(src.size())


# --- response -------------------------------------------------------------------------------------

## The velocity of the point `p` (world) of a ship's body.
static func point_velocity(co, p: Vector2) -> Vector2:
	return co.flight.vel + co.flight.ang_vel * (p - co.flight.pos).rotated(PI / 2.0)


## Centre of mass of a combatant in the world.
static func centre_of(co) -> Vector2:
	return co.flight.pos + ((co.com - co.pivot) * CELL).rotated(co.flight.angle)


static func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


## Apply the impulse `j` at world point `p` to a ship: its velocity (the pivot's, so the part of the
## spin about the centre of mass is taken off) and its spin.
static func _impulse(co, j: Vector2, p: Vector2) -> void:
	var c := centre_of(co)
	var dw: float = _cross(p - c, j) / co.inertia
	co.flight.vel += j / co.mass - dw * (c - co.flight.pos).rotated(PI / 2.0)
	co.flight.ang_vel += dw


## The inverse of the mass felt along unit `axis` at world point `p` by ships `a` and `b` together.
static func _inv_mass(a, b, p: Vector2, axis: Vector2) -> float:
	var ra := _cross(p - centre_of(a), axis)
	var rb := _cross(p - centre_of(b), axis)
	return 1.0 / a.mass + 1.0 / b.mass + ra * ra / a.inertia + rb * rb / b.inertia


static func _resolve(arena, i: int, j: int, contacts: Array) -> void:
	var cfg: Dictionary = arena.collision
	var a = arena.ships[i]
	var b = arena.ships[j]
	var wsum := 0.0
	var nsum := Vector2.ZERO
	var psum := Vector2.ZERO
	var deepest := 0.0
	for c in contacts:
		wsum += c["depth"]
		nsum += c["n"] * c["depth"]
		psum += c["p"] * c["depth"]
		deepest = maxf(deepest, c["depth"])
	var n: Vector2 = nsum.normalized() if nsum.length_squared() > 1e-12 else contacts[0]["n"]
	var p := psum / wsum
	var vrel := point_velocity(b, p) - point_velocity(a, p)
	var closing := -vrel.dot(n)
	if closing > 0.0:  # approaching: the impulse
		var j_mag := (1.0 + float(cfg["restitution"])) * closing / _inv_mass(a, b, p, n)
		_impulse(a, -n * j_mag, p)
		_impulse(b, n * j_mag, p)
	var push := maxf(deepest - float(cfg["separation_slop"]), 0.0) * float(cfg["correction"])
	if push > 0.0:
		var ia: float = 1.0 / a.mass
		var ib: float = 1.0 / b.mass
		a.flight.pos -= n * push * ia / (ia + ib)
		b.flight.pos += n * push * ib / (ia + ib)
	if closing >= float(cfg["min_speed"]):  # the damage is for the speed it came in at; a latch is made after the push, so it starts slack
		_hurt(arena, i, j, contacts, n, p, closing, vrel.normalized())


# --- damage ---------------------------------------------------------------------------------------

## The ram effects of one collision of `i` and `j` at closing speed `closing`: damage to each ship's
## contact cells, crew knocks, a tether if a bow hit, and the "ram" event.
static func _hurt(arena, i: int, j: int, contacts: Array, n: Vector2, p: Vector2, closing: float, vdir: Vector2) -> void:
	var cfg: Dictionary = arena.collision
	var a = arena.ships[i]
	var b = arena.ships[j]
	var mu: float = a.mass * b.mass / (a.mass + b.mass)
	var energy := 0.5 * mu * closing * closing
	arena.log_event("ram", i, Vector2i(-1, -1), {"pos": p, "energy": energy, "a": i, "b": j, "speed": closing, "n": n, "points": _contact_points(contacts)})
	var tether := 0.0
	for side in 2:
		var idx := i if side == 0 else j
		var other := j if side == 0 else i
		var co = arena.ships[idx]
		var share := {}  # my cell -> {w: depth, deal: depth x the other side's multiplier, cos: depth x |cos| of the incidence, n}
		for c in contacts:
			var mine: Vector2i = c["a"] if side == 0 else c["b"]
			var theirs: Vector2i = c["b"] if side == 0 else c["a"]
			var rec: Dictionary = share.get(mine, {"w": 0.0, "deal": 0.0, "cos": 0.0})
			rec["w"] += c["depth"]
			rec["deal"] += c["depth"] * _deal_mult(arena, other, theirs)
			rec["cos"] += c["depth"] * absf(vdir.dot(c["n"]))
			share[mine] = rec
			if _tether_s(arena, other, theirs) > tether:
				tether = _tether_s(arena, other, theirs)
		var total := 0.0
		for cell in share:
			total += share[cell]["w"]
		var budget := energy * float(cfg["damage_k"])
		var damp := _dampener(arena, idx)
		var cells: Array = share.keys()
		cells.sort_custom(func(x, y): return x.y < y.y or (x.y == y.y and x.x < y.x))
		for cell in cells:
			var rec: Dictionary = share[cell]
			var obj: Dictionary = Damage.solid_at(co, cell)
			if obj.is_empty():  # a disabled outside half is there to touch but takes nothing more: the blow goes on into the wall behind it
				cell = _behind_disabled(co, cell)
				obj = Damage.solid_at(co, cell)
			if obj.is_empty():
				continue
			var amount: float = budget * rec["deal"] / total  # its depth share of the budget x the other side's multiplier
			if obj["kind"] != "component":
				amount *= Damage.slope_factor("kinetic", rec["cos"] / rec["w"])
				var take := float(obj["def"].get("ram_take", 1.0)) if str(obj["def"].get("quirk", "")) == "ram" else float(damp["take"])
				amount *= take
			else:
				amount *= float(damp["take"])
			Damage.apply(arena, idx, cell, obj, amount, "kinetic", {"dir": vdir, "n": n if side == 1 else -n, "ram": true})
		if not damp["no_knock"]:
			_knock(arena, idx, cells, closing)
	if tether > 0.0:
		_latch(arena, i, j, p, tether)


## Up to EVENT_POINTS of the world points where the ships touch, evenly picked from `contacts`.
static func _contact_points(contacts: Array) -> Array:
	var step := maxi(1, ceili(float(contacts.size()) / EVENT_POINTS))
	var out := []
	for k in range(0, contacts.size(), step):
		out.append(contacts[k]["p"])
	return out


## The cell behind `cell` when that is part of a disabled outside half (a hull mount's barrel): the first
## cell inward of the barrel, the wall it is mounted through. `cell` itself when it is not.
static func _behind_disabled(co, cell: Vector2i) -> Vector2i:
	var parts = co.ship.components
	var uid: int = parts.at_out(cell)
	if uid < 0 or parts.outside_alive(uid):
		return cell
	var inst: Dictionary = parts.instances[uid]
	var c := cell
	if Mounts.is_angled(inst):  # on a slope: back along its true direction, half a cell at a time
		var p := Vector2(cell) + Vector2(0.5, 0.5)
		for _i in 64:
			p -= Mounts.dir_of(inst) * 0.5
			c = Vector2i(p.floor())
			if parts.at_out(c) != uid:
				break
		return c
	var step := -Mounts.outward(int(inst["rot"]))
	while parts.at_out(c) == uid:
		c += step
	return c


## What the other ship's cell `cell` multiplies the damage it does in a collision by: its ram quirk
## (tile `ram_deal`, component `stats.ram_deal`), else 1.
static func _deal_mult(arena, idx: int, cell: Vector2i) -> float:
	var obj: Dictionary = Damage.solid_at(arena.ships[idx], cell)
	if obj.is_empty():
		return 1.0
	if obj["kind"] == "component":
		var inst: Dictionary = arena.ships[idx].ship.components.instances[obj["uid"]]
		return float(arena.ships[idx].ship.components.def(inst["id"]).get("stats", {}).get("ram_deal", 1.0))
	return float(obj["def"].get("ram_deal", 1.0)) if str(obj["def"].get("quirk", "")) == "ram" else 1.0


## Seconds the other ship's cell `cell` latches on for (a battering bow's `stats.tether_s`), else 0.
static func _tether_s(arena, idx: int, cell: Vector2i) -> float:
	var obj: Dictionary = Damage.solid_at(arena.ships[idx], cell)
	if obj.is_empty() or obj["kind"] != "component":
		return 0.0
	var inst: Dictionary = arena.ships[idx].ship.components.instances[obj["uid"]]
	return float(arena.ships[idx].ship.components.def(inst["id"]).get("stats", {}).get("tether_s", 0.0))


## What ship `idx`'s powered dampeners do: {take: multiple of ram damage its plain cells take (the
## smallest `stats.ram_take`), no_knock: crew keep their feet}.
static func _dampener(arena, idx: int) -> Dictionary:
	var co = arena.ships[idx]
	var take := 1.0
	var no_knock := false
	for uid in co.ship.components.instances:
		if not co.powered.get(uid, false):
			continue
		var st: Dictionary = co.ship.components.def(co.ship.components.instances[uid]["id"]).get("stats", {})
		if st.has("ram_take"):
			take = minf(take, float(st["ram_take"]))
		if float(st.get("no_knock", 0.0)) > 0.0:
			no_knock = true
	return {"take": take, "no_knock": no_knock}


## Crew in a room that touches one of `cells` (ship `idx`) lose crew_knock hp per 100 px/s of impact.
static func _knock(arena, idx: int, cells: Array, closing: float) -> void:
	var ship = arena.ships[idx].ship
	var rooms := {}
	for c in cells:
		for d in [Vector2i.ZERO] + SIDES:
			var r: int = ship.atmosphere.room_of.get(c + d, -1)
			if r >= 0:
				rooms[r] = true
	var amount := float(arena.collision["crew_knock"]) * closing / 100.0
	for m in ship.crew:
		if rooms.has(ship.atmosphere.room_of.get(m.cell(), -1)) and not TraitSet.of(m)["no_knock"]:  # (a ballast rig keeps its wearer on their feet)
			m.hurt(amount)


# --- tethers --------------------------------------------------------------------------------------

## Latch ships `i` and `j` together at the world point `p` for `seconds` (a new latch replaces an old one).
static func _latch(arena, i: int, j: int, p: Vector2, seconds: float) -> void:
	var keep: Array = []
	for t in arena.tethers:
		if not (t["a"] == i and t["b"] == j):
			keep.append(t)
	keep.append({"a": i, "b": j, "la": arena.world_to_local(i, p), "lb": arena.world_to_local(j, p), "left": seconds})
	arena.tethers = keep


## Pull the anchors of every latch together: a velocity constraint along x and y that closes
## `tether_pull` of the gap per substep, so the ships hold fast to each other (and can still turn).
static func _tethers(arena, dt: float) -> void:
	var keep: Array = []
	for t in arena.tethers:
		t["left"] -= dt
		if t["left"] <= 0.0:
			continue
		keep.append(t)
		var a = arena.ships[t["a"]]
		var b = arena.ships[t["b"]]
		var pa: Vector2 = arena.local_to_world(t["a"], t["la"])
		var pb: Vector2 = arena.local_to_world(t["b"], t["lb"])
		var mid := (pa + pb) / 2.0
		for axis in [Vector2.RIGHT, Vector2.DOWN]:
			var vrel := (point_velocity(b, mid) - point_velocity(a, mid)).dot(axis)
			var want := -(pb - pa).dot(axis) * float(arena.collision["tether_pull"]) / dt
			var jm := (want - vrel) / _inv_mass(a, b, mid, axis)
			_impulse(a, -axis * jm, mid)
			_impulse(b, axis * jm, mid)
	arena.tethers = keep
