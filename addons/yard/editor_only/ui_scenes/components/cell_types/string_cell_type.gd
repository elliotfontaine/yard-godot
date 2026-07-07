extends "res://addons/yard/editor_only/ui_scenes/components/cell_types/text_cell_type.gd"

## Plain string columns. Drawing and value parsing (raw text, as-is) come from
## CellType / TextCellType respectively; this class only adds classification.

static func matches(column: ColumnConfig) -> bool:
	return column.is_string_column()
