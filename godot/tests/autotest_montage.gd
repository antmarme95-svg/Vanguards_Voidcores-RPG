## autotest_montage.gd — Visual test harness: capture each locomotion gesture as a
## frame strip ("montage") so the full motion arc is visible in ONE image per gesture.
##
## Run via (WINDOWED, not headless — needs rendered frames):
##   godot --path godot -- --autotest=res://tests/autotest_montage.gd \
##         --origin=miststalker --cls=thief
##
## Output PNGs → godot/test_out/montage_<gesture>_<subclass_tag>.png
## One tile per captured frame, laid out left→right (centered portrait crop).
extends Node

const _PC = preload("res://gameplay/player_controller.gd")

const DT := 1.0 / 60.0

# physical keycodes
const KW := 87
const KSHIFT := 4194325
const KSP := 32

# ── state ──────────────────────────────────────────────────────────────────────
var _origin_id: String  = "miststalker"
var _class_id: String   = "thief"
var _subclass_tag: String = "light"

var _stage: Node3D      = null
var _stub: Node3D       = null
var _montage_cam: Camera3D = null
var _dummy_cam: Camera3D   = null

var _controller = null
var _rig: CharacterRig  = null
var _stats: Stats       = null
var _save: SaveState    = null

var _strips: Array = []   # {name, img} per gesture, for the combined sheet

# Camera framing (FIXED height — never tracks player Y, so vertical arcs show).
var _cam_dist: float = 2.4     # side distance (+X)
var _cam_h: float    = 0.95    # camera height
var _look_h: float   = 0.80    # look-at height

# ── entry point ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_origin_id = str(Debug.args.get("origin", "miststalker"))
	_class_id  = str(Debug.args.get("cls",    "thief"))
	match _class_id:
		"warrior": _subclass_tag = "heavy"
		"mage":    _subclass_tag = "balanced"
		_:         _subclass_tag = "light"
	await get_tree().process_frame
	_run()

# ── main runner ────────────────────────────────────────────────────────────────
func _run() -> void:
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	await get_tree().process_frame

	_build_stage()
	await get_tree().process_frame

	if not _build_player():
		push_error("[montage] FATAL: could not build player stack")
		get_tree().quit(1)
		return

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	await _gesture_idle()
	await _gesture_crouch_walk()
	await _gesture_sprint()
	await _gesture_slide()
	await _gesture_slide_leap()
	await _gesture_jump()

	await _save_combined()

	print("[montage] DONE")
	get_tree().quit(0)

# ── stage builder ───────────────────────────────────────────────────────────────
func _build_stage() -> void:
	_stage = Node3D.new()
	get_tree().root.add_child(_stage)

	var we  := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode      = Environment.BG_COLOR
	env.background_color     = Color("#0c1622")
	env.tonemap_mode         = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure     = 1.15
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color("#bfe8ff")
	env.ambient_light_energy = 0.35
	we.environment = env
	_stage.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.light_energy     = 1.2
	sun.light_color      = Color("#fff4e0")
	sun.shadow_enabled   = true
	_stage.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	fill.light_energy     = 0.3
	fill.light_color      = Color("#bfe8ff")
	fill.shadow_enabled   = false
	_stage.add_child(fill)

	_montage_cam = Camera3D.new()
	_montage_cam.current = true
	_montage_cam.fov  = 60.0
	_montage_cam.near = 0.05
	_montage_cam.far  = 200.0
	_stage.add_child(_montage_cam)

	_dummy_cam = Camera3D.new()
	_dummy_cam.current = false
	_stage.add_child(_dummy_cam)

# ── player stack ────────────────────────────────────────────────────────────────
func _build_player() -> bool:
	_save = SaveState.new()
	_save.origin_id   = _origin_id
	_save.class_id    = _class_id
	_save.player_name = "Montage"

	_stats = Stats.new(_save)
	var passives := Passives.new(_save, _stats)

	_rig = CharacterRig.new()
	_rig.position = Vector3.ZERO
	_stage.add_child(_rig)
	var origin    : Dictionary = OriginsData.get_origin(_origin_id)
	var phenotype : Dictionary = PhenotypeData.default_phenotype()
	_rig.apply_phenotype(phenotype, origin)
	_rig.apply_archetype(_class_id)

	_controller = _PC.new()
	if _controller == null:
		return false
	_stage.add_child(_controller)
	_controller.position = Vector3.ZERO
	_controller.setup(_rig, _stats, passives, _save, _dummy_cam)

	_stub = _make_scene_stub()
	if _stub == null:
		return false
	_controller.scene    = _stub
	_controller.enemies  = []
	_controller._enabled = true

	# Move along +Z (W with cam_yaw=0 → world -Z... we want side-on to a +X camera):
	# cam_yaw=0 maps W to -Z; the +X side camera then sees a clean profile.
	_controller.cam_yaw = 0.0
	_controller.facing  = 0.0
	return true

