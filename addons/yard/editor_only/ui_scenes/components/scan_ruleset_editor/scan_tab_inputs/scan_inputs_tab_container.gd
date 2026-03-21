@tool
extends TabContainer
## Holds one or more scan input controls arranged as tabs. Requires an initial child control to act
## as the default scan input, which will be retained throughout operations, and used to spawn new
## duplicate inputs.

signal inputs_changed
signal request_action(action: StringName, args: Variant)

const ScanInputsTabContainer := preload("./scan_inputs_tab_container.gd")
const ScanTabInput := preload("./scan_tab_input.gd")

@export var tab_display_title := "Value"
@export var scan_tab_input_scene: PackedScene

var _inputs: Array[ScanTabInput] = []

var disabled: bool = false:
	set(value):
		disabled = value
		if is_node_ready():
			for input in _inputs:
				input.disabled = disabled


func _ready() -> void:
	if not Engine.is_editor_hint() or EditorInterface.get_edited_scene_root() == self:
		return
	
	# Clear any placeholder children
	for child in get_children():
		remove_child(child)
		child.queue_free()
	
	# Add one input to act on by default
	_add_input(false)
	
	disabled = disabled
	_update_tabs()


func get_all_values(ignore_empties: bool) -> Array[Variant]:
	var all_values: Array[Variant] = []
	for input in _inputs:
		var value: Variant = input.get_value()
		if ignore_empties:
			var value_type := typeof(value)
			if value_type == TYPE_STRING:
				if (value as String).is_empty():
					continue
		all_values.append(value)
	return all_values


func set_all_values(values: Array[Variant]) -> void:
	var inputs_count := _inputs.size()
	var new_values_count := values.size()
	var delta := new_values_count - inputs_count
	
	if delta > 0: # We need to add
		for i in delta:
			_add_input(false)
	elif delta < 0: # We need to remove
		var inputs_to_delete: Array[ScanTabInput] = []
		# i should be negative, we should be able to take from the end of the inputs list
		for i in absi(delta):
			inputs_to_delete.append(_inputs[(-i - 1)])
		for input in inputs_to_delete:
			_delete_input(input, false)
	
	for i in new_values_count:
		_inputs[i].set_value(values[i])


func render_validation_results(args: Array[Variant]) -> void:
	var args_count := args.size()
	if args_count != _inputs.size():
		printerr("Validation results args count invalid!")
		return
	
	for i in args_count:
		var input := _inputs[i]
		input.render_validation_results(args[i])


## Match the number of inputs & their values to another container's inputs. Only intended for
## containers that share the same input type!
func match_other_tab_inputs_container(other_container: ScanInputsTabContainer) -> void:
	set_all_values(other_container.get_all_values(false))


func update_selected_input_value(value: Variant) -> void:
	(get_current_tab_control() as ScanTabInput).set_value(value)


func _connect_input(input: ScanTabInput) -> void:
	input.input_changed.connect(inputs_changed.emit)
	input.request_action.connect(request_action.emit)
	input.request_delete.connect(_delete_input.bind(input))
	input.request_add.connect(_add_input)


func _delete_input(input: ScanTabInput, emit_changed := true) -> void:
	_inputs.erase(input)
	remove_child(input)
	input.queue_free()
	
	# Always ensure there is at least one available input
	if _inputs.is_empty():
		_add_input(false)
	
	if emit_changed:
		inputs_changed.emit()
	_update_tabs()


func _add_input(emit_changed := true) -> void:
	var new_input: ScanTabInput = scan_tab_input_scene.instantiate()
	_connect_input(new_input)
	add_child(new_input)
	_inputs.append(new_input)
	
	new_input.reset_value()
	
	if emit_changed:
		inputs_changed.emit()
	_update_tabs()


func _update_tabs() -> void:
	var tab_count := get_tab_count()
	for i in tab_count:
		set_tab_title(i, tab_display_title + " %d" % (i + 1))
	
	tabs_visible = tab_count > 1
