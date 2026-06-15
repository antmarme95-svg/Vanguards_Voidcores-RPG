# minimap_ui.gd — Deployable full-zone map. Toggle with M.
# Top-down view (north up), fixed orientation, live player marker.
class_name MinimapUI extends CanvasLayer

const COL_INK     := Color("#eaf6ff")
const COL_INK_DIM := Color(0.918, 0.965, 1.0, 0.5)
const COL_PANEL   := Color(0.039, 0.063, 0.086, 0.95)
const COL_ACCENT  := Color("#46e6ff")

var _canvas: MapCanvas
var _title: Label

# ================================================================
func _ready() -> void:
	layer = 8
	_build()
	visible = false
	# Note: the "minimap:toggled" event is handled by GameDirector (which adds the
	# dialogue/pause guards and calls toggle() here). Do NOT subscribe again, or the
	# two handlers cancel each other and the map never shows.

func _build() -> void:
	# Dim backdrop (game stays faintly visible behind)
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.45)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Centered panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = COL_PANEL
	ps.border_width_left   = 1
	ps.border_width_right  = 1
	ps.border_width_top    = 1
	ps.border_width_bottom = 1
	ps.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.35)
	ps.content_margin_left   = 18
	ps.content_margin_right  = 18
	ps.content_margin_top    = 14
	ps.content_margin_bottom = 14
	ps.corner_radius_top_left     = 6
	ps.corner_radius_top_right    = 6
	ps.corner_radius_bottom_left  = 6
	ps.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	_title = Label.new()
	_title.text = "MAP"
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", COL_ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)

	_canvas = MapCanvas.new()
	_canvas.custom_minimum_size = Vector2(380, 380)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_canvas)

	var hint := Label.new()
	hint.text = "M — close"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", COL_INK_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

# ================================================================
# Public API
# ================================================================
func bind(ctrl, scn) -> void:
	if _canvas != null:
		_canvas.bind(ctrl, scn)
	if _title != null and scn != null:
		var info: Dictionary = {}
		if scn.has_method("get_map_info"):
			info = scn.get_map_info()
		_title.text = "MAP — " + str(info.get("label", "Zone"))

func open() -> void:
	visible = true

func close() -> void:
	visible = false

func toggle() -> void:
	visible = not visible

func is_open() -> bool:
	return visible

func _process(_dt: float) -> void:
	if visible and _canvas != null:
		_canvas.queue_redraw()

# ================================================================
# Inner draw surface
# ================================================================
class MapCanvas extends Control:
	var _ctrl = null
	var _scene = null
	# map_info
	var _shape: String = "circle"
	var _radius: float = 102.0
	var _x_min: float = -10.0
	var _x_max: float =  10.0
	var _z_min: float = -10.0
	var _z_max: float =  10.0
	# cached landmarks
	var _cores: Array = []
	var _interactables: Array = []
	var _obstacles: Array = []
	# transform (set per _draw)
	var _m_scale: float = 1.0
	var _m_center: Vector2 = Vector2.ZERO
	var _m_cx: float = 0.0
	var _m_cz: float = 0.0

	func bind(ctrl, scn) -> void:
		_ctrl = ctrl
		_scene = scn
		_cores = []
		_interactables = []
		_obstacles = []
		if scn == null:
			return
		var info: Dictionary = {}
		if scn.has_method("get_map_info"):
			info = scn.get_map_info()
		_shape = str(info.get("shape", "circle"))
		_radius = float(info.get("radius", 102.0))
		_x_min  = float(info.get("x_min", -10.0))
		_x_max  = float(info.get("x_max",  10.0))
		_z_min  = float(info.get("z_min", -10.0))
		_z_max  = float(info.get("z_max",  10.0))
		var cp = scn.get("core_positions")
		if cp != null:
			_cores = cp
		var it = scn.get("interactables")
		if it != null:
			_interactables = it
		var ob = scn.get("obstacles")
		if ob != null:
			_obstacles = ob
		queue_redraw()

	func _w2s(wx: float, wz: float) -> Vector2:
		# World +x → screen +x, world +z → screen +y (so -z = north = up).
		return _m_center + Vector2((wx - _m_cx) * _m_scale, (wz - _m_cz) * _m_scale)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		_m_center = Vector2(w, h) * 0.5

		# Backdrop
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.078, 0.105, 0.96), true)

		# Compute world→screen transform
		var pad: float = 18.0
		var avail: float = min(w, h) - pad * 2.0
		var span: float
		if _shape == "circle":
			_m_cx = 0.0
			_m_cz = 0.0
			span = _radius * 2.0
		else:
			_m_cx = (_x_min + _x_max) * 0.5
			_m_cz = (_z_min + _z_max) * 0.5
			span = max(_x_max - _x_min, _z_max - _z_min)
		if span <= 0.0:
			span = 1.0
		_m_scale = avail / span

		# Zone boundary
		var border_col := Color(COL_for_accent().r, COL_for_accent().g, COL_for_accent().b, 0.45)
		if _shape == "circle":
			draw_arc(_m_center, _radius * _m_scale, 0.0, TAU, 72, border_col, 2.0, true)
		else:
			var rw: float = (_x_max - _x_min) * _m_scale
			var rh: float = (_z_max - _z_min) * _m_scale
			draw_rect(Rect2(_m_center - Vector2(rw, rh) * 0.5, Vector2(rw, rh)), border_col, false, 2.0)

		# Obstacles (trees / rocks) as small vegetation dots
		for o in _obstacles:
			var ox: float = float(o.get("x", 0.0))
			var oz: float = float(o.get("z", 0.0))
			var orad: float = float(o.get("r", 0.5))
			draw_circle(_w2s(ox, oz), max(1.5, orad * _m_scale * 0.5), Color(0.30, 0.66, 0.36, 0.75))

		# Interactables (yellow dots)
		for it in _interactables:
			var ip = it.get("position", null)
			if ip == null:
				continue
			draw_circle(_w2s(ip.x, ip.z), 3.0, Color(1.0, 0.82, 0.28, 0.9))

		# Core sites (cyan diamonds)
		for c in _cores:
			_draw_diamond(_w2s(c.x, c.z), 6.0, Color(0.27, 0.9, 1.0, 0.95))

		# Player arrow
		if _ctrl != null:
			var pp: Vector2 = _w2s(_ctrl.position.x, _ctrl.position.z)
			var facing: float = float(_ctrl.facing)
			var dir := Vector2(sin(facing), cos(facing))
			if dir.length() < 0.001:
				dir = Vector2(0, -1)
			dir = dir.normalized()
			var perp := Vector2(-dir.y, dir.x)
			var tip := pp + dir * 10.0
			var bl := pp - dir * 6.0 + perp * 6.0
			var br := pp - dir * 6.0 - perp * 6.0
			draw_colored_polygon(PackedVector2Array([tip, bl, br]), Color(0.32, 0.95, 1.0, 1.0))
			draw_circle(pp, 2.0, Color(1, 1, 1, 0.95))

		# North label
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(font, Vector2(_m_center.x - 5.0, 14.0), "N",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(COL_for_accent().r, COL_for_accent().g, COL_for_accent().b, 0.8))

	func COL_for_accent() -> Color:
		return Color("#46e6ff")

	func _draw_diamond(c: Vector2, r: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)
		]), col)
