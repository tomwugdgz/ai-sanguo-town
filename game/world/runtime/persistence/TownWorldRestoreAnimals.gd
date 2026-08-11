class_name TownWorldRestoreAnimals
extends RefCounted


const SAVE_CODEC := preload("res://world/runtime/persistence/TownWorldSaveCodec.gd")
const RESTORE_LAYOUT := preload(
	"res://world/runtime/persistence/TownWorldRestoreLayout.gd"
)


static func prepare_animal_facts(
	value: Variant,
	world_data: Dictionary,
) -> Dictionary:
	var unpacked := SAVE_CODEC.unpack_optional_domain_snapshot(
		value,
		"animalFacts 必须是对象",
	)
	if unpacked.get("ok") != true:
		return {"ok": false, "errors": unpacked.get("errors", [])}
	if unpacked.get("empty") == true:
		return {"ok": true, "facts": {}}
	var snapshot := unpacked.get("snapshot", {}) as Dictionary
	var facts := {}
	var errors: Array[String] = []
	for animal_id_value: Variant in snapshot:
		var animal_id := String(animal_id_value).strip_edges()
		var fact_value: Variant = snapshot.get(
			animal_id_value
		)
		if animal_id.is_empty() or not fact_value is Dictionary:
			errors.append("animalFacts 包含无效动物记录")
			continue
		var fact := fact_value as Dictionary
		for field in [
			"animal_id",
			"display_name",
			"species",
			"exists",
			"place_id",
			"position",
			"generation",
			"public_attention",
			"source_revision",
			"expires_at",
			"source_event_ids",
			"updated_at",
		]:
			if not fact.has(field):
				errors.append(
					"animalFacts.%s 缺少字段：%s"
					% [animal_id, field]
				)
		if String(fact.get("animal_id", "")) != animal_id:
			errors.append("animalFacts.%s 身份不一致" % animal_id)
		var place_id := String(fact.get("place_id", ""))
		if not RESTORE_LAYOUT.world_data_has_place(world_data, place_id):
			errors.append(
				"animalFacts.%s 引用未知地点：%s"
				% [animal_id, place_id]
			)
		var position_value: Variant = fact.get("position")
		if (
			not position_value is Vector2
			or not (position_value as Vector2).is_finite()
		):
			errors.append(
				"animalFacts.%s position 必须是有限 Vector2"
				% animal_id
			)
		if (
			not fact.get("exists") is bool
			or not fact.get("public_attention") is bool
			or not fact.get("generation") is int
			or int(fact.get("generation", -1)) < 0
			or not fact.get("source_revision") is int
			or int(fact.get("source_revision", -1)) < 0
			or not fact.get("expires_at") is int
			or not fact.get("updated_at") is int
			or not fact.get("source_event_ids") is Array
		):
			errors.append(
				"animalFacts.%s 状态字段类型无效" % animal_id
			)
		if (
			String(fact.get("display_name", "")).strip_edges().is_empty()
			or String(fact.get("species", "")).strip_edges().is_empty()
		):
			errors.append(
				"animalFacts.%s 名称或物种为空" % animal_id
			)
		facts[animal_id] = fact.duplicate(true)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "facts": facts}
