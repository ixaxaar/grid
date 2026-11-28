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

## HANDOVER 11-28 late night (Ingrid -> next lead). Manager decisions after the province gate
1. Partial rollout APPROVED: the province street lamps (one per street piece, MultiMesh, lamp_glow halos and road pools),
   plant aircraft lights and flood halos, and engine-driven windows (per-pane emissive, dark when the sector is unserved)
   go to every town job. Also the CC0 asset set proven on WO-23 (Kenney houses with the lit/dark contract, Poly Haven
   trees with dark cores in LOD cells, props, PBR ground, HDRI skies).
2. WO-16 may OPEN its view at the evening-peak hour as presentation only (camera and time of day of the opening frame);
   the simulated day and every engine number stay as they are.

ROLLED OUT vs NOT
- Roll out: lamps, halos, engine-driven windows, kit houses and blocks with far-LOD roof variety (four tints, see P01),
  town cores of taller blocks, WO-23 trees, PBR ground, HDRI day/night skies, loaded lines thick and red when overloaded.
- Do NOT roll out: the grey-roof shed cue (P01) as it stands.
- Not built yet: WO-23 polish (people about 2x and visible in the blackout, headlight cones, hedges and gardens, faint
  moon fill on dark houses, orange core in the smoke, the ghost-white covered car, grey bare trees at the left edge).

P01 FIX IDEA (WO-17 report and any shed frame): mark dead sectors with something no healthy house can show: a cool
shadow (darkened, blue-shifted light term) over the ground and roofs of the zero-energy sectors while the served half
stays in warm sun, or draw the feeders live (glowing) and dead (dark). Remove grey from the healthy roof tints. Put the
report camera on the lit/dead boundary with the city substation in frame. Also: frame WO-16's report on plant + red T7
+ B4; cap the core-tower bloom (P02); make line thickness by load visible below 100 % (P03).

RUN ORDER FOR THE FAMILIES (commit, push and update NOTES after each)
1. Province finish: P01 fix, WO-16 evening-peak opening, WO-17 noon focal point (city substation) and lower camera;
   rescore WO-16/17 with the art director; then every province job (chapters 3, 5, 6, finale).
2. Chapter 7 sites (WO-24..27) with the WO-23 polish list above.
3. Chapter 4 and chapter 8 stages.
4. Bench scenes (includes Q06, the WO-04 camera against the powerhouse wall).
5. Bay and island (includes Q02 black plant meshes at night where the plants appear).
6. Career district, then the title.
7. Sweep 6, one per-job art round, a regression playtest with real hand input on at least one job per chapter (mouse on
   trays, levers, orbit and zoom); 1280x800, 1920x1080, 2560x1440, 4K and the low tier (L16 low was 45-53 fps).
Rules unchanged: CC0 only with docs/ASSETS.md; tests and flows local only (no GitHub workflows); no tag or release;
one helper at a time; look6 only.

