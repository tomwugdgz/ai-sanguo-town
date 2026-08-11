class_name TownSaveJournalStates
extends RefCounted
## 存档/恢复日志状态机唯一事实源(批次D之5,三处常量表合一,内容逐字保留)。
## Store/Coordinator 引用本表;restore_completed 的兜底行为在 Store 原地未动。


const SAVE_STAGES: Array[String] = [
	"save_started",
	"world_candidate_written",
	"agent_commit_started",
	"agent_committed",
	"world_committed",
	"manifest_published",
	"agent_commit_failed",
	"agent_commit_uncertain",
	"agent_orphan_isolated",
	"transaction_failed",
]

const RESTORE_STAGES: Array[String] = [
	"restore_started",
	"restore_world_prepared",
	"restore_agent_started",
	"restore_agent_hydrated",
	"restore_world_validated",
	"restore_agent_commit_started",
	"restore_agent_committed",
	"restore_world_committed",
	"restore_completed",
	"transaction_failed",
]

const STAGE_ORDER := {
	"save_started": 1,
	"world_candidate_written": 10,
	"agent_commit_started": 20,
	"agent_committed": 30,
	"world_committed": 40,
	"manifest_published": 50,
	"restore_started": 110,
	"restore_world_prepared": 120,
	"restore_agent_started": 130,
	"restore_agent_hydrated": 140,
	"restore_world_validated": 150,
	"restore_agent_commit_started": 155,
	"restore_agent_committed": 160,
	"restore_world_committed": 170,
	"restore_completed": 180,
	"agent_commit_failed": 210,
	"agent_commit_uncertain": 220,
	"agent_orphan_isolated": 230,
	"transaction_failed": 240,
}

const SAVE_TRANSITIONS := {
	"save_started": ["world_candidate_written", "transaction_failed"],
	"world_candidate_written": ["agent_commit_started", "transaction_failed"],
	"agent_commit_started": [
		"agent_committed",
		"agent_commit_failed",
		"agent_commit_uncertain",
		"agent_orphan_isolated",
	],
	"agent_committed": ["world_committed", "agent_orphan_isolated"],
	"world_committed": ["manifest_published", "agent_orphan_isolated"],
	"agent_commit_uncertain": ["agent_orphan_isolated"],
}

const RESTORE_TRANSITIONS := {
	"restore_started": ["restore_world_prepared", "transaction_failed"],
	"restore_world_prepared": ["restore_agent_started", "transaction_failed"],
	"restore_agent_started": ["restore_agent_hydrated", "transaction_failed"],
	"restore_agent_hydrated": ["restore_world_validated", "transaction_failed"],
	"restore_world_validated": [
		"restore_agent_commit_started",
		"transaction_failed",
	],
	"restore_agent_commit_started": [
		"restore_agent_committed",
		"transaction_failed",
	],
	"restore_agent_committed": [
		"restore_world_committed",
		"transaction_failed",
	],
	"restore_world_committed": ["restore_completed", "transaction_failed"],
}

const SAVE_TRANSACTION_FAILED_STAGES: Array[String] = [
	"gate_begin",
	"world_prepare",
	"world_candidate_write",
	"world_validate",
	"gate_validate",
]

const RESTORE_TRANSACTION_FAILED_STAGES: Array[String] = [
	"world_prepare",
	"agent_prepare",
	"agent_resident_set",
	"agent_hydrate",
	"world_validate",
	"gate_validate",
	"agent_commit",
	"world_commit_after_agent",
	"post_commit_validation",
]
