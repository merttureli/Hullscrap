extends RefCounted
## The light of a boarding site (board_view.gd): the textures of the flashlight cone and the round lights, and the occluders that stop
## the light at the walls. Static helpers; the textures are made once.
## occluder_rects(): the rectangles (in cells) of the wall cells that touch a floor or a door's room, each shrunk by INSET on the sides
## that face a floor, so the face of a wall stays lit when the light stops at it. Cells are merged into runs, so a station is a few hundred.

const CONE_SIZE := 192
const CONE_HALF := 0.5  ## radians: half the beam's width
const INSET := 0.3  ## cells

static var _cone: ImageTexture = null
static var _round: GradientTexture2D = null


## The flashlight: a beam along +x from the middle of the image, strongest at the source, gone at the edge.
static func cone_texture() -> ImageTexture:
	if _cone == null:
		var img := Image.create(CONE_SIZE, CONE_SIZE, false, Image.FORMAT_RGBA8)
		var h := CONE_SIZE / 2.0
		for y in CONE_SIZE:
			for x in CONE_SIZE:
				var dx := (x + 0.5 - h) / h
				var dy := (y + 0.5 - h) / h
				var r := sqrt(dx * dx + dy * dy)
				var v := 0.0
				if r < 1.0:
					var a := absf(atan2(dy, dx))
					var beam := clampf((CONE_HALF - a) / (CONE_HALF * 0.55), 0.0, 1.0)
					beam = beam * beam * (3.0 - 2.0 * beam)
					var fall := pow(1.0 - r, 1.15)
					v = beam * fall
				img.set_pixel(x, y, Color(v, v, v, 1.0))
		_cone = ImageTexture.create_from_image(img)
	return _cone


## A round light that fades to nothing at its edge.
static func round_texture() -> GradientTexture2D:
	if _round == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(0, 0, 0, 1))
		_round = GradientTexture2D.new()
		_round.gradient = g
		_round.width = 128
		_round.height = 128
		_round.fill = GradientTexture2D.FILL_RADIAL
		_round.fill_from = Vector2(0.5, 0.5)
		_round.fill_to = Vector2(1.0, 0.5)
	return _round


## The occluder rectangles of grid `grid` (cells): [Rect2]. Doors count as wall here (they have occluders of their own, see door_rects).
static func occluder_rects(grid) -> Array:
	var wall := {}  # cell -> true: solid or door
	var open := {}  # cell -> true: floor
	for c in grid.tiles:
		var id: String = grid.tiles[c]
		if grid.tile_flag(id, "solid") or grid.tile_flag(id, "door"):
			wall[c] = true
		else:
			open[c] = true
	var runs := {}  # row -> [[x0, x1, top_open, bottom_open, left_open, right_open]]
	var rows := []
	for c in wall:
		if grid.tile_flag(grid.tiles[c], "door"):
			continue
		var near := false
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if open.has(c + Vector2i(ox, oy)):
					near = true
		if near:
			if not runs.has(c.y):
				runs[c.y] = []
				rows.append(c.y)
			runs[c.y].append(c)
	rows.sort()
	var out := []
	var strips := []  # [x0, x1 (exclusive), y, top, bottom, left, right]
	for y in rows:
		var cells: Array = runs[y]
		cells.sort_custom(func(a, b): return a.x < b.x)
		var i := 0
		while i < cells.size():
			var c0: Vector2i = cells[i]
			var top := open.has(c0 + Vector2i.UP)
			var bottom := open.has(c0 + Vector2i.DOWN)
			var j := i
			while j + 1 < cells.size() and cells[j + 1].x == cells[j].x + 1 and open.has(cells[j + 1] + Vector2i.UP) == top and open.has(cells[j + 1] + Vector2i.DOWN) == bottom:
				j += 1
			var last: Vector2i = cells[j]
			strips.append([c0.x, last.x + 1, y, top, bottom, open.has(c0 + Vector2i.LEFT), open.has(last + Vector2i.RIGHT)])
			i = j + 1
	# merge strips of the same width in consecutive rows whose touching edges are wall
	var used := {}
	for i in strips.size():
		if used.has(i):
			continue
		var s: Array = strips[i]
		var y_end: int = s[2] + 1
		var bottom: bool = s[4]
		for j in range(i + 1, strips.size()):
			var t: Array = strips[j]
			if t[2] == y_end and t[0] == s[0] and t[1] == s[1] and not bottom and not t[3] and t[5] == s[5] and t[6] == s[6] and not used.has(j):
				used[j] = true
				y_end += 1
				bottom = t[4]
		var x0: float = s[0] + (INSET if s[5] else 0.0)
		var x1: float = s[1] - (INSET if s[6] else 0.0)
		var y0: float = s[2] + (INSET if s[3] else 0.0)
		var y1: float = y_end - (INSET if bottom else 0.0)
		out.append(Rect2(x0, y0, maxf(x1 - x0, 0.05), maxf(y1 - y0, 0.05)))
	return out


## The rectangle (cells) of a door piece's occluder: its cells, shrunk on the sides that face a room.
static func door_rect(cells: Array) -> Rect2:
	var a: Vector2i = cells[0]
	var b: Vector2i = cells[1]
	var r := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(a.x - b.x) + 1.0, absf(a.y - b.y) + 1.0))
	if r.size.x > r.size.y:  # lies across a horizontal wall: the rooms are above and below
		return Rect2(r.position + Vector2(0.0, INSET), r.size - Vector2(0.0, 2.0 * INSET))
	return Rect2(r.position + Vector2(INSET, 0.0), r.size - Vector2(2.0 * INSET, 0.0))
