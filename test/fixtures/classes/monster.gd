@icon("res://icon.svg")
extends Resource

enum Element { FIRE, WATER, MINERAL, AIR, PLANT, SPIRIT, METAL, LIGHT, SHADOW }

@export var name: String
@export_multiline var desc: String
@export var dex_number: int
@export var sprite: Texture2D
@export var main_color: Color
@export var asexual: bool
@export var learnset: Dictionary[int, String]
@export_flags("can_contest", "mythic", "feral") var tags: int
@export_range(1, 100, 1) var max_level: float = 50
