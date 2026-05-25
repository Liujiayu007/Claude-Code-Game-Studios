# Game Concept: Shapeshift Survivor

*Created: 2026-05-23*
*Status: Approved*

---

## Elevator Pitch

> A Roguelike survivor where you transform into different monster forms to turn the tide of battle. You absorb enemies to build transformation power, then unleash explosive form shifts that reverse your fortunes with devastating new attack patterns.

Test: Can someone who has never heard of this game understand what they'd be doing in 10 seconds? Yes — it's a survivor game where you transform into different monster forms to survive.

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | Roguelike Survivor with Build System |
| **Platform** | PC (Steam / Epic), Web / Browser |
| **Target Audience** | Achievers (power build enthusiasts) and Explorers (combination tinkerers) |
| **Player Count** | Single-player |
| **Session Length** | 20-40 minutes (complete run) |
| **Monetization** | Premium |
| **Estimated Scope** | Medium (5-6 months, solo) |
| **Comparable Titles** | Brotato, Cult of the Lamb, Nioh 2 |

---

## Core Fantasy

You experience the visceral thrill of transformation — starting as a fragile human, absorbing enemy essence, then shapeshifting into powerful monster forms that dominate the battlefield. The fantasy is not survival itself, but the power fantasy of "build-up → release" — seeing your choices accumulate into a dramatic moment where everything clicks and you become unstoppable.

---

## Unique Hook

Like Vampire Survivors, AND ALSO like Nioh 2's yokai transformations — but in a survivor format. What makes this different is that your power isn't gradual stat creep; it's dramatic, timed form shifts that completely change how you play the game. Each form has its own mutation tree, creating build depth while keeping the core loop simple.

The hook is:
- Explainable in one sentence: "A survivor game where you shapeshift into monster forms with timed power spikes."
- Genuinely novel: Combines survivor genre's simplicity with shapeshifter's dramatic rhythm
- Connected to core fantasy: Transformation IS the fantasy, not a side mechanic
- Affects gameplay: Every form changes attack patterns, positioning, and strategy

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the player FEELS)

| Aesthetic | Priority | How We Deliver It |
| ---- | ---- | ---- |
| **Fantasy** (make-believe, role-playing) | 1 | Transformation power fantasy, absorbing enemies essence |
| **Challenge** (obstacle course, mastery) | 2 | Difficulty progression through areas, mastery of form timing |
| **Expression** (self-expression, creativity) | 3 | Build variety through mutation trees and form combinations |
| **Discovery** (exploration, secrets) | 4 | Unlocking new forms, discovering mutation synergies |
| **Sensation** (sensory pleasure) | 5 | Transformation visual/audio impact, screen shake, particle effects |
| **Submission** (relaxation, comfort zone) | N/A | Not applicable — game requires engagement |
| **Narrative** (drama, story arc) | N/A | Minimal story — background lore only |
| **Fellowship** (social connection) | N/A | Single-player only |

### Key Dynamics (Emergent player behaviors)
- Players will time their transformations for maximum impact against boss waves
- Players will experiment with different mutation trees to find form-specific synergies
- Players will develop "opening gambits" — early-game strategies to reach first transformation quickly
- Players will share optimal mutation combinations and boss-specific form counters with community

### Core Mechanics (Systems we build)

1. **Absorption System** — Killing enemies grants "form points" that accumulate toward transformation meter
2. **Transformation System** — When full, player activates form shift with duration and cooldown
3. **Mutation Trees** — Each form has upgrade branches that enhance specific attacks, shorten cooldowns, or add effects
4. **Area Progression** — Defeating area bosses unlocks new forms with unique themes
5. **Difficulty Selection** — Player可选择难度 to control pressure intensity

---

## Player Motivation Profile

### Primary Psychological Needs Served

| Need | How This Game Satisfies It | Strength |
| ---- | ---- | ---- |
| **Autonomy** (freedom, meaningful choice) | Player chooses which mutations to upgrade, which form to transform into, and when to trigger transformations | Core |
| **Competence** (mastery, skill growth) | Visible progression through mutation unlocks, layer advancement, and timing mastery | Core |
| **Relatedness** (connection, belonging) | Minimal — background lore for each form but no social systems | Minimal |

