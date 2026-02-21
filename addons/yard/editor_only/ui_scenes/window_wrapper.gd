@tool
extends PanelContainer

@onready var floating_window: Window = $FloatingWindow
@onready var registry_editor: MarginContainer = %RegistryEditor


func _on_registry_editor_make_floating_requested() -> void:
	if not EditorInterface.is_multi_window_enabled():
		return
	#floating_window.popup()


func _on_floating_window_close_requested() -> void:
	floating_window.hide()
