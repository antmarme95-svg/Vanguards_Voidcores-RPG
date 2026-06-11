# Global pub/sub bus - direct port of src/core/EventBus.js.
# Channels (same names as the web build): creation:complete, contract:signed,
# quest:update, quest:toast, combat:enemyDown, combat:playerHit, player:died,
# core:destroyed, path:chosen, passive:toggled.
extends Node

var _listeners: Dictionary = {}

func on(event: String, callback: Callable) -> void:
	if not _listeners.has(event):
		_listeners[event] = []
	_listeners[event].append(callback)

func off(event: String, callback: Callable) -> void:
	if _listeners.has(event):
		_listeners[event].erase(callback)

func emit_event(event: String, payload: Dictionary = {}) -> void:
	for callback: Callable in _listeners.get(event, []):
		callback.call(payload)
