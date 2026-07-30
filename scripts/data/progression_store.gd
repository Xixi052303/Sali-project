class_name ProgressionStore
extends RefCounted

enum UnlockResult {
	UNLOCKED_NOW,
	ALREADY_UNLOCKED,
	SAVE_FAILED,
}

const DEFAULT_PATH: String = "user://progression.cfg"
const CONTENT_UNLOCKS_SECTION: String = "content_unlocks"
const FINAL_BOSS_FIRST_CLEAR_KEY: String = "final_boss_first_clear_recorded"


# 最终Boss首胜只登记后续内容解锁资格，不提前定义尚未确认的具体内容。
static func record_final_boss_first_clear(path: String = DEFAULT_PATH) -> UnlockResult:
	var config: ConfigFile = ConfigFile.new()
	if FileAccess.file_exists(path):
		var load_error: Error = config.load(path)
		if load_error != OK:
			push_error(
				"PROGRESSION_LOAD_FAILED path=%s error=%d" % [path, load_error]
			)
			return UnlockResult.SAVE_FAILED
	if bool(config.get_value(CONTENT_UNLOCKS_SECTION, FINAL_BOSS_FIRST_CLEAR_KEY, false)):
		return UnlockResult.ALREADY_UNLOCKED
	config.set_value(CONTENT_UNLOCKS_SECTION, FINAL_BOSS_FIRST_CLEAR_KEY, true)
	var save_error: Error = config.save(path)
	if save_error != OK:
		push_error("PROGRESSION_SAVE_FAILED path=%s error=%d" % [path, save_error])
		return UnlockResult.SAVE_FAILED
	return UnlockResult.UNLOCKED_NOW
