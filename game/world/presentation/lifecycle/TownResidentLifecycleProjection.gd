class_name TownResidentLifecycleProjection
extends RefCounted


const STATUS_ALIVE := "alive"
const STATUS_DEAD := "dead"


static func project(state: Dictionary) -> Dictionary:
	var resident_id := String(state.get("residentId", "")).strip_edges()
	var resident_name := String(state.get("residentName", "")).strip_edges()
	var status := String(state.get("status", ""))
	if (
		resident_id.is_empty()
		or resident_name.is_empty()
		or status not in [STATUS_ALIVE, STATUS_DEAD]
	):
		return {
			"available": false,
			"disabledReason": "居民生命周期状态暂不可用",
		}
	var dead := status == STATUS_DEAD
	var death_event := state.get("deathEvent", {}) as Dictionary
	return {
		"available": true,
		"disabledReason": "",
		"residentId": resident_id,
		"residentName": resident_name,
		"lifecycleStatus": status,
		"statusLabel": "已死亡" if dead else "生活中",
		"isAlive": not dead,
		"isDead": dead,
		"interactionEnabled": not dead,
		"interactionDisabledReason": (
			"该居民已经死亡"
			if dead
			else ""
		),
		"appearancePolicy": "grayscale" if dead else "normal",
		"placementOverride": {},
		"mapPresencePolicy": "removed" if dead else "present",
		"deathSummary": (
			{
				"eventId": String(death_event.get("event_id", "")),
				"time": (
					death_event.get("time", {}) as Dictionary
				).duplicate(true),
				"reason": String(death_event.get("reason", "")),
				"location": (
					death_event.get("location", {}) as Dictionary
				).duplicate(true),
			}
			if dead
			else {}
		),
		"revision": int(state.get("revision", 0)),
	}
