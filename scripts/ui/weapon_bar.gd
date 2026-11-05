extends Control
## The weapon bar along the bottom of the combat screen: one picture slot per weapon of the player's ship (the gun's sprite, its key in
## a cooldown ring, its name small under it, its state, chain and charge pips), edged in its fire group's colour with the group's mark,
## grouped LMB, RMB, then the guns that fire by themselves, each under its mouse icon (gun_badges.gd; right-click a slot to move a fixed
## gun between LMB and RMB). The slot flashes when the gun fires and lights when its gun on the ship is hovered. The state reads ready, cooling, no power, jammed, no ammo,
## out of arc ... Above it, one slot per active ability of the ship (Abilities.slots): the key that
## triggers it (Shift engine, Space shield, Q utility), its name, a ring that shows the time left while
## it runs and the cooldown while it rests, and why it cannot start; a press that is refused flashes
## the reason in the slot. To the left of the rows a small diagram shows the shield: a ring of the bubble's
## sectors, bow up, each as bright and thick as the layers it holds, with the number, dark while open and
## dashed at 0 (arrow keys shift the balance, End makes it even; combat_view.gd takes those keys).
## Reads a CombatSession; the only input it takes is the three ability keys.

const Describe = preload("res://scripts/ui/describe.gd")
const GunBadges = preload("res://scripts/ui/gun_badges.gd")
const Thumbs = preload("res://scripts/ui/thumbs.gd")

const SLOT := Vector2(92.0, 104.0)  ## a weapon slot: key, picture, name, state
const HEAD := 20.0  ## the strip above a fire group with its mouse icon
const GROUP_GAP := 14.0
const ASLOT := Vector2(196.0, 66.0)  ## an ability slot: taller, for the reason
const GAP := 8.0
const BG := Color(0.04, 0.07, 0.11, 0.85)
const TEXT := Color("#cfe6ff")
const READY := Color("#4fd08a")
const COOLING := Color("#f1c40f")
const BAD := Color("#e0453a")
const GREY := Color("#6b7686")
const GOLD := Color("#ffd24a")
const KEY_OF := {KEY_SHIFT: "engine", KEY_SPACE: "shield", KEY_Q: "utility"}  ## keycode -> ability key
const KEY_LABEL := {"engine": "SHIFT", "shield": "SPACE", "utility": "Q"}
const FLASH_MS := 2200  ## how long a refusal stays in its slot
const NAME_W := 104.0  ## px a slot's weapon name has (it starts 58 px in and stops short of the power dot)
const DIAG := Vector2(132.0, 138.0)  ## the shield diagram's box
const DIAG_RING := 33.0  ## its ring's radius
const PIP := Color("#5fd4ff")
const ION := Color("#a07bff")
const BLOCKED_TEXT := {"unpowered": "NO POWER", "disabled": "DISABLED", "overheated": "OVERHEATED", "malfunction": "JAMMED", "wrecked": "WRECKED"}
const STATUS_TEXT := {
	"ready": "READY", "cooling down": "COOLING", "out of arc": "OUT OF ARC", "unpowered": "NO POWER", "no ammo": "NO AMMO",
	"no ammo rack in reach": "NO RACK", "rack empty": "RACK EMPTY", "belt stopped": "BELT STOPPED", "feeding": "FEEDING",
	"malfunction": "JAMMED", "overheated": "OVERHEATED", "disabled": "DISABLED", "wrecked": "WRECKED", "no such weapon": "-",
}

var session  ## combat_session.gd
var badges  ## gun_badges.gd, shared with combat_view.gd: the flashes, the held groups and the hover
var aim: Callable = func() -> Vector2: return Vector2.ZERO  ## the world point the mouse aims at
var last_note := ""  ## what a refused right-click says (combat_view.gd shows it)
var flashes := {}  ## ability slot id -> {text, until (Time.get_ticks_msec)}: the refusals on show


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p_session, p_aim: Callable, p_badges = null) -> void:
	session = p_session
	aim = p_aim
	badges = p_badges


