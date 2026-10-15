# Agent-Friendly Architecture Plan

This program rearchitects the Odin codebase to eliminate recurring agent mistakes and reduce context load.
It decomposes the monolithic source into domain modules and introduces strong types for sectors and assignments.
The work is structured for autonomous execution across six sequential PRs.
PR ids in order are PR-1, PR-2, PR-3, PR-4, PR-5, and PR-6.

## How to read this

One box is one unit of work.
Every box names the evidence that checks it.
A nested box is a sub-step of the box above it.
Check a box only when its evidence exists, a file, a log line, a screenshot, a test run, or a SHA.
The body is a how-to.
The appendices explain and record.

The program runs `pstack/skills/poteto-mode/playbooks/autopilot-stack.md` or `pstack/skills/poteto-mode/playbooks/autopilot-full.md`.
The operator selects the execution playbook before execution starts.
PR-1 through PR-6 are autonomous PRs.

Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Program checklist

### Arm the program

- [ ] State the protocol and this plan to the operator, then stop. Start execution only on the operator's explicit go.
- [ ] Read these from trunk at program start. Re-read them at every tick.
  - [ ] `git show origin/main:pstack/skills/poteto-mode/playbooks/autopilot-stack.md`
  - [ ] `git show origin/main:pstack/skills/swarm/SKILL.md`
  - [ ] `git show origin/main:pstack/skills/control-cli/SKILL.md`
  - [ ] `git show origin/main:pstack/skills/poteto-mode/playbooks/opening-a-pr.md`
  - [ ] `git show origin/main:pstack/skills/correct/SKILL.md`
- [ ] On the operator's go, arm the audit tick as `/loop 1h` with the tick prompt below. Never leave the cadence to memory.
- [ ] Use this tick prompt, verbatim. "Re-read the execution playbook from trunk. Audit the operation against it and fix drift in this tick. Probe every active lane and judge progress by side effects only. Stand down a stuck lane and dispatch its replacement now. Then post a short status message to the operator in chat only when the audit found a tracked change that no earlier status message reported, such as a PR opened, a code-ready head, a round launched or closed, a verdict, a merge, a stuck agent and the action taken, a blocker added or cleared, or a decision only the operator can make. Name every such change and nothing else. Do not repeat a table, the merged list, or an unchanged blocker. If the audit found none, end the turn with no reply text. Either way, log this tick's row in your decision trail. The row names the items reported, or none."
- [ ] On the operator's hold or stand-down, send every owner a zero-writes order at once.

### Spawn owners

- [ ] Spawn one owner per PR with the full lifecycle the execution playbook names.
- [ ] Follow this dependency graph. Start dependent work only after its parent merges, or base it on the parent branch when the execution playbook stacks.
  - [ ] PR-1 is independent and first. It branches from `main`.
  - [ ] PR-2 after PR-1.
  - [ ] PR-3 after PR-2.
  - [ ] PR-4 after PR-3.
  - [ ] PR-5 after PR-4.
  - [ ] PR-6 after PR-5.
- [ ] Hold the file boundaries. PR-1 through PR-6 touch only files in `src/` and `docs/`.
- [ ] Hold the review gate. PR-1 through PR-6 preserve gameplay behavior and UI appearance.

### PR mechanics, for every PR

- [ ] Resolve the forge once. Default to `gh`; if `command -v origin` succeeds and Origin can resolve the repository, use `origin pr` for every PR operation. Record any fallback to `gh`. Never require `gt`.
- [ ] Open the PR ready, never draft, per **Opening a PR**. Use the run's built-in PR tool when it has one, else `origin pr create --status open --base <base-branch>` or `gh pr create --base <base-branch>` according to the resolved forge. A stack child targets its parent branch.
- [ ] Run the repo's lint and typecheck once before the PR-facing push. Push with hooks on.
- [ ] Run `/deslop` before each commit and `/no-comments` before review.
- [ ] Triage every Bugbot and security-reviewer comment per `../references/bugbot-triage.md`.
- [ ] Rebase onto current trunk before the code-ready report and babysit. Keep that merge base in fix rounds. Rebase again only at merge prep, on a `git merge-tree` conflict with trunk, or on a CI failure that comes from a change on trunk.

