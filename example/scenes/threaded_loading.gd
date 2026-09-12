# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

extends VBoxContainer

const MONSTERS: Registry = preload("uid://k2yyt35u8f25")

var load_tracker: Registry.RegistryLoadTracker = null

@onready var status_entries: VBoxContainer = %StatusEntries
@onready var requested_entries: VBoxContainer = %RequestedEntries
@onready var uid_entries: VBoxContainer = %UIDEntries
@onready var resources_entries: VBoxContainer = %ResourcesEntries
@onready var progress: Label = %Progress


func _ready() -> void:
	load_tracker = MONSTERS.load_all_threaded_request()
	update_display()


func update_display() -> void:
	var status: Dictionary = load_tracker.status
	var status_keys := ClassDB.class_get_enum_constants(&"ResourceLoader", &"ThreadLoadStatus")
	fill_vbox(status_entries, load_tracker.status, status_keys)
	fill_vbox(requested_entries, load_tracker.requested)
	fill_vbox(uid_entries, load_tracker.uids)
	fill_vbox(resources_entries, load_tracker.resources)
	progress.text = "%.2f" % load_tracker.progress


func fill_vbox(vbox: VBoxContainer, content: Dictionary, enum_keys: PackedStringArray = []) -> void:
	const MAX_LENGTH := 23
	for child in vbox.get_children():
		child.queue_free()
	for key: Variant in content:
		var label := Label.new()
		var value: Variant = content[key] if enum_keys.is_empty() else enum_keys[content[key]]
		var text := ""
		if str(value).length() > MAX_LENGTH:
			text = "%s: ...%s" % [key, str(value).right(MAX_LENGTH)]
		else:
			text = "%s: %s" % [key, value]
		label.text = text

		vbox.add_child(label)


func _on_poll_button_pressed() -> void:
	update_display()
