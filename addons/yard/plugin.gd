@tool
extends EditorPlugin

var editor_view: Control


func _enter_tree() -> void:
	print("YARD - Yet Another Resource Database")
	editor_view = load(get_script().resource_path.get_base_dir() + "/editor_view.tscn").instantiate()
	get_editor_interface().get_editor_main_screen().add_child(editor_view)
	_make_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(editor_view):
		editor_view.queue_free()


func _has_main_screen():
	return true


func _make_visible(visible):
	if is_instance_valid(editor_view):
		editor_view.visible = visible


func _get_plugin_name():
	return "YARD"


func _get_plugin_icon():
	# will do for now
	return EditorInterface.get_editor_theme().get_icon("ResourcePreloader", "EditorIcons")