### Verdict and merge, for every PR

- [ ] A full swarm runs once, at the code-ready head. Another full swarm runs only for new behavior, a redesign, or a large new diff. A rebase, a merge-conflict resolution, or a minor fix gets a single verifier at the new head. Run each full swarm per `pstack/skills/swarm/SKILL.md`. One gates lane. The ten live lanes from the PR's **Verify, live** block. The perf lane from its **Verify, perf** block. Two or more audit lanes, each with its own focus, that read the diff and the receipts and distrust the PR body. The root audits the receipts in the merge-ready report before the verdict.
- [ ] Clean only when every lane is `PASS`. Findings go back to the owner, including a defect that a lane filed as a note. A new head gets a fresh verdict, except for results that stay valid under the patch-id rule in `playbooks/shipping.md`.
- [ ] The owner squash-merges its own PR in autopilot-full, or the root appends it to the base-branch stack in autopilot-stack.

### Boot recipe, for every live lane

Each live lane runs on its own cloud VM at the PR head. Drive through `control-cli` from `cursor-team-kit`.

- [ ] `git fetch origin <head-branch> && git checkout <head SHA>`.
- [ ] Run `make clean && make`.
- [ ] Run `odin test src -define:ODIN_TEST_THREADS=1`.
- [ ] Save every screenshot to `/tmp/swarm-<pr-id>/worker-<n>/<slug>.png` and return the paths with the report.

## Extract Core Domain Types and Sector Safety (PR-1)

**Depends on.** None.

**Files.**

- [ ] Create `src/types.odin`.
- [ ] Edit `src/main.odin`.

**Build.**

- [ ] Move constants, `Planet` enum, `Sector` enum, and `Construction_Assignment` enum into `src/types.odin`.
- [ ] Use `Sector` for sector tables and `Planet` for planet tables so out-of-bounds indexing fails at compile time.

**You see.**

- [ ] `src/types.odin` defines `Planet` and `Sector` enums.
- [ ] `odin build src -debug` succeeds without errors.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `odin test src -define:ODIN_TEST_THREADS=1`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `gemini-3-8-flash` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run `odin test src -define:ODIN_TEST_THREADS=1` at trunk and head. Save `lane-1-test.png`. Pass when all 224 tests pass.
- [ ] Lane 2. Build debug target. Run `make clean && make`. Save `lane-2-build.png`. Pass when binary exists.
- [ ] Lane 3. Build release target. Run `make clean && make release`. Save `lane-3-release.png`. Pass when binary exists.
- [ ] Lane 4. Verify Sector enum bounds check. Compile test rejecting invalid index. Save `lane-4-bounds.png`. Pass when compiler rejects bad index.
- [ ] Lane 5. Verify reset world resets all sector tables. Run world reset test. Save `lane-5-reset.png`. Pass when clean.
- [ ] Lane 6. Verify starting planets configuration. Run startup test. Save `lane-6-start.png`. Pass when eight planets match.
- [ ] Lane 7. Verify garrison tables align with sector constants. Run garrison test. Save `lane-7-garrison.png`. Pass when matching.
- [ ] Lane 8. Verify headquarters sector index. Run enemy HQ test. Save `lane-8-hq.png`. Pass when sector pos matches.
- [ ] Lane 9. Verify unit constants. Run unit cap test. Save `lane-9-caps.png`. Pass when MAX_UNITS is 2560.
- [ ] Lane 10. Verify compiler check pass. Run `odin check src`. Save `lane-10-check.png`. Pass when zero warnings.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Test execution duration in milliseconds.
- [ ] Probe. Run `odin test src -define:ODIN_TEST_THREADS=1` ten times and take the median.
- [ ] Baseline. Record trunk duration of 125 milliseconds.
- [ ] Rule. Head duration must stay under 250 milliseconds.

