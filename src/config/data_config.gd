## DataConfig Autoload #1 — 游戏中所有可调数值和静态数据表的单一真相源。
##
## Usage:
##   var enemy = DataConfig.get_enemy_config("slime_melee")
##   var pool_size = DataConfig.vfx_pool_attack
##
## ADR: docs/architecture/adr-0005-data-configuration.md
## GDD: design/gdd/data-config.md
##
## Tier 1: @export var 标量 — 80% 的调优旋钮，按系统分组，直接属性读取。
## Tier 2: Custom Resource 数组 — 结构化多字段数据，通过访问器方法查询。
extends Node


# ═══════════════════════════════════════════════════════════════════════════════
# Tier 1: Scalar Config — @export var 标量
# 按系统分组，对应 GDD Tuning Knobs 章节。其他系统直接读取属性。
# ═══════════════════════════════════════════════════════════════════════════════

# ─── VFX: Particle Pool Sizes (GDD vfx-system.md) ───
@export var vfx_pool_attack: int = 50
@export var vfx_pool_burst: int = 80
@export var vfx_pool_aura: int = 30
@export var vfx_pool_dust: int = 10
@export var vfx_pool_death: int = 60
@export var vfx_pool_cooldown: int = 40

# ─── VFX: Performance (GDD vfx-system.md) ───
@export var vfx_max_simultaneous_particles: int = 150
@export var vfx_flash_duration_ms: float = 200.0
@export var vfx_low_hp_threshold: float = 0.3

# ─── Audio: Pool Sizes (GDD audio-system.md) ───
@export var audio_sfx_pool_size: int = 8
@export var audio_ui_pool_size: int = 4

# ─── Audio: BGM (GDD audio-system.md) ───
@export var bgm_crossfade_duration: float = 0.3
@export var bgm_layer_ambient_vol: float = 1.0
@export var bgm_layer_bassline_vol: float = 0.8
@export var bgm_layer_percussion_vol: float = 0.9
@export var bgm_layer_lead_vol: float = 1.0

# ─── Audio: Thresholds (GDD audio-system.md) ───
@export var audio_bassline_threshold: float = 0.25
@export var audio_percussion_threshold: float = 0.5
@export var audio_lead_threshold: float = 0.75
@export var audio_low_hp_heartbeat_period_fast: float = 0.3
@export var audio_low_hp_heartbeat_period_slow: float = 0.5

# ─── HUD: Layout (GDD hud-system.md) ───
@export var hud_hp_bar_width: int = 200
@export var hud_hp_bar_height: int = 20
@export var hud_absorption_bar_width: int = 160
@export var hud_absorption_bar_height: int = 12

# ─── Gameplay: General (GDD data-config.md global.tres) ───
@export var base_move_speed: float = 200.0
@export var invincibility_duration_ms: float = 500.0

# ─── DataConfig: Validation (GDD data-config.md Tuning Knobs G.1) ───
@export_enum("silent", "warn", "error") var validation_strictness: String = "warn"

# ─── Hot Reload: Editor Quick Iteration (ADR-0005 Section 6) ───
@export var hot_reload_enabled: bool = true
@export var hot_reload_interval: float = 1.0


# ═══════════════════════════════════════════════════════════════════════════════
# Tier 2: Custom Resource Arrays — Inspector 中可分配 .tres 文件
# ═══════════════════════════════════════════════════════════════════════════════

@export var form_configs: Array[FormConfig] = []
@export var wave_tables: Array[WaveTable] = []
@export var enemy_configs: Array[EnemyConfig] = []
@export var area_configs: Array[AreaConfig] = []

# ─── Default Fallback Resources — 查询失败时的回退实例 ───

@export var default_form: FormConfig
@export var default_wave_table: WaveTable
@export var default_enemy: EnemyConfig
@export var default_area: AreaConfig


# ═══════════════════════════════════════════════════════════════════════════════
# Internal Caches — _ready() 中构建，运行期间只读
# ═══════════════════════════════════════════════════════════════════════════════

