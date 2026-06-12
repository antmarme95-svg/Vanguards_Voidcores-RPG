# creation_ui.gd — Character creation split-screen.
# Left panel (~31% width): title, tab rail, per-tab content, name input, confirm.
# Right side transparent so the 3D viewport shows through.
# Matches the web build's visual identity using Godot built-in fonts + color/spacing.
class_name CreationUI extends CanvasLayer

# ---- color constants (matching ui.css) ----
const COL_INK       := Color("#eaf6ff")
const COL_INK_DIM   := Color(0.918, 0.965, 1.0, 0.5)
const COL_PANEL     := Color(0.039, 0.063, 0.086, 0.92)
const COL_PANEL_BORDER := Color(0.275, 0.902, 1.0, 0.18)
const COL_ACCENT    := Color("#46e6ff")
const COL_GOLD      := Color("#ffc94d")
const COL_DANGER    := Color("#ff4d5e")
const COL_DARK      := Color(0.02, 0.04, 0.06, 0.96)
const COL_CARD_BG   := Color(0.06, 0.12, 0.18, 0.85)
const COL_CARD_SEL  := Color(0.275, 0.902, 1.0, 0.15)
const COL_TAB_ACTIVE:= Color(0.275, 0.902, 1.0, 1.0)
const COL_TAB_IDLE  := Color(0.918, 0.965, 1.0, 0.45)

# ---- tabs ----
const TABS := ["ORIGIN", "BODY", "FACE", "CLASS"]
const TAB_IDS := ["origin", "body", "face", "class"]

# ---- callbacks (set by director) ----
var on_tab: Callable = func(_t: String) -> void: pass
var on_origin: Callable = func(_o: Dictionary) -> void: pass
var on_phenotype: Callable = func(_id: String, _v) -> void: pass
var on_class_selected: Callable = func(_c: Dictionary) -> void: pass
var on_name: Callable = func(_n: String) -> void: pass
var on_confirm: Callable = func(_n: String) -> void: pass

# ---- internal state ----
var _save: SaveState = null
var _active_tab: String = "origin"
var _accent: Color = COL_ACCENT
var _name_touched: bool = false

# ---- UI nodes ----
var _full_control: Control       # direct child of CanvasLayer; toggled for hide/show
var _root_panel: PanelContainer
var _tab_buttons: Array = []
var _tab_body: VBoxContainer
var _name_edit: LineEdit
var _confirm_btn: Button
var _city_label: String = ""

static func create(save_ref: SaveState) -> CreationUI:
	var ui := CreationUI.new()
	ui._save = save_ref
	return ui

# ================================================================
func _ready() -> void:
	layer = 5
	_build_ui()
	if _save != null:
		show_tab("origin")


