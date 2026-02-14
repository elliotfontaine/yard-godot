@tool
extends Object

static func create_registry_file(
		path: String,
		class_restriction: String = "",
		scan_dir: String = "",
		recursive: bool = false,
		edit_on_creation: bool = false,
) -> Error:
	path = path.strip_edges()

	if path.is_empty() or not is_valid_registry_output_path(path):
		return ERR_FILE_BAD_PATH

	if ResourceLoader.exists(path):
		return ERR_FILE_CANT_WRITE

	var registry := Registry.new()

	if class_restriction and not is_resource_class_string(class_restriction):
		return ERR_DOES_NOT_EXIST

	if scan_dir and not DirAccess.dir_exists_absolute(scan_dir):
		return ERR_DOES_NOT_EXIST

	registry._class_restriction = class_restriction
	registry._scan_directory = scan_dir
	registry._recursive_scan = recursive

	var save_err := ResourceSaver.save(registry, path, ResourceSaver.FLAG_CHANGE_PATH)
	if edit_on_creation and save_err == OK:
		EditorInterface.edit_resource(load(path))

	EditorInterface.get_resource_filesystem().scan()
	return save_err


static func edit_registry_settings(
		registry: Registry,
		class_restriction: String,
		scan_dir: String,
		recursive: bool,
) -> Error:
	if class_restriction and not is_resource_class_string(class_restriction):
		return ERR_DOES_NOT_EXIST

	if scan_dir and not DirAccess.dir_exists_absolute(scan_dir):
		return ERR_DOES_NOT_EXIST

	registry._class_restriction = class_restriction
	registry._scan_directory = scan_dir
	registry._recursive_scan = recursive

	return OK


static func is_valid_registry_output_path(path: String) -> bool:
	path = path.strip_edges()
	if path.is_empty():
		return false

	if path.begins_with("res://"):
		path = path.trim_prefix("res://")

	var dir_rel := path.get_base_dir()
	var file := path.get_file()

	if file.is_empty() or not file.is_valid_filename():
		return false

	var dir_abs := "res://" + dir_rel
	return DirAccess.dir_exists_absolute(dir_abs)


static func is_resource_class_string(class_string: String) -> bool:
	class_string.strip_edges()
	if class_string.is_empty():
		return false

	if is_quoted_string(class_string):
		class_string = class_string.substr(1, class_string.length() - 2)
		if not ResourceLoader.exists(class_string):
			return false

		var res := load(class_string)
		if res == null or not (res is Script):
			return false

		var script := res as Script
		var base_type: StringName = script.get_instance_base_type()
		return base_type == &"Resource" or ClassDB.is_parent_class(base_type, &"Resource")

	if ClassDB.class_exists(class_string):
		return class_string == "Resource" or ClassDB.is_parent_class(class_string, &"Resource")

	for info: Dictionary in ProjectSettings.get_global_class_list():
		if info.get("class", "") == class_string:
			var base := StringName(info.get("base", ""))
			return base == &"Resource" or ClassDB.is_parent_class(base, &"Resource")

	return false


static func is_quoted_string(string: String) -> bool:
	if string.length() < 2:
		return false

	var first := string[0]
	var last := string[-1]

	return (first == "\"" and last == "\"") or (first == "'" and last == "'")
