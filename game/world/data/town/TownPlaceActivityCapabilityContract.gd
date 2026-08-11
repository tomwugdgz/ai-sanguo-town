extends RefCounted


const ASSIGNABLE_WORKPLACE := "assignableWorkplace"
const EXPECTED_ACTIVITY_CAPABILITIES := {
	"公共食堂": ["baking.prepare", "food.clean", "food.prepare"],
	"中心广场": ["music.perform", "news.distribute"],
	"图书馆": ["calligraphy.teach", "library.shelve"],
	"工作坊": ["craft.assembly", "craft.metalwork", "craft.woodwork"],
	"小镇道路": ["mail.delivery"],
	"市集": ["retail.flowers"],
	"独立市集": ["retail.flowers", "retail.goods"],
	"码头仓库": ["fishing.gear", "logistics.inventory"],
	"花房咖啡馆": ["drink.prepare"],
	"社区花园": ["garden.care", "plant.study"],
	"诊所": ["care.medicine"],
	"镇公所": ["civic.records"],
	"渔港": ["fishing.harvest"],
}


static func validate_required_places(places: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var counts := {}
	for place_value: Variant in places:
		if not place_value is Dictionary:
			continue
		var place := place_value as Dictionary
		var place_name_value: Variant = place.get("name")
		if not place_name_value is String:
			continue
		var place_name := place_name_value as String
		if EXPECTED_ACTIVITY_CAPABILITIES.has(place_name):
			counts[place_name] = int(counts.get(place_name, 0)) + 1
	for place_name: String in EXPECTED_ACTIVITY_CAPABILITIES:
		if int(counts.get(place_name, 0)) != 1:
			errors.append(
				"活动 capability 合同要求地点 %s 必须且只能定义一次"
				% place_name
			)
	return errors


static func validate(
	place_name: String,
	capabilities: Dictionary,
) -> PackedStringArray:
	var errors := PackedStringArray()
	var assignable_workplace_value: Variant = capabilities.get(
		ASSIGNABLE_WORKPLACE
	)
	if (
		EXPECTED_ACTIVITY_CAPABILITIES.has(place_name)
		and (
			typeof(assignable_workplace_value) != TYPE_BOOL
			or assignable_workplace_value != true
		)
	):
		errors.append(
			"活动 capability 合同要求地点 %s 必须是可分配工作地"
			% place_name
		)
	var actual: Array[String] = []
	for key_value: Variant in capabilities:
		if typeof(key_value) != TYPE_STRING:
			continue
		var capability := key_value as String
		if capability == ASSIGNABLE_WORKPLACE:
			continue
		actual.append(capability)
		if (
			(EXPECTED_ACTIVITY_CAPABILITIES.get(place_name, []) as Array).has(
				capability
			)
			and (
				typeof(capabilities[key_value]) != TYPE_BOOL
				or capabilities[key_value] != true
			)
		):
			errors.append(
				"地点 %s 的活动 capability %s 必须启用"
				% [place_name, capability]
			)
	actual.sort()
	var expected: Array[String] = []
	for capability_value: Variant in (
		EXPECTED_ACTIVITY_CAPABILITIES.get(place_name, []) as Array
	):
		expected.append(capability_value as String)
	expected.sort()
	if actual != expected:
		errors.append(
			"地点 %s 的活动 capability 集合必须准确匹配：期望 %s，实际 %s"
			% [place_name, expected, actual]
		)
	return errors