var _form_cache: Dictionary = {}
var _wave_table_cache: Dictionary = {}
var _enemy_cache: Dictionary = {}
var _area_cache: Dictionary = {}

var _hot_reload_timer: float = 0.0


# ═══════════════════════════════════════════════════════════════════════════════
# Validation Rules — 每个 Resource 类的字段有效范围
# 来源：Story 001 @export_range 注解 + GDD Tuning Knobs 安全范围
# ═══════════════════════════════════════════════════════════════════════════════

const VALIDATION_RULES := {
	"EnemyConfig": {
		"hp": {"min": 1, "max": 9999, "type": "int"},
		"speed": {"min": 10.0, "max": 500.0, "type": "float"},
		"damage": {"min": 0, "max": 9999, "type": "int"},
		"form_points_drop": {"min": 0, "max": 100, "type": "int"},
	},
	"FormConfig": {
		"hp_multiplier": {"min": 0.1, "max": 10.0, "type": "float"},
		"speed_multiplier": {"min": 0.1, "max": 10.0, "type": "float"},
		"damage_multiplier": {"min": 0.1, "max": 10.0, "type": "float"},
		"duration_seconds": {"min": 1.0, "max": 60.0, "type": "float"},
		"cooldown_seconds": {"min": 1.0, "max": 120.0, "type": "float"},
	},
	"WaveEntry": {
		"spawn_interval": {"min": 0.1, "max": 10.0, "type": "float"},
		"enemy_count": {"min": 1, "max": 9999, "type": "int"},
		"wave_number": {"min": 1, "max": 9999, "type": "int"},
	},
}


# ═══════════════════════════════════════════════════════════════════════════════
# Initialization
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	var start_ms := Time.get_ticks_msec()

	_build_cache(form_configs, _form_cache, "form_id", "FormConfig")
	_build_cache(wave_tables, _wave_table_cache, "table_id", "WaveTable")
	_build_cache(enemy_configs, _enemy_cache, "enemy_id", "EnemyConfig")
	_build_cache(area_configs, _area_cache, "area_id", "AreaConfig")

	var elapsed := Time.get_ticks_msec() - start_ms
	if elapsed > 2:
		push_warning("[DataConfig] Load took %dms — exceeds ADR-0005 <1ms budget." % elapsed)

	_ensure_defaults()

	var total_files := form_configs.size() + wave_tables.size() + enemy_configs.size() + area_configs.size()
	if total_files == 0:
		print("[DataConfig] No config files assigned in editor — using auto-created defaults.")

	_validate_all_configs()


func _ensure_defaults() -> void:
	if not default_form:
		default_form = FormConfig.new()
		default_form.form_id = "default"
		default_form.form_name = "Default"
		default_form.duration_seconds = 10.0
		default_form.cooldown_seconds = 15.0
	if not default_enemy:
		default_enemy = EnemyConfig.new()
		default_enemy.enemy_id = "default"
		default_enemy.display_name = "Default Enemy"
		default_enemy.hp = 30
		default_enemy.speed = 80.0
		default_enemy.damage = 10
		default_enemy.form_points_drop = 10
	if not default_wave_table:
		default_wave_table = WaveTable.new()
		default_wave_table.table_id = "default"
	if not default_area:
		default_area = AreaConfig.new()
		default_area.area_id = "default"
		default_area.area_name = "Default"
	# Seed caches with defaults so accessor lookups succeed silently
	if _form_cache.is_empty():
		_form_cache["default"] = default_form
	if _enemy_cache.is_empty():
		_enemy_cache["default"] = default_enemy
	if _wave_table_cache.is_empty():
		_wave_table_cache["default"] = default_wave_table
	if _area_cache.is_empty():
		_area_cache["default"] = default_area


# ═══════════════════════════════════════════════════════════════════════════════
# Hot Reload — 编辑器快速迭代支持
# ═══════════════════════════════════════════════════════════════════════════════

