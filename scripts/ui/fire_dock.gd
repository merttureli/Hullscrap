extends Control
## The fire groups in build mode: the same four sections as the weapon bar (LMB, RMB, Q, AUTO, each with its header even when empty),
## with one small chip per placed gun (its number key, group mark and name). Drag a chip to another section to move the gun there,
## or right-click it to cycle its group; the chip on the ship follows at once. Reads a BuildMode (its ship, its guns); only shown in build mode.

const WeaponBar = preload("res://scripts/ui/weapon_bar.gd")
const GunBadges = preload("res://scripts/ui/gun_badges.gd")

const SLOT := Vector2(104.0, 30.0)
const BG := Color(0.04, 0.07, 0.11, 0.92)
const TEXT := Color("#cfe6ff")
const TOP := 64.0  ## px from the top of the window to the headers' top

var build  ## build_mode.gd
var drag := {}  ## {uid, grab, at, start, moved}: the chip in hand; empty when none
var last_note := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func bind(p_build) -> void:
	build = p_build


func guns() -> Array:
	return build.gun_entries() if build != null else []


func layout() -> Dictionary:
	return WeaponBar.sections(guns(), SLOT, WeaponBar.HEAD)


func _active() -> bool:
	return build != null and build.build_on and build.ship != null and not build.combat and not guns().is_empty()


func _base(lay: Dictionary) -> Vector2:
	return Vector2((size.x - lay["width"]) / 2.0, 0.0)


func _has_point(p: Vector2) -> bool:
	if not _active():
		return false
	if not drag.is_empty():
		return true
	var lay := layout()
	var r := Rect2(_base(lay), Vector2(lay["width"], WeaponBar.HEAD + SLOT.y))
	return r.grow(4.0).has_point(p)


func slot_at(p: Vector2) -> Dictionary:
	var lay := layout()
	for s in lay["slots"]:
		if Rect2(s["rect"].position + _base(lay), s["rect"].size).has_point(p):
			return s
	return {}


func group_at(p: Vector2) -> int:
	var lay := layout()
	for z in lay["zones"]:
		var r: Rect2 = z["rect"]
		r = Rect2(r.position + _base(lay) - Vector2(WeaponBar.GROUP_GAP / 2.0, 40.0), r.size + Vector2(WeaponBar.GROUP_GAP, 80.0))
		if r.has_point(p):
			return z["group"]
	return -1


func _process(_dt: float) -> void:
	visible = _active()
	var vp := get_viewport_rect().size
	size = Vector2(vp.x, WeaponBar.HEAD + SLOT.y + 8.0)
	position = Vector2(0.0, TOP)
	if visible:
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if not _active():
		return
	if e is InputEventMouseButton:
		var p: Vector2 = e.position
		if e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var s := slot_at(p)
			if not s.is_empty():
				drag = {"uid": s["w"]["uid"], "grab": p - (s["rect"].position + _base(layout())), "at": p, "start": p, "moved": false}
		elif e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			var s := slot_at(p)
			if not s.is_empty():
				GunBadges.cycle(build.ship.components, build._aim(), s["w"]["uid"])
				build.queue_redraw()
		elif not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not drag.is_empty():
			drop_at(p)
		accept_event()
	elif e is InputEventMouseMotion and not drag.is_empty():
		drag["at"] = e.position
		if e.position.distance_to(drag["start"]) >= WeaponBar.DRAG_PX:
			drag["moved"] = true
		accept_event()


## The chip in hand is let go at local `p`: dropped on the section under it. Returns the group, -1 when nothing moved.
func drop_at(p: Vector2) -> int:
	var d := drag
	drag = {}
	if d.is_empty() or not d["moved"]:
		return -1
	var g := group_at(p)
	if g < 0:
		return -1
	var got := GunBadges.assign(build.ship.components, build._aim(), d["uid"], g)
	build.queue_redraw()
	return got


func _draw() -> void:
	if not _active():
		return
	var lay := layout()
	var base := _base(lay)
	var over: int = group_at(drag["at"]) if not drag.is_empty() and drag["moved"] else -1
	for h in lay["heads"]:
		WeaponBar.draw_head(self, h["rect"].position + base, h["rect"].size, h["group"], over == h["group"])
	for z in lay["zones"]:
		var gcol: Color = GunBadges.style({"group": z["group"]})["color"]
		var r: Rect2 = z["rect"]
		r.position += base
		var body := Rect2(r.position + Vector2(0.0, WeaponBar.HEAD), Vector2(r.size.x, r.size.y - WeaponBar.HEAD))
		if over == z["group"]:
			draw_rect(r.grow(3.0), Color(gcol, 0.2))
			draw_rect(r.grow(3.0), Color(gcol, 0.95), false, 2.5)
		elif not lay["slots"].any(func(sl): return GunBadges.bar_group(sl["w"]) == z["group"]):
			draw_rect(body, Color(gcol, 0.07))
			draw_rect(body, Color(gcol, 0.4), false, 1.0)
	var held := {}
	for sl in lay["slots"]:
		if not drag.is_empty() and drag["moved"] and sl["w"]["uid"] == drag["uid"]:
			held = sl
			draw_rect(Rect2(sl["rect"].position + base, SLOT), Color(0.5, 0.55, 0.65, 0.4), false, 1.0)
			continue
		_slot(sl["rect"].position + base, sl, false)
	if not held.is_empty():
		_slot(drag["at"] - drag["grab"], held, true)


func _slot(at: Vector2, sl: Dictionary, lifted: bool) -> void:
	var w: Dictionary = sl["w"]
	var sty := GunBadges.style(w)
	var col: Color = sty["color"]
	var r := Rect2(at, SLOT)
	if lifted:
		draw_rect(Rect2(at + Vector2(4.0, 5.0), SLOT), Color(0, 0, 0, 0.45))
	draw_rect(r, Color(0.07, 0.11, 0.17, 1.0) if lifted else BG)
	draw_rect(Rect2(at + Vector2(0.0, 2.0), Vector2(SLOT.x, 3.0)), Color(col, 0.9))
	draw_rect(r, Color(col, 1.0 if lifted else 0.8), false, 2.0)
	if lifted:
		draw_rect(r.grow(2.0), Color(1, 1, 1, 0.8), false, 1.5)
	var font := ThemeDB.fallback_font
	if sl["number"] <= 9:
		draw_string(font, at + Vector2(6.0, 22.0), str(sl["number"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT)
	GunBadges.draw_mark(self, at + Vector2(SLOT.x - 12.0, 15.0), 5.0, sty["mark"], col)
	var shown: Dictionary = WeaponBar.fit_name(str(w["name"]), SLOT.x - 44.0)
	draw_string(font, at + Vector2(20.0, 21.0), shown["text"], HORIZONTAL_ALIGNMENT_LEFT, SLOT.x - 44.0, mini(shown["size"], 11), TEXT)
