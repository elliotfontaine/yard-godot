extends "res://addons/yard/editor_only/classes/data_table/cell_types/text_cell_type.gd"
## Integer and float columns. Shares the LineEdit editor with StringCellType via
## TextCellType, but parses the committed text back into an int or float.

static func matches(column: ColumnConfig) -> bool:
	return column.type in [TYPE_INT, TYPE_FLOAT]


static func get_sort_key(value: Variant, _column: ColumnConfig) -> Variant:
	return float(value)


static func read_editor_value(editor: Node, column: ColumnConfig) -> Variant:
	var line_edit: LineEdit = editor
	var text := line_edit.text
	if column.type == TYPE_INT and text.is_valid_int():
		return int(text)
	elif column.type == TYPE_FLOAT and text.is_valid_float():
		return float(text)
	return null
