class_name AgentPromptText
extends RefCounted


static func escape_dynamic(value: Variant) -> String:
	return str(value) \
		.replace("<", "＜") \
		.replace(">", "＞") \
		.replace("[", "［") \
		.replace("]", "］") \
		.replace("```", "｀｀｀") \
		.replace("\r", " ") \
		.replace("\n", " ") \
		.strip_edges()
