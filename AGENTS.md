# AGENTS.md — DOTS

Project-specific guidance for ZCode agents working in this repository.

## What this is

DOTS is a **Godot 4.7 (GDScript) 2D slot-machine game**. Mobile-first portrait layout
(design 1080×1920, test 540×960), `gl_compatibility` renderer (desktop **and** mobile).
Main scene: `res://scenes/slot/SlotMachine.tscn`. 5 reels × 3 rows, 20 paylines, left-to-right matching, min 3 to win.

## Running

- **Editor:** `run_godot.bat` (expects Godot installed via `winget install GodotEngine.GodotEngine`).
  Opens the project at `%LOCALAPPDATA%\...\GodotEngine.GodotEngine_...`.
- **No Godot CLI/build pipeline is wired into package.json or CI** — run via the editor or `godot.exe` directly.
- Headless scripts are invoked as:
  `godot --headless --path <project> res://scenes/setup/<Scene>.tscn` (RTP sim) or
  `godot --headless --script res://scripts/setup/<script>.gd --path <project>` (data gen).

### Verification (there is no formal test framework — these are the test tools)

| Tool | Scene / Script | Purpose |
|------|----------------|---------|
| Generate data | `scripts/setup/generate_default_data.gd` (SceneTree script) | Regenerates **all** `.tres` under `resources/`. Re-run after balance changes. |
| RTP sim | `scenes/setup/SimScene.tscn` (`scripts/setup/run_rtp_sim.gd`) | 100k headless spins; prints RTP/hit-rate. Acceptable band **85–105%**, tune target **92–96%**. |
| Capture | `scenes/setup/CaptureTest.tscn` (`scripts/setup/run_capture_test.gd`) | GUI run, saves `captures/spin_N.png` (gitignored). |
| View flow | `scenes/setup/ViewTest.tscn` (`scripts/setup/run_view_test.gd`) | Editor (F5) run; headless frame-limit can drop evaluations. |

`generate_default_data.gd` deliberately does **not** depend on autoloads — on first run
`GameConfig` will print a "default_slot.tres not found" error that is safe to ignore.

## Directory layout & layer rules

```
autoload/        Singletons (registered in project.godot [autoload])
scripts/
  core/          Pure game logic. NO scene tree / view coupling.
                 SlotMachine.gd       – spin state machine (IDLE/SPINNING/STOPPING/EVALUATING)
                 WinCalculator.gd     – runs EvaluationPass chain
                 SpinEvaluator.gd     – single-payline evaluation
                 passes/              – EvaluationPass subclasses (Line/Scatter/Jackpot)
  data/          Resource data classes (SlotConfig, SymbolData, ReelStrip, Payline, Paytable,
                 SpinResult, LineWin, UnitData) + mechanics/ (SymbolMechanic subclasses per Kind)
  data/mechanics/ SymbolMechanic plugins — Normal/Wild/Scatter/Bonus (preload-loaded, tag-based)
  battle/        Phase 7 defense layer: Unit (Area2D), BattleField (lane + base HP),
                 BattleFieldView (HP bars), UnitSpawner (slot→unit pipeline), WaveManager
  view/          UI: SlotMachineView (orchestrator + battle integration), ReelView, SymbolView,
                 PaylineOverlay, HUD, GameOverOverlay
  effects/       BackgroundFX, WinEffects, FloatingText, JackpotFX, CameraShake,
                 ParticleBudget, SlowMotion (last two are also autoloads)
  systems/       BonusManager (free-spin state machine; also an autoload),
                 SoulGauge (Phase 8-A: soul/level progression — enemy_killed listener)
  setup/         Data-gen + test harness scripts (above)
resources/       Generated .tres: config/, symbols/(knight/archer/mage/skull), reels/, paylines/, paytables/
scenes/          slot/ (game), setup/ (test harnesses), Main.tscn
assets/          audio/, fonts/, shaders/, sprites/ (currently placeholder only)
```

**Coupling rule:** Core talks to the outside world **only via `EventBus` signals** and autoload
singletons. View/Effects/Audio **connect** to `EventBus`; they never reach into core objects
directly except `SlotMachineView` owning its `SlotMachine`. When adding features, emit/consume
signals rather than passing references.

### Critical evaluation ordering

In `SlotMachine._evaluate()`, `evaluation_completed` is emitted **before** `WalletManager.add_win`.
This lets `BonusManager` (an autoload listener) apply the free-spin multiplier to `SpinResult.total_win`
*in place* before the win is credited. Do not reorder these without updating `BonusManager._on_eval`.

### Singleton autoloads (project.godot)

`GameConfig`, `EventBus`, `WalletManager`, `JackpotSystem`, `AudioManager`, `GameManager`,
`ParticleBudget`, `SlowMotion`, `BonusManager`, `SoulGauge`.

> **Naming gotcha:** Autoload scripts that would collide with a `class_name` (e.g. `SlotConfig`)
> intentionally omit `class_name` and are referenced by their **autoload node name** (e.g.
> `GameConfig`, `BonusManager`). `BonusManager` is registered from `scripts/systems/`, not `autoload/`.

