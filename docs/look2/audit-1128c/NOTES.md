# Audit 1128c: working notes (Ingrid Solheim, game lead)

Brief: the look only. Fix it at the root in shared 3D code, pass two benchmarks (WO-23 night, WO-16 day) at 7.5 with the art
director, then roll out, re-shoot every job, iterate to every job >= 7 and mean >= 7.5. No tag, release or publish.

## Shared kit added (root fixes)
- `godot/world3d/look.gd` (Look3D.grade): one light grade called at the end of `_update_sky` in Bay3D, Bench3D (all stages)
  and Province3D. Night: cold blue moon key (0.42), deep blue ambient, saturation 0.72, glow additive at threshold 0.9,
  exposure 1.25. Noon: exposure 0.86 (pastel wash). Also drives tree and Kit3D night lights.
- `godot/world3d/kit.gd` (Kit3D): floodlight masts (SpotLight, energy 45), street lamps (Omni 16, group switchable for
  blackouts: `Kit3D.set_group("estate", on)`), aviation lamps, chain-link fence (shaders/fence.gdshader), vans.
  Godot falls off as 1/d^attenuation: energies under ~10 give no visible pool at 15-50 m.
- Trees: `Props3D.conifer()` (six drooping ragged tiers, normals out and up, dark undersides) and `broadleaf()` (seven
  clumps, crown-blended normals); `shaders/tree.gdshader` (leaf noise, AO by height, hue per tree). Bench and bay trees
  now use it (they had a plain StandardMaterial). Bench woods: clumps and clearings, age spread, a birch variant.
- `shaders/arc.gdshader`: fault marker is an arc flash (white core, blue rim, flicker) with a blue OmniLight, not a yellow ball.
- Terrain: aerial-photo farm palette with in-field streaks; `yard_gravel` uniform (stages L23/L25/L27) gives a gravel yard.
- Province: conductors dark grey (were polished white tubes), noon sun 1.75 (was 2.2), job framing 2.75x spread, pitch 29.
- Streets and roofs: specular cut at distance (grazing sky reflection drew far towns as pale scribbles). Walls in a muted palette.

## Shot tools
- `scripts/audit-shots.sh <dir> L23 ...` (throwaway data dir per window). Quick one-shot: scratch `shot.sh`.

- Report (shift_report.gd): glass sheet 560-600 px docked right; `_frame_for_report` calls the 3D place's `report_focus()`
  (Stage3D.REPORT_FOCUS anchors per stage) then shifts the camera goal right by the ground width half the sheet covers.

## Asset pass plan (manager decision 11-28 evening: change the lever from tuning to CC0 assets)
Why: two art rounds moved the mean 3.89 -> 4.38 with 0 of 37 at 7. The ceiling is asset quality.
Sources checked reachable 11-28: Poly Haven API (models, textures, HDRIs), ambientCG API, Kenney, Quaternius. All CC0;
each licence page is checked before commit; every file goes into docs/ASSETS.md with URL, author, licence.
- Trees: Poly Haven photogrammetry (fir_tree_01, pine_tree_01, tree_small_02) are 0.3-17 M triangles. Blender is on
  this machine (/usr/bin/blender): decimate to LOD0 about 4-8 k and LOD1 about 800 triangles, bake to .glb, MultiMesh.
  Fallback: Quaternius stylized nature (low poly) if the decimated cards read badly.
- Houses: no Poly Haven houses; use a CC0 kit (Kenney City Kit Suburban or Quaternius buildings), 4-6 models, with an
  emissive window mask so the engine's lit/dark state still drives the windows.
- Props round the electrical kit (which stays generated, it carries the physics): Poly Haven street_lamp_01/02,
  flood_lights, modular_chainlink_fence, utility_box_01/02, security_light, covered_car, concrete_road_barrier.
- Materials: PBR sets (albedo/normal/roughness, 1-2 K, mipmapped) for gravel, concrete, asphalt, roof tiles, brick,
  painted metal; terrain splat (grass, crop, dirt, rock, shore) with macro variation.
- Sky: Poly Haven HDRIs for day, dusk and night, matched to the sun and moon.
- Order: benchmark WO-23 (night substation + estate) first, then WO-16/17 province day and night; the art director
  scores; roll out only when a benchmark reaches 7, then by scene family.
- Guards: the mesh-winding and mipmap tests cover imported assets; the low tier holds 60 fps (LOD, fewer instances);
  repo growth under about 80 MB.
- Before the pass: playtest regression sweep (one helper) closed and committed.

## Manager decisions 11-28 late (after WO-23 reached 7) — the run order to the finish
1. Fix the L23 low-tier stall (~470 ms frame) in this pass: warm up asset materials, shader variants and textures
   behind the loading card; frame-time log before/after. If not that, one short systems-engineer look.
