# P0 placeholder boot scene: proves rendering, lighting, and the screenshot
# harness work. Replaced by the real GameDirector flow in later packages.
extends Node3D

func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 4.5)
	cam.look_at_from_position(cam.position, Vector3(0, 0.8, 0))
	add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	add_child(_make_env())

	# A cel-ish test dummy: three stacked boxes in aether colors.
	var colors := [Color("#46e6ff"), Color("#ff9d4d"), Color("#9fe8a8")]
	for i in range(3):
		var box := MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		box.material_override = mat
		box.position = Vector3(float(i - 1) * 1.4, 0.5, 0)
		add_child(box)

	print("[Main] BORISAWA godot skeleton booted")

func _make_env() -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0c1622")
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	we.environment = env
	return we

func _process(delta: float) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.rotate_y(delta * 0.8)
