@tool
extends Object

const REGISTRY_FILE_EXTENSIONS := ["tres"]


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
	EditorInterface.get_resource_filesystem().scan()

	if edit_on_creation and save_err == OK:
		_edit_new_after_delay(path, 0.5)

	return save_err


static func _edit_new_after_delay(path: String, delay: float) -> void:
	await Engine.get_main_loop().create_timer(delay).timeout
	EditorInterface.edit_resource(load(path))


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


static func rename_entry(
		registry: Registry,
		old_string_id: StringName,
		new_string_id: StringName,
) -> void:
	var uid := registry.get_uid(old_string_id)
	if uid:
		registry._string_ids_to_uids.erase(old_string_id)
		var unique_new_string_id := _make_string_unique(registry, new_string_id)
		registry._string_ids_to_uids[unique_new_string_id] = uid
		registry._uids_to_string_ids[uid] = unique_new_string_id


static func change_entry_uid(registry: Registry, id: StringName, new_uid: StringName) -> void:
	var old_uid := registry.get_uid(id)
	if not old_uid:
		return

	var string_id := registry.get_string_id(old_uid)
	if registry.has_uid(new_uid):
		var already_there_string_id := registry.get_string_id(new_uid)
		push_error(
			"UID Change Error: You can't use %s for '%s', as it's already in the registry as '%s'" % [
				new_uid,
				string_id,
				already_there_string_id,
			],
		)
		return

	if registry._class_restriction:
		var res := load(new_uid)
		if not _is_resource_class_valid(registry, res):
			push_error(
				"UID Change Error: The associated resource '%s' doesn't match the registry class restriction (%s)." % [
					res.resource_path.get_file(),
					registry._class_restriction,
				],
			)
			return

	registry._uids_to_string_ids.erase(old_uid)
	registry._uids_to_string_ids[new_uid] = string_id
	registry._string_ids_to_uids[string_id] = new_uid


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


## add a new Resource to the Registry from a UID.
## If no string_id is given, it will use the file basename.
## If the string_id is already used in the Registry, it will append a number to it.
static func _add_entry(registry: Registry, uid: StringName, string_id: String = "") -> bool:
	var cache_id: int = ResourceUID.text_to_id(uid)
	if not ResourceUID.has_id(cache_id):
		return false

	if string_id.begins_with(("uid://")):
		return false

	if not string_id:
		string_id = ResourceUID.get_id_path(cache_id).get_file().get_basename()

	if string_id in registry._string_ids_to_uids:
		string_id = _make_string_unique(registry, string_id)

	if uid in registry._uids_to_string_ids:
		return false

	registry._uids_to_string_ids[uid] = string_id as StringName
	registry._string_ids_to_uids[string_id] = uid
	return true


static func _make_string_unique(registry: Registry, string_id: String) -> String:
	if not string_id in registry._string_ids_to_uids:
		return string_id

	var regex := RegEx.new()
	regex.compile("(_\\d+)$")
	string_id = regex.sub(string_id, "", true)

	var id_to_try := string_id
	var n := 2
	while id_to_try + "_" + str(n) in registry._string_ids_to_uids:
		n += 1
	return id_to_try + "_" + str(n)


static func _validate_uids(registry: Registry) -> Dictionary[StringName, bool]:
	var ret: Dictionary[StringName, bool] = { }
	for uid in registry._uids_to_string_ids:
		ret[uid] = _is_uid_valid(uid)
	return ret


static func _is_uid_valid(uid: StringName) -> bool:
	if uid == &"" or uid == Registry.INVALID_RESOURCE_ID:
		return false

	var uid_str := String(uid)
	if not uid_str.begins_with("uid://"):
		return false

	var cache_id: int = ResourceUID.text_to_id(uid_str)
	return ResourceUID.has_id(cache_id)


static func _validate_resource_classes(registry: Registry) -> void:
	for uid: StringName in registry._uids_to_string_ids:
		if not ResourceLoader.exists(uid):
			continue
		var is_valid := _is_resource_class_valid(registry, load(uid))
		if not is_valid:
			pass
			#set_invalid_resource(uid)
	#_emit_registry_entries_changed()


static func _is_resource_class_valid(registry: Registry, res: Resource) -> bool:
	# TODO: refactor using the new Class Utils script
	if res == null:
		return false
	#if valid_classes.is_empty():
	#return true
	if not registry._class_restriction:
		return true

	var class_restriction: StringName = registry._class_restriction
	var class_stringname: StringName
	var res_script: Script = res.get_script()
	if res_script != null:
		var global_name := StringName(res_script.get_global_name())
		if not global_name.is_empty():
			class_stringname = global_name
		else:
			class_stringname = StringName(res.get_class())
	else:
		class_stringname = StringName(res.get_class())

	#for valid_class in valid_classes:
	if class_stringname == class_restriction:
		return true
	if res.is_class(String(class_restriction)):
		return true
	if ClassDB.is_parent_class(String(class_stringname), String(class_restriction)):
		return true

	return false
