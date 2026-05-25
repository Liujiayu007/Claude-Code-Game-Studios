# Architecture Review Report

**Date**: 2026-05-25 (re-review after ADR fixes)
**Engine**: Godot 4.6 (GL Compatibility)
**GDDs Reviewed**: 14 (1 game-concept + 12 MVP system GDDs + 1 systems-index)
**ADRs Reviewed**: 16 (4 cross-cutting + 12 system-specific)
**Mode**: full (re-review after conflict resolution)

---

## Previous Review Status

The prior review (same date) returned a **CONCERNS** verdict with 3 blocking and 3 non-blocking ADR conflicts. All 6 issues have been fixed. This re-review verifies the fixes and checks for regressions.

---

## Conflict Resolution Verification

### Previously Blocking (HIGH) — All Resolved

| # | Conflict | Fix Applied | Verified |
|---|----------|-------------|----------|
| 1 | ADR-0009 activation gate: `meter > 0` + "COMBAT" state | Gate changed to `meter_current >= meter_max` + CHARGING. Enum `METER_EMPTY` → `METER_NOT_FULL`. All 13 COMBAT/PAUSED references replaced. | ✅ |
| 2 | ADR-0010 signal name: `enemy_defeated` vs GDD `enemy_killed` | Signal renamed to `enemy_killed`. Payload parameter `energy_value` → `form_points_drop`. All 6 occurrences updated. | ✅ |
| 3 | ADR-0012 stat defaults conflict with GDD | 6 stat values aligned: damage 5.0, range 48px, cooldown 0.8s, collider 8px, iframe 0.15s, pickup 24px. GDD-authoritative note added. | ✅ |

### Previously Non-Blocking (MEDIUM/LOW) — All Resolved

| # | Conflict | Fix Applied | Verified |
|---|----------|-------------|----------|
| 4 | ADR-0011: non-existent "COMBAT"/"PAUSED" GSM states | `enemy_defeated` → `enemy_killed`. "COMBAT" → "CHARGING" in lifecycle diagram and validation. | ✅ |
| 5 | ADR-0001: WaveSystem self-referential dependency ("9") | Fixed to "depends on 1,5,8" (AreaSystem, not self). | ✅ |
| 6 | ADR-0013: contradictory ordering note ("after" vs "before") | "after ADR-0011" → "before ADR-0011". Matches Autoload order (#8 before #9). | ✅ |

---

## Cross-ADR Conflicts

**No conflicts detected.** A full re-scan of all 16 ADRs for stale references (COMBAT, PAUSED, enemy_defeated, METER_EMPTY, meter > 0) across all modified files returned zero matches.

---

## ADR Dependency Ordering

### Topological Sort

**Foundation (no dependencies):**
1. ADR-0001: Autoload Singleton Architecture
2. ADR-0002: CanvasLayer Z-Ordering (requires 1)
3. ADR-0003: Object Pooling Architecture (requires 1)
4. ADR-0004: Signal Bus Pattern (requires 1, 3)

**Foundation — depends on Foundation:**
5. ADR-0005: Data Configuration (requires 1)
6. ADR-0006: Input System (requires 1, 5)

**Core — depends on Foundation:**
7. ADR-0007: GSM State Machine (requires 1, 4, 6)
8. ADR-0012: Player System (requires 1, 6, 7)
9. ADR-0010: Enemy System (requires 1, 5, 7)
10. ADR-0008: Absorption System (requires 1, 5, 7, 10, 12)
11. ADR-0009: Transformation System (requires 1, 5, 7, 8)
12. ADR-0013: Area System (requires 1, 5, 7)
13. ADR-0011: Wave System (requires 1, 5, 7, 10)

**Presentation — depends on Core:**
14. ADR-0014: HUD/UI System (requires 12, 9, 11)
15. ADR-0015: VFX System (requires 7, 12, 9)
16. ADR-0016: Audio System (requires 7, 12, 9, 11)

**Status**: All 16 ADRs are `Accepted`. No unresolved dependencies. No dependency cycles detected.

---

## Engine Compatibility Issues

### Engine Audit Results

| Metric | Value |
|--------|-------|
| Engine | Godot 4.6 |
| ADRs with Engine Compatibility section | 16 / 16 (100%) |
| ADRs using Post-Cutoff APIs | 1 / 16 (ADR-0015: `CpuParticles2D.emit_particle()` 4.4+) |
| Deprecated API references | 0 |
| Stale version references | 0 |
| Renderer conflicts | 0 |
| Physics engine conflicts | 0 |

**Assessment**: Clean. All ADRs correctly target Godot 4.6. ADR-0015's use of `CpuParticles2D.emit_particle()` (Godot 4.4+) is fully compatible with the pinned 4.6 version and properly documented in its Engine Compatibility section.

---

## GDD Revision Flags

No GDD revision flags — all GDD assumptions are consistent with verified engine behaviour and corrected ADRs.

---

## Architecture Document Coverage

`docs/architecture/architecture.md` does not exist. Expected for the current phase — the architecture is defined through individual ADRs rather than a unified architecture document.

---

## Pre-Gate Checklist

| Item | Status | Action |
|------|--------|--------|
| `tests/unit/` directory | ❌ Missing | Run `/test-setup` |
| `tests/integration/` directory | ❌ Missing | Run `/test-setup` |
| `.github/workflows/tests.yml` | ❌ Missing | Run `/test-setup` |
| `design/ux/accessibility-requirements.md` | ❌ Missing | Run `/ux-design` |
| `design/ux/interaction-patterns.md` | ❌ Missing | Run `/ux-design` |

---

## Verdict: PASS

**Rationale**: All 6 previously-identified cross-ADR conflicts have been resolved. No new conflicts detected. Engine compatibility is clean across all 16 ADRs (100% Engine Compatibility coverage, zero deprecated API references, zero stale version references). All 12 MVP systems have both a GDD and a corresponding ADR with aligned specifications.

The 5 missing pre-gate checklist items (test infrastructure, UX/accessibility docs) are expected at this stage — they are created during Pre-Production setup, not during ADR authoring.

### Required Actions Before Gate-Check

1. Run `/test-setup` to create test infrastructure (`tests/unit/`, `tests/integration/`, CI workflow)
2. Run `/ux-design` to create accessibility requirements and interaction patterns
3. Consider creating `docs/architecture/architecture.md` as a synthesis document before Production phase
