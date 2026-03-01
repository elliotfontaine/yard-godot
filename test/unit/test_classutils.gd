extends GutTest

@warning_ignore_start("untyped_declaration")

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const ClassUtils := Namespace.ClassUtils

const UPGRADE_DATA_SCRIPT = preload("uid://dal80o4tjrktw")
const UPGRADE_GEAR_DATA_SCRIPT = preload("uid://cepmbq60ss420") # class_name, extends UpgradeData by class_name
const UpgradeWeaponData = preload("uid://dk08sbdai3pem") # no class_name, extends UpgradeData by path
const UpgradeToolData = preload("uid://debq61hnidsro") # no class_name, extends UpgradeData by class_name

const WOOD = preload("uid://uge4rk0vtwxs")
const UPGRADE_STRENGTH = preload("uid://c6hsg3j74vm56")
const WEAPON_BLIZZARD: UpgradeWeaponData = preload("uid://djqq1lqaevth5")
const TOOL_SHOVEL: UpgradeToolData = preload("uid://b3lolnnlh808g")


class TestTypeName extends GutTest:
	func test_assert_eq_wood_typename_is_item():
		assert_eq(ClassUtils.get_type_name(WOOD), &"Item")


	func test_assert_eq_blizzard_typename_is_upgradedata():
		assert_eq(ClassUtils.get_type_name(WEAPON_BLIZZARD), &"UpgradeData")


	func test_assert_eq_shovel_typename_is_upgradedata():
		assert_eq(ClassUtils.get_type_name(WEAPON_BLIZZARD), &"UpgradeData")
	
	func test_assert_eq_upgrade_data_script_typename_is_upgradedata():
		assert_eq(ClassUtils.get_type_name(UPGRADE_DATA_SCRIPT), &"UpgradeData")
	
	func test_assert_eq_upgrade_gear_data_script_typename_is_upgradegeardata():
		assert_eq(ClassUtils.get_type_name(UPGRADE_GEAR_DATA_SCRIPT), &"UpgradeGearData")


class TestScriptInheritance extends GutTest:
	func test_assert_eq():
		assert_has(ClassUtils.get_script_inheritance_list(UpgradeWeaponData), UpgradeData)


class TestInheritance extends GutTest:
	func test_assert_true_resource_is_resource():
		assert_true(ClassUtils.is_class_of("Resource", "Resource"))
		assert_true(ClassUtils.is_class_of(&"Resource", "Resource"))
		assert_true(ClassUtils.is_class_of(&"Resource", &"Resource"))
		assert_true(ClassUtils.is_class_of(Resource.new(), "Resource"))
		assert_true(ClassUtils.is_class_of("Resource", Resource.new()))
		assert_true(ClassUtils.is_class_of(Resource.new(), Resource.new()))


	func test_assert_false_resource_is_node():
		assert_false(ClassUtils.is_class_of("Resource", "Node"))


	func test_assert_true_item_script_is_resource():
		assert_true(ClassUtils.is_class_of("Item", "Resource"))
		assert_true(ClassUtils.is_class_of(Item, "Resource"))


	func test_assert_false_resource_is_not_item():
		assert_false(ClassUtils.is_class_of("Resource", "Item"))


	func test_assert_true_item_instance_is_resource():
		assert_true(ClassUtils.is_class_of("Item", "Resource"))
		assert_true(ClassUtils.is_class_of(Item.new(), "Resource"))


	func test_assert_true_wood_is_item():
		assert_true(ClassUtils.is_class_of(WOOD, "Item"))


	func test_assert_true_upgrade_data_instance_is_resource():
		assert_true(ClassUtils.is_class_of(UpgradeData.new(), "Resource"))


	func test_assert_true_upgrade_data_script_is_resource():
		assert_true(ClassUtils.is_class_of(UpgradeData, "Resource"))


	func test_upgrade_weapon_data_script_is_resource():
		assert_true(ClassUtils.is_class_of(UpgradeWeaponData, "Resource"))


	func test_upgrade_weapon_data_instance_is_resource():
		assert_true(ClassUtils.is_class_of(UpgradeWeaponData.new(), "Resource"))


	func test_upgrade_weapon_data_script_is_upgrade_data():
		assert_true(ClassUtils.is_class_of(UpgradeWeaponData, "UpgradeData"))


	func test_upgrade_weapon_data_instance_is_upgrade_data():
		assert_true(ClassUtils.is_class_of(UpgradeWeaponData.new(), "UpgradeData"))


	func test_weapon_blizzard_instance_is_upgrade_weapon_data():
		assert_true(ClassUtils.is_class_of(WEAPON_BLIZZARD, UpgradeWeaponData))


	func test_weapon_blizzard_instance_is_not_gdscript():
		assert_false(ClassUtils.is_class_of(WEAPON_BLIZZARD, GDScript))


	func test_tool_shovel_instance_is_upgrade_tool_data():
		assert_true(ClassUtils.is_class_of(TOOL_SHOVEL, UpgradeToolData))
	
	
	func test_upgrade_strength_is_not_upgrade_tool_data():
		assert_false(ClassUtils.is_class_of(UPGRADE_STRENGTH, UpgradeToolData))


	func test_upgrade_gear_class_is_not_upgrade_tool_data():
		assert_false(ClassUtils.is_class_of(UpgradeGearData, UpgradeToolData))


	func test_upgrade_tool_script_is_not_upgrade_gear_data():
		assert_false(ClassUtils.is_class_of(UpgradeToolData, UpgradeGearData))


	func test_upgrade_data_class_is_not_upgrade_gear_data():
		assert_false(ClassUtils.is_class_of(UpgradeData, UpgradeGearData))

	func test_upgrade_gear_instance_is_not_upgrade_tool_data():
		assert_false(ClassUtils.is_class_of(UpgradeGearData.new(), UpgradeToolData))