# ================================================================
func _build_ui() -> void:
	# Full-screen container — left 31% is the panel, rest is transparent
	var full := Control.new()
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(full)
	_full_control = full

	# Left panel — dark gradient
	_root_panel = PanelContainer.new()
	_root_panel.set_anchor(SIDE_LEFT,   0.0)
	_root_panel.set_anchor(SIDE_TOP,    0.0)
	_root_panel.set_anchor(SIDE_RIGHT,  0.315)
	_root_panel.set_anchor(SIDE_BOTTOM, 1.0)
	_root_panel.set_offset(SIDE_LEFT,   0)
	_root_panel.set_offset(SIDE_TOP,    0)
	_root_panel.set_offset(SIDE_RIGHT,  0)
	_root_panel.set_offset(SIDE_BOTTOM, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = COL_DARK
	ps.border_width_right = 1
	ps.border_color = COL_PANEL_BORDER
	_root_panel.add_theme_stylebox_override("panel", ps)
	full.add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_root_panel.add_child(vbox)

	# ---- Header ----
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 3)
	var hm := StyleBoxFlat.new()
	hm.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	hm.content_margin_left   = 18
	hm.content_margin_right  = 18
	hm.content_margin_top    = 16
	hm.content_margin_bottom = 12

	var sub_lbl := Label.new()
	sub_lbl.text = "Conqueror's Contract · Intake Form 7-C"
	sub_lbl.add_theme_font_size_override("font_size", 10)
	sub_lbl.add_theme_color_override("font_color", COL_INK_DIM)
	header.add_child(sub_lbl)

	var title_lbl := Label.new()
	title_lbl.text = "FORGE YOUR MERCENARY"
	title_lbl.add_theme_font_size_override("font_size", 19)
	title_lbl.add_theme_color_override("font_color", _accent)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title_lbl)

	# Store reference to retint
	header.set_meta("title_label", title_lbl)
	_root_panel.set_meta("title_label", title_lbl)

	var sep1 := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = COL_PANEL_BORDER
	sep_style.content_margin_top = 0
	sep_style.content_margin_bottom = 0
	sep1.add_theme_stylebox_override("separator", sep_style)
	sep1.add_theme_constant_override("separation", 1)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left",   18)
	header_margin.add_theme_constant_override("margin_right",  18)
	header_margin.add_theme_constant_override("margin_top",    16)
	header_margin.add_theme_constant_override("margin_bottom", 10)
	header_margin.add_child(header)
	vbox.add_child(header_margin)
	vbox.add_child(sep1)

	# ---- Tab rail ----
	var tab_rail := HBoxContainer.new()
	tab_rail.add_theme_constant_override("separation", 0)
	var tab_margin := MarginContainer.new()
	tab_margin.add_theme_constant_override("margin_left",   0)
	tab_margin.add_theme_constant_override("margin_right",  0)
	tab_margin.add_theme_constant_override("margin_top",    0)
	tab_margin.add_theme_constant_override("margin_bottom", 0)
	tab_margin.add_child(tab_rail)
	vbox.add_child(tab_margin)

	_tab_buttons.clear()
	for i in range(TABS.size()):
		var tab_id: String = TAB_IDS[i]
		var btn := Button.new()
		btn.text = TABS[i]
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", COL_TAB_IDLE)
		btn.add_theme_color_override("font_hover_color", COL_INK)
		btn.add_theme_color_override("font_pressed_color", _accent)
		var btn_normal := StyleBoxFlat.new()
		btn_normal.bg_color = Color(0, 0, 0, 0)
		btn_normal.border_width_bottom = 2
		btn_normal.border_color = Color(0, 0, 0, 0)
		btn_normal.content_margin_top    = 8
		btn_normal.content_margin_bottom = 8
		btn.add_theme_stylebox_override("normal",   btn_normal)
		btn.add_theme_stylebox_override("hover",    btn_normal)
		btn.add_theme_stylebox_override("pressed",  btn_normal)
		btn.add_theme_stylebox_override("focus",    btn_normal)
		btn.set_meta("tab_id", tab_id)
		btn.pressed.connect(func() -> void: _on_tab_pressed(tab_id))
		tab_rail.add_child(btn)
		_tab_buttons.append(btn)

	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", sep_style.duplicate())
	sep2.add_theme_constant_override("separation", 1)
	vbox.add_child(sep2)

	# ---- Scrollable tab body ----
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left",   12)
	body_margin.add_theme_constant_override("margin_right",  12)
	body_margin.add_theme_constant_override("margin_top",    10)
	body_margin.add_theme_constant_override("margin_bottom", 10)
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body_margin)

	_tab_body = VBoxContainer.new()
	_tab_body.add_theme_constant_override("separation", 6)
	_tab_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.add_child(_tab_body)

	# ---- Footer ----
	var sep3 := HSeparator.new()
	sep3.add_theme_stylebox_override("separator", sep_style.duplicate())
	sep3.add_theme_constant_override("separation", 1)
	vbox.add_child(sep3)

	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	var fm := MarginContainer.new()
	fm.add_theme_constant_override("margin_left",   14)
	fm.add_theme_constant_override("margin_right",  14)
	fm.add_theme_constant_override("margin_top",    10)
	fm.add_theme_constant_override("margin_bottom", 12)
	fm.add_child(footer)
	vbox.add_child(fm)

	# Name row
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	var name_lbl := Label.new()
	name_lbl.text = "NAME"
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", COL_INK_DIM)
	name_lbl.custom_minimum_size.x = 46
	name_row.add_child(name_lbl)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Sign-in name…"
	_name_edit.max_length = 18
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", 13)
	_name_edit.add_theme_color_override("font_color", COL_INK)
	_name_edit.add_theme_color_override("font_placeholder_color", COL_INK_DIM)
	var ne_style := StyleBoxFlat.new()
	ne_style.bg_color = Color(0.04, 0.09, 0.14, 0.9)
	ne_style.border_color = COL_PANEL_BORDER
	ne_style.border_width_bottom = 1
	ne_style.content_margin_left = 8
	ne_style.content_margin_right = 8
	ne_style.content_margin_top = 5
	ne_style.content_margin_bottom = 5
	_name_edit.add_theme_stylebox_override("normal", ne_style)
	_name_edit.add_theme_stylebox_override("focus",  ne_style)
	_name_edit.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_edit)
	footer.add_child(name_row)

	# Confirm button
	_confirm_btn = Button.new()
	_confirm_btn.text = "Select Origin · Look · Class"
	_confirm_btn.disabled = true
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.add_theme_font_size_override("font_size", 13)
	_confirm_btn.focus_mode = Control.FOCUS_NONE
	_style_confirm_btn(false)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	footer.add_child(_confirm_btn)

