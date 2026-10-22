# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
extends "res://addons/yard/editor_only/classes/data_table/cell_types/cell_type.gd"
## Array/Dictionary columns. display-only: no custom editor.

const ResourceCellType := Namespace.ResourceCellType

const ARRAY_TYPES := [
	TYPE_ARRAY,
	TYPE_PACKED_BYTE_ARRAY,
	TYPE_PACKED_INT32_ARRAY,
	TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY,
	TYPE_PACKED_FLOAT64_ARRAY,
	TYPE_PACKED_STRING_ARRAY,
	TYPE_PACKED_VECTOR2_ARRAY,
	TYPE_PACKED_VECTOR3_ARRAY,
	TYPE_PACKED_VECTOR4_ARRAY,
	TYPE_PACKED_COLOR_ARRAY,
]


static func matches(column: ColumnConfig) -> bool:
	return _is_dictionary(column) or _is_array(column)


static func draw_cell(
	canvas: CanvasItem,
	rect: Rect2,
	value: Variant,
	column: ColumnConfig,
	style: CellStyle,
) -> void:
	var text := _format_collection_text(value, column)
	draw_text(
		canvas,
		rect,
		text,
		resolve_font(column, style.font),
		style.font_size,
		column.h_alignment,
		resolve_text_color(column, style),
	)


static func get_tooltip(value: Variant, column: ColumnConfig) -> String:
	return _value_to_string_pretty(value, 0, _get_null_element_text(column))


static func get_sort_key(value: Variant, column: ColumnConfig) -> Variant:
	return _format_collection_text(value, column)


static func get_filter_key(value: Variant, column: ColumnConfig) -> Variant:
	return _format_collection_text(value, column)


static func _is_array(column: ColumnConfig) -> bool:
	return column.type in ARRAY_TYPES


static func _is_dictionary(column: ColumnConfig) -> bool:
	return column.type == TYPE_DICTIONARY


static func _is_array_with_enum_values(column: ColumnConfig) -> bool:
	return (
		column.type == TYPE_ARRAY and column.hint_string
		and _is_enum_collection_hint(column.hint_string)
	)


static func _is_dict_with_enum_keys(column: ColumnConfig) -> bool:
	return (
		_is_dictionary(column) and column.hint_string
		and _is_enum_collection_hint(_get_dict_key_hint_part(column))
	)


static func _is_dict_with_enum_values(column: ColumnConfig) -> bool:
	return (
		_is_dictionary(column) and column.hint_string
		and _is_enum_collection_hint(_get_dict_value_hint_part(column))
	)


static func _is_enum_collection_hint(hint: String) -> bool:
	return hint.length() > 3 and hint[1] == "/" and int(hint[2]) == PROPERTY_HINT_ENUM


## Array elements or dictionary values typed as a Resource, where null is an
## empty resource slot, as in a single Resource column.
static func _holds_resources(column: ColumnConfig) -> bool:
	if column.type == TYPE_ARRAY:
		return _is_resource_collection_hint(column.hint_string)
	return (
		_is_dictionary(column) and column.hint_string
		and _is_resource_collection_hint(_get_dict_value_hint_part(column))
	)


static func _is_resource_collection_hint(hint: String) -> bool:
	return hint.begins_with("%d/%d:" % [TYPE_OBJECT, PROPERTY_HINT_RESOURCE_TYPE])


static func _get_null_element_text(column: ColumnConfig) -> String:
	return editor_tr("<empty>") if _holds_resources(column) else "null"


static func _get_dict_key_hint_part(column: ColumnConfig) -> String:
	return column.hint_string.split(";", true, 1)[0]


static func _get_dict_value_hint_part(column: ColumnConfig) -> String:
	return column.hint_string.split(";", true, 1)[1]


static func _get_values_map(column: ColumnConfig) -> Dictionary:
	return column.get_cached(
		&"enum_values_map",
		parse_enum_hint_string.bind(_get_enum_value_hint_string(column)),
	)


