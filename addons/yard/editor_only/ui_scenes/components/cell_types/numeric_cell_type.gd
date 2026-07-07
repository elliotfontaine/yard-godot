extends "res://addons/yard/editor_only/ui_scenes/components/cell_types/text_cell_type.gd"
## Integer and float columns. Shares the LineEdit editor with StringCellType via
## TextCellType, but parses the committed text back into an int or float.
## Also serves as the editing fallback for RangeCellType, which has no editor
## of its own and is numeric.

static func matches(column: ColumnConfig) -> bool:
	return column.is_numeric_column()


static func get_sort_key(value: Variant, _column: ColumnConfig) -> Variant:
	return float(value)


static func read_editor_value(editor: Node, column: ColumnConfig) -> Variant:
	var line_edit: LineEdit = editor
	var text := line_edit.text
	if column.is_integer_column() and text.is_valid_int():
		return int(text)
	elif column.is_float_column() and text.is_valid_float():
		return float(text)
	return null