# ================================================================
func show_tab(tab_id: String) -> void:
	_active_tab = tab_id
	# Update tab button styles
	for btn in _tab_buttons:
		var is_active: bool = btn.get_meta("tab_id") == tab_id
		if is_active:
			btn.add_theme_color_override("font_color", _accent)
			var active_style := StyleBoxFlat.new()
			active_style.bg_color = Color(0, 0, 0, 0)
			active_style.border_width_bottom = 2
			active_style.border_color = _accent
			active_style.content_margin_top    = 8
			active_style.content_margin_bottom = 8
			btn.add_theme_stylebox_override("normal",  active_style)
			btn.add_theme_stylebox_override("hover",   active_style)
			btn.add_theme_stylebox_override("pressed", active_style)
		else:
			btn.add_theme_color_override("font_color", COL_TAB_IDLE)
			var idle_style := StyleBoxFlat.new()
			idle_style.bg_color = Color(0, 0, 0, 0)
			idle_style.border_width_bottom = 2
			idle_style.border_color = Color(0, 0, 0, 0)
			idle_style.content_margin_top    = 8
			idle_style.content_margin_bottom = 8
			btn.add_theme_stylebox_override("normal",  idle_style)
			btn.add_theme_stylebox_override("hover",   idle_style)
			btn.add_theme_stylebox_override("pressed", idle_style)

	# Rebuild tab body
	for child in _tab_body.get_children():
		_tab_body.remove_child(child)
		child.queue_free()

	match tab_id:
		"origin": _build_origin_tab()
		"class":  _build_class_tab()
		_:        _build_phenotype_tab(tab_id)

	on_tab.call(tab_id)

# ================================================================
func _section_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", COL_INK_DIM)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 2)
	m.add_child(lbl)
	_tab_body.add_child(m)

func _make_card_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_CARD_SEL if selected else COL_CARD_BG
	s.border_width_left   = 2
	s.border_width_right  = 0
	s.border_width_top    = 0
	s.border_width_bottom = 0
	s.border_color = _accent if selected else COL_PANEL_BORDER
	s.content_margin_left   = 12
	s.content_margin_right  = 12
	s.content_margin_top    = 10
	s.content_margin_bottom = 10
	return s