**Review gate.** None. PR-1 is not review-gated.

**Merge.**

- [ ] Root clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] PR appended to stack or merged.

## Extract Vector UI Primitives (PR-2)

**Depends on.** PR-1.

**Files.**

- [ ] Create `src/ui_primitives.odin`.
- [ ] Edit `src/main.odin`.

**Build.**

- [ ] Move vector drawing functions including `draw_chamfered_panel` and `draw_segmented_meter` to `src/ui_primitives.odin`.
- [ ] Remove 847 lines of primitive drawing procs from `src/main.odin`.

**You see.**

- [ ] `src/ui_primitives.odin` contains all vector drawing primitives.
- [ ] `src/main.odin` shrinks by 847 lines.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `odin test src -define:ODIN_TEST_THREADS=1`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `gemini-3-8-flash` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run `odin test src -define:ODIN_TEST_THREADS=1` at trunk and head. Save `lane-1-test.png`. Pass when all tests pass.
- [ ] Lane 2. Build debug target. Run `make clean && make`. Save `lane-2-build.png`. Pass when binary builds.
- [ ] Lane 3. Build release target. Run `make clean && make release`. Save `lane-3-release.png`. Pass when binary builds.
- [ ] Lane 4. Verify button hitboxes. Run button rect calculation tests. Save `lane-4-buttons.png`. Pass when rects match.
- [ ] Lane 5. Verify segmented meter math. Run segmented meter step test. Save `lane-5-meter.png`. Pass when values clamp.
- [ ] Lane 6. Verify winged panel metrics. Run winged panel layout tests. Save `lane-6-wings.png`. Pass when dimensions match.
- [ ] Lane 7. Verify optical reticle coordinates. Run reticle test. Save `lane-7-reticle.png`. Pass when geometry checks pass.
- [ ] Lane 8. Verify progress bracket clamp logic. Run progress test. Save `lane-8-progress.png`. Pass when clamp holds.
- [ ] Lane 9. Verify corner bracket extents. Run corner tests. Save `lane-9-corners.png`. Pass when offsets match.
- [ ] Lane 10. Verify compiler check pass. Run `odin check src`. Save `lane-10-check.png`. Pass when zero warnings.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Full compilation time of debug binary in seconds.
- [ ] Probe. Run `make clean && time make` five times and take the median.
- [ ] Baseline. Record trunk compilation time of 2.1 seconds.
- [ ] Rule. Head compilation time must stay under 3.5 seconds.

**Review gate.** None. PR-2 is not review-gated.

**Merge.**

- [ ] Root clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] PR appended to stack or merged.

## Extract Save and Load Serialization System (PR-3)

**Depends on.** PR-2.

**Files.**

- [ ] Create `src/save_system.odin`.
- [ ] Edit `src/main.odin`.

**Build.**

- [ ] Move `serialize_game_state`, `deserialize_game_state`, `save_game`, and `load_game` to `src/save_system.odin`.
- [ ] Centralize save format tokens and field parsers in one place.

**You see.**

