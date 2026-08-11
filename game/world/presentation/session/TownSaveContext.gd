class_name TownSaveContext
extends RefCounted
## 存档三元组(slot_id/session_id/save_revision)与修订目录布局的唯一事实源
## (批次E之1首刀:路径模板 4 份收 1)。世界侧修订目录一律 %020d 补零;
## agent 归档侧的非补零 %d 布局是另一约定,不走本表(见执行记录风险点)。


static func revision_directory(context: Dictionary) -> String:
	return "slots/%s/sessions/%s/revisions/%020d" % [
		String(context.get("slot_id", "")),
		String(context.get("session_id", "")),
		int(context.get("save_revision", 0)),
	]


static func revision_reference(context: Dictionary, file_name: String) -> String:
	return "%s/%s" % [revision_directory(context), file_name]


## 修订引用的结构拆解(不做业务校验:文件名白名单/revision下界/上下文合法性
## 仍由调用方按各自语义判定)。
static func parse_revision_reference(reference: String) -> Dictionary:
	var parts := reference.split("/", false)
	if (
		parts.size() != 7
		or parts[0] != "slots"
		or parts[2] != "sessions"
		or parts[4] != "revisions"
	):
		return {"ok": false}
	return {
		"ok": true,
		"slot_id": parts[1],
		"session_id": parts[3],
		"revision_text": parts[5],
		"file_name": parts[6],
	}


static func join_path(base: String, child: String) -> String:
	return "%s/%s" % [base.trim_suffix("/"), child.trim_prefix("/")]


## camelCase 请求信封 -> snake_case 内部三元组(批次E之1出入口翻译收口)。
## 只做键名翻译不做校验;值(含缺键时的 null)原样传递,交 validate_context 判定。
static func camel_to_snake(value: Dictionary) -> Dictionary:
	return {
		"slot_id": value.get("slotId"),
		"session_id": value.get("sessionId"),
		"save_revision": value.get("saveRevision"),
	}