# ================================================================
func _build_origin_tab() -> void:
	_section_label("Choose your lineage — it picks your kingdom, your passive, and your enemies")
	# _tab_body is a VBoxContainer with separation=6, so cards naturally have gaps
	for origin in OriginsData.ORIGINS:
		var is_sel: bool = _save.origin_id == origin["id"]
		var card := _make_origin_card(origin, is_sel)
		_tab_body.add_child(card)

func _make_origin_card(origin: Dictionary, selected: bool) -> PanelContainer:
	# PanelContainer drives card size via container layout; VBoxContainer fills it.
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _make_card_style(selected))
	card.set_meta("origin_id", origin["id"])

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(inner)

	var tag := Label.new()
	tag.text = origin.get("tag", "")
	tag.add_theme_font_size_override("font_size", 9)
	tag.add_theme_color_override("font_color", _accent)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(tag)

	var name_lbl := Label.new()
	name_lbl.text = origin.get("name", "")
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", COL_INK)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(name_lbl)

	var lore := Label.new()
	lore.text = origin.get("lore", "")
	lore.add_theme_font_size_override("font_size", 11)
	lore.add_theme_color_override("font_color", COL_INK_DIM)
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lore.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(lore)

	var passive: Dictionary = origin.get("passive", {})
	var passive_lbl := Label.new()
	passive_lbl.text = passive.get("name", "") + " — " + passive.get("desc", "")
	passive_lbl.add_theme_font_size_override("font_size", 10)
	passive_lbl.add_theme_color_override("font_color", COL_GOLD)
	passive_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passive_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	passive_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(passive_lbl)

	var city: Dictionary = origin.get("city", {})
	var city_lbl := Label.new()
	city_lbl.text = "⌂ " + city.get("name", "") + " · " + city.get("desc", "")
	city_lbl.add_theme_font_size_override("font_size", 10)
	city_lbl.add_theme_color_override("font_color", COL_INK_DIM)
	city_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	city_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	city_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(city_lbl)

	# Stat chips from passive attribute mods
	var mods: Dictionary = passive.get("attributeMods", {})
	if not mods.is_empty():
		var chips_row := HBoxContainer.new()
		chips_row.add_theme_constant_override("separation", 6)
		chips_row.mouse_filter = Control.MOUSE_FILTER_PASS
		for k in mods:
			var chip := _make_stat_chip(k.capitalize(), str(mods[k]))
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
			chips_row.add_child(chip)
		inner.add_child(chips_row)

	# Use gui_input on the PanelContainer for click detection
	var oid: String = origin["id"]
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_on_origin_selected(oid)
	)
	return card

# ================================================================
func _build_class_tab() -> void:
	_section_label("Background training — attributes & skill bonuses")
	for cls in ClassesData.CLASSES:
		var is_sel: bool = _save.class_id == cls["id"]
		var card := _make_class_card(cls, is_sel)
		_tab_body.add_child(card)

func _make_class_card(cls: Dictionary, selected: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _make_card_style(selected))
	var cls_id: String = cls["id"]
	card.set_meta("class_id", cls_id)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(inner)

	var tag := Label.new()
	tag.text = cls.get("tag", "")
	tag.add_theme_font_size_override("font_size", 9)
	tag.add_theme_color_override("font_color", _accent)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(tag)

	var name_lbl := Label.new()
	name_lbl.text = cls.get("name", "")
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", COL_INK)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = cls.get("desc", "")
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", COL_INK_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(desc_lbl)

	var attrs: Dictionary = cls.get("attributes", {})
	var chips_row := HBoxContainer.new()
	chips_row.add_theme_constant_override("separation", 6)
	chips_row.mouse_filter = Control.MOUSE_FILTER_PASS
	if attrs.has("health"):
		var ch_hp := _make_stat_chip("HP", str(attrs["health"]))
		ch_hp.mouse_filter = Control.MOUSE_FILTER_PASS
		chips_row.add_child(ch_hp)
	if attrs.has("magicka"):
		var ch_mp := _make_stat_chip("MP", str(attrs["magicka"]))
		ch_mp.mouse_filter = Control.MOUSE_FILTER_PASS
		chips_row.add_child(ch_mp)
	if attrs.has("stamina"):
		var ch_sp := _make_stat_chip("SP", str(attrs["stamina"]))
		ch_sp.mouse_filter = Control.MOUSE_FILTER_PASS
		chips_row.add_child(ch_sp)
	inner.add_child(chips_row)

	var combat: Dictionary = cls.get("combat", {})
	var skills_text := ""
	var bonuses: Dictionary = cls.get("skillBonuses", {})
	var parts: Array = []
	for sk in bonuses:
		parts.append(sk + " +" + str(bonuses[sk]))
	skills_text = " · ".join(parts)
	var weapon_lbl := Label.new()
	weapon_lbl.text = combat.get("weaponName", "") + "   " + skills_text
	weapon_lbl.add_theme_font_size_override("font_size", 10)
	weapon_lbl.add_theme_color_override("font_color", COL_INK_DIM)
	weapon_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(weapon_lbl)

	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_on_class_card_pressed(cls_id)
	)
	return card

