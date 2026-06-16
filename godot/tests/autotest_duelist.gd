## autotest_duelist.gd — Visual acceptance test for Duelist (thief) per-origin attack VFX.
## Run via: godot --path godot -- --autotest=res://tests/autotest_duelist.gd
##
## For each of the 3 thief origins (aetherborn, ironblooded, miststalker):
##   1. Build a minimal stage (env + lights + camera + flat floor scene stub).
##   2. Construct PlayerController + Stats + Passives + SaveState for thief + that origin.
##   3. Call try_attack() to fire the Duelist VFX.
##   4. Screenshot IMMEDIATELY (1 frame) so fast-moving projectiles are still in frame.
##      Player is aimed sideways (+X) and camera looks along that axis so projectile
##      travels across the frame rather than away from the lens.
##   5. Screenshot to test_out/duelist_<name>.png.
## Writes duelist_results.json and quits.
extends Node

const _PC  = preload("res://gameplay/player_controller.gd")

var CASES: Array = [
	{ "name": "spellblade",    "origin_id": "aetherborn",  "label": "Spell-Blade" },
	{ "name": "scrapslinger",  "origin_id": "ironblooded", "label": "Scrap-Slinger" },
	{ "name": "shadowstalker", "origin_id": "miststalker", "label": "Shadow-Stalker" },
]

var _results: Array   = []
var _cam: Camera3D    = null
var _stage: Node3D    = null   # reused stage root (rebuilt per case)

func _ready() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	# Remove placeholder main scene
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	await get_tree().process_frame

	for case_def in CASES:
		await _run_case(case_def)

	Debug.write_json("res://test_out/duelist_results.json", {"cases": _results, "done": true})
	print("[autotest_duelist] all cases complete, quitting")
	get_tree().quit(0)

# ── per-case runner ─────────────────────────────────────────────────────────────
func _run_case(case_def: Dictionary) -> void:
	var origin_id: String = case_def["origin_id"]
	var case_name: String = case_def["name"]
	print("[autotest_duelist] starting case: ", case_name, " (", case_def["label"], ")")

	# (a) Tear down any prior stage
	if _stage != null and is_instance_valid(_stage):
		_stage.queue_free()
		_stage = null
	await get_tree().process_frame

	# (b) Build fresh stage
	_build_stage()
	await get_tree().process_frame

	# (c) Build SaveState: thief class + this origin
	var sv := SaveState.new()
	sv.origin_id   = origin_id
	sv.class_id    = "thief"
	sv.player_name = "Duelist"

	# (d) Build Stats + Passives
	var st := Stats.new(sv)
	var ps := Passives.new(sv, st)

	# (e) Build CharacterRig (minimal, needed by PlayerController.setup())
	var rig := CharacterRig.new()
	rig.position = Vector3(0.0, 0.0, 0.0)
	_stage.add_child(rig)
	var origin: Dictionary    = OriginsData.get_origin(origin_id)
	var phenotype: Dictionary = PhenotypeData.default_phenotype()
	rig.apply_phenotype(phenotype, origin)
	rig.apply_archetype("thief")

	# (f) Build PlayerController
	var pc: CharacterBody3D = _PC.new()
	_stage.add_child(pc)
	pc.position = Vector3(0.0, 0.0, 0.0)
	pc.setup(rig, st, ps, sv, _cam)

	# (g) Wire the "scene" stub so _update_projectiles / _spawn_* don't crash
	pc.scene    = _make_scene_stub()
	pc.enemies  = []
	pc._enabled = true
	pc.attack_cooldown = 0.0

	# ── KEY TRICK: aim SIDEWAYS (+X) so the projectile travels left→right across
	# the camera view instead of straight away from the lens.
	# cam_yaw = -PI/2 → forward = +X (sin(-PI/2)=-1 negated = +X, cos(-PI/2)=0)
	# cam_pitch = 0 → level shot
	pc.cam_yaw   = -PI / 2.0
	pc.cam_pitch = 0.0

	# Camera: sit above-left at (-3, 2, 0), look toward (3, 1.35, 0).
	# This gives a side-on view: projectile flies left-to-right across the frame.
	_cam.position = Vector3(-3.0, 2.0, 0.0)
	_cam.look_at(Vector3(3.0, 1.35, 0.0), Vector3.UP)

	# (h) Fire — spawns all VFX nodes synchronously
	pc.try_attack()

	# (i) Wait exactly ONE render frame so the GPU submits the draw calls,
	# then screenshot. One frame keeps fast projectiles still near spawn point.
	# For the blink afterimage (0.12s life) and muzzle flash (0.06s life), even
	# one frame is tight — screenshot fires on frame_post_draw so it's the
	# result of THIS frame's draw, which includes all nodes added this frame.
	await get_tree().process_frame

	# (j) Screenshot
	var out_path: String = "res://test_out/duelist_%s.png" % case_name
	await Debug.screenshot(out_path)

	# Tally projectiles still alive right after screenshot
	var proj_count: int = pc.projectiles.size()
	print("[autotest_duelist] case done: ", case_name,
		  " — active projectiles at screenshot: ", proj_count)

	_results.append({
		"case":        case_name,
		"origin":      origin_id,
		"label":       case_def["label"],
		"screenshot":  out_path,
		"projectiles": proj_count,
		"ok":          true,
	})

	pc.queue_free()
	await get_tree().process_frame

# ── minimal "scene stub" node ────────────────────────────────────────────────────
# PlayerController._spawn_duelist_projectile() calls scene.add_child() and
# _update_projectiles calls scene.get_height(). The stub satisfies both.
func _make_scene_stub() -> Node3D:
	var stub := Node3D.new()
	# Attach a flat-floor ground mesh so there's something to see
	var ground := MeshInstance3D.new()
	var gm     := PlaneMesh.new()
	gm.size    = Vector2(10.0, 10.0)
	ground.mesh = gm
	ground.material_override = ToonMaterials.toon_mat(Color("#1a2a1a"))
	stub.add_child(ground)
	_stage.add_child(stub)
	# Attach GDScript methods that PlayerController expects
	stub.set_script(_build_stub_script())
	return stub

# Returns a GDScript that provides get_height / clamp_position / is_in_grass
# so PlayerController doesn't crash when calling those on the stub.
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

# ── stage builder ────────────────────────────────────────────────────────────────
func _build_stage() -> void:
	_stage = Node3D.new()
	get_tree().root.add_child(_stage)

	# World environment
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

	# Key light
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.light_energy     = 1.2
	sun.light_color      = Color("#fff4e0")
	sun.shadow_enabled   = true
	_stage.add_child(sun)

	# Fill light
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	fill.light_energy     = 0.3
	fill.light_color      = Color("#bfe8ff")
	fill.shadow_enabled   = false
	_stage.add_child(fill)

	# Camera — persists across stage rebuilds
	if _cam == null:
		_cam = Camera3D.new()
		get_tree().root.add_child(_cam)
	_cam.fov  = 65.0    # wider to keep full trajectory in frame
	_cam.near = 0.05
	_cam.far  = 200.0
	_cam.position = Vector3(-3.0, 2.0, 0.0)
	_cam.look_at(Vector3(3.0, 1.35, 0.0), Vector3.UP)
