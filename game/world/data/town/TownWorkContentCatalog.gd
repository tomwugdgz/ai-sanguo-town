class_name TownWorkContentCatalog
extends RefCounted

# 玩法内容目录:运行时代码引用的地点名、物品、任务优先级与结算活动白名单
# 的单一来源。调整内容(改地点名、调优先级、增减结算活动)只改这里,
# 不再改 TownWorldRuntime / TownWorkSettlement 的业务代码。

const PLACE_MARKET := "独立市集"
const PLACE_DINING_HALL := "公共食堂"
const PLACE_CAFE := "花房咖啡馆"
const PLACE_WAREHOUSE := "码头仓库"
const PLACE_CLINIC := "诊所"
const PLACE_LIBRARY := "图书馆"
const PLACE_WORKSHOP := "工作坊"
const PLACE_FISHING_PORT := "渔港"
const PLACE_GARDEN := "社区花园"
const PLACE_PLAZA := "中心广场"
const PLACE_TOWN_HALL := "镇公所"
const PLACE_SOUTH_ENTRANCE := "南入口"

const ITEM_FISH := "fish"
const ITEM_PLANT_SAMPLE := "plant_sample"
const ITEM_FRESH_FLOWERS := "fresh_flowers"
const ITEM_BOUQUET := "bouquet"
const ITEM_RESEARCH_BOOKLET := "research_booklet"
const ITEM_BREWED_COFFEE := "brewed_coffee"
const ITEM_GENERAL_GOODS := "general_goods"

# 结算分派与各 handler 门槛共用的活动白名单:分派规则与 handler 内部检查
# 引用同一份清单,新增活动只改此处。
const WAREHOUSE_SETTLEMENT_ACTIVITIES := [
	"activity_warehouse_check_manifest",
	"activity_warehouse_move_cargo",
]
const PRODUCTION_SETTLEMENT_ACTIVITIES := [
	"activity_fisher_catch_in_region",
	"activity_farm_water_beds",
	"activity_garden_harvest_region",
]
const BOTANIST_SETTLEMENT_ACTIVITIES := [
	"activity_botanist_observe_plants",
	"activity_botanist_verify_sources",
	"activity_botanist_record_plants",
]
const WORKSHOP_SETTLEMENT_ACTIVITIES := [
	"activity_workshop_take_lumber",
	"activity_workshop_grind_parts",
	"activity_workshop_assemble_item",
]
const BAKER_SETTLEMENT_ACTIVITIES := [
	"activity_baker_prepare_dough",
	"activity_baker_bake_bread",
]
const FACILITY_CLEANUP_SOURCE_BY_ACTIVITY := {
	"activity_dining_wash_dishes": "dirty_dishes",
	"activity_cafe_tidy_tables": "used_table",
}
const POSTAL_CAPABILITY_BY_ACTIVITY := {
	"activity_postal_sort_mail": "message.sort",
	"activity_postal_prepare_mailbag": "message.prepare",
}
const PLANT_RESEARCH_CAPABILITY_BY_ACTIVITY := {
	"activity_botanist_observe_plants": "research.observe",
	"activity_botanist_verify_sources": "research.verify",
	"activity_botanist_record_plants": "research.record",
}
const DAILY_OPERATION_ACTIVITY_BY_CAPABILITY := {
	"cafe.handoff": "activity_cafe_tidy_tables",
	"care.treatment": "activity_clinic_prepare_medicine",
	"retail.stock": "activity_grocer_count_goods",
	"retail.sale": "activity_flower_watch_stall",
}

# 任务优先级表:键按"来源域+用途"命名,值越大越优先。
const TASK_PRIORITY := {
	"private_message_delivery": 75,
	"occupation_service_request": 75,
	"cargo_receipt": 75,
	"fishing_plan": 72,
	"garden_care_plan": 68,
	"garden_harvest_plan": 70,
	"daily_baking_plan": 58,
	"retail_display_plan": 67,
	"craft_request": 62,
	"music_rehearsal_plan": 55,
	"place_service_task": 85,
	"clinic_treatment": 82,
	"service_stock_restock_lot": 80,
	"facility_cleanup": 69,
	"daily_postal_collection": 76,
	"library_catalog_check": 50,
	"civic_case": 64,
	"staffing_review": 82,
	"civic_urgent_case": 84,
	"meal_demand_order": 76,
	"warehouse_audit": 52,
	"inventory_discrepancy": 86,
	"research_sample_request": 71,
	"specialty_meal_demand": 84,
	"specialty_fishing_demand": 82,
	"research_booklet_handoff": 78,
	"postal_sort": 79,
	"service_result_delivery_lot": 74,
	"fishing_catch_lot": 78,
	"plant_sample_lot": 80,
	"garden_harvest_lot": 74,
	"research_accession_follow_up": 64,
	"craft_output_lot": 70,
	"performance_bulletin": 72,
	"baked_goods_lot": 78,
	"civic_bulletin": 66,
	"postal_mailbag": 78,
	"research_booklet_lot": 67,
}
