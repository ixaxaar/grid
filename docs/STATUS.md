# GRID status (handoff, 2026-11-10 ~09:20)

Plan: docs/BUILD-PLAN.md. Decisions/deviations: docs/DECISIONS.md (read #5-#11). Program log: ../status/grid.md.
Verify: `pnpm typecheck && ./node_modules/.bin/vitest run` → tsc clean, **29 files / 305 tests green** at handoff. Tests run locally only (`make test`, `make flows`); GitHub Actions only build releases (owner, 11-28).

## Milestone: M0 done except the phone gate; M1 ≈ 60 %.
### Done (evidence = tests in the named folders)
- M0.1 scaffold (core now 2034140, CI templates installed, green). M0.2 GridState/GameDef skeleton (placeholder level T00).
  M0.3 region packs `global` (ship) + `in` (draft), strict schema, release gate, ruleset data-hash pins (src/regions/pins.ts).
  M0.4 literal-string lint (scripts/lint-strings.mjs + src/strings-lint.test.ts).
- M1.0 tools/oracles/expected.json: 71 oracles + L03/L07/L15/L17/L19, unrounded (emit_expected.py, check_printed.py: 0 mismatches).
- M1.1+1.2 src/sim/network, src/sim/loadflow (NR, Q-limits, continuation/collapse, GS, DC, sensitivities): PS-06..16, G-10/11/17, L15; P1,P2,P4,P5,P7-P14,P25 @2,000.
- M1.3 src/sim/bench (MNA, harmonics, 4-wire, machine, L01/L03 scenarios): AC-01..22, G-01..05/15/19/20, L03; P3,P6,P21,P22.
- M1.4 src/sim/dynamics (frequency window, SMIB): PS-23..26, G-12, G-13, L19 table; P16,P17.
- M1.5 src/sim/protection, src/sim/thermal (faults, relays, breakers, overload, cascade): PS-17/18/19, G-06/07/18; P19,P20.
- M1.6 src/sim/dispatch: PS-20/21/22, G-09, G-16; P15,P18.  M1.7 src/sim/weather: G-08, G-14, shape tests.
- Oracle coverage: **71/71** rows (PS-01..05/09/10/27/28 added in network.test.ts via src/sim/network/closedForm.ts); was 62/71 have engine tests. Missing: PS-01..05, PS-09, PS-10 (per-unit/3-phase/SIL/loss closed forms) and
  PS-27/28 (generator phasor; L13 stretch). Small task: add them (bench/network helpers) before the M1 exit.

### Partial (committed as WIP)
- M1.8 catalogues: row types/validator extended (src/regions/data.ts); src/data/{conductors,lineTemplates,governors,types}.ts entered.
  NOT done: src/regions/{global,in}/catalogues/** rows (generators, transformers, compensation, storage, protection, line costs,
  cables, fuels), pack wiring, src/data/data.test.ts (+RELEASE gate), 10-row spot check. Notes: l33-dog thermal MVA prints 13 vs
  13.4 computed (needs rounding allowance); Drake ampacity is US basis (skip in monotonic test); entering real rows changes the pack
  hash → bump rulesetVersion, update pins.ts AND the hard-coded `@1.1` in game.test.ts/solution.test.ts; regions.test.ts pins the
  open-recall list as provenance-only paths → must be updated when catalogue `recall` rows are added.

### Not started (next, in order)
1. ~~M1.10 systems pipeline~~ DONE (see DECISIONS #12): src/sim/tick.ts, event.ts, actions.ts, queries.ts; synthetic 10-bus day + goldens.
2. M1.8 finish (above) + M1.9 data verification (web; zero `recall` in global, 13 grid-code provenance entries are recall today).
3. ~~M1.11 verify, M1.12 perf~~ DONE (DECISIONS #13): src/leaderboard/verify.ts (GRID1 envelope + levelHash), `pnpm build:verify` -> dist/verify.mjs, src/perf.test.ts (all 7 budgets met), `pnpm fuzz:nightly`.
   **50k nightly run FAILED (546 s): P16 case 32916 (seed 20260610, window times out, 2.75 Hz off), P11 seed 20300579 (warm start lands on a different solution, |dV| 1.26 pu), P25 unresolved 859 > 2 % of 27 154 failing (3.2 %). Fix in the engine lanes, then rerun `pnpm fuzz:nightly`.**
4. M2 vertical slice (P0, L01-L03, L07) per BUILD-PLAN.

## Open issues
- ~~L17 reference sign error~~ RESOLVED (DECISIONS #10, trip load 308 MW). Was: (DECISIONS #10): reviewer script's line-charging sign is wrong; correct physics puts caps-only at
  300.05 MW vs 300 MW trip → lesson gate broken. Fix script, regenerate, re-tune L17 trip load before L17 authoring (M3).
- **Phone gate M0 not done**: APK builds (`core/qa/buildapk.sh` → build/android/GRID-debug.apk). scripts/phone-m0.sh installs +
  screenshots; run it under `flock …/.locks/phone.lock env CB_PHONE_LOCKED=1 zsh scripts/phone-m0.sh` (queue is long: other games).
- PS-22 at 3 outer iterations is 0.2 % (oracle test uses 8; DECISIONS #11).
- Godot front-end is a placeholder (clock drawer only); SMOKE OK.

## In flight at handoff
None (all workers stopped; nothing uncommitted except this handoff).

## HALT (2026-11-10, user order) - M1 done except noted; M2 ~50 %
M1: 8.x-1.12 done, 71/71 oracles, L17 fixed, 50k fuzz passes, perf in budget, Pixel M0 gate passed. M2 done: 2.1-2.4 (levels P0/L01/L02/L03/L07, world, drawers/HUD). NOT done: 2.5 failure viz, 2.6 coach, 2.7 audio, 2.8 input parity, Pixel 30fps log, M2 gate (Opus critic, testers). WIP in tree: L07 frequency bug fix (stand-in unit pMin=0, src/level/levels/l07.ts + l07-frequency.test.ts) UNVERIFIED; L07 frequency diverged >1 kHz because the 9 MW pMin stand-in unit overshoots the 0.3 MW night load. Verify full vitest + goldens before keeping.
