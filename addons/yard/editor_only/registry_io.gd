@tool
extends Object

const REGISTRY_FILE_EXTENSIONS := ["tres"]
const LOGGING_INFO_COLOR := "lightslategray"


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
	for uid in registry.get_all_uids():
		if not is_resource_matching_restriction(registry, load(uid)):
			erase_entry(registry, uid)

	registry._recursive_scan = recursive
	registry._scan_directory = scan_dir

	return ResourceSaver.save(registry)


## add a new Resource to the Registry from a UID.
## If no string_id is given, it will use the file basename.
## If the string_id is already used in the Registry, it will append a number to it.
static func add_entry(registry: Registry, uid: StringName, string_id: String = "") -> Error:
	var cache_id: int = ResourceUID.text_to_id(uid)
	if not ResourceUID.has_id(cache_id):
		return ERR_CANT_ACQUIRE_RESOURCE

	if string_id.begins_with(("uid://")):
		return ERR_INVALID_PARAMETER

	if uid in registry._uids_to_string_ids:
		return ERR_ALREADY_EXISTS

	if not is_resource_matching_restriction(registry, load(uid)):
		return ERR_DATABASE_CANT_WRITE

	if not string_id:
		string_id = ResourceUID.get_id_path(cache_id).get_file().get_basename()

	if string_id in registry._string_ids_to_uids:
		string_id = _make_string_unique(registry, string_id)

	registry._uids_to_string_ids[uid] = string_id as StringName
	registry._string_ids_to_uids[string_id] = uid

	return ResourceSaver.save(registry)


static func erase_entry(registry: Registry, id: StringName) -> Error:
	var uid := registry.get_uid(id)
	if not uid:
		return ERR_INVALID_PARAMETER

	registry._string_ids_to_uids.erase(registry.get_string_id(uid))
	registry._uids_to_string_ids.erase(uid)

	return ResourceSaver.save(registry)


static func rename_entry(
		registry: Registry,
		id: StringName,
		new_string_id: StringName,
) -> Error:
	var uid := registry.get_uid(id)
	if not uid:
		return ERR_INVALID_PARAMETER

	registry._string_ids_to_uids.erase(id)
	var unique_new_string_id := _make_string_unique(registry, new_string_id)
	registry._string_ids_to_uids[unique_new_string_id] = uid
	registry._uids_to_string_ids[uid] = unique_new_string_id
	return ResourceSaver.save(registry)


static func change_entry_uid(registry: Registry, id: StringName, new_uid: StringName) -> Error:
	var old_uid := registry.get_uid(id)
	if not old_uid:
		return ERR_INVALID_PARAMETER

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
		return ERR_INVALID_PARAMETER

	if registry._class_restriction:
		var res := load(new_uid)
		if not is_resource_matching_restriction(registry, res):
			push_error(
				"UID Change Error: The associated resource '%s' doesn't match the registry class restriction (%s)." % [
					res.resource_path.get_file(),
					registry._class_restriction,
				],
			)
			return ERR_INVALID_PARAMETER

	registry._uids_to_string_ids.erase(old_uid)
	registry._uids_to_string_ids[new_uid] = string_id
	registry._string_ids_to_uids[string_id] = new_uid
	return ResourceSaver.save(registry)


static func sync_registry_entries_from_scan_dir(registry: Registry) -> void:
	if not registry._scan_directory or not DirAccess.dir_exists_absolute(registry._scan_directory):
		return

	var n_added := 0
	var n_removed := 0
	var first_added := ""
	var first_removed := ""
	var scanned_uids := { }

	# Add
	for res in dir_get_matching_resources(registry, registry._scan_directory, registry._recursive_scan):
		var uid := ResourceUID.path_to_uid(res.resource_path)
		scanned_uids[uid] = true
		if add_entry(registry, uid) == OK:
			n_added += 1
			if n_added == 1:
				first_added = registry.get_string_id(uid)

	# Remove
	for uid in registry.get_all_uids():
		if scanned_uids.has(uid):
			continue
		var string_id := registry.get_string_id(uid)
		if erase_entry(registry, StringName(uid)) == OK:
			n_removed += 1
			if n_removed == 1:
				first_removed = string_id
		else:
			print_rich(
				"[color=%s]Failed to remove %s from %s.[/color]" % [
					LOGGING_INFO_COLOR,
					string_id,
					registry.resource_path.get_file(),
				],
			)

	var _log := func(action: String, prep: String, n: int, first: String) -> void:
		if n == 1:
			print_rich(
				"[color=%s]%s %s %s %s.[/color]" % [
					LOGGING_INFO_COLOR,
					action.capitalize(),
					first,
					prep,
					registry.resource_path.get_file(),
				],
			)
		elif n > 1:
			print_rich(
				"[color=%s]%s %s and %d more entr%s %s %s.[/color]" % [
					LOGGING_INFO_COLOR,
					action.capitalize(),
					first,
					n - 1,
					"ies" if n > 2 else "y",
					prep,
					registry.resource_path.get_file(),
				],
			)

	_log.call("added", "to", n_added, first_added)
	_log.call("removed", "from", n_removed, first_removed)


static func dir_has_matching_resource(registry: Registry, path: String, recursive: bool = false) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false

	dir.list_dir_begin()
	var next: String = dir.get_next()

	while next != "":
		var next_path: String = dir.get_current_dir().path_join(next)

		if recursive and dir.current_is_dir():
			var has_valid := dir_has_matching_resource(registry, next_path, recursive)
			if has_valid:
				dir.list_dir_end()
				return true
		elif (
			ResourceLoader.exists(next_path)
			and is_resource_matching_restriction(registry, load(next_path))
		):
			dir.list_dir_end()
			return true

		next = dir.get_next()
	return false


static func dir_get_matching_resources(registry: Registry, path: String, recursive: bool = false) -> Array[Resource]:
	var dir := DirAccess.open(path)
	if not path or not dir:
		return []

	dir.list_dir_begin()
	var next: String = dir.get_next()
	var matching_resources: Array[Resource] = []

	while next != "":
		var next_path: String = dir.get_current_dir().path_join(next)

		if recursive and dir.current_is_dir():
			matching_resources += dir_get_matching_resources(registry, next_path, recursive)
		elif ResourceLoader.exists(next_path):
			var res := load(next_path)
			if is_resource_matching_restriction(registry, res):
				matching_resources.append(res)

		next = dir.get_next()

	dir.list_dir_end()
	return matching_resources


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


static func is_resource_matching_restriction(registry: Registry, res: Resource, alt_restriction: StringName = &"") -> bool:
	# TODO: refactor using the new Class Utils script
	if res == null:
		return false
	#if valid_classes.is_empty():
	#return true
	if not registry._class_restriction and not alt_restriction:
		return true

	var class_restriction: StringName = alt_restriction if alt_restriction else registry._class_restriction
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


static func would_erase_entries(registry: Registry, new_restriction: String) -> bool:
	for uid: StringName in registry.get_all_uids():
		if not ResourceLoader.exists(uid):
			continue
		var is_valid := is_resource_matching_restriction(registry, load(uid), new_restriction)
		if not is_valid:
			return true

	return false


static func is_quoted_string(string: String) -> bool:
	if string.length() < 2:
		return false

	var first := string[0]
	var last := string[-1]

	return (first == "\"" and last == "\"") or (first == "'" and last == "'")


static func _edit_new_after_delay(path: String, delay: float) -> void:
	await Engine.get_main_loop().create_timer(delay).timeout
	EditorInterface.edit_resource(load(path))


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
