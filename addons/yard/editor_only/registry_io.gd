@tool
extends Object

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const ClassUtils := Namespace.ClassUtils

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
		indexed_props: String,
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

	var props: Array[StringName] = []
	for p: String in indexed_props.split(",", false):
		props.append(StringName(p.strip_edges()))
	_replace_indexed_properties_list(registry, props)

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


## Rebuilds the property index by loading every registered resource and reading
## the currently indexed properties.[br][br]
##
## This is a blocking operation — it loads all resources synchronously.
## Only properties already registered via [method add_indexed_property] are indexed.
## Entries whose resource cannot be loaded are skipped.
static func rebuild_property_index(registry: Registry) -> Error:
	# Clear existing values while keeping registered property keys
	for property: StringName in registry._property_index:
		registry._property_index[property] = { }

	for uid: StringName in registry.get_all_uids():
		if not ResourceLoader.exists(uid):
			continue
		var res := load(uid)
		if res == null:
			continue
		var string_id := registry.get_string_id(uid)
		for property: StringName in registry._property_index.keys():
			if not property in res:
				continue
			var value: Variant = res.get(property)
			if not registry._property_index[property].has(value):
				registry._property_index[property][value] = { }
			registry._property_index[property][value][string_id] = true

	return ResourceSaver.save(registry)


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


## Returns true if [param res] matches the registry's class restriction (or [param alt_restriction]).
## Handles native classes, named scripts (class_name), and unnamed scripts (quoted path).
## Subclasses of the restriction are accepted.
static func is_resource_matching_restriction(
		registry: Registry,
		res: Resource,
		alt_restriction: StringName = &"",
) -> bool:
	if res == null:
		return false

	var restriction := String(alt_restriction if alt_restriction else registry._class_restriction)
	if restriction.is_empty():
		return true

	if is_quoted_string(restriction):
		var script_path := unquote(restriction)
		if not ResourceLoader.exists(script_path):
			return false
		var restriction_script := load(script_path) as Script
		if restriction_script == null:
			return false

		return ClassUtils.is_class_of(res, restriction_script)

	else:
		return ClassUtils.is_class_of(res, restriction)


## Returns true if [param class_string] names a valid Resource subclass.[br]
## Accepts native class names, script class_names, and quoted script paths.
static func is_resource_class_string(class_string: String) -> bool:
	class_string = class_string.strip_edges()
	if class_string.is_empty():
		return false

	if is_quoted_string(class_string):
		var path := unquote(class_string)
		if not ResourceLoader.exists(path):
			return false
		var script := load(path) as Script
		if script == null:
			return false
		return ClassUtils.is_class_of(script, "Resource")
	else:
		return ClassUtils.is_class_of(class_string, "Resource")


static func would_erase_entries(registry: Registry, new_restriction: String) -> bool:
	for uid: StringName in registry.get_all_uids():
		if not ResourceLoader.exists(uid):
			continue
		if not is_resource_matching_restriction(registry, load(uid), new_restriction):
			return true
	return false


## Returns true if [param string] is wrapped in matching single or double quotes.
static func is_quoted_string(string: String) -> bool:
	if string.length() < 2:
		return false
	var first := string[0]
	var last := string[-1]
	return (first == "\"" and last == "\"") or (first == "'" and last == "'")


## Strips the surrounding quotes from a quoted string.
## Call [method is_quoted_string] first to ensure the input is valid.
static func unquote(string: String) -> String:
	return string.substr(1, string.length() - 2)


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


## Reconciles the set of indexed properties to match [param properties] exactly.[br][br]
##
## Properties in [param properties] not yet indexed are added.
## Properties currently indexed but absent from [param properties] are removed.
## Existing index data for kept properties is preserved. Call
## [method rebuild_property_index] afterwards to refresh values.
static func _replace_indexed_properties_list(registry: Registry, properties: Array[StringName]) -> Error:
	var target := { }
	for p in properties:
		target[p] = true

	for existing: StringName in registry._property_index.keys():
		if not target.has(existing):
			registry._property_index.erase(existing)

	for p in properties:
		if not registry._property_index.has(p):
			registry._property_index[p] = { }

	return ResourceSaver.save(registry)
