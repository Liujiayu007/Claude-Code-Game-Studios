## DataConfig Validation 单元测试 — 覆盖 Story 003 AC4, AC4-ext, AC11
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


func _make_wave_entry(wave_number: int = 1, enemy_count: int = 5) -> WaveEntry:
	var we := WaveEntry.new()
	we.wave_number = wave_number
	we.enemy_count = enemy_count
	we.spawn_interval = 1.0
	return we


# ═══════════════════════════════════════════════════════════════════════════════
# AC4: Range Validation — Clamps Below Minimum
# ═══════════════════════════════════════════════════════════════════════════════

func test_range_validation_clamps_below_minimum() -> void:
	# Arrange: EnemyConfig with hp=-5 (valid range: 1–9999)
	var enemy := _make_enemy("slime", -5)
	_config.enemy_configs = [enemy]
	_config.validation_strictness = "warn"
	_config._ready()

	# Assert: hp should be clamped to 1
	assert_int(enemy.hp).is_equal(1)


func test_range_validation_clamps_speed_below_minimum() -> void:
	# Arrange: EnemyConfig with speed=5.0 (valid range: 10.0–500.0)
	var enemy := _make_enemy("slime", 10, 5.0)
	_config.enemy_configs = [enemy]
	_config.validation_strictness = "warn"
	_config._ready()

	# Assert: speed should be clamped to 10.0
	assert_float(enemy.speed).is_equal(10.0)


# ═══════════════════════════════════════════════════════════════════════════════
# AC4-ext: Range Validation — Clamps Above Maximum
# ═══════════════════════════════════════════════════════════════════════════════

func test_range_validation_clamps_above_maximum() -> void:
	# Arrange: EnemyConfig with hp=20000 (valid range: 1–9999)
	var enemy := _make_enemy("slime", 20000)
	_config.enemy_configs = [enemy]
	_config.validation_strictness = "warn"
	_config._ready()

	# Assert: hp should be clamped to 9999
	assert_int(enemy.hp).is_equal(9999)


func test_range_validation_clamps_damage_above_maximum() -> void:
	# Arrange: EnemyConfig with damage=20000 (valid range: 0–9999)
	var enemy := _make_enemy("slime", 10, 100.0)
	enemy.damage = 20000
	_config.enemy_configs = [enemy]
	_config.validation_strictness = "warn"
	_config._ready()

	# Assert: damage should be clamped to 9999
	assert_int(enemy.damage).is_equal(9999)


# ═══════════════════════════════════════════════════════════════════════════════
# AC4: Range Validation — FormConfig Fields
# ═══════════════════════════════════════════════════════════════════════════════

func test_range_validation_clamps_form_multiplier_below_minimum() -> void:
	# Arrange: FormConfig with hp_multiplier=0.05 (valid range: 0.1–10.0)
	var form := _make_form("beast")
	form.hp_multiplier = 0.05
	_config.form_configs = [form]
	_config.validation_strictness = "warn"
	_config._ready()

	# Assert: hp_multiplier should be clamped to 0.1
	assert_float(form.hp_multiplier).is_equal(0.1)


func test_range_validation_clamps_form_duration_above_maximum() -> void:
	# Arrange: FormConfig with duration_seconds=120.0 (valid range: 1.0–60.0)
	var form := _make_form("beast")
	form.duration_seconds = 120.0
	_config.form_configs = [form]
	_config.validation_strictness = "warn"
	_config._ready()

	# Assert: duration_seconds should be clamped to 60.0
	assert_float(form.duration_seconds).is_equal(60.0)


# ═══════════════════════════════════════════════════════════════════════════════
# AC4: Range Validation — WaveEntry Fields
# ═══════════════════════════════════════════════════════════════════════════════

func test_range_validation_clamps_wave_entry_enemy_count_below_minimum() -> void:
	# Arrange: WaveEntry with enemy_count=0 (valid range: 1–9999)
	var wt := _make_wave_table("plains")
	var entry := _make_wave_entry(1, 0)
	wt.entries = [entry]
	_config.wave_tables = [wt]
	_config.validation_strictness = "warn"
	_config._ready()

	# Assert: enemy_count should be clamped to 1
	assert_int(entry.enemy_count).is_equal(1)