- [ ] `src/save_system.odin` owns file persistence.
- [ ] `src/main.odin` shrinks by 550 lines.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `odin test src -define:ODIN_TEST_THREADS=1`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `gemini-3-8-flash` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run `odin test src -define:ODIN_TEST_THREADS=1` at trunk and head. Save `lane-1-test.png`. Pass when all tests pass.
- [ ] Lane 2. Build debug binary. Run `make clean && make`. Save `lane-2-build.png`. Pass when build succeeds.
- [ ] Lane 3. Verify serialization round trip. Run save and load test case. Save `lane-3-roundtrip.png`. Pass when deserialized state matches.
- [ ] Lane 4. Verify save file existence check. Run `save_game_exists` test. Save `lane-4-exists.png`. Pass when probe succeeds.
- [ ] Lane 5. Verify unit record serialization. Run unit save test. Save `lane-5-unitsave.png`. Pass when positions match.
- [ ] Lane 6. Verify sector orbital defense save. Run orbital defense persistence test. Save `lane-6-defense.png`. Pass when level matches.
- [ ] Lane 7. Verify base counts and build queue save. Run base save test. Save `lane-7-bases.png`. Pass when queues match.
- [ ] Lane 8. Verify camera position save. Run camera save test. Save `lane-8-camera.png`. Pass when vectors match.
- [ ] Lane 9. Verify refinery status save. Run refinery save test. Save `lane-9-refinery.png`. Pass when flags match.
- [ ] Lane 10. Verify compiler check pass. Run `odin check src`. Save `lane-10-check.png`. Pass when zero warnings.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Save game serialization and deserialization duration in microseconds.
- [ ] Probe. Benchmark serializing and deserializing 1000 units in test harness.
- [ ] Baseline. Record baseline duration of 1800 microseconds.
- [ ] Rule. Head duration must stay under 3600 microseconds.

**Review gate.** None. PR-3 is not review-gated.

**Merge.**

- [ ] Root clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] PR appended to stack or merged.

## Extract 3D Visuals and Procedural Rendering (PR-4)

**Depends on.** PR-3.

**Files.**

- [ ] Create `src/rendering_3d.odin`.
- [ ] Edit `src/main.odin`.

**Build.**

- [ ] Move 3D model generation, drone models, planet procedural textures, and starfield rendering to `src/rendering_3d.odin`.
- [ ] Move combat nebulae, laser bolts, and Earth industrial light rendering.

**You see.**

- [ ] `src/rendering_3d.odin` encapsulates all procedural mesh and texture generation.
- [ ] `src/main.odin` shrinks by over 2000 lines.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `odin test src -define:ODIN_TEST_THREADS=1`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `gemini-3-8-flash` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run `odin test src -define:ODIN_TEST_THREADS=1` at trunk and head. Save `lane-1-test.png`. Pass when all tests pass.
- [ ] Lane 2. Build debug binary. Run `make clean && make`. Save `lane-2-build.png`. Pass when build succeeds.
- [ ] Lane 3. Build release binary. Run `make clean && make release`. Save `lane-3-release.png`. Pass when build succeeds.
- [ ] Lane 4. Verify starfield generation determinism. Run starfield seed tests. Save `lane-4-stars.png`. Pass when coordinates match.
- [ ] Lane 5. Verify drone model vertex counts. Run model mesh test. Save `lane-5-mesh.png`. Pass when buffers match.
- [ ] Lane 6. Verify laser animation timing logic. Run laser anim test. Save `lane-6-lasers.png`. Pass when timer advances on unpause.
- [ ] Lane 7. Verify combat nebula intensity transition. Run nebula test. Save `lane-7-nebula.png`. Pass when intensity decays.
- [ ] Lane 8. Verify planet spin calculation. Run spin speed tests. Save `lane-8-spin.png`. Pass when rates match.
- [ ] Lane 9. Verify orbital defense muzzle position math. Run muzzle calculation test. Save `lane-9-muzzle.png`. Pass when vectors match.
- [ ] Lane 10. Verify compiler check pass. Run `odin check src`. Save `lane-10-check.png`. Pass when zero warnings.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Compilation speed in seconds.
- [ ] Probe. Run `make clean && time make` five times and take the median.
- [ ] Baseline. Record trunk duration of 2.1 seconds.
- [ ] Rule. Head duration must stay under 3.5 seconds.

**Review gate.** None. PR-4 is not review-gated.

**Merge.**

- [ ] Root clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] PR appended to stack or merged.

## Extract HUD and Planet Inspector UI (PR-5)

**Depends on.** PR-4.

**Files.**

- [ ] Create `src/ui_inspector.odin`.
- [ ] Create `src/ui_hud.odin`.
- [ ] Edit `src/main.odin`.

**Build.**

