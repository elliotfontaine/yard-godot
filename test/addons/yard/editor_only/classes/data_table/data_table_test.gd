# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends GdUnitTestSuite
## Data, sorting, filtering and selection of the generic spreadsheet. Rendering is left out.

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const DataTable := Namespace.DataTable
const ColumnConfig := Namespace.ColumnConfig

var _table: DataTable


func before_test() -> void:
	_table = auto_free(DataTable.new())
	add_child(_table)
	var columns: Array[ColumnConfig] = [
		ColumnConfig.new(&"name", "Name", TYPE_STRING),
		ColumnConfig.new(&"price", "Price", TYPE_INT),
		ColumnConfig.new(&"color", "Color", TYPE_COLOR),
	]
	_table.set_columns(columns)
	_set_rows(
		{
			&"potion": { &"name": "Potion", &"price": 10, &"color": Color.RED },
			&"sword": { &"name": "Sword", &"price": 30, &"color": Color.BLUE },
			&"elixir": { &"name": "Elixir", &"price": 5, &"color": Color.GREEN },
		},
	)


## DataTable expects each row as a Dictionary[StringName, Variant], like RegistryTableView builds
## them. Untyped rows break sorting and filtering.
func _set_rows(rows_by_id: Dictionary) -> void:
	var rows: Array[Dictionary] = []
	var row_ids: Array[StringName] = []
	for row_id: StringName in rows_by_id:
		var row: Dictionary[StringName, Variant] = { }
		row.assign(rows_by_id[row_id])
		row_ids.append(row_id)
		rows.append(row)
	_table.set_data(rows, row_ids)


func test_set_data_keeps_the_given_order() -> void:
	assert_array(_table.get_displayed_rows()).is_equal([&"potion", &"sword", &"elixir"])
	assert_that(_table.get_cell_value(&"sword", &"price")).is_equal(30)


func test_get_cell_value_of_an_unknown_cell_is_null() -> void:
	assert_that(_table.get_cell_value(&"shield", &"price")).is_null()
	assert_that(_table.get_cell_value(&"potion", &"weight")).is_null()


func test_ordering_by_a_numeric_column() -> void:
	_table.ordering_data(&"price")
	assert_array(_table.get_displayed_rows()).is_equal([&"elixir", &"potion", &"sword"])
	_table.ordering_data(&"price", false)
	assert_array(_table.get_displayed_rows()).is_equal([&"sword", &"potion", &"elixir"])
	assert_str(_table.sort_column).is_equal("price")
	assert_bool(_table.sort_ascending).is_false()


func test_ordering_by_a_text_column() -> void:
	_table.ordering_data(&"name")
	assert_array(_table.get_displayed_rows()).is_equal([&"elixir", &"potion", &"sword"])


func test_ordering_by_a_color_column_sorts_by_hue() -> void:
	_table.ordering_data(&"color")
	assert_array(_table.get_displayed_rows()).is_equal([&"potion", &"elixir", &"sword"])


func test_ordering_by_an_unknown_column_does_nothing() -> void:
	_table.ordering_data(&"weight")
	assert_array(_table.get_displayed_rows()).is_equal([&"potion", &"sword", &"elixir"])
	assert_str(_table.sort_column).is_empty()


func test_filter_is_case_insensitive_and_applied_on_set_data() -> void:
	_table.set_filter(&"name", "O")
	_set_rows(
		{
			&"potion": { &"name": "Potion", &"price": 10 },
			&"sword": { &"name": "Sword", &"price": 30 },
			&"elixir": { &"name": "Elixir", &"price": 5 },
		},
	)
	assert_array(_table.get_displayed_rows()).is_equal([&"potion", &"sword"])
	assert_str(_table.get_filter_column()).is_equal("name")
	assert_str(_table.get_filter_text()).is_equal("O")


func test_filter_on_a_removed_column_is_cleared() -> void:
	_table.set_filter(&"weight", "heavy")
	_set_rows({ &"potion": { &"name": "Potion" } })
	assert_array(_table.get_displayed_rows()).is_equal([&"potion"])
	assert_str(_table.get_filter_column()).is_empty()


func test_set_data_keeps_the_selection_of_remaining_rows() -> void:
	_table.set_selected_cell(&"sword", &"name")
	_set_rows({ &"sword": { &"name": "Sword" }, &"shield": { &"name": "Shield" } })
	assert_array(_table.selected_rows).is_equal([&"sword"])
	assert_str(_table.focused_row).is_equal("sword")

	_set_rows({ &"shield": { &"name": "Shield" } })
	assert_array(_table.selected_rows).is_empty()
	assert_str(_table.focused_row).is_empty()


func test_set_selected_cell_emits_cell_selected() -> void:
	var signals := monitor_signals(_table)
	_table.set_selected_cell(&"potion", &"price")
	# is_emitted() is a coroutine, but declared @abstract, so the analyzer can't tell.
	@warning_ignore("redundant_await")
	await assert_signal(signals).is_emitted(_table.cell_selected, &"potion", &"price")


func test_select_all_rows() -> void:
	_table.select_all_rows()
	assert_array(_table.selected_rows).is_equal([&"potion", &"sword", &"elixir"])
	assert_str(_table.focused_row).is_equal("potion")


func test_add_update_and_remove_rows() -> void:
	_table.add_row(&"shield", { &"name": "Shield", &"price": 40 })
	_table.update_cell(&"shield", &"price", 45)
	assert_that(_table.get_cell_value(&"shield", &"price")).is_equal(45)

	_table.update_row(&"potion", { &"name": "Big Potion" })
	assert_that(_table.get_cell_value(&"potion", &"name")).is_equal("Big Potion")
	assert_that(_table.get_cell_value(&"potion", &"price")).is_null()

	_table.set_selected_cell(&"sword", &"name")
	_table.remove_row(&"sword")
	assert_array(_table.get_displayed_rows()).not_contains([&"sword"])
	assert_array(_table.selected_rows).is_empty()
	assert_str(_table.focused_row).is_empty()