## 每帧检查是否需要热重载。仅在编辑器中启用 hot_reload_enabled 时生效。
## 累积 delta 到达 hot_reload_interval 时触发 _refresh_all_caches()。
func _process(delta: float) -> void:
	if not Engine.is_editor_hint() or not hot_reload_enabled:
		return

	_hot_reload_timer += delta
	if _hot_reload_timer >= hot_reload_interval:
		_hot_reload_timer = 0.0
		_refresh_all_caches()


## 清除全部 4 个缓存，从 @export 数组重建，重新验证，打印重载摘要。
func _refresh_all_caches() -> void:
	_form_cache.clear()
	_wave_table_cache.clear()
	_enemy_cache.clear()
	_area_cache.clear()

	_build_cache(form_configs, _form_cache, "form_id", "FormConfig")
	_build_cache(wave_tables, _wave_table_cache, "table_id", "WaveTable")
	_build_cache(enemy_configs, _enemy_cache, "enemy_id", "EnemyConfig")
	_build_cache(area_configs, _area_cache, "area_id", "AreaConfig")

	_validate_all_configs()

	var total := _form_cache.size() + _wave_table_cache.size() + _enemy_cache.size() + _area_cache.size()
	print("[DataConfig] Hot reload complete: %d configs loaded across 4 categories." % total)


## 通用缓存构建方法。
## 遍历资源数组，以指定 id_field 为键插入缓存字典。
## 重复键时后加载覆盖前加载 + push_warning。
func _build_cache(configs: Array, cache: Dictionary, id_field: String, category: String) -> void:
	if configs == null:
		push_error("[DataConfig] %s config array is null — skipping." % category)
		return

	for config in configs:
		if config == null:
			push_warning("[DataConfig] Null entry found in %s config array — skipping." % category)
			continue

		var key: String = config.get(id_field)
		if key == null or key == "":
			push_warning("[DataConfig] %s has empty or null %s — skipping entry." % [category, id_field])
			continue

		if cache.has(key):
			push_warning("[DataConfig] Duplicate config key '%s' in %s — overwriting previous." % [key, category])

		cache[key] = config


# ═══════════════════════════════════════════════════════════════════════════════
# Validation — 启动时自动执行，检查数值范围和引用完整性
# ═══════════════════════════════════════════════════════════════════════════════

## 遍历所有缓存中的 Resource，对每个字段执行范围检查和引用完整性验证。
## 违规值被自动修正（clamp/默认值），日志级别由 validation_strictness 控制。
func _validate_all_configs() -> void:
	for config in _enemy_cache.values():
		_validate_resource_fields(config)
	for config in _form_cache.values():
		_validate_resource_fields(config)
	for table in _wave_table_cache.values():
		if table.entries != null:
			for entry in table.entries:
				_validate_resource_fields(entry)

	# Reference integrity checks — extend here when cross-cache references are added


## 对单个 Resource 的所有注册字段运行范围验证。
func _validate_resource_fields(resource: Resource) -> void:
	var script_ref: Script = resource.get_script()
	var class_name_str: String = ""
	if script_ref:
		class_name_str = str(script_ref.get_global_name())
	var rules: Dictionary = VALIDATION_RULES.get(class_name_str, {})
	if rules.is_empty():
		return

	var source: String = resource.resource_path
	if source == "":
		source = class_name_str
	if source == "":
		source = resource.get_class()

	for field_name in rules:
		var rule: Dictionary = rules[field_name]
		var current_value = resource.get(field_name)
		_validate_numeric_range(source, field_name, current_value, rule, resource)


## 检查数值是否在 [min, max] 范围内。越界时 clamp 并记录日志。
func _validate_numeric_range(source: String, field_name: String, value, rule: Dictionary, resource: Resource) -> void:
	var min_val = rule["min"]
	var max_val = rule["max"]
	var type_str: String = rule.get("type", "float")

	if typeof(value) == TYPE_FLOAT or type_str == "float":
		var v: float = float(value)
		if v < min_val:
			_apply_correction(resource, field_name, v, float(min_val), source)
		elif v > max_val:
			_apply_correction(resource, field_name, v, float(max_val), source)
	else:
		var v: int = int(value)
		if v < int(min_val):
			_apply_correction(resource, field_name, v, int(min_val), source)
		elif v > int(max_val):
			_apply_correction(resource, field_name, v, int(max_val), source)