func _make_stat_chip(label_text: String, value: String) -> Label:
	var chip := Label.new()
	chip.text = label_text + " " + value
	chip.add_theme_font_size_override("font_size", 10)
	chip.add_theme_color_override("font_color", _accent)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(_accent.r, _accent.g, _accent.b, 0.1)
	cs.border_width_left   = 1
	cs.border_width_right  = 1
	cs.border_width_top    = 1
	cs.border_width_bottom = 1
	cs.border_color = Color(_accent.r, _accent.g, _accent.b, 0.35)
	cs.content_margin_left   = 5
	cs.content_margin_right  = 5
	cs.content_margin_top    = 2
	cs.content_margin_bottom = 2
	cs.corner_radius_top_left     = 2
	cs.corner_radius_top_right    = 2
	cs.corner_radius_bottom_left  = 2
	cs.corner_radius_bottom_right = 2
	chip.add_theme_stylebox_override("normal", cs)
	return chip

# ================================================================
func _build_phenotype_tab(tab_id: String) -> void:
	var current_section := ""
	for field in PhenotypeData.PHENOTYPE_FIELDS:
		if field.get("tab", "") != tab_id:
			continue
		var section: String = field.get("section", "")
		if section != current_section:
			current_section = section
			_section_label(section)
		var kind: String = field.get("kind", "")
		match kind:
			"float": _build_slider(field)
			"pick":  _build_picker(field)
			"color": _build_swatches(field)

