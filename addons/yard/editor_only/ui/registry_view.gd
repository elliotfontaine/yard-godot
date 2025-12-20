@tool
extends Panel

# Reference to dynamic table
@onready var dynamic_table := $DynamicTable
# Popups
@onready var popup := $PopupMenu
@onready var confirm_popup := $ConfirmationDialog
@onready var ico := load("res://icon.svg")

var headers: Array # array of columns header
var data: Array # array of data, rows and columns
var current_selected_row := -1
var current_multiple_selected_rows := -1 # current multiple selected_rows
var multiple_selected_rows: Array # array of selected rows


func _ready() -> void:
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END

	headers = ["ID|C", "Name", "Lastname", "Age|r", "Job", "City", "Date", "Task|p", "Completed|check", "Icon|image"]
	dynamic_table.set_headers(headers)
	
	# Example data
	data = [
		[1, "Michael", "Smith", 34, "Engineer", "London", "10/12/2005", 0.5, 1, ico],
		[2, "Louis", "Johnson", 28, "Doctor", "New York", "05/11/2023", 0],
		[3, "Ann", "Williams", 42, "Lawyer", "Tokyo", "18/03/2025", 0, 0],
		[4, "John", "Brown", 31, "Teacher", "Sydney", "02/07/2024", 0, 0],
		[5, "Frances", "Jones", 25, "Designer", "Paris", "29/09/2023", 0, 0],
		[6, "Robert", "", 39, "Architect", "Berlin", "14/01/2026", 0, 0],
		[7, "Lucy", "Davis", 36, "Accountant", "Madrid", "07/04/2024", 0, 0],
		[8, "Mark", "Miller", 44, "Entrepreneur", "Toronto", "21/08/2025", 0, 0],
		[9, "Paula", "Wilson", 29, "Journalist", "Rio de Janeiro", "10/12/2023", 0, 0],
		[10, "Stephen", "Moore", 33, "Programmer", "Dubai", "30/11/2024", 0, 0],
		[11, "Mark", "Jefferson", 31, "Dentist", "Lisbona", "10/02/2018", 0.47, 1],
		[12, "James", "Taylor", 28, "Doctor", "Chicago", "03/06/2026", 0, 0],
		[13, "Carmen", "Anderson", 42, "Lawyer", "Hong Kong", "25/02/2024", 0, 0],
		[14, "John", "Thomas", 39, "Architect", "Amsterdam", "17/10/2025", 0, 0],
		[15, "Paul", "Jackson", 44, "Entrepreneur", "Singapore", "09/05/2023", 0, 0],
		[16, "Jennifer", "White", 29, "Journalist", "Cape Town", "01/03/2023", 0, 0],
		[17, "Luke", "Harris", 33, "Programmer", "Seoul", "28/04/2023", 0, 0],
		[18, "Peter", "Martin", 25, "Designer", "Mexico City", "11/08/2024", 0, 0],
		[19, "Matthew", "Thompson", 39, "Architect", "Moscow", "13/09/2024", 0, 0],
		[20, "Louise", "Garcia", 36, "Accountant", "Istanbul", "04/12/2025", 0, 0],
		[21, "Matthew", "Martinez", 44, "Entrepreneur", "Buenos Aires", "06/01/2025", 0, 0],
		[22, "Stephanie", "Robinson", 29, "Journalist", "Cairo", "22/07/2023", 0, 0],
		[23, "Christopher", "Clark", 51, "Architect", "Tokyo", "12/05/2021", 0, 0],
		[24, "Amanda", "Rodriguez", 33, "Graphic Designer", "Sydney", "11/03/2020", 0, 0],
		[25, "Daniel", "Lewis", 47, "Software Engineer", "Berlin", "03/04/2023", 0, 0],
		[26, "Victoria", "Lee", 28, "Marketing Specialist", "Toronto", "04/05/2021", 0, 0],
		[27, "Joseph", "Walker", 55, "Professor", "London", "12/05/2021", 0, 0],
		[28, "Ashley", "Young", 39, "Chef", "Paris", "22/05/2024", 0, 0],
		[29, "Kevin", "Allen", 42, "Financial Analyst", "Mexico City", "08/02/2025", 0, 0],
		[30, "Elizabeth", "King", 31, "Photographer", "Rome", "11/09/2020", 0, 0]
	]

	# Insert data table
	dynamic_table.set_data(data)
	# Default sorted column 
	dynamic_table.ordering_data(0, true) # 0 -> ID column and true -> ascending order
	
	# Signals connections
	dynamic_table.cell_selected.connect(_on_cell_selected)
	dynamic_table.cell_right_selected.connect(_on_cell_right_selected)
	dynamic_table.cell_edited.connect(_on_cell_edited)
	dynamic_table.header_clicked.connect(_on_header_clicked)
	dynamic_table.column_resized.connect(_on_column_resized)
	dynamic_table.multiple_rows_selected.connect(_on_multiple_rows_selected)