func _make_scene_stub() -> Node3D:
	var stub := Node3D.new()
	var ground := MeshInstance3D.new()
	var gm     := PlaneMesh.new()
	gm.size    = Vector2(80.0, 80.0)
	ground.mesh = gm
	ground.material_override = ToonMaterials.toon_mat(Color("#1a2a1a"))
	stub.add_child(ground)
	_stage.add_child(stub)
	stub.set_script(_build_stub_script())
	return stub

func _build_stub_script() -> GDScript:
	var sc := GDScript.new()
	sc.source_code = """
extends Node3D
func get_height(_x: float, _z: float) -> float:
	return 0.0
func clamp_position(pos: Vector3) -> Vector3:
	return pos
func is_in_grass(_pos: Vector3) -> bool:
	return false
"""
	sc.reload()
	return sc

# ── camera aim (FIXED height — reveals vertical motion) ──────────────────────────
func _aim_cam() -> void:
	var p: Vector3 = _controller.position
	# Side-on: camera offset along +X; the player moves along Z, crossing the view.
	_montage_cam.position = Vector3(p.x + _cam_dist, _cam_h, p.z + 0.3)
	_montage_cam.look_at(Vector3(p.x, _look_h, p.z), Vector3.UP)

# ── reset ─────────────────────────────────────────────────────────────────────
func _reset() -> void:
	_controller.position      = Vector3.ZERO
	_controller.facing        = 0.0
	_controller.cam_yaw       = 0.0
	_controller.grounded      = true
	_controller.vel_y         = 0.0
	_controller.crouching     = false
	_controller._slide_dir    = Vector3.ZERO
	_controller._slide_entry_dir = Vector3.ZERO
	_controller._air_vel      = Vector3.ZERO
	_controller._leaping      = false
	_controller._was_sliding  = false
	_controller._crouch_just_pressed_this_frame = false
	_controller._keys_down    = {}
	_controller._horiz_speed  = 0.0
	_controller._prev_position = Vector3.ZERO
	if _stats != null:
		_stats.stamina    = _stats.max_stamina
		_stats.exhausted  = false
		_stats._regen_hold = 0.0
	# ground-gesture framing by default
	_cam_dist = 2.4
	_cam_h    = 0.95
	_look_h   = 0.80

# tick the controller (keeping keys held) without capturing
func _tick(keys: Dictionary) -> void:
	_controller._keys_down = keys.duplicate()
	_controller.update(DT)

# tick + capture one frame
func _grab(keys: Dictionary, frames: Array) -> void:
	_controller._keys_down = keys.duplicate()
	_controller.update(DT)
	_aim_cam()
	await RenderingServer.frame_post_draw
	frames.append(get_viewport().get_texture().get_image())

# ── GESTURES ─────────────────────────────────────────────────────────────────
func _gesture_idle() -> void:
	_reset()
	var frames: Array = []
	for _i in range(6):
		await _grab({}, frames)
	_save_montage(frames, "idle")

func _gesture_crouch_walk() -> void:
	_reset()
	_controller.crouching = true
	var keys := { KW: true }
	var frames: Array = []
	for i in range(16):
		if i % 2 == 0:
			await _grab(keys, frames)
		else:
			_tick(keys)
			await get_tree().process_frame
	_save_montage(frames, "crouch_walk")

func _gesture_sprint() -> void:
	_reset()
	var keys := { KW: true, KSHIFT: true }
	var frames: Array = []
	for i in range(16):
		if i % 2 == 0:
			await _grab(keys, frames)
		else:
			_tick(keys)
			await get_tree().process_frame
	_save_montage(frames, "sprint")

func _gesture_slide() -> void:
	_reset()
	var keys := { KW: true, KSHIFT: true }
	for _i in range(8):   # warmup to sprint speed
		_tick(keys)
		await get_tree().process_frame
	_controller.crouching = true
	_controller._crouch_just_pressed_this_frame = true
	var frames: Array = []
	var captured := 0
	for i in range(30):
		_controller._crouch_just_pressed_this_frame = false
		if i % 3 == 0 and captured < 10:
			await _grab(keys, frames)
			captured += 1
		else:
			_tick(keys)
			await get_tree().process_frame
	_save_montage(frames, "slide")

func _gesture_slide_leap() -> void:
	_reset()
	# airborne framing: pull back + raise so the leap arc fits
	_cam_dist = 4.2
	_cam_h    = 1.7
	_look_h   = 1.15
	var keys := { KW: true, KSHIFT: true }
	for _i in range(8):
		_tick(keys)
		await get_tree().process_frame
	_controller.crouching = true
	_controller._crouch_just_pressed_this_frame = true
	var frames: Array = []
	for i in range(6):   # a couple of slide frames
		_controller._crouch_just_pressed_this_frame = false
		if i % 3 == 0:
			await _grab(keys, frames)
		else:
			_tick(keys)
			await get_tree().process_frame
	# trigger leap
	await _grab({ KW: true, KSHIFT: true, KSP: true }, frames)
	# airborne arc
	var captured := 0
	for i in range(18):
		if i % 2 == 0 and captured < 8:
			await _grab(keys, frames)
			captured += 1
		else:
			_tick(keys)
			await get_tree().process_frame
	_save_montage(frames, "slide_leap")