## The weapons laid out for the bar: {slots: [{rect, w, number}], heads: [{rect, group}], width}, positions against the bar's top
## left. Grouped LMB, RMB, then the guns that fire by themselves, each group under its mouse icon; `number` is the gun's key.
func layout() -> Dictionary:
	var list: Array = session.weapons() if session != null else []
	var slots := []
	var heads := []
	var x := 0.0
	var y := (ASLOT.y + GAP if session != null and not session.ability_slots().is_empty() else 0.0) + HEAD
	for g in [1, 2, 3]:
		var first := true
		var x0 := x
		for i in list.size():
			if GunBadges.bar_group(list[i]) != g:
				continue
			slots.append({"rect": Rect2(Vector2(x, y), SLOT), "w": list[i], "number": i + 1})
			x += SLOT.x + GAP
			first = false
		if not first:
			heads.append({"rect": Rect2(Vector2(x0, y - HEAD + 2.0), Vector2(x - GAP - x0, HEAD - 4.0)), "group": g})
			x += GROUP_GAP - GAP
	return {"slots": slots, "heads": heads, "width": maxf(x - GROUP_GAP, 0.0)}


## The slot under local point `p`: its layout entry, {} when none.
func slot_at(p: Vector2) -> Dictionary:
	if session == null:
		return {}
	var base := Vector2((size.x - layout()["width"]) / 2.0, 0.0)
	for s in layout()["slots"]:
		if Rect2(s["rect"].position + base, s["rect"].size).has_point(p):
			return s
	return {}


## A right-click at bar-local `p` on a slot cycles that fixed gun's group (LMB, RMB); true when the click was on a slot (it is used up).
func click(p: Vector2, button: int) -> bool:
	var s := slot_at(p)
	if s.is_empty() or button != MOUSE_BUTTON_RIGHT:
		return false
	var co = session.arena.ships[session.PLAYER]
	var uid: int = s["w"]["uid"]
	if not co.mounts[uid]["virtual"] and GunBadges.cycle(co.ship.components, session.arena.weapons, uid) != 0:
		return true
	last_note = "%s fires by itself" % s["w"]["name"] if str(s["w"]["aim"]) != "fixed" else ""
	return true


func _process(_dt: float) -> void:
	if not visible or session == null:
		return
	var weapons_w: float = layout()["width"]
	var abilities_w := _row_width(session.ability_slots().size(), ASLOT.x)
	size = Vector2(maxf(weapons_w, abilities_w), HEAD + SLOT.y + (ASLOT.y + GAP if abilities_w > 0.0 else 0.0))
	if badges != null:  # the mouse on a slot lights that gun on the ship
		var hs := slot_at(get_local_mouse_position())
		badges.bar_hover = int(hs["w"]["uid"]) if not hs.is_empty() else -1
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - size.x) / 2.0, vp.y - size.y - 14.0)
	queue_redraw()


func _row_width(n: int, slot_w: float) -> float:
	return n * (slot_w + GAP) - GAP if n > 0 else 0.0


## The ability keys: Shift, Space and Q press the engine, shield and utility abilities.
func _unhandled_input(e: InputEvent) -> void:
	if not visible or session == null or not (e is InputEventKey and e.pressed and not e.echo) or not KEY_OF.has(e.keycode):
		return
	press(KEY_OF[e.keycode])
	if is_inside_tree():
		get_viewport().set_input_as_handled()


## Press ability key `key` ("engine", "shield" or "utility"); every refusal is flashed in its slot.
## Returns the session's {"started", "refused"}.
func press(key: String) -> Dictionary:
	var r: Dictionary = session.press_ability(key)
	for slot in r["refused"]:
		flashes[slot] = {"text": r["refused"][slot], "until": Time.get_ticks_msec() + FLASH_MS}
	return r


