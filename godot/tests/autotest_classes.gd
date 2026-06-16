## autotest_classes.gd — Sprint 3 GATE: 9-sub-style legibility at ~3 m distance.
## Run via: godot --path godot -- --autotest=res://tests/autotest_classes.gd
##
## Arranges ALL 9 sub-styles in a 3×3 grid:
##   rows    = origins  (aetherborn / ironblooded / miststalker)
##   columns = classes  (warrior / mage / thief)
##
## Camera is pulled back so each character occupies ~the same apparent size a
## player would see them at ~3 m in-game. Silhouette + origin color must carry;
## fine detail should not be needed to tell them apart.
##
## Outputs:
##   godot/test_out/classes_grid.png           (all 9 in one wide shot — GATE artifact)
##   godot/test_out/class_<origin>_<class>.png (individual close-up per cell, optional)
##   godot/test_out/classes_results.json       (bytes + ok flag per cell)
extends Node

# ---- 3×3 matrix ----
const ORIGINS: Array = ["aetherborn", "ironblooded", "miststalker"]
const CLASSES: Array = ["warrior",    "mage",        "thief"]

# Grid spacing in metres
const GRID_SPACING_X: float = 2.0   # column gap (left/right)
const GRID_SPACING_Z: float = 2.2   # row gap    (front/back) — slight Z separation for depth
const GRID_OFFSET_X:  float = -2.0  # centre the 3-col grid
const GRID_OFFSET_Z:  float = -2.2  # centre the 3-row grid

var _rigs: Array   = []   # [row][col] CharacterRig
var _results: Array = []
var _cam: Camera3D  = null

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	# (a) Remove placeholder main scene
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	await get_tree().process_frame

	# (b) Build stage (lighting + floor + camera)
	_build_stage()

	# (c) Instantiate all 9 rigs in one pass — persistent VFX are present from the start.
	for row in range(ORIGINS.size()):
		var origin_id: String = ORIGINS[row]
		var origin_dict: Dictionary = OriginsData.get_origin(origin_id)
		var phenotype:   Dictionary = PhenotypeData.default_phenotype()
		var row_rigs: Array = []

		for col in range(CLASSES.size()):
			var class_id: String = CLASSES[col]

			var rig := CharacterRig.new()
			rig.position = Vector3(
				GRID_OFFSET_X + float(col) * GRID_SPACING_X,
				0.0,
				GRID_OFFSET_Z + float(row) * GRID_SPACING_Z
			)
			get_tree().root.add_child(rig)

			# Apply phenotype first, then archetype — order-independent but convention.
			rig.apply_phenotype(phenotype, origin_dict)
			rig.apply_archetype(class_id)

			row_rigs.append(rig)

		_rigs.append(row_rigs)

	# (d) Advance frames: particles need several ticks to emit and shaders need compile.
	#     10 frames is consistent with autotest_strategist (most complex VFX).
	for _i in range(12):
		await get_tree().process_frame

	# (e) WIDE SHOT — all 9 rigs in frame: the primary GATE artifact.
	var grid_path: String = "res://test_out/classes_grid.png"
	await Debug.screenshot(grid_path)

	var grid_fa := FileAccess.open(grid_path, FileAccess.READ)
	var grid_bytes: int = 0
	if grid_fa != null:
		grid_bytes = grid_fa.get_length()
		grid_fa.close()
	var grid_ok: bool = grid_bytes > 8192  # wide scene should be larger than single-char shot
	print("[autotest_classes] classes_grid.png → %d bytes, ok=%s" % [grid_bytes, str(grid_ok)])

	# (f) Individual close-up shots — move camera per cell, reset after.
	#     Save original camera position to restore after individual shots.
	var cam_pos_backup:    Vector3 = _cam.position
	var cam_target_backup: Vector3 = Vector3(0.0, 0.95, 0.0)  # original look-at point

	for row in range(ORIGINS.size()):
		var origin_id: String = ORIGINS[row]
		for col in range(CLASSES.size()):
			var class_id: String = CLASSES[col]
			var rig: CharacterRig = _rigs[row][col]

			# Reposition camera to frame this single character
			var rig_center: Vector3 = rig.position + Vector3(0.0, 0.95, 0.0)
			var cell_cam_pos: Vector3 = rig.position + Vector3(0.0, 1.25, 2.8)
			_cam.position = cell_cam_pos
			_cam.look_at_from_position(cell_cam_pos, rig_center, Vector3.UP)

			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame

			var cell_name: String = "class_" + origin_id + "_" + class_id
			var cell_path: String = "res://test_out/" + cell_name + ".png"
			await Debug.screenshot(cell_path)

			var fa := FileAccess.open(cell_path, FileAccess.READ)
			var fbytes: int = 0
			if fa != null:
				fbytes = fa.get_length()
				fa.close()
			var ok: bool = fbytes > 4096
			_results.append({
				"case":   cell_name,
				"origin": origin_id,
				"class":  class_id,
				"bytes":  fbytes,
				"ok":     ok,
			})
			print("[autotest_classes] %s → %d bytes, ok=%s" % [cell_name, fbytes, str(ok)])

	# Restore camera to grid-wide view and re-shoot (confirm grid is stable)
	_cam.position = cam_pos_backup
	_cam.look_at_from_position(cam_pos_backup, cam_target_backup, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	# (g) Write results JSON and quit.
	Debug.write_json("res://test_out/classes_results.json", {
		"grid_bytes": grid_bytes,
		"grid_ok":    grid_ok,
		"cells":      _results,
		"done":       true,
	})
	print("[autotest_classes] all done, quitting")
	get_tree().quit(0)

# ----------------------------------------------------------------
func _build_stage() -> void:
	# WorldEnvironment: dark-navy sky — emphasises colour rimlight and glow VFX.
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
	get_tree().root.add_child(we)

	# Key light: front-slightly-right so silhouettes cast a readable shadow to the left.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -25.0, 0.0)
	sun.light_energy     = 1.2
	sun.light_color      = Color("#fff4e0")
	sun.shadow_enabled   = true
	get_tree().root.add_child(sun)

	# Soft fill from opposite side — lifts shadow side so silhouettes don't go black.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 155.0, 0.0)
	fill.light_energy     = 0.3
	fill.light_color      = Color("#bfe8ff")
	fill.shadow_enabled   = false
	get_tree().root.add_child(fill)

	# Neutral grey floor — gives ground rings / decals something to sit on.
	var ground := MeshInstance3D.new()
	var gm     := PlaneMesh.new()
	gm.size    = Vector2(20.0, 20.0)
	ground.mesh = gm
	ground.material_override = ToonMaterials.toon_mat(Color("#1a2030"))
	get_tree().root.add_child(ground)

	# Camera: pulled far back + raised slightly so all 9 characters fit in frame and
	# each reads small — approximately the apparent size a player sees targets at ~3 m.
	# Grid is 2 cols × 2.0 m = 4 m wide, 2 rows × 2.2 m = 4.4 m deep, centred at origin.
	# Camera at Z=7.5, Y=3.5 gives roughly a ~65° diagonal FOV view of the whole grid.
	_cam = Camera3D.new()
	_cam.fov      = 65.0
	_cam.position = Vector3(0.0, 3.5, 7.5)
	# Look slightly downward toward the grid centre (all characters at Y~0.95 average)
	_cam.look_at_from_position(_cam.position, Vector3(0.0, 0.6, 0.0), Vector3.UP)
	get_tree().root.add_child(_cam)