func _build_slider(field: Dictionary) -> void:
	var fid: String = field.get("id", "")
	var value: float = float(_save.phenotype.get(fid, field.get("default", 0.5)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = field.get("label", "")
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", COL_INK)
	lbl.custom_minimum_size.x = 130
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	# Style
	var slider_style := StyleBoxFlat.new()
	slider_style.bg_color = Color(0.12, 0.18, 0.24, 0.9)
	slider_style.content_margin_top = 2
	slider_style.content_margin_bottom = 2
	slider.add_theme_stylebox_override("slider", slider_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = _accent
	slider.add_theme_stylebox_override("grabber_area", fill_style)
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = str(roundi(value * 100))
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_color_override("font_color", _accent)
	val_lbl.custom_minimum_size.x = 28
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	_tab_body.add_child(row)

	if field.has("hint"):
		var hint := Label.new()
		hint.text = field.get("hint", "")
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", COL_INK_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tab_body.add_child(hint)

	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = str(roundi(v * 100))
		_save.phenotype[fid] = v
		on_phenotype.call(fid, v)
	)

func _build_picker(field: Dictionary) -> void:
	var fid: String = field.get("id", "")
	var current_idx: int = int(_save.phenotype.get(fid, field.get("default", 0)))
	var options: Array = field.get("options", [])

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_tab_body.add_child(grid)

	for i in range(options.size()):
		var opt_name: String = options[i]
		var is_sel: bool = i == current_idx
		var btn := Button.new()
		btn.text = opt_name
		btn.flat = false
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 10)
		_style_pick_btn(btn, is_sel)
		var cap_i := i
		btn.pressed.connect(func() -> void:
			_save.phenotype[fid] = cap_i
			on_phenotype.call(fid, cap_i)
			for child in grid.get_children():
				if child is Button:
					_style_pick_btn(child, false)
			_style_pick_btn(btn, true)
		)
		grid.add_child(btn)

func _style_pick_btn(btn: Button, selected: bool) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(_accent.r, _accent.g, _accent.b, 0.18) if selected else Color(0.06, 0.1, 0.14, 0.8)
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.border_color = _accent if selected else COL_PANEL_BORDER
	s.content_margin_left   = 6
	s.content_margin_right  = 6
	s.content_margin_top    = 4
	s.content_margin_bottom = 4
	s.corner_radius_top_left     = 2
	s.corner_radius_top_right    = 2
	s.corner_radius_bottom_left  = 2
	s.corner_radius_bottom_right = 2
	btn.add_theme_stylebox_override("normal",  s)
	btn.add_theme_stylebox_override("hover",   s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus",   s)
	btn.add_theme_color_override("font_color", _accent if selected else COL_INK_DIM)

func _build_swatches(field: Dictionary) -> void:
	var fid: String = field.get("id", "")
	var current_idx: int = int(_save.phenotype.get(fid, field.get("default", 0)))
	var palette_key: String = field.get("paletteKey", "skin")

	var palette: Array = []
	match palette_key:
		"skin":  palette = Array(PaletteData.SKIN_TONES)
		"hair":  palette = Array(PaletteData.HAIR_COLORS)
		"paint": palette = Array(PaletteData.PAINT_COLORS)

	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_tab_body.add_child(grid)

	for i in range(palette.size()):
		var col: Color = palette[i]
		var is_sel: bool = i == current_idx
		var swatch := Button.new()
		swatch.flat = false
		swatch.custom_minimum_size = Vector2(24, 24)
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.tooltip_text = field.get("label", "")
		var ss := StyleBoxFlat.new()
		ss.bg_color = col
		ss.border_width_left   = 2 if is_sel else 1
		ss.border_width_right  = 2 if is_sel else 1
		ss.border_width_top    = 2 if is_sel else 1
		ss.border_width_bottom = 2 if is_sel else 1
		ss.border_color = Color.WHITE if is_sel else Color(col.r, col.g, col.b, 0.4)
		swatch.add_theme_stylebox_override("normal", ss)
		swatch.add_theme_stylebox_override("hover",  ss)
		var cap_i := i
		var cap_col := col
		swatch.pressed.connect(func() -> void:
			_save.phenotype[fid] = cap_i
			on_phenotype.call(fid, cap_i)
			for child in grid.get_children():
				if child is Button:
					var cs := child.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
					cs.border_width_left   = 1
					cs.border_width_right  = 1
					cs.border_width_top    = 1
					cs.border_width_bottom = 1
					cs.border_color = Color(cs.bg_color.r, cs.bg_color.g, cs.bg_color.b, 0.4)
					child.add_theme_stylebox_override("normal", cs)
					child.add_theme_stylebox_override("hover",  cs)
			var new_ss := StyleBoxFlat.new()
			new_ss.bg_color = cap_col
			new_ss.border_width_left   = 2
			new_ss.border_width_right  = 2
			new_ss.border_width_top    = 2
			new_ss.border_width_bottom = 2
			new_ss.border_color = Color.WHITE
			swatch.add_theme_stylebox_override("normal", new_ss)
			swatch.add_theme_stylebox_override("hover",  new_ss)
		)
		grid.add_child(swatch)

# ================================================================
func _on_tab_pressed(tab_id: String) -> void:
	show_tab(tab_id)

func _on_origin_selected(origin_id: String) -> void:
	_save.origin_id = origin_id
	var origin: Dictionary = OriginsData.get_origin(origin_id)
	if not _name_touched:
		var def_name: String = origin.get("defaultName", "Borisawa")
		_name_edit.text = def_name
		_save.player_name = def_name
	var theme: Dictionary = origin.get("theme", {})
	var accent_hex: String = theme.get("accent", "#46e6ff")
	set_accent(Color(accent_hex))
	on_origin.call(origin)
	show_tab("origin")
	_refresh_begin()

func _on_class_card_pressed(cls_id: String) -> void:
	_save.class_id = cls_id
	var cls: Dictionary = ClassesData.find_class(cls_id)
	on_class_selected.call(cls)
	show_tab("class")
	_refresh_begin()

func _on_name_changed(new_text: String) -> void:
	_name_touched = new_text.strip_edges().length() > 0
	_save.player_name = new_text.strip_edges()
	on_name.call(new_text.strip_edges())
	_refresh_begin()

func _on_confirm_pressed() -> void:
	if _confirm_btn.disabled:
		return
	on_confirm.call(_save.player_name)

# ================================================================
func _refresh_begin() -> void:
	var ready: bool = _save.origin_id != "" and _save.class_id != "" and _save.player_name.strip_edges().length() > 0
	_confirm_btn.disabled = not ready
	if ready:
		var origin: Dictionary = OriginsData.get_origin(_save.origin_id)
		var city_name: String = origin.get("city", {}).get("name", "?")
		_confirm_btn.text = "Sign On — Deploy to " + city_name
	else:
		_confirm_btn.text = "Select Origin · Look · Class"
	_style_confirm_btn(ready)

func _style_confirm_btn(enabled: bool) -> void:
	var s := StyleBoxFlat.new()
	if enabled:
		s.bg_color = Color(_accent.r, _accent.g, _accent.b, 0.18)
		s.border_color = _accent
	else:
		s.bg_color = Color(0.08, 0.12, 0.16, 0.6)
		s.border_color = COL_PANEL_BORDER
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.content_margin_left   = 12
	s.content_margin_right  = 12
	s.content_margin_top    = 9
	s.content_margin_bottom = 9
	_confirm_btn.add_theme_stylebox_override("normal",   s)
	_confirm_btn.add_theme_stylebox_override("hover",    s)
	_confirm_btn.add_theme_stylebox_override("pressed",  s)
	_confirm_btn.add_theme_stylebox_override("focus",    s)
	_confirm_btn.add_theme_stylebox_override("disabled", s)
	_confirm_btn.add_theme_color_override("font_color",          _accent if enabled else COL_INK_DIM)
	_confirm_btn.add_theme_color_override("font_disabled_color", COL_INK_DIM)
	_confirm_btn.add_theme_font_size_override("font_size", 13)

# ================================================================
func set_accent(new_accent: Color) -> void:
	_accent = new_accent
	# Retint title
	if _root_panel != null and _root_panel.has_meta("title_label"):
		var tl: Label = _root_panel.get_meta("title_label")
		tl.add_theme_color_override("font_color", _accent)
	_refresh_begin()

# programmatic helpers for autotest
func set_name_text(text: String) -> void:
	_name_edit.text = text
	_save.player_name = text.strip_edges()
	_name_touched = text.strip_edges().length() > 0
	on_name.call(text.strip_edges())
	_refresh_begin()

func move_slider(field_id: String, value: float) -> void:
	# Walk the tab body looking for the slider with matching field
	_save.phenotype[field_id] = value
	on_phenotype.call(field_id, value)

# ---- Explicit show/hide: toggle root Control child so panel hides reliably ----
# CanvasLayer.visible is unreliable in headless Godot 4.6; we toggle the
# actual Control child directly. Call these instead of .visible = true/false.
func show_panel() -> void:
	visible = true
	if _full_control != null:
		_full_control.visible = true

func hide_panel() -> void:
	visible = false
	if _full_control != null:
		_full_control.visible = false
