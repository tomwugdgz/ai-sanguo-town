class_name AgentTestCli
extends RefCounted


static func parse_options(arguments: PackedStringArray) -> Dictionary:
	var options: Dictionary = {}
	for argument: String in arguments:
		if not argument.begins_with("--"):
			continue
		var body := argument.trim_prefix("--")
		var separator := body.find("=")
		if separator < 0:
			options[body] = true
		else:
			options[body.left(separator)] = body.substr(separator + 1)
	return options
