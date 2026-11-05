# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends GdUnitTestSuite

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const ColumnConfig := Namespace.ColumnConfig
const CellType := Namespace.CellType
const StringCellType := Namespace.StringCellType
const StringNameCellType := Namespace.StringNameCellType
const MultilineCellType := Namespace.MultilineCellType
const NumericCellType := Namespace.NumericCellType
const BooleanCellType := Namespace.BooleanCellType
const RangeCellType := Namespace.RangeCellType
const ColorCellType := Namespace.ColorCellType
const ResourceCellType := Namespace.ResourceCellType
const PathCellType := Namespace.PathCellType
const EnumCellType := Namespace.EnumCellType
const BitFlagsCellType := Namespace.BitFlagsCellType
const RegistryEntryCellType := Namespace.RegistryEntryCellType
const CollectionCellType := Namespace.CollectionCellType

# Custom hints have no PropertyHint member.
@warning_ignore("int_as_enum_without_match")
const REGISTRY_HINT := Registry.PROPERTY_HINT_CUSTOM as PropertyHint


func _column(
	type: Variant.Type,
	hint: PropertyHint = PROPERTY_HINT_NONE,
	hint_string: String = "",
) -> ColumnConfig:
	var column := ColumnConfig.new(&"column", "Column", type)
	column.property_hint = hint
	column.hint_string = hint_string
	return column


func test_numeric_columns_are_right_aligned() -> void:
	assert_int(_column(TYPE_INT).h_alignment).is_equal(HORIZONTAL_ALIGNMENT_RIGHT)
	assert_int(_column(TYPE_FLOAT).h_alignment).is_equal(HORIZONTAL_ALIGNMENT_RIGHT)
	assert_int(_column(TYPE_STRING).h_alignment).is_equal(HORIZONTAL_ALIGNMENT_LEFT)
	var centered := ColumnConfig.new(&"name", "Name", TYPE_STRING, HORIZONTAL_ALIGNMENT_CENTER)
	assert_int(centered.h_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)


func test_width_never_goes_below_the_minimum() -> void:
	var column := _column(TYPE_STRING)
	column.minimum_width = 80.0
	column.current_width = 10.0
	assert_float(column.current_width).is_equal(80.0)
	column.current_width = 150.0
	column.minimum_width = 200.0
	assert_float(column.current_width).is_equal(200.0)


func test_get_cached_computes_once() -> void:
	var column := _column(TYPE_STRING)
	var calls: Array[int] = [0]
	var compute := func() -> int:
		calls[0] += 1
		return 42
	assert_int(column.get_cached(&"answer", compute)).is_equal(42)
	assert_int(column.get_cached(&"answer", compute)).is_equal(42)
	assert_int(calls[0]).is_equal(1)


func test_get_cell_type_picks_the_most_specific_type() -> void:
	var expected_cell_types: Array[Array] = [
		[_column(TYPE_INT, PROPERTY_HINT_RANGE, "0,10"), RangeCellType],
		[_column(TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,1"), RangeCellType],
		[_column(TYPE_BOOL), BooleanCellType],
		[_column(TYPE_COLOR), ColorCellType],
		[_column(TYPE_OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), ResourceCellType],
		[_column(TYPE_STRING, PROPERTY_HINT_FILE, "*.png"), PathCellType],
		[_column(TYPE_STRING, PROPERTY_HINT_DIR), PathCellType],
		[_column(TYPE_STRING_NAME, REGISTRY_HINT, "res://registry.tres"), RegistryEntryCellType],
		[_column(TYPE_STRING, REGISTRY_HINT, "res://registry.tres"), RegistryEntryCellType],
		[_column(TYPE_INT, PROPERTY_HINT_ENUM, "Low,High"), EnumCellType],
		[_column(TYPE_STRING, PROPERTY_HINT_ENUM, "red,green"), EnumCellType],
		[_column(TYPE_STRING_NAME, PROPERTY_HINT_ENUM_SUGGESTION, "a,b"), EnumCellType],
		[_column(TYPE_INT, PROPERTY_HINT_FLAGS, "A,B,C"), BitFlagsCellType],
		[_column(TYPE_ARRAY), CollectionCellType],
		[_column(TYPE_PACKED_STRING_ARRAY), CollectionCellType],
		[_column(TYPE_DICTIONARY), CollectionCellType],
		[_column(TYPE_STRING, PROPERTY_HINT_MULTILINE_TEXT), MultilineCellType],
		[_column(TYPE_STRING_NAME), StringNameCellType],
		[_column(TYPE_STRING), StringCellType],
		[_column(TYPE_INT), NumericCellType],
		[_column(TYPE_FLOAT), NumericCellType],
		[_column(TYPE_VECTOR2), CellType],
		[_column(TYPE_OBJECT), CellType],
	]
	for expected: Array in expected_cell_types:
		var column: ColumnConfig = expected[0]
		assert_object(column.get_cell_type()) \
				.append_failure_message("type %s, hint %d"
		% [type_string(column.type), column.property_hint]) \
				.is_same(expected[1])


func test_enum_suggestion_only_applies_to_strings() -> void:
	var column := _column(TYPE_INT, PROPERTY_HINT_ENUM_SUGGESTION, "1,2")
	assert_object(column.get_cell_type()).is_same(NumericCellType)


func test_get_editor_cell_type_falls_back_to_text_editors() -> void:
	assert_object(_column(TYPE_INT, PROPERTY_HINT_RANGE, "0,10").get_editor_cell_type()).is_same(
		NumericCellType,
	)
	assert_object(_column(TYPE_COLOR).get_editor_cell_type()).is_same(ColorCellType)
	assert_object(_column(TYPE_STRING).get_editor_cell_type()).is_same(StringCellType)
	assert_object(_column(TYPE_BOOL).get_editor_cell_type()).is_same(BooleanCellType)
