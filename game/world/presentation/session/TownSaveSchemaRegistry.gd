class_name TownSaveSchemaRegistry
extends RefCounted
## 存档链路版本常量唯一事实源(批次E之3)。各文件原常量改为引用本表,
## 数值逐字保留。目标:回答"v1 存档今天还能不能开"时只查一处。
## agent 层的 PERSISTENT_STATE/MEMORY_STATE 版本归 agent 域(tim),不入本表。

const WORLD_SCHEMA_VERSION := 2
const WORLD_SUPPORTED_SCHEMA_VERSIONS := [1, 2]
const MANIFEST_SCHEMA_VERSION := 3
const MANIFEST_LEGACY_SCHEMA_VERSION := 1
const MANIFEST_PREVIOUS_SCHEMA_VERSION := 2
const PROFILE_SCHEMA_VERSION := 2
const PROFILE_LEGACY_SCHEMA_VERSION := 1
const AGENT_SAVE_FORMAT_VERSION := 3
const NEW_GAME_DRAFT_SCHEMA_VERSION := 1
const CUSTOM_RESIDENT_LIBRARY_SCHEMA_VERSION := 1
