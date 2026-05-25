## DataConfig Hot Reload & Export 集成测试 — 覆盖 Story 004 AC5, AC6, AC10
## 测试框架: GdUnit4
extends GdUnitTestSuite

var _config: DataConfig


# ─── Test Fixture ───

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


# ═══════════════════════════════════════════════════════════════════════════════
# AC10: Performance — 3600 Queries Under 36ms
# ═══════════════════════════════════════════════════════════════════════════════

func test_performance_3600_queries_under_36ms() -> void:
	# Arrange
	_config.enemy_configs = [_make_enemy("test_enemy", 10, 100.0)]
	_config._ready()

	# Act: 3600 queries (60 seconds at 60fps, one per frame)
	var start_us := Time.get_ticks_usec()
	for _i in range(3600):
		_config.get_enemy_config("test_enemy")
	var elapsed_ms := (Time.get_ticks_usec() - start_us) / 1000.0

	# Assert: total time < 36ms (0.01ms per query × 3600)
	assert_float(elapsed_ms).is_less_than(36.0)


func test_performance_single_query_under_point_zero_one_ms() -> void:
	# Arrange
	_config.enemy_configs = [_make_enemy("test_enemy", 10, 100.0)]
	_config._ready()

	# Act: single query
	var start_us := Time.get_ticks_usec()
	var _result := _config.get_enemy_config("test_enemy")
	var elapsed_us := Time.get_ticks_usec() - start_us

	# Assert: single query < 10 microseconds (0.01ms = 10us)
	assert_float(float(elapsed_us)).is_less_than(10.0)


# ═══════════════════════════════════════════════════════════════════════════════
# AC5: Hot Reload Detects Changed Resource
# ═══════════════════════════════════════════════════════════════════════════════

func test_hot_reload_detects_changed_resource() -> void:
	# Arrange: load enemy with hp=10
	var enemy := _make_enemy("slime_melee", 10, 100.0)
	_config.enemy_configs = [enemy]
	_config.hot_reload_enabled = true
	_config._ready()

	# Simulate editor reload: designer modifies .tres in Inspector
	# Godot updates the Resource in-place on the exported array
	enemy.hp = 20

	# Act: trigger hot reload polling
	_config._refresh_all_caches()

	# Assert: query returns updated value without restart
	assert_int(_config.get_enemy_config("slime_melee").hp).is_equal(20)


func test_hot_reload_detects_modified_speed() -> void:
	# Arrange
	var enemy := _make_enemy("slime_melee", 10, 100.0)
	_config.enemy_configs = [enemy]
	_config._ready()

	enemy.speed = 250.0

	# Act
	_config._refresh_all_caches()

	# Assert
	assert_float(_config.get_enemy_config("slime_melee").speed).is_equal(250.0)


# ═══════════════════════════════════════════════════════════════════════════════
# AC6: Export Build — No Hot Reload Polling
# ═══════════════════════════════════════════════════════════════════════════════

func test_process_skips_polling_when_hot_reload_disabled() -> void:
	# Arrange
	_config.enemy_configs = [_make_enemy("slime_melee", 10)]
	_config.hot_reload_enabled = false
	_config._ready()

	var enemy := _config.enemy_configs[0]
	enemy.hp = 999  # modify without going through refresh

	# Act: _process should early-return when hot_reload_enabled=false
	_config._process(0.016)

	# Assert: old value still returned (no refresh occurred)
	assert_int(_config.get_enemy_config("slime_melee").hp).is_equal(10)


# ═══════════════════════════════════════════════════════════════════════════════
# Edge Cases
# ═══════════════════════════════════════════════════════════════════════════════

func test_hot_reload_with_new_config_in_array() -> void:
	# Arrange
	var enemy1 := _make_enemy("slime", 10)
	_config.enemy_configs = [enemy1]
	_config._ready()

	# Simulate designer adding new .tres to Inspector array
	var enemy2 := _make_enemy("bat", 5, 80.0)
	_config.enemy_configs.append(enemy2)

	# Act
	_config._refresh_all_caches()

	# Assert: new config is accessible
	var result := _config.get_enemy_config("bat")
	assert_that(result).is_not_null()
	assert_str(result.enemy_id).is_equal("bat")
	assert_int(result.hp).is_equal(5)


func test_hot_reload_preserves_defaults_after_refresh() -> void:
	# Arrange
	_config.enemy_configs = [_make_enemy("slime", 10)]
	_config._ready()

	# Act
	_config._refresh_all_caches()

	# Assert: default fallback still works for non-existent keys
	var result := _config.get_enemy_config("nonexistent")
	assert_that(result).is_not_null()
	assert_str(result.enemy_id).is_equal("default_enemy")


func test_process_timer_accumulates_before_refresh() -> void:
	# Arrange
	_config.enemy_configs = [_make_enemy("slime", 10)]
	_config.hot_reload_enabled = true
	_config.hot_reload_interval = 1.0
	_config._ready()

	var enemy := _config.enemy_configs[0]
	enemy.hp = 99

	# Act: process with delta < interval — should NOT trigger refresh
	_config._process(0.5)

	# Assert: old value still returned (timer hasn't triggered yet)
	assert_int(_config.get_enemy_config("slime").hp).is_equal(10)

	# Act: process with remaining delta to reach interval
	_config._process(0.5)

	# Assert: now refresh should have triggered
	assert_int(_config.get_enemy_config("slime").hp).is_equal(99)