func _process(_delta: float) -> void:
	if (Input.is_key_pressed(KEY_DELETE) and (current_selected_row >= 0 or current_multiple_selected_rows > 0)): # add support deleting items from keyboard
		_confirm_delete_rows()
		

func _on_cell_selected(row: int, column: int) -> void:
	print("Cell selected on row ", row, ", column ", column, " Cell value: ", dynamic_table.get_cell_value(row, column), " Row value: ", dynamic_table.get_row_value(row))
	current_selected_row = row
	current_multiple_selected_rows = -1


func _on_cell_right_selected(row: int, column: int, mouse_pos: Vector2) -> void:
	print("Cell right selected on row ", row, ", column ", column, " Mouse position x: ", mouse_pos.x, " y: ", mouse_pos.y)
	if (row >= 0): # ignore header cells
		current_selected_row = row
		popup.position = mouse_pos
		if (data.size() == 0 or row == data.size()):
			popup.set("item_1/disabled", true)
			current_multiple_selected_rows = -1
		else:
			popup.set("item_1/disabled", false)
		popup.show()


func _on_multiple_rows_selected(rows: Array) -> void:
	current_multiple_selected_rows = rows.size() # number of current multiple rows selected
	multiple_selected_rows = rows # current multiple rows selected array


func _on_cell_edited(row: int, column: int, old_value: Variant, new_value: Variant) -> void:
	print("Cell edited on row ", row, ", column ", column, " Old value: ", old_value, " New value: ", new_value)


func _on_header_clicked(column: int) -> void:
	print("Header clicked on column ", column)


func _on_column_resized(column: int, new_width: float) -> void:
	print("Column ", column, " resized at width ", new_width)


func _on_popup_menu_id_pressed(id: int) -> void:
	if (id == 0): # Insert data row
		dynamic_table.insert_row(current_selected_row, [0, "----", "--------", "--", "-----", "-----", "01/01/2000", 0, 0])
	else: # Delete data row
		_confirm_delete_rows()


func _confirm_delete_rows() -> void:
	var dialogtext := "Are you sure you want to delete %s?"
	if (current_multiple_selected_rows > 0):
		confirm_popup.dialog_text = dialogtext % ["these " + str(current_multiple_selected_rows) + " rows"]
	else:
		confirm_popup.dialog_text = dialogtext % "this row"
	confirm_popup.show()


func _on_confirmation_dialog_confirmed() -> void:
	if (current_multiple_selected_rows > 0): # multiple rows
		multiple_selected_rows.sort_custom(func(a: Array, b: Array) -> bool: return a > b)
		for rowidx in range(0, multiple_selected_rows.size()):
			dynamic_table.delete_row(multiple_selected_rows[rowidx])
		multiple_selected_rows.clear()
	else:
		dynamic_table.delete_row(current_selected_row) # single row
	dynamic_table.set_selected_cell(-1, -1) # cancel current selection