## 将修正值写回 Resource 字段，并按 strictness 级别记录日志。
func _apply_correction(resource: Resource, field_name: String, original, corrected, source: String) -> void:
	resource.set(field_name, corrected)

	match validation_strictness:
		"silent":
			pass
		"error":
			push_error("[DataConfig] Value out of range in %s: %s = %s → clamped to %s" % [source, field_name, str(original), str(corrected)])
		_:
			push_warning("[DataConfig] Value out of range in %s: %s = %s → clamped to %s" % [source, field_name, str(original), str(corrected)])


## 检查 Resource 引用字段的完整性。引用目标不在对应缓存中时替换为默认值。
func _validate_reference_integrity(resource: Resource, field_name: String, target_cache: Dictionary, target_default: Resource, target_name: String) -> void:
	var referenced := resource.get(field_name) as Resource
	if referenced == null:
		resource.set(field_name, target_default)
		if validation_strictness != "silent":
			var msg := "[DataConfig] Null reference in %s: %s → using default %s" % [resource.resource_path, field_name, target_name]
			_log_or_error(msg)
		return

	# Check if the referenced resource exists as a value in the target cache
	var found := false
	for v in target_cache.values():
		if v == referenced:
			found = true
			break

	if not found:
		resource.set(field_name, target_default)
		if validation_strictness != "silent":
			var msg := "[DataConfig] Broken reference in %s: %s → using default %s" % [resource.resource_path, field_name, target_name]
			_log_or_error(msg)


func _log_or_error(message: String) -> void:
	if validation_strictness == "error":
		push_error(message)
	else:
		push_warning(message)


# ═══════════════════════════════════════════════════════════════════════════════
# Tier 2: Accessor Methods — 类型安全的配置查询接口
# ═══════════════════════════════════════════════════════════════════════════════

## 查询 FormConfig by form_id。不存在时返回 default_form。
func get_form_config(form_id: String) -> FormConfig:
	if _form_cache.has(form_id):
		return _form_cache[form_id]
	print("[DataConfig] FormConfig '%s' not found — using default." % form_id)
	return default_form


## 查询 EnemyConfig by enemy_id。不存在时返回 default_enemy。
func get_enemy_config(enemy_id: String) -> EnemyConfig:
	if _enemy_cache.has(enemy_id):
		return _enemy_cache[enemy_id]
	print("[DataConfig] EnemyConfig '%s' not found — using default." % enemy_id)
	return default_enemy


## 查询 WaveTable by table_id。不存在时返回 default_wave_table。
func get_wave_table(table_id: String) -> WaveTable:
	if _wave_table_cache.has(table_id):
		return _wave_table_cache[table_id]
	print("[DataConfig] WaveTable '%s' not found — using default." % table_id)
	return default_wave_table


## 查询 AreaConfig by area_id。不存在时返回 default_area。
func get_area_config(area_id: String) -> AreaConfig:
	if _area_cache.has(area_id):
		return _area_cache[area_id]
	print("[DataConfig] AreaConfig '%s' not found — using default." % area_id)
	return default_area


## 返回所有已加载 FormConfig 的数组。
func get_all_forms() -> Array[FormConfig]:
	var result: Array[FormConfig] = []
	for config in _form_cache.values():
		result.append(config)
	return result


## 返回所有已加载 EnemyConfig 的数组。
func get_all_enemies() -> Array[EnemyConfig]:
	var result: Array[EnemyConfig] = []
	for config in _enemy_cache.values():
		result.append(config)
	return result


## 返回所有已加载 WaveTable 的数组。
func get_all_wave_tables() -> Array[WaveTable]:
	var result: Array[WaveTable] = []
	for config in _wave_table_cache.values():
		result.append(config)
	return result


## 返回所有已加载 AreaConfig 的数组。
func get_all_areas() -> Array[AreaConfig]:
	var result: Array[AreaConfig] = []
	for config in _area_cache.values():
		result.append(config)
	return result
