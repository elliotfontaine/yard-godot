@tool
extends EditorPlugin

var editor_view: Control


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	print("YARD - Yet Another Resource Database")
	editor_view = load(get_script().resource_path.get_base_dir() + "/editor_only/ui/editor_view.tscn").instantiate()
	EditorInterface.get_editor_main_screen().add_child(editor_view)
	_make_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(editor_view):
		editor_view.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(editor_view):
		editor_view.visible = visible


func _handles(object: Object) -> bool:
	return object is Registry


func _edit(object: Object) -> void:
	if not object:
		return
	var edited_registry := object as Registry
	editor_view.open_registry(edited_registry)


func _get_plugin_name() -> String:
	return "YARD"


func _get_plugin_icon() -> Texture2D:
	# will do for now
	return EditorInterface.get_editor_theme().get_icon("ResourcePreloader", "EditorIcons")
