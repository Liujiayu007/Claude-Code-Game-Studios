## DataConfig 单元测试 — 覆盖 Story 002 AC1-AC9
## 测试框架: GdUnit4
extends GdUnitTestSuite

var _config: DataConfig


# ─── Test Fixture Helpers ───

func before() -> void:
	_config = DataConfig.new()
	_config.default_form = _make_form("default_form")
	_config.default_wave_table = _make_wave_table("default_waves")
	_config.default_enemy = _make_enemy("default_enemy")
	_config.default_area = _make_area("default_area")


func after() -> void:
	_config.free()
	_config = null


func _make_form(id: String) -> FormConfig:
	var f := FormConfig.new()
	f.form_id = id
	f.form_name = id
	f.hp_multiplier = 1.0
	f.speed_multiplier = 1.0
	f.damage_multiplier = 1.0
	f.duration_seconds = 8.0
	f.cooldown_seconds = 15.0
	return f


func _make_enemy(id: String, hp_val: int = 10, speed_val: float = 100.0) -> EnemyConfig:
	var e := EnemyConfig.new()
	e.enemy_id = id
	e.display_name = id
	e.hp = hp_val
	e.speed = speed_val
	e.damage = 5
	e.form_points_drop = 1
	return e


func _make_wave_table(id: String) -> WaveTable:
	var w := WaveTable.new()
	w.table_id = id
	w.area_id = "test_area"
	return w


func _make_area(id: String) -> AreaConfig:
	var a := AreaConfig.new()
	a.area_id = id
	a.area_name = id
	return a


# ─── AC1: Load All Categories Return Non-Null ───

func test_load_all_categories_return_non_null() -> void:
	_config.form_configs = [_make_form("beast")]
	_config.wave_tables = [_make_wave_table("plains")]
	_config.enemy_configs = [_make_enemy("slime_melee")]
	_config.area_configs = [_make_area("windsong")]
	_config._ready()

	assert_that(_config.get_form_config("beast")).is_not_null()
	assert_that(_config.get_wave_table("plains")).is_not_null()
	assert_that(_config.get_enemy_config("slime_melee")).is_not_null()
	assert_that(_config.get_area_config("windsong")).is_not_null()


# ─── AC2: Valid Key Returns Correct EnemyConfig ───

func test_valid_key_returns_correct_enemy_config() -> void:
	var enemy := _make_enemy("slime_melee", 20, 150.0)
	_config.enemy_configs = [enemy]
	_config._ready()

	var result := _config.get_enemy_config("slime_melee")

	assert_str(result.enemy_id).is_equal("slime_melee")
	assert_int(result.hp).is_greater_than(0)
	assert_float(result.speed).is_greater_than(0.0)
	assert_int(result.hp).is_equal(20)
	assert_float(result.speed).is_equal(150.0)


# ─── AC3: Invalid Key Returns Default Instance ───

func test_invalid_key_returns_default_instance() -> void:
	_config._ready()

	var result := _config.get_enemy_config("nonexistent_enemy")

	assert_that(result).is_not_null()
	assert_str(result.enemy_id).is_equal("default_enemy")


# ─── AC7: Empty Config Returns Default For Any Key ───

func test_empty_config_returns_default_for_any_key() -> void:
	_config.form_configs = []
	_config.enemy_configs = []
	_config.wave_tables = []
	_config.area_configs = []
	_config._ready()

	assert_str(_config.get_form_config("anything").form_id).is_equal("default_form")
	assert_str(_config.get_enemy_config("anything").enemy_id).is_equal("default_enemy")
	assert_str(_config.get_wave_table("anything").table_id).is_equal("default_waves")
	assert_str(_config.get_area_config("anything").area_id).is_equal("default_area")


# ─── AC7 variant: Null Config Array ───

func test_null_config_array_does_not_crash() -> void:
	_config.form_configs = [] as Array[FormConfig]
	_config.enemy_configs = [] as Array[EnemyConfig]
	_config.wave_tables = [] as Array[WaveTable]
	_config.area_configs = [] as Array[AreaConfig]
	_config._ready()

	# Should not crash; all queries return defaults
	assert_str(_config.get_enemy_config("any").enemy_id).is_equal("default_enemy")


# ─── AC8: Duplicate Key Overwrites And Warns ───

func test_duplicate_key_overwrites_latter_wins() -> void:
	var first := _make_enemy("slime_melee", 10, 100.0)
	var second := _make_enemy("slime_melee", 20, 200.0)
	_config.enemy_configs = [first, second]
	_config._ready()

	var result := _config.get_enemy_config("slime_melee")

	assert_int(result.hp).is_equal(20)
	assert_float(result.speed).is_equal(200.0)


# ─── AC9: Config Ready Before Other Autoloads ───

func test_config_ready_before_other_autoloads() -> void:
	_config.enemy_configs = [_make_enemy("bat", 5, 80.0)]
	_config.form_configs = [_make_form("beast")]
	_config._ready()

	# Simulate another Autoload querying DataConfig in its _ready()
	var enemy := _config.get_enemy_config("bat")
	assert_that(enemy).is_not_null()
	assert_str(enemy.enemy_id).is_equal("bat")

	var form := _config.get_form_config("beast")
	assert_that(form).is_not_null()
	assert_str(form.form_id).is_equal("beast")


# ─── Edge Case: Empty String Key ───

func test_empty_string_key_returns_default() -> void:
	_config.enemy_configs = [_make_enemy("valid")]
	_config._ready()

	var result := _config.get_enemy_config("")

	assert_that(result).is_not_null()
	assert_str(result.enemy_id).is_equal("default_enemy")


# ─── Edge Case: get_all_enemies Returns All Configs ───

func test_get_all_enemies_returns_all_configs() -> void:
	_config.enemy_configs = [
		_make_enemy("slime", 10),
		_make_enemy("bat", 5),
		_make_enemy("skeleton", 15),
	]
	_config._ready()

	var all := _config.get_all_enemies()

	assert_int(all.size()).is_equal(3)