func _draw() -> void:
	if session == null:
		return
	var parts: Array = session.shield_sectors()
	if not parts.is_empty():
		var rows_left := (size.x - maxf(layout()["width"], _row_width(session.ability_slots().size(), ASLOT.x))) / 2.0
		_shield_diagram(Vector2(rows_left - DIAG.x - 14.0, size.y - DIAG.y), parts)
	var slots: Array = session.ability_slots()
	if not slots.is_empty():
		var x0 := (size.x - _row_width(slots.size(), ASLOT.x)) / 2.0
		for i in slots.size():
			_ability_slot(Vector2(x0 + i * (ASLOT.x + GAP), 0.0), slots[i])
	var target: Vector2 = aim.call()
	var lay := layout()
	var base := Vector2((size.x - lay["width"]) / 2.0, 0.0)
	for h in lay["heads"]:
		var sty := GunBadges.style({"aim": "turret" if h["group"] == 3 else "fixed", "group": h["group"]})
		var r: Rect2 = h["rect"]
		r.position += base
		draw_rect(r, Color(sty["color"], 0.18))
		draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - 2.0), Vector2(r.size.x, 2.0)), sty["color"])
		GunBadges.draw_mouse(self, Rect2(r.position + Vector2(3.0, 1.0), Vector2(10.0, r.size.y - 4.0)), h["group"], sty["color"])
		_text(sty["label"], r.position + Vector2(17.0, r.size.y - 5.0), 11, sty["color"])
	for sl in lay["slots"]:
		_slot(sl["rect"].position + base, sl["number"], sl["w"], target)


func _slot(at: Vector2, number: int, w: Dictionary, target: Vector2) -> void:
	var st: Dictionary = session.slot_state(w["uid"], target)
	var status: String = st["status"]
	var col: Color = READY if status == "ready" else (COOLING if status in ["cooling down", "feeding"] else (GREY if status == "out of arc" else BAD))
	var sty := GunBadges.style(w)
	var gcol: Color = sty["color"]
	var fl: float = badges.flash_of(w["uid"]) if badges != null else 0.0
	var hot: bool = badges != null and badges.hover_uid() == w["uid"]
	var held: bool = badges != null and badges.outlined(w)
	var r := Rect2(at, SLOT)
	draw_rect(r, BG)
	draw_rect(Rect2(at + Vector2(0.0, 2.0), Vector2(SLOT.x, 3.0)), Color(gcol, 0.9))  # the group's colour along the top edge
	if fl > 0.0:
		draw_rect(r, Color(gcol, 0.45 * fl))
	draw_rect(r, Color(gcol, 1.0 if (hot or held) else 0.75), false, 3.0 if (hot or held) else 2.0)
	var ship = session.arena.ships[session.PLAYER].ship
	var pic := Rect2(at + Vector2(6.0, 10.0), Vector2(SLOT.x - 12.0, 50.0))
	if ship.components.has(str(w["id"])):
		Thumbs.draw(self, {"kind": "part", "id": str(w["id"])}, ship, pic, Time.get_ticks_msec() / 1000.0)
	var c := at + Vector2(17.0, 17.0)  # the key number inside the cooldown ring
	draw_circle(c, 13.0, Color(0, 0, 0, 0.7))
	draw_arc(c, 12.0, 0.0, TAU, 24, Color(1, 1, 1, 0.14), 3.0, true)
	var total: float = maxf(st["cooldown"], 0.01)
	var done := 1.0 - clampf(st["cooldown_left"] / total, 0.0, 1.0)
	if done > 0.0:
		draw_arc(c, 12.0, -PI / 2.0, -PI / 2.0 + TAU * done, 24, Color(col, 0.95), 3.0, true)
	if number <= 9:
		_text(str(number), c + Vector2(-4.0, 6.0), 16, TEXT)
	GunBadges.draw_mark(self, at + Vector2(SLOT.x - 14.0, 17.0), 6.0, sty["mark"], gcol)
	_pips(at + Vector2(7.0, 62.0), w)
	var shown := fit_name(str(w["name"]), SLOT.x - 8.0)
	_text(shown["text"], at + Vector2(5.0, 76.0), mini(shown["size"], 11), TEXT, SLOT.x - 8.0)
	var label: String = STATUS_TEXT.get(status, status.to_upper())
	if status == "cooling down":
		label += " %.1f" % st["cooldown_left"]
	_text(label, at + Vector2(5.0, 92.0), 11, col, SLOT.x - 22.0)
	var powered: bool = status not in ["unpowered", "disabled", "overheated", "malfunction", "wrecked"]
	draw_circle(at + Vector2(SLOT.x - 8.0, SLOT.y - 9.0), 3.5, READY if powered else BAD)