static func _get_keys_map(column: ColumnConfig) -> Dictionary:
	return column.get_cached(
		&"enum_keys_map",
		parse_enum_hint_string.bind(_get_enum_key_hint_string(column)),
	)


static func _get_enum_value_hint_string(column: ColumnConfig) -> String:
	if column.type == TYPE_ARRAY:
		return column.hint_string.split(":", true, 1)[1]
	if _is_dictionary(column):
		return _get_dict_value_hint_part(column).split(":", true, 1)[1]
	return column.hint_string


static func _get_enum_key_hint_string(column: ColumnConfig) -> String:
	return _get_dict_key_hint_part(column).split(":", true, 1)[1]


static func _format_collection_text(collection: Variant, column: ColumnConfig) -> String:
	var is_dict := _is_dictionary(column)
	var items: Array = (collection as Dictionary).keys() if is_dict else (collection as Array)
	var keys_map: Dictionary = _get_keys_map(column) if _is_dict_with_enum_keys(column) else { }
	var values_map: Dictionary = (
		_get_values_map(column)
		if _is_dict_with_enum_values(column) or _is_array_with_enum_values(column)
		else { }
	)
	var null_text := _get_null_element_text(column)
	var parts: Array[String] = []
	for idx in items.size():
		if is_dict:
			var key: Variant = items[idx]
			var val: Variant = (collection as Dictionary)[key]
			parts.append(
				"%s: %s"
				% [
					_format_element_text(key, keys_map),
					_format_element_text(val, values_map, null_text),
				],
			)
		else:
			parts.append(_format_element_text(items[idx], values_map, null_text))

	var result := ", ".join(parts)
	return "{ %s }" % result if is_dict else "[%s]" % result


static func _format_element_text(
	elem: Variant,
	enum_map: Dictionary = { },
	null_text: String = "null",
) -> String:
	if elem == null:
		return null_text
	if elem is Resource:
		return "<%s>" % ResourceCellType.get_label(elem)
	if elem is Array:
		return "Array(%d)" % (elem as Array).size()
	if elem is Dictionary:
		return "Dict(%d)" % (elem as Dictionary).size()
	if elem is int and not enum_map.is_empty():
		var int_elem := elem as int
		return enum_map[int_elem] if enum_map.has(int_elem) else "?:%d" % int_elem
	return var_to_str(elem)


# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: Copyright 2025 Okxa <https://github.com/godotengine/godot-proposals/issues/538#issuecomment-2989009057>
# SPDX-SnippetCopyrightText: 2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-SnippetComment: Adapted for YARD: typed loops, formats dictionary keys of any type,
# resource summaries and empty resource slots.
#
# SPDX-License-Identifier: MIT
static func _value_to_string_pretty(
	value: Variant,
	indent_level: int = 0,
	null_text: String = "null",
) -> String:
	const INDENT: String = "    "
	var formatted: String = ""
	match typeof(value):
		var type when type in ARRAY_TYPES:
			if value.is_empty():
				formatted += "[]"
			else:
				formatted += "[\n"
				for i: int in value.size():
					formatted += (
						INDENT.repeat(indent_level + 1)
						+ _value_to_string_pretty(value[i], indent_level + 1, null_text)
						+ ("," if i < value.size() - 1 else "") + "\n"
					)
				formatted += INDENT.repeat(indent_level) + "]"
		TYPE_DICTIONARY:
			if value.is_empty():
				formatted += "{}"
			else:
				formatted += "{\n"
				var keys: Array = value.keys()
				for i: int in keys.size():
					formatted += (
						INDENT.repeat(indent_level + 1)
						+ _value_to_string_pretty(keys[i], indent_level + 1) + ": "
						+ _value_to_string_pretty(value[keys[i]], indent_level + 1, null_text)
						+ ("," if i < keys.size() - 1 else "") + "\n"
					)
				formatted += INDENT.repeat(indent_level) + "}"
		TYPE_NIL:
			formatted += null_text
		TYPE_OBJECT when value is Resource:
			formatted += ResourceCellType.get_inline_summary(value)
		_:
			formatted += var_to_str(value)
	return formatted
# SPDX-SnippetEnd
