@tool
@icon("res://addons/yard/editor_only/assets/FileList.svg")
class_name Registry
extends Resource

## Invalid resources are not fetched and don't push errors.
const INVALID_RESOURCE_ID := &"<invalid>"
const CACHE_MODE_REUSE := ResourceLoader.CacheMode.CACHE_MODE_REUSE

@warning_ignore_start("unused_private_class_variable")
@export_storage var _class_restriction: StringName = &""
@export_storage var _scan_directory: String = ""
@export_storage var _recursive_scan: bool = false
@warning_ignore_restore("unused_private_class_variable")

@export_storage var _uids_to_string_ids: Dictionary[StringName, StringName]
@export_storage var _string_ids_to_uids: Dictionary[StringName, StringName]


func _init() -> void:
	if not Engine.is_editor_hint():
		# I mean, it already "private". But still.
		_uids_to_string_ids.make_read_only()
		_string_ids_to_uids.make_read_only()


func size() -> int:
	return _uids_to_string_ids.size()


func is_empty() -> bool:
	return _uids_to_string_ids.is_empty()


func has_uid(uid: StringName) -> bool:
	return _uids_to_string_ids.has(uid)


func has_string_id(id: StringName) -> bool:
	return _string_ids_to_uids.has(id)


func get_all_uids() -> Array[StringName]:
	return _uids_to_string_ids.keys()


func get_all_string_ids() -> Array[StringName]:
	return _uids_to_string_ids.keys()


## Given an [param id] (either String ID or UID),
## always returns the UID text ("uid://..."), or "" if [param id] is invalid
## (i.e. not in the registry).
func get_uid(id: StringName) -> StringName:
	if id == INVALID_RESOURCE_ID:
		return &""

	if id.is_empty():
		return &""

	if id.begins_with("uid://"):
		return id if _uids_to_string_ids.has(id) else &""

	var string_id := StringName(id)
	return _string_ids_to_uids.get(string_id, &"")


func get_string_id(uid: StringName) -> StringName:
	if _uids_to_string_ids.has(uid):
		return _uids_to_string_ids[uid]
	else:
		return &""


## Given an [param id] (either StringID or UID), returns the associated Resource in the Registry.
func load_entry(
		id: StringName,
		type_hint: String = "",
		cache_mode: ResourceLoader.CacheMode = CACHE_MODE_REUSE,
) -> Resource:
	var uid := get_uid(id)
	if uid == &"" or not ResourceLoader.exists(uid):
		return null
	else:
		return ResourceLoader.load(uid, type_hint, cache_mode)


func load_entry_threaded_get(id: StringName) -> Resource:
	var uid := get_uid(id)
	if uid == &"":
		return null
	else:
		return ResourceLoader.load_threaded_get(uid)


func load_entry_threaded_get_status(id: StringName, progress: Array = []) -> ResourceLoader.ThreadLoadStatus:
	var uid := get_uid(id)
	if uid == &"":
		return ResourceLoader.ThreadLoadStatus.THREAD_LOAD_INVALID_RESOURCE
	else:
		return ResourceLoader.load_threaded_get_status(uid, progress)


func load_entry_threaded_request(
		id: StringName,
		type_hint: String = "",
		use_sub_threads: bool = false,
		cache_mode: ResourceLoader.CacheMode = CACHE_MODE_REUSE,
) -> Error:
	var uid := get_uid(id)
	if uid == &"":
		return Error.ERR_CANT_RESOLVE
	else:
		return ResourceLoader.load_threaded_request(uid, type_hint, use_sub_threads, cache_mode)


func load_all_blocking(
		type_hint: String = "",
		cache_mode: ResourceLoader.CacheMode = CACHE_MODE_REUSE,
) -> Dictionary[StringName, Resource]:
	var dict: Dictionary[StringName, Resource] = { }

	for uid in get_all_uids():
		if not uid == &"" and ResourceLoader.exists(uid):
			dict[_uids_to_string_ids[uid]] = ResourceLoader.load(
				uid,
				type_hint,
				cache_mode,
			)

	return dict


func load_all_threaded_request(
		type_hint: String = "",
		use_sub_threads: bool = false,
		cache_mode := CACHE_MODE_REUSE,
) -> RegistryLoadTracker:
	var tracker := RegistryLoadTracker.new()

	for string_id: StringName in get_all_string_ids():
		var uid := get_uid(string_id)
		tracker.__uids[string_id] = uid
		tracker.__resources[string_id] = null
		var err := ResourceLoader.load_threaded_request(uid, type_hint, use_sub_threads, cache_mode)
		if err == OK:
			tracker.__requested[string_id] = true
			tracker.__status[string_id] = ResourceLoader.ThreadLoadStatus.THREAD_LOAD_IN_PROGRESS
		else:
			tracker.__requested[string_id] = false
			tracker.__status[string_id] = ResourceLoader.ThreadLoadStatus.THREAD_LOAD_INVALID_RESOURCE

	return tracker


class RegistryLoadTracker extends RefCounted:
	var progress: float:
		get:
			_poll()
			return __progress
	var uids: Dictionary[StringName, StringName]:
		get:
			return __uids.duplicate()
	var requested: Dictionary[StringName, bool]:
		get:
			return __requested.duplicate()
	var status: Dictionary[StringName, ResourceLoader.ThreadLoadStatus]:
		get:
			_poll()
			return __status.duplicate()
	var resources: Dictionary[StringName, Resource]:
		get:
			_poll()
			return __resources.duplicate()

	var __progress: float = 0.0
	var __uids: Dictionary[StringName, StringName]
	var __requested: Dictionary[StringName, bool]
	var __status: Dictionary[StringName, ResourceLoader.ThreadLoadStatus]
	var __resources: Dictionary[StringName, Resource]


	func _poll() -> void:
		var n_res_requested := 0
		var n_res_loaded := 0.0 # allow fractional loading progress
		for uid: String in __uids.values():
			var res_progress := []
			if not __requested[uid]:
				continue
			n_res_requested += 1
			__status[uid] = ResourceLoader.load_threaded_get_status(uid, res_progress)
			n_res_loaded += res_progress[0]
			if (
				__status[uid] == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED
				and __resources[uid] == null
			):
				__resources[uid] = ResourceLoader.load_threaded_get(uid)

		__progress = n_res_loaded / n_res_requested
