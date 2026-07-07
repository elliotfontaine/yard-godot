extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Array/Dictionary columns. Read-only: no editor, no special input. The
## enum-array / enum-key-dictionary / enum-value-dictionary hint variants only
## affect how individual elements are formatted here, not a separate type.

static func matches(column: ColumnConfig) -> bool:
	return column.is_collection_column()


static func draw_cell(canvas: CanvasItem, rect: Rect2, value: Variant, column: ColumnConfig, style: CellStyle) -> void:
	var text: String
	if value is not Array and value is not Dictionary:
		text = str(value) if value != null else ""
	else:
		text = _format_collection_text(value, column)
	draw_text(canvas, rect, text, resolve_font(column, style.font), style.font_size, column.h_alignment, resolve_text_color(column, style))


static func _format_collection_text(collection: Variant, column: ColumnConfig) -> String:
	var is_dict := collection is Dictionary
	var items: Array = (collection as Dictionary).keys() if is_dict else (collection as Array)
	var keys_map: Dictionary = column.enum_keys_map if column.is_enum_key_dictionary_column() else { }
	var values_map: Dictionary = column.enum_values_map if column.is_enum_value_dictionary_column() or column.is_enum_array_column() else { }
	var parts: Array[String] = []
	for i in mini(items.size(), 3):
		if is_dict:
			var key: Variant = items[i]
			var val: Variant = (collection as Dictionary)[key]
			parts.append(
				"%s: %s" % [
					_format_collection_elem(key, keys_map),
					_format_collection_elem(val, values_map),
				],
			)
		else:
			parts.append(_format_collection_elem(items[i], values_map))

	var result := ", ".join(parts)
	var remaining := items.size() - 3
	if remaining > 0:
		result += " and {remaining} more".format({ &"remaining": remaining })
	return "{ %s }" % result if is_dict else "[%s]" % result


static func _format_collection_elem(elem: Variant, enum_map: Dictionary = { }) -> String:
	if elem is Resource:
		return "<%s>" % (elem as Resource).resource_path.get_file()
	if elem is Array:
		return "Array(%d)" % (elem as Array).size()
	if elem is Dictionary:
		return "Dict(%d)" % (elem as Dictionary).size()
	if elem is int and not enum_map.is_empty():
		var int_elem := elem as int
		return enum_map[int_elem] if enum_map.has(int_elem) else "?:%d" % int_elem
	return str(elem)
