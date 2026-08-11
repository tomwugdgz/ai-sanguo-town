class_name TownWorldLogPresentation
extends RefCounted


const KIND_LABELS := {
	"conversation": "对话",
	"work": "工作",
	"production": "生产",
	"research": "研究",
	"cargo": "搬运",
	"inventory": "库存",
	"commerce": "售卖",
	"service": "服务",
	"message": "消息",
	"mail": "邮递",
	"social": "公共事项",
	"public_matter": "公共事项",
	"commitment": "承诺",
	"announcement": "公告",
	"animal": "动物",
	"activity": "日常活动",
	"daily_activity": "日常活动",
	"weather": "天气",
	"conflict": "冲突",
	"health": "医疗",
	"world_change": "世界变化",
}
const SOURCE_LABELS := {
	"private_message": "口信",
	"cargo_event": "货物变化",
	"service_result": "服务变化",
	"conflict_event": "冲突变化",
	"resident_activity": "居民活动",
	"resident_attendance": "居民出勤变化",
	"resident_lifecycle": "居民变化",
	"animal_event": "动物变化",
	"social_matter": "公共事项",
	"work_task": "工作进展",
	"story_event": "世界变化",
	"action_result": "世界变化",
	"world_event": "世界变化",
}
const CAPABILITY_LABELS := {
	"bulletin.publish": "公告发布",
	"staffing.coordinate": "人员安排",
	"care.consult": "诊疗服务",
	"care.examine": "诊疗检查",
	"care.treatment": "治疗服务",
	"library.accession": "书籍入藏",
	"library.assist": "资料协助",
	"library.loan": "借书办理",
	"library.return": "归还书籍待整理",
	"craft.repair": "设备维修",
	"craft.production": "工坊制作",
	"craft.handoff": "成品交付",
	"music.perform": "公开演出",
	"music.rehearse": "演出排练",
	"civic.service": "镇务办理",
	"cafe.order": "咖啡订单",
	"cafe.production": "咖啡制作",
	"cafe.handoff": "咖啡交付",
	"retail.sale": "商品售卖",
	"retail.arrange": "商品陈列",
	"retail.receive": "商店收货",
	"retail.stock": "商品补货",
	"food.production": "餐食制作",
	"food.service": "供餐服务",
	"food.cleanup": "餐后整理",
	"cargo.pickup": "货物取货",
	"cargo.transport": "货物运输",
	"cargo.deliver": "货物送达",
	"cargo.direct_handoff": "货物交接",
	"fishing.harvest": "捕鱼收获",
	"garden.care": "园艺照料",
	"garden.harvest": "园艺采收",
	"inventory.receive": "货物验收",
	"inventory.store": "货物入库",
	"inventory.release": "货物放行",
	"research.observe": "植物观察",
	"research.verify": "资料查证",
	"research.record": "研究记录",
	"research.handoff": "研究入藏",
	"message.accept": "口信待接取",
	"message.sort": "信件分拣",
	"message.prepare": "邮袋整理",
	"message.deliver": "口信投递",
}
const INTERNAL_EVENT_TYPES := [
	"story_event",
	"action_result",
	"resident_activity",
	"work_task",
	"world_event",
	"service_result",
	"cargo_event",
	"private_message",
	"conflict_event",
	"resident_lifecycle",
	"resident_attendance",
	"animal_event",
	"social_matter",
]
const GATHERING_HOT_PARTICIPANT_COUNT := 3


static func kind_label(kind: String) -> String:
	return String(KIND_LABELS.get(kind, "世界变化"))


static func source_label(source_kind: String) -> String:
	return String(SOURCE_LABELS.get(source_kind, "世界变化"))


static func capability_label(capability: String) -> String:
	return String(CAPABILITY_LABELS.get(capability, ""))


static func story_action_label(payload: Dictionary) -> String:
	if String(payload.get("storyType", "")).strip_edges() != "action_outcome":
		return ""
	return String({
		"用道具": "行动完成",
		"做活动": "活动完成",
	}.get(String(payload.get("actionType", "")).strip_edges(), "行动完成"))


static func title_contains_internal_token(title: String) -> bool:
	for token: String in INTERNAL_EVENT_TYPES:
		if title.contains(token):
			return true
	return false


static func event_type_label(
	source_kind: String,
	event_type: String,
	payload: Dictionary = {},
) -> String:
	var normalized := event_type.strip_edges()
	if normalized.begins_with("工作任务"):
		var capability := capability_label(
			String(payload.get("capability", "")).strip_edges(),
		)
		return capability if not capability.is_empty() else "工作进展"
	if normalized == "居民公开反应":
		return "居民回应"
	if normalized == "天气变了":
		var weather := String(payload.get("weather", "")).strip_edges()
		return "天气变为%s" % weather if not weather.is_empty() else "天气变化"
	if normalized == "身体状况变化" or normalized.begins_with("condition_"):
		var condition_label := String(payload.get("label", "")).strip_edges()
		return condition_label if not condition_label.is_empty() else "身体状况变化"
	if normalized in INTERNAL_EVENT_TYPES:
		return source_label(source_kind)
	# 公开事件的玩家文案目前是中文；带下划线或点号的值按内部标识处理，
	# 防止新来源忘记加展示映射时把协议名直接画出来。
	if normalized.contains("_") or normalized.contains("."):
		return source_label(source_kind)
	return normalized if not normalized.is_empty() else source_label(source_kind)
