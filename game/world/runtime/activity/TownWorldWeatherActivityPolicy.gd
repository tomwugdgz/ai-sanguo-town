class_name TownWorldWeatherActivityPolicy
extends RefCounted


const WEATHER_TYPES := [
	"晴天",
	"阴天",
	"小雨",
	"中雨",
	"大雨",
	"雷暴",
	"下雪",
]
const PUBLIC_INDOOR_KINDS := [
	"leisure",
	"need",
	"service",
	"social",
]


func evaluate(
	weather: String,
	space_id: String,
	activity: Dictionary,
	role: String,
) -> Dictionary:
	var normalized_weather := (
		weather
		if WEATHER_TYPES.has(weather)
		else "晴天"
	)
	var outdoors := space_id == "town_outdoor"
	var kind := String(activity.get("kind", ""))
	if outdoors:
		match normalized_weather:
			"雷暴":
				return {
					"available": false,
					"suitability": "unsafe",
					"preference": -100,
					"reason": "雷暴期间不适合继续户外活动。",
					"disabledReason": "ACTIVITY_WEATHER_UNSAFE",
				}
			"大雨":
				return {
					"available": true,
					"suitability": "discouraged",
					"preference": -3,
					"reason": "大雨使这项户外活动很不方便。",
					"disabledReason": "",
				}
			"中雨":
				return {
					"available": true,
					"suitability": "discouraged",
					"preference": -2,
					"reason": "持续降雨使这项户外活动不太合适。",
					"disabledReason": "",
				}
			"小雨":
				return {
					"available": true,
					"suitability": "discouraged",
					"preference": -1,
					"reason": "小雨会影响这项户外活动，但仍可继续。",
					"disabledReason": "",
				}
			"下雪":
				return {
					"available": true,
					"suitability": "discouraged",
					"preference": -1,
					"reason": "下雪使这项户外活动更费力。",
					"disabledReason": "",
				}
			"晴天":
				return {
					"available": true,
					"suitability": "preferred",
					"preference": 1,
					"reason": "天气适合户外活动。",
					"disabledReason": "",
				}
			_:
				return _normal()
	if (
		normalized_weather in ["小雨", "中雨", "大雨", "雷暴", "下雪"]
		and (
			PUBLIC_INDOOR_KINDS.has(kind)
			or role in ["visitor", "participant"]
		)
	):
		return {
			"available": true,
			"suitability": "preferred",
			"preference": 2 if normalized_weather == "雷暴" else 1,
			"reason": "这种天气下，室内活动更舒适。",
			"disabledReason": "",
		}
	return _normal()


func public_context(weather: String) -> Dictionary:
	var normalized_weather := (
		weather
		if WEATHER_TYPES.has(weather)
		else "晴天"
	)
	match normalized_weather:
		"小雨":
			return {
				"impact": "mild",
				"outdoorPolicy": "discouraged",
				"summary": "小雨会影响户外活动。可以去室内公共地点、回家，或按事情轻重继续户外行动；回家不是默认答案。",
			}
		"中雨":
			return {
				"impact": "strong",
				"outdoorPolicy": "discouraged",
				"summary": "持续降雨明显影响户外活动。优先比较可到达的室内公共地点、本人住处与尚未完成的事情，不要一律回家。",
			}
		"大雨":
			return {
				"impact": "strong",
				"outdoorPolicy": "discouraged",
				"summary": "大雨使户外活动很不方便。室内公共地点、回家和坚持处理重要事情都是不同选择，应按本人性格与需要决定。",
			}
		"雷暴":
			return {
				"impact": "dangerous",
				"outdoorPolicy": "unavailable",
				"summary": "雷暴期间户外活动暂不可用，应在可到达的公共室内地点、工作地或住处之间选择，不要让所有人去同一个地方。",
			}
		"下雪":
			return {
				"impact": "strong",
				"outdoorPolicy": "discouraged",
				"summary": "下雪使户外活动更费力。可以进公共室内地点停留和碰面，也可以回家或坚持重要行动，不要一律回家。",
			}
		"晴天":
			return {
				"impact": "none",
				"outdoorPolicy": "preferred",
				"summary": "天气适合户外活动。",
			}
		_:
			return {
				"impact": "none",
				"outdoorPolicy": "normal",
				"summary": "天气没有对当前活动形成明显限制。",
			}


func _normal() -> Dictionary:
	return {
		"available": true,
		"suitability": "normal",
		"preference": 0,
		"reason": "",
		"disabledReason": "",
	}