### Player Type Appeal (Bartle Taxonomy)

- [x] **Achievers** (goal completion, collection, progression) — How: Unlocking new forms, completing mutation trees, reaching higher layers
- [x] **Explorers** (discovery, understanding systems, finding secrets) — How: Experimenting with mutation combinations, discovering form synergies
- [ ] **Socializers** (relationships, cooperation, community) — Not applicable
- [ ] **Killers/Competitors** (domination, PvP, leaderboards) — Not applicable

### Flow State Design

Flow occurs when challenge matches skill. How does this game maintain flow?

- **Onboarding curve**: First 10 minutes teach basic movement, absorption, and first transformation with guided prompts
- **Difficulty scaling**: Challenge grows through area progression (more enemy types, higher density) with difficulty selection allowing players to calibrate to their skill level
- **Feedback clarity**: Layer number cleared, mutation unlocks, form availability all provide clear progress indicators
- **Recovery from failure**: Runs are 20-40 minutes, fail conditions are clear, death shows what killed you and suggests adaptations

---

## Core Loop

### Moment-to-Moment (30 seconds)

In human form, you move to position, auto-attack nearby enemies, and collect dropped "form points" from kills. A visual meter fills with rising audio intensity. When full, a prompt appears to transform. Activating transformation triggers screen flash, character model change to chosen form, and attack pattern shift to the new form's unique style. You remain in this form for a fixed duration, then automatically revert to human form and repeat the loop.

**Intrinsic satisfaction sources**:
- "Build-up → release" emotional rhythm (charge sound, visual glow, transformation boom)
- Audio feedback (rising intensity, thunderous transformation sound)
- Visual juice (charge particle effects, screen shake on transformation, form-specific attack visuals)
- Clear power spike (damage output visibly increases, enemies melt faster)

### Short-Term (5-15 minutes)

Each enemy wave clears, and you're presented with 3-4 mutation upgrade options. You think strategically: "Which mutation helps me survive the next wave?" or "Should I invest in my current form's main branch or unlock a side branch for synergy?" As mutations accumulate, you see your build taking shape — this form attacks faster, that form lasts longer, cooldowns shorten.

**"One more run" psychology**: When you've just unlocked a powerful mutation, you want to test it in the next wave. When you've just unlocked a new form, you want to try it immediately. The game hooks you with "just one more mutation" and "just one more form to try."

### Session-Level (30-120 minutes)

A complete session is reaching a specific layer or defeating a boss. You see your best layer achieved, which forms you unlocked, and your strongest mutation combination. When you die or complete the area, you see a summary: "You reached Layer 12, unlocked 3 forms, found the fire-breath mutation synergy." The session ends with a natural stopping point AND a question: "If I had chosen that other mutation, could I have reached Layer 13?"

### Long-Term Progression

Over days/weeks, you progress by:
- Unlocking new forms by defeating area bosses
- Exploring different mutation tree branches for each form
- Discovering optimal form combinations for different enemy types
- Progressing through areas to face harder challenges

The game is "complete" when you've unlocked all forms and experienced the major mutation combinations, but replayability comes from trying different build paths and achieving higher layers.

### Retention Hooks

- **Curiosity**: What mutations does the next form offer? What form unlocks in the next area?
- **Investment**: You've invested in this build, you want to see how far it can go. You're 1 mutation away from completing that branch.
- **Mastery**: You've mastered the timing for Form A. Can you master Form B? Can you reach the next difficulty tier?
- **Variety**: You've played a defensive build. What if you try an all-out offense build? Different forms, different experience.

---

## Game Pillars

Design pillars are non-negotiable principles that guide EVERY decision. When two design choices conflict, pillars break the tie.

### Pillar 1: Explosive Transformation

The transformation moment must deliver dramatic, satisfying power release — screen flash, sound impact, visible strength increase.

*Design test*: If we're debating between a subtle transformation and a dramatic one, this pillar says we choose the dramatic one, even if it costs development time.

### Pillar 2: Meaningful Choice

Every mutation and form choice must have visible, important effects on gameplay — not just stat creep, but fundamentally different play patterns.

*Design test*: If we're debating between two upgrade options, this pillar says we choose the one that significantly changes how the player plays, not just adds +5% damage.

