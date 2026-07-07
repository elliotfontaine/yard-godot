extends RefCounted
## Column schema for DataTable, plus per-column dispatch to the CellType
## script responsible for it (see get_cell_type() below).

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const CellType := Namespace.CellType
const StringCellType := Namespace.StringCellType
const NumericCellType := Namespace.NumericCellType
const BooleanCellType := Namespace.BooleanCellType
const RangeCellType := Namespace.RangeCellType
const ColorCellType := Namespace.ColorCellType
const ResourceCellType := Namespace.ResourceCellType
const PathCellType := Namespace.PathCellType
const EnumCellType := Namespace.EnumCellType
const CollectionCellType := Namespace.CollectionCellType

var identifier: StringName
var header: String
var type: Variant.Type
var property_hint: PropertyHint
var hint_string: String
var class_string: String
var h_alignment: HorizontalAlignment
var custom_font_color: Color
var custom_font: Font
var minimum_width: float:
	set(value):
		minimum_width = value
		current_width = current_width
var current_width: float:
	set(value):
		current_width = max(value, minimum_width)
var enum_values_map: Dictionary[int, String]:
	get:
		if not _enum_values_map_ready:
			enum_values_map = _parse_enum_hint_string(_get_enum_value_hint_string())
			_enum_values_map_ready = true
		return enum_values_map
var enum_keys_map: Dictionary[int, String]:
	get:
		if not _enum_keys_map_ready:
			enum_keys_map = _parse_enum_hint_string(_get_enum_key_hint_string())
			_enum_keys_map_ready = true
		return enum_keys_map
var range_config: Dictionary[StringName, Variant]:
	get:
		if not _range_config_ready:
			range_config = _compute_range_config()
			_range_config_ready = true
		return range_config

var _range_config_ready := false
var _enum_values_map_ready := false
var _enum_keys_map_ready := false
var _cell_type: GDScript
var _cell_type_ready := false


func _init(p_identifier: StringName, p_header: String, p_type: Variant.Type, p_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	identifier = p_identifier
	header = p_header
	type = p_type
	h_alignment = p_alignment
	if self.is_numeric_column():
		h_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func is_path_column() -> bool:
	var is_filesystem_hint := property_hint in [
		PROPERTY_HINT_FILE,
		PROPERTY_HINT_FILE_PATH,
		PROPERTY_HINT_DIR,
	]
	return type == TYPE_STRING and is_filesystem_hint


func is_range_column() -> bool:
	return type in [TYPE_FLOAT, TYPE_INT] and property_hint == PROPERTY_HINT_RANGE


func is_boolean_column() -> bool:
	return type == TYPE_BOOL


func is_string_column() -> bool:
	return type == TYPE_STRING


func is_numeric_column() -> bool:
	return type in [TYPE_INT, TYPE_FLOAT]


func is_integer_column() -> bool:
	return type == TYPE_INT


func is_float_column() -> bool:
	return type == TYPE_FLOAT


func is_color_column() -> bool:
	return type == TYPE_COLOR


func is_enum_column() -> bool:
	return property_hint == PROPERTY_HINT_ENUM


func is_resource_column() -> bool:
	return type == TYPE_OBJECT and property_hint == PROPERTY_HINT_RESOURCE_TYPE


func is_array_column() -> bool:
	return type == TYPE_ARRAY


func is_dictionary_column() -> bool:
	return type == TYPE_DICTIONARY


func is_collection_column() -> bool:
	return is_array_column() or is_dictionary_column()


func is_enum_array_column() -> bool:
	return is_array_column() and hint_string and _is_enum_collection_hint(hint_string)


func is_enum_key_dictionary_column() -> bool:
	return is_dictionary_column() and hint_string and _is_enum_collection_hint(_dict_key_hint_part())


func is_enum_value_dictionary_column() -> bool:
	return is_dictionary_column() and hint_string and _is_enum_collection_hint(_dict_value_hint_part())


func _get_enum_value_hint_string() -> String:
	if is_array_column():
		return hint_string.split(":", true, 1)[1]
	if is_dictionary_column():
		return _dict_value_hint_part().split(":", true, 1)[1]
	return hint_string


func _get_enum_key_hint_string() -> String:
	return _dict_key_hint_part().split(":", true, 1)[1]


func _dict_key_hint_part() -> String:
	return hint_string.split(";", true, 1)[0]


func _dict_value_hint_part() -> String:
	return hint_string.split(";", true, 1)[1]


func _is_enum_collection_hint(hint: String) -> bool:
	return hint.length() > 3 and hint[1] == "/" and int(hint[2]) == PROPERTY_HINT_ENUM


static func _parse_enum_hint_string(enum_hint_string: String) -> Dictionary[int, String]:
	var map: Dictionary[int, String] = { }
	var next_implicit := 0
	for entry: String in enum_hint_string.split(",", false):
		var colon := entry.rfind(":")
		if colon == -1:
			map[next_implicit] = entry
			next_implicit += 1
		else:
			var explicit_val := entry.substr(colon + 1).to_int()
			map[explicit_val] = entry.substr(0, colon)
			next_implicit = explicit_val + 1
	return map


func _compute_range_config() -> Dictionary[StringName, Variant]:
	if not is_range_column():
		return { }
	var hint_elements := hint_string.split(",", false)
	var result: Dictionary[StringName, Variant] = {
		&"min": float(hint_elements[0]) if hint_elements.size() > 0 else 0.0,
		&"max": float(hint_elements[1]) if hint_elements.size() > 1 else 1.0,
		&"step": float(hint_elements[2]) if hint_elements.size() > 2 else (0.001 if is_float_column() else 1.0),
	}
	for hint_str in hint_elements.slice(3):
		match hint_str:
			"or_greater":
				result[&"or_greater"] = true
			"or_less":
				result[&"or_less"] = true
	return result


## Returns the CellType script that draws/sorts/handles input for this column.
## First match wins; the order below reproduces the priority the old dispatch
## used (range and boolean checked before the type-neutral fallbacks).
func get_cell_type() -> GDScript:
	if not _cell_type_ready:
		_cell_type = _resolve_cell_type()
		_cell_type_ready = true
	return _cell_type


## Like get_cell_type(), but falls back to the generic text editor (Numeric/
## String) for columns whose own CellType has no editor of its own (Range).
func get_editor_cell_type() -> GDScript:
	var handler := get_cell_type()
	if handler.has_editor():
		return handler
	if is_numeric_column():
		return NumericCellType
	if is_string_column():
		return StringCellType
	return handler


func _resolve_cell_type() -> GDScript:
	if is_range_column():
		return RangeCellType
	if is_boolean_column():
		return BooleanCellType
	if is_color_column():
		return ColorCellType
	if is_resource_column():
		return ResourceCellType
	if is_path_column():
		return PathCellType
	if is_enum_column():
		return EnumCellType
	if is_collection_column():
		return CollectionCellType
	if is_string_column():
		return StringCellType
	if is_numeric_column():
		return NumericCellType
	return CellType
