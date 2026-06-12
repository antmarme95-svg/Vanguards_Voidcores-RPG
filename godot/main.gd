# main.gd — Boot scene. Instantiates GameDirector as the game entry point.
# Replaces the P0 placeholder boxes scene.
# Debug autoload handles --screenshot-and-quit and --autotest args separately.
extends Node3D

var _director: GameDirector = null

func _ready() -> void:
	_director = GameDirector.new()
	add_child(_director)
	_director.start()
	print("[Main] BORISAWA Godot — GameDirector booted")