### Pillar 3: Paced Mastery

Players must have agency over challenge pacing — the ability to control pressure through timing choices, not pure reaction.

*Design test*: If we're debating between adding a mechanic, this pillar says we choose the one that allows players to mitigate pressure through strategic timing, not just react faster.

### Anti-Pillars (What This Game Is NOT)

Anti-pillars are equally important — they prevent scope creep and keep the vision focused.

- **NOT highly precise action requirements**: Because this would undermine the "transformation reverses fortunes" fantasy and add frustration
- **NOT extended single-form gameplay**: Because this would diminish the specialness of transformations and reduce the "build-up → release" rhythm
- **NOT random, unstable transformation mechanics**: Because this would conflict with the player's strategic choice fantasy and make planning meaningless

---

## Visual Identity Anchor

**Selected Direction**: 形态对比（Form Contrast） - 清晰的视觉区分是变形体验的关键

**One-Line Visual Rule**: 每个形态有独特的颜色主题和视觉轮廓，玩家一瞥就能识别当前形态

**Supporting Visual Principles**:
- **颜色纪律** - 每个形态的主色贯穿其所有资产和特效
  *设计测试*: 在两个视觉元素中选择时，选择那个符合形态颜色主题的

- **轮廓差异** - 人类形态与怪物形态的轮廓有足够对比，变形瞬间明确
  *设计测试*: 如果两个形态的轮廓相似，重新设计其中一个使其独特

- **特效统一** - 每个形态的攻击特效使用相同的视觉语言（粒子形状、光晕模式）
  *设计测试*: 如果一个形态的攻击特效与其他不一致，统一到该形态的风格

**Color Philosophy**: 颜色是身份，不是装饰。玩家应该看到红色粒子就知道这是"火焰形态"，看到蓝色就知道是"冰霜形态"。颜色编码必须一致且可预测。

---

## Inspiration and References

| Reference | What We Take From It | What We Do Differently | Why It Matters |
| ---- | ---- | ---- | ---- |
| **Brotato** | Rich build depth with varied character options, difficulty selection for pacing control | Instead of different characters, we have shapeshifting forms that change mid-game | Validates that build depth is competitive in low-budget indie games |
| **Nioh 2** | Transformation rhythm (build-up → release), distinct form styles with unique attack patterns | Simplified for survivor genre, no complex input requirements | Proves transformation's visceral thrill potential |
| **Slay the Spire** | Card成型后的正反馈节奏，策略深度 vs 随机性 | Instead of cards, we have mutation trees; instead of deck building, we have form progression | Validates the "build-up → power fantasy" emotional rhythm |

**Non-game inspirations**:
- *Jekyll & Hyde* literary duality — the tension between human restraint and monster release
- *Werewolf transformation folklore* — the loss of control mixed with gaining power

---

## Target Player Profile

| Attribute | Detail |
| ---- | ---- |
| **Age range** | 18-35 |
| **Gaming experience** | Mid-core — plays multiple genres, comfortable with systems |
| **Time availability** | 30-60 minute sessions, plays on evenings and weekends |
| **Platform preference** | PC (Steam), enjoys browser games for quick sessions |
| **Current games they play** | Brotato, Cult of the Lamb, Slay the Spire, Nioh 2 |
| **What they're looking for** | Rich build systems with visible power progression, transformative moments where choices payoff |
| **What would turn them away** | High-stress action games with steep failure penalties, games with little meaningful choice or feedback |

---

## Technical Considerations

| Consideration | Assessment |
| ---- | ---- |
| **Recommended Engine** | Godot 4.6 — Good Web export support, gentle learning curve for first game, free/open-source |
| **Key Technical Challenges** | State machine complexity for multi-form transformations, balancing transformation frequency |
| **Art Style** | 2D Pixel or Cartoon — lowest asset cost, focuses visual budget on transformation effects |
| **Art Pipeline Complexity** | Low-Medium — Asset reuse strategy (enemies share resources with different colors/particles) |
| **Audio Needs** | Moderate — Transformation sound impact is critical, ambient and combat music |
| **Networking** | None |
| **Content Volume** | 5-6 forms, each with 3-4 mutation branches (2-3 tiers each), 5 areas (10-15 waves each), ~3-5 enemy types per area |
| **Procedural Systems** | Enemy wave generation (density scaling), mutation option presentation (weighted by current build needs) |