- [ ] Move planet inspector layout and unit roster rendering to `src/ui_inspector.odin`.
- [ ] Move top dock, squads badge bar, controls overlay, and pause menu to `src/ui_hud.odin`.
- [ ] Couple button drawing with click hitbox definitions into shared layout procs to eliminate offset drift.

**You see.**

- [ ] Inspector code lives in `src/ui_inspector.odin`.
- [ ] HUD and modals live in `src/ui_hud.odin`.
- [ ] `src/main.odin` shrinks by another 1800 lines.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `odin test src -define:ODIN_TEST_THREADS=1`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `gemini-3-8-flash` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run `odin test src -define:ODIN_TEST_THREADS=1` at trunk and head. Save `lane-1-test.png`. Pass when all tests pass.
- [ ] Lane 2. Build debug binary. Run `make clean && make`. Save `lane-2-build.png`. Pass when build succeeds.
- [ ] Lane 3. Verify inspector layout coordinates. Run inspector rect tests. Save `lane-3-inspector.png`. Pass when rects match.
- [ ] Lane 4. Verify pause menu navigation logic. Run pause menu keyboard tests. Save `lane-4-pause.png`. Pass when wrapping holds.
- [ ] Lane 5. Verify squad HUD badge formatting. Run squad badge count tests. Save `lane-5-squads.png`. Pass when counts match.
- [ ] Lane 6. Verify ghost inspector section stacking. Run ghost view layout tests. Save `lane-6-ghost.png`. Pass when offsets match.
- [ ] Lane 7. Verify control overlay rect calculation. Run controls rect test. Save `lane-7-controls.png`. Pass when bounds match.
- [ ] Lane 8. Verify auto build button state toggling. Run autobuild test. Save `lane-8-autobuild.png`. Pass when state flips.
- [ ] Lane 9. Verify queue slot click detection. Run queue slot test. Save `lane-9-queue.png`. Pass when slot cancels.
- [ ] Lane 10. Verify compiler check pass. Run `odin check src`. Save `lane-10-check.png`. Pass when zero warnings.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Unit test suite duration in milliseconds.
- [ ] Probe. Run `odin test src -define:ODIN_TEST_THREADS=1` ten times and take the median.
- [ ] Baseline. Record baseline duration of 125 milliseconds.
- [ ] Rule. Head duration must stay under 250 milliseconds.

**Review gate.** None. PR-5 is not review-gated.

**Merge.**

- [ ] Root clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] PR appended to stack or merged.

## Extract Combat, Economy, and Simulation Modules (PR-6)

**Depends on.** PR-5.

**Files.**

- [ ] Create `src/combat.odin`.
- [ ] Create `src/economy.odin`.
- [ ] Create `src/simulation.odin`.
- [ ] Edit `src/main.odin`.

**Build.**

- [ ] Move combat resolution, wave spawning, and orbital defense interception to `src/combat.odin`.
- [ ] Move mining calculation, refinery construction, and unit production to `src/economy.odin`.
- [ ] Move step simulation, input handling, and game initialization to `src/simulation.odin`.
- [ ] Leave `src/main.odin` as a thin entry point under 300 lines with the main loop.

**You see.**

