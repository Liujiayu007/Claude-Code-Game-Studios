# HUD HP Bar Formula Unit Tests
#
# Tests the HP bar fill ratio formula from HUD GDD F.1:
#   hp_fill = clamp(hp_current / hp_max, 0.0, 1.0)
#   hp_display_width = hp_fill * hp_bar_max_width
#
# Prerequisites to run:
#   1. GdUnit4 addon installed (AssetLib → GdUnit4 → Install)
#   2. project.godot in project root with GdUnit4 plugin enabled
#   3. Run: godot --headless --script tests/gdunit4_runner.gd

extends GdUnitTestSuite


# ── hp_fill ratio ──────────────────────────────────────────────

func test_hp_fill_full_health_returns_1() -> void:
	var hp_current: int = 100
	var hp_max: int = 100
	var fill: float = clampf(float(hp_current) / float(hp_max), 0.0, 1.0)
	assert_float(fill).is_equal(1.0)

func test_hp_fill_half_health_returns_0_5() -> void:
	var hp_current: int = 50
	var hp_max: int = 100
	var fill: float = clampf(float(hp_current) / float(hp_max), 0.0, 1.0)
	assert_float(fill).is_equal(0.5)

func test_hp_fill_zero_health_returns_0() -> void:
	var hp_current: int = 0
	var hp_max: int = 100
	var fill: float = clampf(float(hp_current) / float(hp_max), 0.0, 1.0)
	assert_float(fill).is_equal(0.0)


# ── hp_fill ratio edges ────────────────────────────────────────

func test_hp_fill_at_30_percent_returns_0_3() -> void:
	var hp_current: int = 30
	var hp_max: int = 100
	var fill: float = clampf(float(hp_current) / float(hp_max), 0.0, 1.0)
	assert_float(fill).is_equal(0.3)

func test_hp_fill_at_15_percent_returns_0_15() -> void:
	var hp_current: int = 15
	var hp_max: int = 100
	var fill: float = clampf(float(hp_current) / float(hp_max), 0.0, 1.0)
	assert_float(fill).is_equal(0.15)


# ── hp_fill clamps out-of-range values ─────────────────────────

func test_hp_fill_over_max_clamps_to_1() -> void:
	var hp_current: int = 150
	var hp_max: int = 100
	var fill: float = clampf(float(hp_current) / float(hp_max), 0.0, 1.0)
	assert_float(fill).is_equal(1.0)

func test_hp_fill_negative_hp_clamps_to_0() -> void:
	var hp_current: int = -10
	var hp_max: int = 100
	var fill: float = clampf(float(hp_current) / float(hp_max), 0.0, 1.0)
	assert_float(fill).is_equal(0.0)


# ── hp_display_width ───────────────────────────────────────────

const HP_BAR_MAX_WIDTH: int = 120

func test_hp_display_width_full_hp_equals_max() -> void:
	var fill: float = 1.0
	var width: int = int(fill * HP_BAR_MAX_WIDTH)
	assert_int(width).is_equal(120)

func test_hp_display_width_85_percent_equals_102() -> void:
	var fill: float = 0.85
	var width: int = int(fill * HP_BAR_MAX_WIDTH)
	assert_int(width).is_equal(102)

func test_hp_display_width_zero_hp_equals_0() -> void:
	var fill: float = 0.0
	var width: int = int(fill * HP_BAR_MAX_WIDTH)
	assert_int(width).is_equal(0)


# ── Low HP warning alpha threshold (F.4) ───────────────────────

func test_warning_alpha_above_30_percent_is_zero() -> void:
	var hp_ratio: float = 0.5
	var alpha: float = 0.0 if hp_ratio > 0.3 else 1.0
	assert_float(alpha).is_equal(0.0)

func test_warning_alpha_at_25_percent_is_nonzero() -> void:
	var hp_ratio: float = 0.25
	var alpha: float = 0.0 if hp_ratio > 0.3 else ((0.3 - hp_ratio) / 0.15 * 0.3)
	assert_float(alpha).is_equal(0.1)

func test_warning_alpha_at_10_percent_triggers_critical() -> void:
	var hp_ratio: float = 0.10
	var is_critical: bool = hp_ratio <= 0.15
	assert_bool(is_critical).is_true()