## Chain steps (diamonds) and stored charges (dots) of a gun that has them, read from the weapons' accessors when they exist
## (chain_steps, chain_max, charges, charge_max). Returns nothing; `pips_of` is what tests read.
func _pips(at: Vector2, w: Dictionary) -> void:
	var p := pips_of(session, w)
	var x := 0.0
	for kind in ["chain", "charge"]:
		for i in int(p[kind][1]):
			var on: bool = i < int(p[kind][0])
			var cc := at + Vector2(x + 4.0, 4.0)
			if kind == "chain":
				draw_colored_polygon(PackedVector2Array([cc + Vector2(0, -4), cc + Vector2(4, 0), cc + Vector2(0, 4), cc + Vector2(-4, 0)]), Color(PIP, 1.0 if on else 0.25))
			else:
				draw_circle(cc, 3.5, Color(ION, 1.0 if on else 0.25))
			x += 10.0
		x += 4.0


## {chain: [steps, max], charge: [stored, max]} of weapon entry `w`; [0, 0] where the gun has no such mechanic (or the accessor is not there).
static func pips_of(sess, w: Dictionary) -> Dictionary:
	var out := {"chain": [0, 0], "charge": [0, 0]}
	var ws = sess.arena.weapons
	var d: Dictionary = ws.def(str(w["id"]))
	var pl: int = sess.PLAYER
	if ws.has_method("chain_max") and ws.has_method("chain_steps"):
		out["chain"] = [int(ws.chain_steps(sess.arena, pl, w["uid"])), int(ws.chain_max(d))]
	if ws.has_method("charge_max") and ws.has_method("charges"):
		out["charge"] = [int(ws.charges(sess.arena, pl, w["uid"])), int(ws.charge_max(d))]
	return out