- [ ] `src/main.odin` is a clean entry point under 300 lines.
- [ ] Each domain has its own dedicated file under 1200 lines.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run `odin test src -define:ODIN_TEST_THREADS=1`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `gemini-3-8-flash` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run `odin test src -define:ODIN_TEST_THREADS=1` at trunk and head. Save `lane-1-test.png`. Pass when all tests pass.
- [ ] Lane 2. Build debug binary. Run `make clean && make`. Save `lane-2-build.png`. Pass when build succeeds.
- [ ] Lane 3. Build release binary. Run `make clean && make release`. Save `lane-3-release.png`. Pass when build succeeds.
- [ ] Lane 4. Verify minor wave targeting logic. Run minor wave greedy pairing tests. Save `lane-4-minorwaves.png`. Pass when pairings match.
- [ ] Lane 5. Verify enemy wave HQ spawning. Run regular wave test. Save `lane-5-waves.png`. Pass when counts match.
- [ ] Lane 6. Verify mining rate and caps. Run economy mps tests. Save `lane-6-economy.png`. Pass when rates match.
- [ ] Lane 7. Verify friendly fire prevention. Run friendly fighters defense test. Save `lane-7-friendlyfire.png`. Pass when zero friendly damage.
- [ ] Lane 8. Verify constructing miners assignment isolation. Run double count regression tests. Save `lane-8-miners.png`. Pass when counts stay isolated.
- [ ] Lane 9. Verify defeat and victory triggers. Run win condition tests. Save `lane-9-victory.png`. Pass when flags latch.
- [ ] Lane 10. Verify compiler check pass. Run `odin check src`. Save `lane-10-check.png`. Pass when zero warnings.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Test suite execution duration in milliseconds.
- [ ] Probe. Run `odin test src -define:ODIN_TEST_THREADS=1` ten times and take the median.
- [ ] Baseline. Record baseline duration of 125 milliseconds.
- [ ] Rule. Head duration must stay under 250 milliseconds.

**Review gate.** None. PR-6 is not review-gated.

**Merge.**

- [ ] Root clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] PR appended to stack or merged.

## Close the program

- [ ] Every box above is checked with its evidence.
- [ ] Reply to the operator with the report the execution playbook names.

## Appendix A. Prototype evidence

Two open architectural questions were settled by prototypes.

Question 1. Can `src/main.odin` be decomposed into multiple files in `package main` without altering the Makefile or breaking compilation and tests?
Result. Proven on branch `prototype/modular-file-split`.
Evidence. 847 lines of vector UI primitives were extracted into `src/ui_primitives.odin`.
Running `make clean && make` compiled cleanly in 2.0 seconds with no Makefile changes needed.
Running `odin test src -define:ODIN_TEST_THREADS=1` passed all 224 test cases in 128 milliseconds.

Question 2. Can out-of-bounds HQ indexing crashes be made impossible at compile time?
Result. Proven in scratch prototypes `test_enum_arrays.odin` and `test_enum_reject.odin`.
Evidence. When arrays are indexed by `Planet` enum (8 elements), indexing with a `Sector` enum value causes `odin check` to fail compilation with `Error: Index 's' must be an enum of type 'Planet'`.
This statically eliminates the bounds bug seen in commit `f90b799`.

## Appendix B. Alternatives rejected

Alternative 1. Nested subpackages such as `src/combat/`, `src/rendering/`, `src/ui/`.
Rejected because Odin forbids circular imports between packages.
Game logic, rendering, and UI share unit and planet data.
Keeping files in the root `src/` directory under `package main` grants clean symbol sharing across files without circular dependency friction.

Alternative 2. Massive monolithic refactor in a single PR.
Rejected because any regression would be buried across 8500 lines of simultaneous changes.
Sequencing into verifiable units per `principle-sequence-verifiable-units` guarantees every step compiles and passes all 224 tests before the next starts.

## Appendix C. Risks

Risk 1. Missing symbol visibility during file extraction.
PR involved. PR-1 through PR-6.
Mitigation. Odin files in `package main` share package scope automatically. Running `odin check src` after each file extraction verifies all symbols resolve.

Risk 2. Hidden global variable mutation order.
PR involved. PR-6.
Mitigation. Unit tests in `src/main_test.odin` run after every step to verify identical simulation behavior.

## Appendix D. Links and reading list

- `pstack/skills/poteto-mode/SKILL.md`
- `pstack/skills/correct/SKILL.md`
- `pstack/skills/architect/SKILL.md`
- `pstack/skills/principle-model-the-domain/SKILL.md`
- `pstack/skills/principle-type-system-discipline/SKILL.md`
- `pstack/skills/principle-sequence-verifiable-units/SKILL.md`
- `pstack/skills/principle-minimize-reader-load/SKILL.md`
- `pstack/skills/principle-boundary-discipline/SKILL.md`
