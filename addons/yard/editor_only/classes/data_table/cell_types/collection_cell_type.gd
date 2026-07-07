extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Array/Dictionary columns. display-only: no custom editor.

static func matches(column: ColumnConfig) -> bool:
	return column.type in [TYPE_ARRAY, TYPE_DICTIONARY]


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
	var keys_map: Dictionary = _get_keys_map(column) if _is_dict_with_enum_keys(column) else { }
	var values_map: Dictionary = (
		_get_values_map(column)
		if _is_dict_with_enum_values(column) or _is_array_with_enum_values(column)
		else { }
	)
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


static func _is_array_with_enum_values(column: ColumnConfig) -> bool:
	return column.type == TYPE_ARRAY and column.hint_string and _is_enum_collection_hint(column.hint_string)


static func _is_dict_with_enum_keys(column: ColumnConfig) -> bool:
	return column.type == TYPE_DICTIONARY and column.hint_string and _is_enum_collection_hint(_get_dict_key_hint_part(column))


static func _is_dict_with_enum_values(column: ColumnConfig) -> bool:
	return column.type == TYPE_DICTIONARY and column.hint_string and _is_enum_collection_hint(_get_dict_value_hint_part(column))


static func _is_enum_collection_hint(hint: String) -> bool:
	return hint.length() > 3 and hint[1] == "/" and int(hint[2]) == PROPERTY_HINT_ENUM


static func _get_dict_key_hint_part(column: ColumnConfig) -> String:
	return column.hint_string.split(";", true, 1)[0]


static func _get_dict_value_hint_part(column: ColumnConfig) -> String:
	return column.hint_string.split(";", true, 1)[1]


static func _get_values_map(column: ColumnConfig) -> Dictionary:
	return column.get_cached(&"enum_values_map", parse_enum_hint_string.bind(_get_enum_value_hint_string(column)))


static func _get_keys_map(column: ColumnConfig) -> Dictionary:
	return column.get_cached(&"enum_keys_map", parse_enum_hint_string.bind(_get_enum_key_hint_string(column)))


static func _get_enum_value_hint_string(column: ColumnConfig) -> String:
	if column.type == TYPE_ARRAY:
		return column.hint_string.split(":", true, 1)[1]
	if column.type == TYPE_DICTIONARY:
		return _get_dict_value_hint_part(column).split(":", true, 1)[1]
	return column.hint_string


static func _get_enum_key_hint_string(column: ColumnConfig) -> String:
	return _get_dict_key_hint_part(column).split(":", true, 1)[1]
