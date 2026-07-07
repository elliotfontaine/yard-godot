extends "res://addons/yard/editor_only/classes/data_table/cell_types/text_cell_type.gd"
## Plain string columns. Drawing and value parsing (raw text, as-is) come from
## CellType / TextCellType respectively; this class only adds classification.

static func matches(column: ColumnConfig) -> bool:
	return column.type == TYPE_STRING
