# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
@icon("res://example/godomon/assets/class_icons/spiral.svg")
class_name GdmStatus
extends Resource

## Whether the status persists (major) or fades on switch-out (volatile).
## A monster can have only one MAJOR status at a time.
enum Kind {
	MAJOR,
	VOLATILE,
}

@export var name: String
@export_multiline var description: String
@export var kind: Kind = Kind.MAJOR

## All mechanical effects (including duration) live in the battle
## engine under this id.
@export var status_handler: StringName = &"none"

## Free-form tags checked by game logic, e.g.:
## &"prevents_action", &"boosts_capture"...
@export var flags: Array[StringName]

@export_group("Messages")
## Shown when the status is inflicted. {0} = monster name.
@export var apply_message: String
## Shown when trying to inflict it on an already-afflicted monster.
@export var already_message: String
## Shown each time the status's effect triggers (end of turn, skipped action...).
@export var trigger_message: String
## Shown when the status is cured or wears off.
@export var cure_message: String

@export_group("Presentation")
@export var color: Color
@export var icon: Texture2D
@export var short_label: String # 3-letter badge, e.g. "BRN"