---

## Risks and Open Questions

### Design Risks
- **Transformation frequency balance difficult**: Too frequent loses impact, too rare causes frustration
  *Mitigation*: Early prototype testing, dynamic cooldown adjustment (kills reduce cooldown)
- **Player motivation unclear after main forms unlocked**: What keeps players coming back?
  *Mitigation*: Mutation tree depth provides long-term exploration, different builds encourage replay

### Technical Risks
- **State machine complexity** (multiple active forms with different attack patterns): Potential for bugs in transformation transitions
  *Mitigation*: Modular state machine architecture, clear state transition boundaries, extensive testing
- **Web performance** with many particle effects: May lag on lower-end browsers
  *Mitigation*: Particle quality settings, spawn pooling, GPU-based particles where available

### Market Risks
- **Genre saturation with established competitors**: Vampire Survivors clone market is crowded
  *Mitigation*: Unique shapeshift hook provides differentiation, focus on build depth over pure survivor mechanics
- **Target audience may be too niche**: Build-focused survivors have dedicated but limited audience
  *Mitigation*: Cross-pollinate with Roguelike audience through streaming/word-of-mouth

### Scope Risks
- **Multiple forms development work**: Each new form requires new art, animations, and systems
  *Mitigation*: Asset reuse strategy, limit to 5-6 forms initially, prioritize form differentiation over quantity
- **Mutation tree depth**: Full mutation trees for 5-6 forms is a lot of content
  *Mitigation*: MVP with 2-3 forms and simplified trees, expand post-launch

### Open Questions
- **Optimal transformation duration**: How long should a form last to feel powerful but not boring? (Prototype: test 5, 10, 15 second durations)
- **Mutation tree depth vs variety tradeoff**: Fewer deep trees or more shallow trees? (Prototype: test both approaches)
- **Boss form synergy**: Should bosses reward specific forms? (Prototype: test boss patterns against different forms)

---

## MVP Definition

**Core hypothesis**: Players find the "charge → transform → release" loop engaging for 30+ minute sessions, with mutation choices creating meaningful strategy depth.

**Required for MVP**:
1. 2 forms (starting form + 1 unlockable)
2. Each form has 2 mutation branches (2-3 mutations each)
3. 1 complete area with 3-5 enemy types and 1 boss
4. Transformation system with duration, cooldown, and meter
5. Basic UI for mutation selection and form display

**Explicitly NOT in MVP** (defer to later):
- More than 2 forms
- Boss-specific form rewards
- Complex mutation synergies
- Story or narrative elements
- Achievement or progression systems outside runs

### Scope Tiers (if budget/time shrinks)

| Tier | Content | Features | Timeline |
| ---- | ---- | ---- | ---- |
| **MVP** | 2 forms, 1 area, basic mutation trees | Core transformation loop, mutation selection, area progression | 3-4 months (solo, first game) |
| **MVP+** | 3-4 forms, 3 areas, expanded mutation trees | All core features, multi-form synergies, boss progression | 5-6 months (solo, first game) |
| **Alpha** | 5 forms, 5 areas, full mutation trees | All forms complete, final balance, placeholder polish | 7-8 months (solo) |
| **Full Vision** | All planned forms and areas, polished | All content, full polish, achievements, meta-progression | 9+ months |

---

## Next Steps

- [x] Run `/setup-engine` to configure the engine and populate version-aware reference docs
- [ ] Run `/art-bible` to create the visual identity specification — do this BEFORE writing GDDs
- [ ] Use `/design-review design/gdd/game-concept.md` to validate concept completeness
- [ ] **Prototype core idea** (`/prototype [core-mechanic]`) — before writing GDDs, validate the transformation loop is fun
- [ ] If prototype PROCEEDS: Decompose concept into systems (`/map-systems`)
- [ ] Design each system (`/design-system [system-name]`) — use prototype learnings
- [ ] Plan the technical architecture with `/create-architecture`
- [ ] Validate readiness to advance with `/gate-check pre-production`