# ═══════════════════════════════════════════════════════════════════════════════
# AC11: Reference Integrity — Broken Reference Replaced with Default
# ═══════════════════════════════════════════════════════════════════════════════

func test_reference_integrity_null_replaced_with_default() -> void:
	# Arrange: AreaConfig with null background_tileset
	var area := _make_area("windsong")
	area.background_tileset = null
	var default_tileset := TileSet.new()
	var empty_cache := {}

	# Act
	_config._validate_reference_integrity(area, "background_tileset", empty_cache, default_tileset, "default_tileset")

	# Assert: null reference should be replaced with default
	assert_that(area.background_tileset).is_same(default_tileset)


func test_reference_integrity_broken_replaced_with_default() -> void:
	# Arrange: AreaConfig with tileset not present in cache
	var area := _make_area("windsong")
	var orphan_tileset := TileSet.new()
	area.background_tileset = orphan_tileset
	var default_tileset := TileSet.new()
	var empty_cache := {}

	# Act
	_config._validate_reference_integrity(area, "background_tileset", empty_cache, default_tileset, "default_tileset")

	# Assert: broken reference should be replaced with default
	assert_that(area.background_tileset).is_same(default_tileset)


# ═══════════════════════════════════════════════════════════════════════════════
# AC4: Range Validation — Boundary Values
# ═══════════════════════════════════════════════════════════════════════════════

func test_range_validation_clamps_hp_zero_to_one() -> void:
	# Arrange: EnemyConfig with hp=0 (boundary value — valid range: 1–9999)
	var enemy := _make_enemy("slime", 0)
	_config.enemy_configs = [enemy]
	_config.validation_strictness = "warn"
	_config._ready()

	# Assert: hp=0 should be clamped to 1 (0 is not a valid HP value)
	assert_int(enemy.hp).is_equal(1)


# ═══════════════════════════════════════════════════════════════════════════════
# Validation Strictness: Silent Mode
# ═══════════════════════════════════════════════════════════════════════════════

func test_silent_mode_corrects_value_without_crashing() -> void:
	# Arrange: value out of range + silent mode
	var enemy := _make_enemy("slime", -5)
	_config.enemy_configs = [enemy]
	_config.validation_strictness = "silent"
	_config._ready()

	# Assert: value still corrected, no crash
	assert_int(enemy.hp).is_equal(1)


# ═══════════════════════════════════════════════════════════════════════════════
# Validation Strictness: Error Mode
# ═══════════════════════════════════════════════════════════════════════════════

func test_error_mode_still_corrects_value() -> void:
	# Arrange: value out of range + error mode
	var enemy := _make_enemy("slime", -5)
	_config.enemy_configs = [enemy]
	_config.validation_strictness = "error"
	_config._ready()

	# Assert: value still corrected (push_error used instead of push_warning)
	assert_int(enemy.hp).is_equal(1)


# ═══════════════════════════════════════════════════════════════════════════════
# Meta: Validation Runs Automatically in _ready()
# ═══════════════════════════════════════════════════════════════════════════════

func test_validation_runs_automatically_in_ready() -> void:
	# Arrange: multiple invalid configs across categories
	var enemy := _make_enemy("dragon", -100)
	var form := _make_form("beast")
	form.speed_multiplier = -5.0
	_config.enemy_configs = [enemy]
	_config.form_configs = [form]
	_config.validation_strictness = "warn"

	# Act: _ready() should automatically validate all configs
	_config._ready()

	# Assert: both configs corrected
	assert_int(enemy.hp).is_equal(1)
	assert_float(form.speed_multiplier).is_equal(0.1)


func test_validation_handles_all_valid_data() -> void:
	# Arrange: all configs within valid ranges
	var enemy := _make_enemy("slime", 50, 120.0)
	enemy.damage = 20
	var form := _make_form("beast")
	form.hp_multiplier = 1.5
	form.duration_seconds = 10.0
	_config.enemy_configs = [enemy]
	_config.form_configs = [form]
	_config.validation_strictness = "warn"

	# Act
	_config._ready()

	# Assert: valid values remain unchanged
	assert_int(enemy.hp).is_equal(50)
	assert_float(enemy.speed).is_equal(120.0)
	assert_int(enemy.damage).is_equal(20)
	assert_float(form.hp_multiplier).is_equal(1.5)
	assert_float(form.duration_seconds).is_equal(10.0)