## Status (latest first)
- 11-29 (Kofi): PROVINCE ROUND 4 (the art director's list). Trees: LOD1 is the scan re-cut with fewer, larger cards and no hull (dark core and cone stack deleted; visibility ranges dither); conifers are two Quaternius CC0 pines (poly.pizza) with leaf cards tinted blue-green and the scan's bark triplanar on the trunk (tools/blender/quat.py); ASSETS.md rows; trees 2.6 MB glb+atlas+leaf. C18 (clock): DECISION: before Run the dial, the radio and the sky show the 18:30 preview; the first block eases the sky to the engine's hour over about a second and the radio re-stamps its preview lines with the level start, so the log is monotonic (12:00, 14:00 ...). tests/clock_agree_truth.gd, 61 checks over L14-L18. The 'night at 14:00' and 'noon at 18:30' frames were QA overrides (CB_SKY_MIN, CB_WORLD_MINUTE) in the audit scripts; the WO-14 14:45 night is the failed-report hold (C05). WO-17 report: no ground polygon; shed houses about 40-50 % darker and desaturated, windows and lamps off; a failed report with a shed city holds the night (ShiftReport.set_shed_hold), substation on the left third, boundary running away. The feathering along feeder streets is NOT done (I removed the ground overlay instead). WO-17 opening: shifted so the spire clears the dial and the chimney the panel; the camera backs off on windows narrower than 16:9. WO-16: idle plants keep dim site lights on at night, bigger flood halos, lines continuous (glow pulse_depth 0.2), report camera 2.4x; B5 is still cut at the left edge of the WO-16 report. Toolbar: the finale/WO-17 cap bank reads 'Cap 220 / 50 MVAr' (it ran into the next tile). Low tier L16 59/59/52/49, GPU 15.5 ms; L23 60/59/60/60, GPU 12.2 ms. Not done: wind sway, the lit plant is still modest in the WO-16 evening frame, closest-zoom province woods. Province round 4 stops here.
- 11-29 (Kofi): TREES second pass (C17), province round 3 still PAUSED (resume: re-shoot is not needed, the -r3 shots are in assets-province/; open: low-tier cost is diffuse, see below; NOT done: the L16 report/night art-director look). The solid-crown trees (3dc28b7, 4e59474) were rejected up close. Replaced by generated trees (tools/blender/treegen.py + sprites.py): spruce, pine, oak, birch, shrub; a tapering trunk, forking branches, foliage cards that sit on twig ends; LOD0 (0.2-5k tris) / LOD1 (0.1-1.2k) by visibility range, one MultiMesh per LOD; broadleaf picks oak or birch by position, gardens add shrubs (Assets3D.broad_kind). The stray dark flat quad of the rejected close-up was the flat bottom cap of a solid crown (gone with the crowns). tests/vegetation_truth.gd: 29 checks, every foliage card must have a twig end inside its box, branches must end in a crown or at the trunk; controls fail. Low tier (iGPU, 1080p, CB_WORLD_MINUTE=720): L16 50/50/60/49 before, 60/60/60/60 after; L23 60 before and after (GPU 10.7 ms both); frame cost unchanged within noise. Not done: wind sway (no cheap shader hook on the StandardMaterial), oak/birch crowns are umbrella-shaped limbs, closest-zoom shots of province woods (the L17 camera frames the substation; species close-ups are from the viewer tests/tree_view.gd). `make flows` before this pass: 37 PASS, exit 0. Low-tier fps on L16 (before the tree pass) had no single cost: lamp halos 2.6 ms, forests 1.8, houses 1.7, water 1.6 of 15.3 GPU ms (CB_PERF_OFF toggles); 3D off = 60 fps.
- 11-29 (Kofi): PROVINCE ROUND 3 PAUSED for the owner's tree bug (C17). Committed: WO-16 evening-peak preview (30a1e98); the rest in the next commit: P01 shed cue (cool shadow fan over shed sectors, shed_cast.gdshader; shed roofs/walls cool and dark; no grey roof tint, Assets3D.ROOF_TINTS_*), city substation yard at the end of the transmission line on WO-17 with the opening and report cameras on it / on the lit-dead boundary, fresher green and paler wheat on the generated province (terrain.gdshader grass_hue, crop_hue, wheat_c), WO-16 report frames plant + red T7 + B4, lines thicker and load-coloured (idle lines thin teal), core blocks taller from map height, core window emission capped (P02), tests/province_shed_truth.gd (31 checks). Scene hour for WO-16 before Run is 18:30 (the engine's clock stays at the level start; the dial and radio read 18:30 until the first block, then the engine's hour). NOT done yet: -r3 shot set and its art-director look, L14/L15/L18 regression shots, `make flows`, the fps fix. Low tier L16 (CB_PERF_OFF toggles, 1080p iGPU, GPU 15.3 ms of a 20 ms frame): no single cost; switching off lamp halos saves 2.6 ms, forests 1.8, houses 1.7, water 1.6, the new shed fan 0. 3D off = 60 fps. Resume from there.
- 11-28 night (Kofi): ROLLOUT 1 of the province night kit (2c57990 and the four before it). Kit3D.glow (kit.gd) draws the province's lamp_glow halo (and a road pool above low) for every Kit3D/Assets3D street lamp, flood mast and aviation lamp, one mesh per lamp group; lamp_glow got a `lit` uniform (default -1: the province is unchanged). New lamps: bay homes (follow the home's (V/V0)^2), L10 (one per pole, mean of its three houses), Career streets (dark with the section's windows). Existing lamps got the halo: ch7 estate/sites (WO-23 blackout switches halo off with its windows), ch8 villages (level = window emission), L11 yard, flood masts, aviation lamps. Low tier: halo on every other lamp, no pools. Windows: bay/L10/ch8/Career already draw one quad per pane from Bay3D.windows_mesh with the engine contract; I did not give them the province's per-pane hash look (that needs the kit houses, the family pass). Not done: L12 city (no streets), WO-25..27 beyond the shared floods/aviation, bench scenes, a lit-night shot of bay/Career. Shots in rollout1/. The grey-roof cue is not rolled out.
- 11-28 late night: STOPPED AT THE GATE (manager rule: a benchmark under 7 after two rounds). Province round 2
  (ffc06a5, b2e55b9): WO-17 job 6 (noon 5, night 7, report 5); WO-16 job 5 (day 4, night 6, report 6). Owner on look6:
  "a cursory look at the graphics currently look gorgeous" (asset direction confirmed, keep the style).
  What blocks 7: (1) WO-17 report: shed sectors shown by grey roofs, but grey is also a healthy roof tint (bug, P01);
  needs a signal no healthy house has (cool shadow on the dead sectors with the served half in sun, or live/dead
  feeders drawn) and the camera on the boundary. (2) WO-17 noon: olive grade (grass texture and ochre fields), chimney
  as focal point instead of the city substation, camera high. (3) WO-16 report camera: plant, red T7 and B4 not in one
  frame. (4) WO-16 day map: town cores have no silhouette at map height, lines thin and not load-coloured at the opening,
  plant small and dull; or open at the evening peak (an engine/level decision, not mine). Also: core towers blown
  to white at night; "lines thicken with loading" not visible at 69 %.
  Art director's rollout advice: roll out the lamps, halos and engine-driven windows now; not the grey-roof cue.
  Low tier L16 45-53 fps (target 60, cost not found; machine at load 20 during measurement).
- 11-28 late (Kofi): province round 2 (shots *-r2 in assets-province/). TownGen placed almost no street lamps (its 34 m spacing never fit the 22 m street pieces: 6 lamps in the L17 town); now one per piece. Lamps and aircraft/flood beacons are billboard halos (lamp_glow.gdshader) with road pools (not on low), one instance per lamp, dark with their energy sector. Shed buildings (engine: town live, building energy 0) go cool and grey by day (instance .b), dark at night; report_focus frames a shed town. Core of tall blocks per generated town, house variety by position, 3 of 4 houses and a quarter of the lamps on low. Not done: the L16 day terrain still reads olive (the grass texture itself; a calmer field plot made it flatter, reverted); low-tier fps was measured with the machine at load 20, so read it as 45-53.
- 11-28 night: PROVINCE BENCHMARK round 1 (81dfa52, 3bdd695; Kofi): art director WO-17 4 -> 5 (report 4, night 5),
  WO-16 3 -> 3 (night 4). Near houses better; far towns a salmon smear; no street lights; WO-17 report shows no shed;
  lines thin. Stall fixed at its cause (music WAV encode, 098c34a). Round 2 in progress: far LOD colour, town cores,
  street lamps and town glow, visible shed sector and loaded lines, house variety, lit plant. If round 2 misses 7, stop
  and report what blocks it (manager rule). Also closed tonight: C04 (2634770), C08 (ab8f60d), C11 (a0e6c02).
- 11-28 night (Kofi, programmer): TASK A done: the L23 low-tier ~470 ms frame was the music stems' WAV encode on the main thread about 10 s after launch, not assets (it appears on L10, high tier and the classic look too; CB_NOAUDIO=1 removes it); fixed in 098c34a (encode on the worker thread). CB_HITCH=<ms> logs frames over that time. TASK B (province benchmark) in progress: Kenney kit houses and blocks (near LOD, MultiMesh chunks, engine-driven lit panes/bays), Poly Haven trees (LOD0/LOD1, generated beyond 1.4 km), day HDRI sky, asphalt streets; shots in assets-province/. Not scored by the art director.
- 11-28 night (Ingrid, while the province helper works): Q01 fixed (Retry replays every logged setting; tests/
  retry_truth.gd 99 checks, 36a24ba). Stall: the 470 ms frame was the music WAV encode on the main thread; moved to the
  worker (098c34a); hitch log shows no frame over 100 ms after loading. Q05 not reproduced (engine 0.3 s for L28; window
  runs fine). Q03 fixed (324ac10), Q04 fixed (3c539ae), C10 fixed (f3ad97f), C12 part (90a182d). Q07 is in shared core
  (codex.gd:78), left for the core owner. Open for the families: C04, C08 (ch8), C09 (WO-14 label), C11 (Career), Q02
  (plants), Q06 (WO-04 camera). Province benchmark (WO-16/17) in progress with a helper.
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
