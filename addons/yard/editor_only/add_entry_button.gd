@tool
extends EditorIconMenuButton

@onready var entry_name_line_edit := %EntryNameLineEdit

func _input(event):
	if !disabled and shortcut.matches_event(event) and event.is_released() and entry_name_line_edit.has_focus() and entry_name_line_edit.text:
		pressed.emit()
		entry_name_line_edit.edit()
		get_viewport().set_input_as_handled()
