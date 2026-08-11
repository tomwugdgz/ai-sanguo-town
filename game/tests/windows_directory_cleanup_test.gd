extends SceneTree


const SESSION_STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const PHOTO_STORE := preload(
	"res://world/integration/TownConversationPhotoStore.gd"
)
const ARCHIVE_SERVICE := preload(
	"res://world/integration/TownFormalSlotArchiveService.gd"
)
const AGENT_FILE_SYSTEM := preload("res://agent/AgentFileSystem.gd")

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var suffix := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_test_session_store_cleanup(suffix)
	_test_photo_store_cleanup(suffix)
	_test_archive_cleanup(suffix)
	_test_agent_filesystem_cleanup(suffix)
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
	for _index in 5:
		await process_frame
	await create_timer(0.3, true, false, true).timeout
	if _failures.is_empty():
		print("WINDOWS_DIRECTORY_CLEANUP_PASS checks=%d" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		printerr("WINDOWS_DIRECTORY_CLEANUP_FAIL: %s" % failure)
	quit(1)


func _test_session_store_cleanup(suffix: String) -> void:
	var test_root := (
		"user://tests/town_session_saves/windows_cleanup_%s" % suffix
	)
	var store: RefCounted = SESSION_STORE.new()
	_expect_ok(
		store.call("configure_test_root", test_root) as Dictionary,
		"会话存档清理测试目录可配置",
	)
	_expect(
		_write_nested_fixture(test_root),
		"会话存档清理夹具可创建",
	)
	_expect_ok(
		store.call("cleanup_test_root") as Dictionary,
		"会话存档目录可递归删除",
	)
	_expect(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(test_root),
		),
		"会话存档根目录已删除",
	)


func _test_photo_store_cleanup(suffix: String) -> void:
	var photo_root := (
		"user://tests/town_conversation_photos/windows_cleanup_%s" % suffix
	)
	var save_root := (
		"user://tests/town_session_saves/windows_photo_cleanup_%s" % suffix
	)
	var store: RefCounted = PHOTO_STORE.new()
	_expect_ok(
		store.call(
			"configure_test_roots",
			photo_root,
			save_root,
		) as Dictionary,
		"照片清理测试目录可配置",
	)
	_expect_ok(
		store.call("configure_session", "slot", "session") as Dictionary,
		"照片会话可建立",
	)
	var session_root := "%s/slot/session" % photo_root
	_expect(
		_write_nested_fixture(session_root),
		"照片会话清理夹具可创建",
	)
	_expect_ok(
		store.call("discard_unpublished_session") as Dictionary,
		"未发布照片会话可递归删除",
	)
	_expect(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(session_root),
		),
		"照片会话目录已删除",
	)
	var save_store := store.get("_save_store") as RefCounted
	_expect_ok(
		save_store.call("cleanup_test_root") as Dictionary,
		"照片测试使用的会话锁目录已清理",
	)
	_expect(
		store.call("_remove_tree", photo_root) == OK,
		"照片测试根目录可清理",
	)


func _test_archive_cleanup(suffix: String) -> void:
	var base := (
		"user://tests/town_session_saves/formal_slot_archive/"
		+ "windows_cleanup_%s" % suffix
	)
	var service: RefCounted = ARCHIVE_SERVICE.new()
	_expect_ok(
		service.call(
			"configure_test_roots",
			"%s/world/slots" % base,
			"%s/agent" % base,
			"%s/backups" % base,
			"%s/photos" % base,
		) as Dictionary,
		"正式存档备份清理目录可配置",
	)
	_expect(
		_write_nested_fixture(base),
		"正式存档备份清理夹具可创建",
	)
	_expect(
		bool(service.call("_remove_tree", base)),
		"正式存档备份目录可递归删除",
	)
	_expect(
		not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(base)),
		"正式存档备份根目录已删除",
	)
	var empty_archive_root := "%s_empty" % base
	_expect(
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(empty_archive_root),
		) in [OK, ERR_ALREADY_EXISTS],
		"空备份目录夹具可创建",
	)
	service.call("_remove_empty_archive_root", empty_archive_root)
	_expect(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(empty_archive_root),
		),
		"空备份目录释放遍历句柄后可删除",
	)


func _test_agent_filesystem_cleanup(suffix: String) -> void:
	var root_path := "user://tests/agent_save/windows_cleanup_%s" % suffix
	_expect(
		_write_nested_fixture(root_path),
		"居民存档清理夹具可创建",
	)
	_expect(
		AGENT_FILE_SYSTEM.remove_tree(root_path) == OK,
		"居民存档目录可递归删除",
	)
	_expect(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(root_path),
		),
		"居民存档根目录已删除",
	)
	var empty_path := "%s_empty" % root_path
	_expect(
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(empty_path),
		) in [OK, ERR_ALREADY_EXISTS],
		"居民空目录夹具可创建",
	)
	AGENT_FILE_SYSTEM.remove_empty_directory(empty_path)
	_expect(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(empty_path),
		),
		"居民空目录释放遍历句柄后可删除",
	)


func _write_nested_fixture(root_path: String) -> bool:
	var nested_path := "%s/nested/child" % root_path
	var error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(nested_path),
	)
	if error not in [OK, ERR_ALREADY_EXISTS]:
		return false
	var file := FileAccess.open("%s/payload.txt" % nested_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("windows-directory-cleanup")
	file.flush()
	var write_error := file.get_error()
	file = null
	return write_error == OK


func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(
		bool(result.get("ok", false)),
		"%s（%s）" % [message, result.get("errorCode", "")],
	)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