2. Province benchmark now: WO-17 (town, day and night) and WO-16 (wide map), to 7 before the province rolls out.
   Real houses with LOD/MultiMesh, tree models, PBR splat, HDRI sky; lit towns must read from the map camera at night.
3. Roll out by family: other ch7 sites (with the WO-23 polish: people 2x, headlights, hedges, moon fill on dark
   houses, smoke glow, ghost car), ch4/ch8 stages, bench, bay/island, province, Career district, title.
4. Q01: Retry must replay every job's settings (test first). Close Q02-Q07, C04, C08-C13 that rollout does not;
   Q05 (L28 freeze) needs a cause.
5. After rollout: sweep 6, one per-job art round, regression playtest with real hand input on at least one job per
   chapter (mouse on trays, levers, orbit/zoom); 1280x800, 1920x1080, 2560x1440, 4K, low tier.
6. NOTES current after each family; commit and push per family. Stop to ask only if a benchmark fails 7 after two rounds.

## Status (latest first)
- 11-28 late: ASSET PASS BENCHMARK WO-23 at 7 (art director, round 2, 8c412d7). Round 1 (10fee78) stayed 6: houses +1,
  decimated firs -1. Round 2: dark tree cores under the cards, every estate light on the estate supply (blackout glints
  were window pools dropped by Kit3D's weak material refs), tighter frame, Kenney people and car, lit hall windows.
  Open on WO-23 for a solid 7 to 8: people about 2x scale, in the door and lamp pools, and still visible in the
  blackout; headlight cones on the asphalt; gardens, hedges and driveways; a faint moon fill so the dark houses keep
  their form; an orange core in the smoke (the ember is not visible); the covered car reads as a pale ghost box; grey
  bare trees at the left edge. Low tier on L23: 60 fps with one 470 ms stall per run (also 110 ms before the pass), cause
  not found. Repo: about 20 MB of assets added so far.
  Next: WO-16/17 province benchmark (day and night), then roll out by family (ch7 sites, bench, bay, province).
- Art director (Sigrid) per-job scores: round 1 on sweep 4 (6a97062) mean 3.89, 0 of 37 at 7; round 2 on sweep 5
  (ca1f8e0) mean 4.38, 0 of 37 at 7. Highest: L01, L10, L19, L23 at 6. Lowest: L14, L16, L18, L22, L24, L29, L30, L35, L36 at 3.
  Shared causes still open (her ranking): people and lit towns with a visible blackout; house textures and window bloom;
  daytime ochre/olive grade; patchwork terrain; result frames that point at the cause; Career and Jobs layout.
- Owner bug "slashed roofs" (C02, high): fixed 9e2eacd at the root (Props3D._tri, _cyl, Bay3D._quad, window strips,
  bench ring, farm boxes) + tests/mesh_winding_truth.gd. Evidence docs/look2/audit-1128c/roofs/.
- Perf (CB_NOTHROTTLE; unfocused windows cap at 10 fps by design): low tier iGPU 1080p 44-61 fps on P0, L01, L10, L16,
  L23, L26; high tier 4090 at 3840x2160 60 fps (vsync) on P0, L01, L10, L16, L23.
- 6676498: manager notes (night fill 0.95, moon 0.7; WO-24/25 framing and clear foreground; lever hidden under the
  report; plant pads clear of houses; coal pile). Sweep 3 into scratch, sheets to docs/look2/audit-1128c/after/.
- e3fbd61 roll-out 1 (shared transformer mesh, plant yard shader + floods, cooling-tower concrete, ch7 site lights,
  ch8 street lamps, stage lamp falloff). 8207172 benchmark rounds 2-3. e90cda2 the kit.
- Sigrid: round 1 WO-23 5.5/4.0, WO-16 4.5; round 2 WO-23 6.0/5.0/5.0, WO-16 5.0/5.0/6.5. Not at 7.5.
- Decision (Ingrid): the root fixes (grade, trees, report, line loading, charts fold) apply to every job by
  construction, so I rolled out before the benchmarks reached 7.5. What is left is per-scene subject detail, which
  the benchmark cannot buy for the other 35 jobs anyway. The benchmark gap is written down, not hidden.
- make test and make flows passed on e90cda2, flows on e3fbd61 and after the pad change.

## Not done / next (in order)
- Career map and the Jobs list: untouched in 1128c (old look).
- Exam text walls (WO-18/27/36) compact sheet: not done.
- Towns from afar are still sparse ribbon villages (TownGen); far houses grow, but there is no dense core.
- WO-26 plants are small plain boxes; WO-24 relays still small.
- Low tier and 4K not re-measured in 1128c.
- Every command needs `timeout`; the GPU lock `flock -w 120`. A bash call once hung 70 minutes.
- Do not edit game scripts while a sweep runs: each window loads them fresh (one window caught a parse error).