func _gesture_jump() -> void:
	_reset()
	_cam_dist = 4.2
	_cam_h    = 1.7
	_look_h   = 1.15
	var keys := { KW: true, KSHIFT: true }
	for _i in range(4):
		_tick(keys)
		await get_tree().process_frame
	var frames: Array = []
	await _grab({ KW: true, KSHIFT: true, KSP: true }, frames)   # jump frame
	var captured := 0
	for i in range(18):
		if i % 2 == 0 and captured < 9:
			await _grab(keys, frames)
			captured += 1
		else:
			_tick(keys)
			await get_tree().process_frame
	_save_montage(frames, "jump")

# ── montage compositing ───────────────────────────────────────────────────────
func _save_montage(frames: Array, gesture_name: String) -> void:
	if frames.is_empty():
		push_error("[montage] no frames for %s" % gesture_name)
		return
	var first: Image = frames[0] as Image
	if first == null:
		return
	# Centered PORTRAIT crop around the character, scaled to a tall tile.
	var fw: int = first.get_width()
	var fh: int = first.get_height()
	var crop_w: int = int(min(float(fw), float(fh) * 0.62))
	var cx0: int = int((fw - crop_w) / 2.0)
	const TILE_H := 320
	var scale: float = float(TILE_H) / float(fh)
	var tile_w: int  = int(float(crop_w) * scale)
	const SEP  := 4

	var total_w: int = frames.size() * (tile_w + SEP) - SEP
	var out := Image.create(total_w, TILE_H, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.08, 0.08, 0.10, 1.0))

	for i in range(frames.size()):
		var img: Image = frames[i] as Image
		if img == null:
			continue
		var c: Image = img.get_region(Rect2i(cx0, 0, crop_w, fh))
		c.resize(tile_w, TILE_H, Image.INTERPOLATE_BILINEAR)
		c.convert(Image.FORMAT_RGBA8)
		out.blit_rect(c, Rect2i(0, 0, tile_w, TILE_H), Vector2i(i * (tile_w + SEP), 0))

	_strips.append({ "name": gesture_name, "img": out })

	var res_path := "res://test_out/montage_%s_%s.png" % [gesture_name, _subclass_tag]
	var abs_path := ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err: int = out.save_png(abs_path)
	if err != OK:
		push_error("[montage] save_png failed (err=%d) %s" % [err, abs_path])
	else:
		print("[montage] wrote montage_%s_%s.png (%d frames, %dx%d)" \
			% [gesture_name, _subclass_tag, frames.size(), total_w, TILE_H])

# ── combined contact sheet: all gestures stacked + labelled in ONE PNG ──────────
func _save_combined() -> void:
	if _strips.is_empty():
		return
	const ROW_H := 320
	const LABEL_W := 250
	const SEP := 8
	var max_w: int = 0
	for s in _strips:
		max_w = max(max_w, (s["img"] as Image).get_width())
	var total_w: int = LABEL_W + max_w + SEP * 2
	var total_h: int = _strips.size() * (ROW_H + SEP) + SEP

	var sv := SubViewport.new()
	sv.size = Vector2i(total_w, total_h)
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08, 1.0)
	bg.size  = Vector2(total_w, total_h)
	sv.add_child(bg)

	var header := Label.new()
	header.text = "SUBCLASS: %s/%s (%s)" % [_origin_id, _class_id, _subclass_tag]
	header.add_theme_font_size_override("font_size", 26)
	header.add_theme_color_override("font_color", Color(1, 1, 1))
	header.position = Vector2(12, 6)
	sv.add_child(header)

	var y: int = SEP
	for s in _strips:
		var img: Image = s["img"]
		var lbl := Label.new()
		lbl.text = str(s["name"])
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
		lbl.position = Vector2(14, y + int(ROW_H * 0.5) - 18)
		sv.add_child(lbl)

		var tr := TextureRect.new()
		tr.texture  = ImageTexture.create_from_image(img)
		tr.position = Vector2(LABEL_W, y)
		sv.add_child(tr)

		y += ROW_H + SEP

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var combined: Image = sv.get_texture().get_image()
	var res_path := "res://test_out/montage_ALL_%s.png" % _subclass_tag
	var abs_path := ProjectSettings.globalize_path(res_path)
	var err: int = combined.save_png(abs_path)
	if err != OK:
		push_error("[montage] combined save_png failed (err=%d) %s" % [err, abs_path])
	else:
		print("[montage] wrote montage_ALL_%s.png (%dx%d, %d rows)" \
			% [_subclass_tag, total_w, total_h, _strips.size()])
	sv.queue_free()
