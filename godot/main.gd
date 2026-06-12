# main.gd — Boot scene. Instantiates GameDirector as the game entry point.
# Replaces the P0 placeholder boxes scene.
# Debug autoload handles --screenshot-and-quit and --autotest args separately.
extends Node3D

var _director: GameDirector = null

func _ready() -> void:
	# When running under --autotest, the test script creates its own GameDirector.
	# Skip main-scene boot to avoid two directors rendering simultaneously.
	if Debug.args.has("autotest") or Debug.args.has("screenshot-and-quit"):
		print("[Main] BORISAWA Godot — autotest mode, skipping main director boot")
		return
	_director = GameDirector.new()
	add_child(_director)
	_director.start()
	print("[Main] BORISAWA Godot — GameDirector booted")
