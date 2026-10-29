# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT
@tool
@icon("res://example/godomon/assets/class_icons/dragon.svg")
class_name GdmMonster
extends Resource

enum GenderRatio {
	GENDERLESS,
	ALWAYS_MALE,
	FEMALE_ONE_EIGHTH,
	FEMALE_25_PERCENT,
	FEMALE_50_PERCENT,
	FEMALE_75_PERCENT,
	FEMALE_SEVEN_EIGHTH,
	ALWAYS_FEMALE,
}

enum GrowthRate {
	FAST,
	MEDIUM_FAST, # Also known as "medium"
	SLOW,
	MEDIUM_SLOW, # Also known as "parabolic"
	ERRATIC,
	FLUCTUATING,
}

enum EggGroup {
	MONSTER = 1 << 0,
	SEA_CREATURE = 1 << 1,
	BUG = 1 << 2,
	FLYING = 1 << 3,
	FIELD = 1 << 4,
	FAIRY = 1 << 5,
	VEGETAL = 1 << 6,
	HUMANLIKE = 1 << 7,
	SHELLFISH = 1 << 8,
	MINERAL = 1 << 9,
	AMORPHOUS = 1 << 10,
	FISH = 1 << 11,
	DRAGON = 1 << 12,
	UNDISCOVERED = 1 << 13,
}

## Body shape silhouette, used for dex sorting/filtering
enum BodyShape {
	HEAD, ## head only (e.g. a floating orb or face)
	SERPENTINE, ## snake-like, limbless elongated body
	FINNED, ## fish-like, fins instead of limbs
	HEAD_ARMS, ## head with arms, no legs
	HEAD_BASE, ## head atop a base/blob, no limbs
	BIPEDAL_TAIL, ## two legs with a tail
	HEAD_LEGS, ## head with legs directly attached
	QUADRUPED, ## four-legged
	WINGED, ## single pair of wings
	MULTIPED, ## many legs (more than four)
	MULTI_BODY, ## multiple bodies/segments (clusters, swarms)
	BIPEDAL, ## two legs, humanoid stance
	MULTI_WINGED, ## multiple pairs of wings
	INSECTOID, ## insect-like body plan
}

## The main body color of the species.
enum BodyColor {
	BLACK,
	BLUE,
	BROWN,
	GRAY,
	GREEN,
	PINK,
	PURPLE,
	RED,
	WHITE,
	YELLOW,
}

const REGISTRY_HINT := Registry.PROPERTY_HINT_CUSTOM
const ITEMS := "res://example/godomon/data/items.tres"
const MOVES := "res://example/godomon/data/moves.tres"
const MONSTERS := "res://example/godomon/data/monsters.tres"
const ELEMENTS := "res://example/godomon/data/elements.tres"
const ABILITIES := "res://example/godomon/data/abilities.tres"

@export var name: String
@export var form_name: String
@export var dex_number: int = 0
@export_custom(REGISTRY_HINT, ELEMENTS) var type_1: StringName = &"wild"
@export_custom(REGISTRY_HINT, ELEMENTS) var type_2: StringName
@export var evolutions: Array[GdmEvolution]
@export var flags: Array[StringName]

@export_group("Base Stats", "base_")
@export_range(0, 255, 1) var base_hp: int = 1
@export_range(0, 255, 1) var base_attack: int = 1
@export_range(0, 255, 1) var base_defense: int = 1
@export_range(0, 255, 1) var base_sp_attack: int = 1
@export_range(0, 255, 1) var base_sp_defense: int = 1
@export_range(0, 255, 1) var base_speed: int = 1
@export_custom(
	PROPERTY_HINT_RANGE,
	"0,800,hide_control",
	PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR,
) var base_stats_total: int:
	get:
		return (
			base_hp + base_attack + base_defense + base_sp_attack + base_sp_defense + base_speed
		)
	set(value):
		return

@export_group("Experience")
@export var growth_rate: GrowthRate = GrowthRate.MEDIUM_FAST
@export var experience_yield: int = 0
@export_subgroup("EVs")
@export_range(0, 3, 1) var ev_hp: int = 0
@export_range(0, 3, 1) var ev_attack: int = 0
@export_range(0, 3, 1) var ev_defense: int = 0
@export_range(0, 3, 1) var ev_sp_attack: int = 0
@export_range(0, 3, 1) var ev_sp_defense: int = 0
@export_range(0, 3, 1) var ev_speed: int = 0

@export_group("Encounter")
@export var gender_ratio: GenderRatio = GenderRatio.FEMALE_50_PERCENT
@export_range(0, 255, 5) var catch_rate: int = 255
@export_range(0, 255, 1) var happiness: int = 70
@export_subgroup("Held Items")
@export_custom(REGISTRY_HINT, ITEMS) var wild_item_common: Array[StringName] # 50%
@export_custom(REGISTRY_HINT, ITEMS) var wild_item_uncommon: Array[StringName] # 5%
@export_custom(REGISTRY_HINT, ITEMS) var wild_item_rare: Array[StringName] # 1%

@export_group("Moves & Abilities")
@export_custom(REGISTRY_HINT, MOVES) var moves: Dictionary[StringName, int]
@export_custom(REGISTRY_HINT, MOVES) var tutor_moves: Array[StringName]
@export_custom(REGISTRY_HINT, MOVES) var egg_moves: Array[StringName]
@export_custom(REGISTRY_HINT, ABILITIES) var abilities: Array[StringName]
@export_custom(REGISTRY_HINT, ABILITIES) var hidden_abilities: Array[StringName]

@export_group("Breeding")
@export var step_cycles: int = 1
@export_custom(REGISTRY_HINT, ITEMS) var incense: StringName
@export_custom(REGISTRY_HINT, MONSTERS + ",sort=dex_number") var custom_offspring: Array[StringName]
@export var egg_groups: int = EggGroup.UNDISCOVERED # See `_validate_property`

@export_group("Dex Info")
@export var category: String
@export_multiline var dex_entry: String
@export var height: float = 0.1
@export var weight: float = 0.1
@export var color: BodyColor = BodyColor.GRAY
@export var shape: BodyShape = BodyShape.QUADRUPED
@export var habitat: StringName
@export var keywords: String

@export_group("Graphics")
@export_subgroup("Sprites")
@export var front_normal: CompressedTexture2D
@export var front_shiny: CompressedTexture2D
@export var back_normal: CompressedTexture2D
@export var back_shiny: CompressedTexture2D
@export var menu_normal: CompressedTexture2D
@export var menu_shiny: CompressedTexture2D
@export var overworld_normal: CompressedTexture2D
@export var overworld_shiny: CompressedTexture2D
@export var dex_footprint: CompressedTexture2D
@export_subgroup("Metrics")
@export var front_offset: Vector2i
@export var back_offset: Vector2i

@export_group("Audio")
@export var cry: AudioStream
@export var cry_faint: AudioStream


func _validate_property(property: Dictionary) -> void:
	if property.name == "egg_groups":
		property.hint = PROPERTY_HINT_FLAGS
		property.hint_string = ",".join(EggGroup.keys())
