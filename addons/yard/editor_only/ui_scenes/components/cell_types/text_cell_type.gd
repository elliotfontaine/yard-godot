extends "res://addons/yard/editor_only/ui_scenes/components/cell_types/cell_type.gd"
## Shared LineEdit-based editor for StringCellType and NumericCellType. Not used
## directly as a handler; the two subclasses only differ in how the committed
## text is parsed back into a value.

static func has_editor() -> bool:
	return true


static func create_editor(owner: Control, rect: Rect2, value: Variant, column: ColumnConfig, on_finished: Callable) -> Node:
	var editor := LineEdit.new()
	owner.add_child(editor)
	editor.position = rect.position
	editor.size = rect.size
	editor.text = str(value) if value != null else ""
	editor.alignment = column.h_alignment
	editor.text_submitted.connect(func(_text: String) -> void: on_finished.call(true))
	editor.focus_exited.connect(func() -> void: on_finished.call(true))
	editor.grab_focus()
	editor.select_all()
	return editor


static func read_editor_value(editor: Node, _column: ColumnConfig) -> Variant:
	var line_edit: LineEdit = editor
	return line_edit.text
