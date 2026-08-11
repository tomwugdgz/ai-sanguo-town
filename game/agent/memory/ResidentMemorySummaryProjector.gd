class_name AgentResidentMemorySummaryProjector
extends RefCounted


const MAX_IMPORTANT_CHARACTERS := 1400
const MAX_CURRENT_THOUGHT_CHARACTERS := 1000


func project(old_summary: Dictionary, entries: Array) -> Dictionary:
	var important_lines: Array[String] = []
	var thought_lines: Array[String] = []
	for index in range(entries.size() - 1, -1, -1):
		var entry := entries[index] as Dictionary
		var state := String(entry.get("state", "past"))
		if state not in ["influencing", "doubtful", "anomalous", "corrected"]:
			continue
		var subject := String(entry.get("subject", "")).strip_edges()
		var interpretation := String(entry.get("interpretation", "")).strip_edges()
		# 整理器的归纳负责压缩，原文主体负责让对话记忆仍可追溯；两者都
		# 保留在工作摘要里，完整来源仍保存在正式记忆条目的 subject 上。
		for line: String in [interpretation, subject]:
			if not line.is_empty() and not important_lines.has(line):
				important_lines.push_front(line)
		if state == "doubtful":
			thought_lines.push_front("我开始怀疑：%s" % subject)
		elif state == "anomalous":
			thought_lines.push_front("这段记忆似乎有异常：%s" % subject)
		elif state == "corrected":
			thought_lines.push_front("我后来修正了理解：%s" % subject)
	var important := "\n".join(important_lines)
	if important.length() > MAX_IMPORTANT_CHARACTERS:
		important = important.right(MAX_IMPORTANT_CHARACTERS)
	var old_thoughts := String(old_summary.get("current_thoughts", "")).strip_edges()
	var current_thoughts := "\n".join(thought_lines)
	if current_thoughts.is_empty():
		current_thoughts = old_thoughts
	elif not old_thoughts.is_empty():
		current_thoughts += "\n%s" % old_thoughts
	current_thoughts = current_thoughts.left(MAX_CURRENT_THOUGHT_CHARACTERS)
	return {
		"important_memories": important,
		"relationships": String(old_summary.get("relationships", "")),
		"current_thoughts": current_thoughts,
		"long_term_goals": String(old_summary.get("long_term_goals", "")),
		"short_term_goals": String(old_summary.get("short_term_goals", "")),
	}
