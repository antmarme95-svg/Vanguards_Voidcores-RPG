# pause_ui.gd — Pause menu with mouse sensitivity sliders.
class_name PauseUI extends CanvasLayer

const COL_INK     := Color("#eaf6ff")
const COL_INK_DIM := Color(0.918, 0.965, 1.0, 0.5)
const COL_PANEL   := Color(0.039, 0.063, 0.086, 0.94)
const COL_ACCENT  := Color("#46e6ff")

var _controller   = null   # PlayerController ref set on open()
var _sens_x_label: Label
var _sens_y_label: Label

# ================================================================
func _ready() -> void:
	layer = 9
	_build()
	visible = false

func _build() -> void:
	# Dark overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.62)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Centered panel
	var panel := PanelContainer.new()
	panel.set_anchor(SIDE_LEFT,   0.5)
	panel.set_anchor(SIDE_TOP,    0.5)
	panel.set_anchor(SIDE_RIGHT,  0.5)
	panel.set_anchor(SIDE_BOTTOM, 0.5)
	panel.set_offset(SIDE_LEFT,  -200)
	panel.set_offset(SIDE_RIGHT,  200)
	panel.set_offset(SIDE_TOP,   -190)
	panel.set_offset(SIDE_BOTTOM, 190)
	var ps := StyleBoxFlat.new()
	ps.bg_color = COL_PANEL
	ps.border_width_left   = 1
	ps.border_width_right  = 1
	ps.border_width_top    = 1
	ps.border_width_bottom = 1
	ps.border_color = Color(1, 1, 1, 0.12)
	ps.content_margin_left   = 28
	ps.content_margin_right  = 28
	ps.content_margin_top    = 24
	ps.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COL_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(1, 1, 1, 0.1)
	sep.add_theme_stylebox_override("separator", ss)
	vbox.add_child(sep)

	# Mouse sensitivity section label
	var sens_header := Label.new()
	sens_header.text = "MOUSE SENSITIVITY"
	sens_header.add_theme_font_size_override("font_size", 11)
	sens_header.add_theme_color_override("font_color", COL_INK_DIM)
	vbox.add_child(sens_header)

	# X sensitivity
	_sens_x_label = _add_slider(vbox, "Horizontal  (X)", 0.2, 3.0, 1.0, _on_sens_x_changed)

	# Y sensitivity
	_sens_y_label = _add_slider(vbox, "Vertical  (Y)", 0.2, 3.0, 1.0, _on_sens_y_changed)

	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", ss)
	vbox.add_child(sep2)

	# Resume button
	var resume_btn := Button.new()
	resume_btn.text = "RESUME"
	resume_btn.add_theme_font_size_override("font_size", 13)
	resume_btn.add_theme_color_override("font_color", COL_ACCENT)
	resume_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.1)
	bs.border_width_left   = 1
	bs.border_width_top    = 1
	bs.border_width_right  = 1
	bs.border_width_bottom = 1
	bs.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.5)
	bs.content_margin_top    = 10
	bs.content_margin_bottom = 10
	resume_btn.add_theme_stylebox_override("normal",  bs)
	resume_btn.add_theme_stylebox_override("hover",   bs)
	resume_btn.add_theme_stylebox_override("pressed", bs)
	resume_btn.add_theme_stylebox_override("focus",   bs)
	resume_btn.pressed.connect(_on_resume)
	vbox.add_child(resume_btn)

	var esc_hint := Label.new()
	esc_hint.text = "ESC — resume"
	esc_hint.add_theme_font_size_override("font_size", 10)
	esc_hint.add_theme_color_override("font_color", COL_INK_DIM)
	esc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(esc_hint)

func _add_slider(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, default_v: float, cb: Callable) -> Label:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	row.add_child(hrow)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", COL_INK)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%.1f" % default_v
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", COL_ACCENT)
	val_lbl.custom_minimum_size.x = 30
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hrow.add_child(val_lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.1
	slider.value = default_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = "%.1f" % v
		cb.call(v)
	)
	row.add_child(slider)

	return val_lbl

# ================================================================
# Public API
# ================================================================
func open(ctrl) -> void:
	_controller = ctrl
	if ctrl != null:
		_sync_sliders(ctrl.sens_x, ctrl.sens_y)
	visible = true

func close() -> void:
	visible = false
	if _controller != null:
		_controller.recapture_mouse()

func is_open() -> bool:
	return visible

func _sync_sliders(sx: float, sy: float) -> void:
	# Update slider values to match controller (find sliders by walking the tree)
	_update_slider_in_tree(0, sx)
	_update_slider_in_tree(1, sy)

func _update_slider_in_tree(idx: int, val: float) -> void:
	var sliders: Array = []
	_collect_sliders(self, sliders)
	if idx < sliders.size():
		sliders[idx].value = val

func _collect_sliders(node: Node, out: Array) -> void:
	if node is HSlider:
		out.append(node)
	for child in node.get_children():
		_collect_sliders(child, out)

# ================================================================
func _on_sens_x_changed(v: float) -> void:
	if _controller != null:
		_controller.sens_x = v

func _on_sens_y_changed(v: float) -> void:
	if _controller != null:
		_controller.sens_y = v

func _on_resume() -> void:
	close()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			close()
