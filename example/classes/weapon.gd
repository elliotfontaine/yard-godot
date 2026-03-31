class_name Weapon
extends Item

enum WeaponType { SWORD, AXE, BLUNT, BOW, CROSSBOW, DAGGER, THROWN, SHIELD, STAFF }
enum DamageType { PHYSICAL, MAGICAL }

@export var weapon_type: WeaponType = WeaponType.SWORD
@export var damage_type: DamageType = DamageType.PHYSICAL
@export var damage_min: int = 1
@export var damage_max: int = 5
@export_range(0.0, 10.0, 1.0, "or_greater") var attack_speed: float = 1.0
@export_range(0.0, 1.0, 0.01) var critical_hit_chance: float = 0.05
@export var is_two_handed: bool = false
@export var is_ranged_weapon: bool = false
@export var required_strength: int = 0