## A weapon's name as the slot shows it: {size, text} - the font size (14 down to 10) that fits `max_w` px, else the name cut
## short with an ellipsis at 10.
static func fit_name(text: String, max_w := NAME_W) -> Dictionary:
	var font := ThemeDB.fallback_font
	var size := 14
	while size > 10 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		size -= 1
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		var n := text.length()
		while n > 1 and font.get_string_size(text.left(n).strip_edges() + "\u2026", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
			n -= 1
		text = text.left(n).strip_edges() + "\u2026"
	return {"size": size, "text": text}


## One ability slot: key, name, a ring (time left while it runs, cooldown while it rests), its state and,
## for a few seconds after a refused press, the reason.
func _ability_slot(at: Vector2, s: Dictionary) -> void:
	var st: Dictionary = session.ability_state(s)
	var state: String = st["state"]
	var flash = flashes.get(s["slot"])
	if flash != null and Time.get_ticks_msec() >= flash["until"]:
		flashes.erase(s["slot"])
		flash = null
	var col := READY
	var frac := 1.0
	var label := "READY"
	match state:
		"active":
			col = GOLD
			frac = st["active_left"] / maxf(st["duration"], 0.01)
			label = "ON %.1f" % st["active_left"]
		"cooling":
			col = COOLING
			frac = 1.0 - st["cooldown_left"] / maxf(st["cooldown"], 0.01)
			label = "COOLDOWN %d" % ceili(st["cooldown_left"] - 1e-6)
		"blocked":
			col = BAD
			label = BLOCKED_TEXT.get(st["reason"], "NEEDS CREW" if st["reason"].begins_with("needs") else st["reason"].to_upper())
	draw_rect(Rect2(at, ASLOT), BG)
	draw_rect(Rect2(at, ASLOT), Color(BAD if flash != null else col, 0.9), false, 3.0 if flash != null else 2.0)
	var c := at + Vector2(30.0, ASLOT.y / 2.0)
	draw_arc(c, 19.0, 0.0, TAU, 28, Color(1, 1, 1, 0.12), 4.0, true)
	draw_arc(c, 19.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(frac, 0.0, 1.0), 28, Color(col, 0.95), 4.0, true)
	var key: String = KEY_LABEL.get(s["key"], "?")
	_text(key, c + Vector2(-19.0, 4.0 if key.length() > 1 else 6.0), 10 if key.length() > 1 else 17, TEXT, 38.0, HORIZONTAL_ALIGNMENT_CENTER)
	_text(str(s["name"]), at + Vector2(58.0, 20.0), 14, TEXT)
	if flash != null:
		draw_multiline_string(ThemeDB.fallback_font, at + Vector2(58.0, 33.0), flash["text"], HORIZONTAL_ALIGNMENT_LEFT, ASLOT.x - 64.0, 10, 3, BAD)
	else:
		_text(label, at + Vector2(58.0, 39.0), 11, col)
		_text(str(s["part"]), at + Vector2(58.0, 55.0), 10, GREY)


## The shield diagram at `at`: `parts` is session.shield_sectors().
func _shield_diagram(at: Vector2, parts: Array) -> void:
	var n := parts.size()
	var ion: bool = session.arena.ships[session.PLAYER].ion_lock > 0.0
	draw_rect(Rect2(at, DIAG), BG)
	draw_rect(Rect2(at, DIAG), Color(PIP, 0.5), false, 2.0)
	var c := at + Vector2(DIAG.x / 2.0, 70.0)
	_text("SHIELD", at + Vector2(8.0, 14.0), 11, TEXT)
	if n > 1:
		_text("arrows  End", at + Vector2(DIAG.x - 8.0, 14.0), 9, GREY, -1.0)
	var width := TAU / n
	var gap := 0.07 if n > 1 else 0.0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	for k in n:
		var st: Dictionary = parts[k]
		var mid := -PI / 2.0 + k * width
		var a0 := mid - width / 2.0 + gap
		var a1 := mid + width / 2.0 - gap
		var up: float = 0.0 if ion else minf(float(st["layers"]), 4.0)
		var frac := clampf(float(st["layers"]) / maxf(float(st["cap"]), 1.0), 0.0, 1.0)
		if st["open"]:
			draw_arc(c, DIAG_RING, a0, a1, 12, Color("#243242"), 5.0, true)
		elif ion:
			draw_arc(c, DIAG_RING, a0, a1, 12, Color(ION, 0.4 + 0.3 * pulse), 4.0, true)
		elif up < 1.0:  # no whole layer: dashes
			var steps := maxi(3, int((a1 - a0) / 0.22))
			for d in steps:
				if d % 2 == 0:
					draw_arc(c, DIAG_RING, lerpf(a0, a1, float(d) / steps), lerpf(a0, a1, float(d + 1) / steps), 4, Color(GREY, 0.7), 2.0, true)
		else:
			draw_arc(c, DIAG_RING, a0, a1, 12, Color(PIP, 0.3 + 0.65 * frac), 3.0 + 1.6 * up, true)
		if st["filling"] and not ion:  # layers on their way back
			draw_arc(c, DIAG_RING + 8.0, a0, a1, 12, Color(PIP, 0.25 + 0.5 * pulse), 1.5, true)
		var shown := float(st["layers"])
		var label := "%d" % floori(shown + 1e-6) if is_equal_approx(shown, roundf(shown)) else "%.1f" % shown
		var tp := c + Vector2.from_angle(mid) * (DIAG_RING + 15.0) if n > 1 else c + Vector2(0.0, 24.0)
		_text(label, tp + Vector2(-4.0 * label.length(), 4.0), 12, Color(TEXT, 0.35 if st["open"] else 1.0), -1.0)
	var bow := PackedVector2Array([c + Vector2(0.0, -11.0), c + Vector2(7.0, 9.0), c + Vector2(0.0, 5.0), c + Vector2(-7.0, 9.0)])
	draw_colored_polygon(bow, Color(GREY, 0.8))
	if n <= 4:
		var weights := PackedStringArray(parts.map(func(st): return "%.1f" % st["weight"]))
		_text("balance " + (" ".join(weights) if n > 1 else "one piece"), at + Vector2(8.0, DIAG.y - 6.0), 10, GREY)


func _text(text: String, at: Vector2, size: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(ThemeDB.fallback_font, at, text, align, width, size, col)
