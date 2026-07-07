extends RefCounted
## Column schema for DataTable, plus per-column dispatch to the CellType script
## responsible for it (see get_cell_type() below). This class only stores raw
## fields plus a generic cache that CellType scripts use to memoize their own
## derived data (range config, enum maps, etc.).

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

const CELL_TYPES_PRIORITY_LIST: Array[GDScript] = [
	RangeCellType,
	BooleanCellType,
	ColorCellType,
	ResourceCellType,
	PathCellType,
	EnumCellType,
	CollectionCellType,
	StringCellType,
	NumericCellType,
]

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

var _cache: Dictionary = { }


func _init(p_identifier: StringName, p_header: String, p_type: Variant.Type, p_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	identifier = p_identifier
	header = p_header
	type = p_type
	h_alignment = p_alignment
	if p_type in [TYPE_INT, TYPE_FLOAT]:
		h_alignment = HORIZONTAL_ALIGNMENT_RIGHT


## Generic memoization for CellType scripts to cache their own derived data
## (parsed hint strings, etc.) without ColumnConfig having to know what it means.
func get_cached(key: StringName, compute: Callable) -> Variant:
	if not _cache.has(key):
		_cache[key] = compute.call()
	return _cache[key]


## Returns the CellType script that draws/sorts/handles input for this column.
## First match wins; the order below is the dispatch priority.
func get_cell_type() -> GDScript:
	return get_cached(&"cell_type", _resolve_cell_type) as GDScript


## Like get_cell_type(), but falls back to the generic text editor (Numeric/
## String) for columns whose own CellType has no editor of its own (e.g. Range).
func get_editor_cell_type() -> GDScript:
	var handler := get_cell_type()
	if handler.has_editor():
		return handler
	if NumericCellType.matches(self):
		return NumericCellType
	if StringCellType.matches(self):
		return StringCellType
	return handler


func _resolve_cell_type() -> GDScript:
	for cell_type: GDScript in CELL_TYPES_PRIORITY_LIST:
		if cell_type.matches(self):
			return cell_type
	return CellType
