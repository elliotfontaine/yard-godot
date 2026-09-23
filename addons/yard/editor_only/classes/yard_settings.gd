# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends Object

## Registers YARD's custom Project Settings. Add a new one by adding an
## entry to SETTINGS below.

const UPDATE_CHANNEL := "yard/updates/channel"

const SETTINGS: Array[Dictionary] = [
	{
		"name": UPDATE_CHANNEL,
		"type": TYPE_STRING,
		"default": "Stable",
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Stable,Prerelease",
	},
]


## Safe to call every time the plugin loads: only fills in a value for
## settings that don't exist yet, never overwrites a project's own choice.
static func register_settings() -> void:
	for setting: Dictionary in SETTINGS:
		var path: String = setting.name
		if not ProjectSettings.has_setting(path):
			ProjectSettings.set_setting(path, setting.default)
		ProjectSettings.set_initial_value(path, setting.default)
		ProjectSettings.add_property_info(
			{
				"name": path,
				"type": setting.type,
				"hint": setting.get("hint", PROPERTY_HINT_NONE),
				"hint_string": setting.get("hint_string", ""),
			}
		)
		ProjectSettings.set_as_basic(path, true)