## Extension points (prefer these over of editing core)

- **New eval rule** (Ways-to-win, Cascade, Cluster…): subclass `EvaluationPass`, implement
  `process(result, ctx)`, add to `WinCalculator.default_passes()`. `ctx` keys:
  `grid, paylines, paytable, bet, line_bet, free_multiplier, payline_count`.
- **New symbol behavior** (ExpandingWild, Multiplier, Sticky…): subclass `SymbolMechanic`,
  override the 4 query methods, assign an instance to `SymbolData.mechanic`. `SpinEvaluator`
  stays untouched — it never switches on `SymbolData.Kind` directly.
- **Result post-processing**: register a `Callable` via `SlotMachine.add_result_modifier(cb)`
  (called on the `SpinResult` in place, after passes, before `evaluation_completed`).

## Persistence

- `user://wallet.save` — credit + total_won (`WalletManager`, ConfigFile).
- `user://jackpot.save` — 4-tier (Mini/Minor/Major/Grand) progressive pools (`JackpotSystem`).
Both load on `_ready()`, save on every mutation **only after** `initialize()` has run.

## Conventions

- **Comments and docstrings are written in Korean** (GDScript `##` headers). Match this when editing.
- Typed code: use `class_name`, typed arrays (`Array[ReelStrip]`), `PackedInt32Array`/`PackedFloat32Array`.
  Note typed arrays cannot be assigned a plain `Array` directly — convert explicitly (see `generate_default_data.gd`).
  **⚠️ MOBILE SERIALIZATION BUG (2026-07-07)**: Do NOT use `@export var x: PackedInt32Array` on
  `Resource` subclasses — Godot 4.7 silently serializes it as an empty array in binary `.res` export
  (desktop `.tres` is unaffected, so this only breaks on Android/iOS). This caused a full week of
  debugging (matches evaluated to `has_win=false` on phone only). **Use individual `@export int` fields
  instead** — see `SymbolData.payout_3/4/5` and `Payline.row_r0..row_r4`. Same hazard applies to
  `PackedFloat32Array` and `PackedStringArray` on exported Resource fields.
- Symbols (Phase 8 redesign): `knight` (tank, blue shield), `archer` (ranged dealer, green bow),
  `mage` (heavy dealer, purple magic circle), `skull` (miss/grunt, gray skull). Wild/Scatter/Bonus
  symbols were **removed** when gems were cut to 4 unit types — the `Kind` enum and mechanic classes
  remain for forward compatibility. Each `SymbolData.unit_id` maps a match to a `UnitData` to spawn.
- **SymbolMechanic mobile loading**: `SymbolMechanic.for_kind()` must `preload` its subclasses
  (Normal/Wild/Scatter/Bonus) — `class_name` lazy references fail on APK runtime first call. The
  registry uses a `Dictionary` (OCP: add new mechanic via `_register()` one-liner, no match edit).
  `is_scatter()`/`is_bonus()` use `get_tags()` lookup, **not** `is X` type checks (forward-compat).
- `.tres` resources are **generated**, not hand-edited for balance — change constants in
  `generate_default_data.gd` (`REEL_STRIPS`, `PAYLINES`, payout fields, paytable) and regenerate.
- Renderer **must stay `gl_compatibility`** for both desktop and mobile — keep shaders/assets compatible.
- Godot `.uid` files and `.godot/` (the latter is gitignored) are engine-managed; don't hand-edit.

## Mobile testing (Android)

- APK debug build: `export_presets.cfg` (preset "Android Debug", Gradle disabled for speed).
- Full setup + install guide: see **`docs/MOBILE_TEST_GUIDE.md`**.
- Build via `DOTS_test.bat` [6], install to phone via [7] (requires USB debugging + USB connection).
- Package name: `com.ralph.dots`. Output: `build/DOTS-debug.apk` (~58MB).
- **⚠️ Stale data trap (2026-07-07 lesson)**: `adb install -r` preserves `user://` save data
  (`wallet.save`, `jackpot.save`). After code changes, if you rebuild APK but the phone is still
  running the old version, the old code + old save produces "fixed-but-still-broken" symptoms.
  Always (a) rebuild APK after edits, (b) `adb install -r` to actually update the on-device binary,
  (c) `adb shell pm clear com.ralph.dots` to wipe stale user data when behavior looks stale.

## Asset generation (ComfyUI)

- Pixel-art symbols are generated via a ComfyUI pipeline on `ralph@ralphpark.com:2202` (user-owned server).
- Scripts: `tools/comfyui/` (`comfy_gem.py` = single symbol, `comfy_dots_symbols.py` = batch 7).
- Full workflow (SSH access, API control, prompts, troubleshooting): see **`docs/COMFYUI_GUIDE.md`**.
- Generated PNGs go in `assets/sprites/{id}_transparent_180.png`; `generate_default_data.gd` auto-loads
  them into `SymbolData.texture` (null → procedural shape fallback).

## Git

- `.godot/`, `captures/`, `*.translation`, IDE dirs are gitignored.
- Recent work is in Korean commit messages (`feat: Phase N …`). Branch: `main`.
