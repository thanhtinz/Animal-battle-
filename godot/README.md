# Empire Age — Godot prototype (P2 + asset thật + P3 combat/AI/fog)

2D top-down RTS prototype in Godot 4.4 / GDScript. Everything is built from
code in `_ready()` — scenes are thin shells, gameplay lives in `scripts/`.
Real pixel art is now in: the new Villager / Militia / Archer sprite sheets
(sent by Tín) were extracted with `tools/extract_sprites2.py`, and the map
dresses itself from 7 CraftPix packs (extracted under
`~/workspace/empire-age/assets-src/craftpix/`, game-ready copies in
`assets/env/`).

Run it: open this folder as a Godot 4.4 project, or
`godot --path . ` (main scene `main.tscn`, 1152×648).

## Controls

| Input | Action |
|---|---|
| Left click | Select unit / own building |
| Left drag | Selection box (own units) |
| Double-click a unit | Select **all own units of that type on the whole map** |
| Right click (no drag) | Context order: move / gather (on tree, gold, stone) / build (on own unfinished building) |
| Long-press (≥0.45 s) with units selected | Same as right-click order (touch tap mode) |
| Middle-drag or right-drag | Pan camera |
| WASD / arrow keys | Pan camera |
| Mouse wheel | Zoom (toward cursor), 0.4×–2.5× |
| Two-finger drag (touch) | Pinch zoom + pan |
| Esc | Cancel building placement (refunds cost) / cancel rally mode / clear selection |
| Minimap click / drag | Move camera there |
| Flag button (beside minimap) | Rally mode: next map click sets where newly trained villagers walk to |
| Crosshair button | Centre camera on your Town Center |
| Layers button | Select all your villagers |
| Gear button (top right) | Opens the "Khác" panel (pause / restart) |

Camera is clamped to the 64×64-tile map (2048×2048 px).

## What works (P2 scope)

- **Map**: 64×64 tiles × 32 px, seeded (12345) grassland with per-tile shade
  variation, forest clusters (trees), 2 gold clusters, 2 stone clusters, one
  lake. Trees/mines/stone/lake and buildings all share one obstacle grid that
  feeds AStarGrid2D.
- **Bases**: player Town Center (bottom-left) + 3 Villagers; enemy
  stronghold (top-right) — Town Center + Barracks + 2 Houses + Watch
  Tower in deep-blue art, run by the P3 enemy AI (see the P3 section).
- **Economy**: Food 200 / Wood 200 / Gold 100 start (Stone and Iron tracked
  too; Iron has no source yet). Villager gather loop: walk to node → gather
  2 s → carry 10 → return to Town Center → deposit +10 → repeat; when a node
  is depleted the villager automatically continues at the nearest node of the
  same type. Carried resource shows as a coloured box (the Carry animation's
  sack while returning). Every deposit is logged, and the HUD's "+x/s" rates
  are the real trailing-60-second average. **Berry bushes (CraftPix) are Food
  nodes** — the game's first Food source; villagers harvest them with the
  Harvest animation and deposit +10 Food per trip.
- **Training**: the HUD "Huấn luyện" tab trains a Villager (50 Food, ~5 s,
  queue + progress shown) at the player Town Center — no need to select the
  TC. New villagers walk to the rally point (flag button beside the minimap;
  default: beside the TC). Population is capped by completed buildings
  (TC +5, House +5); training is refused at cap. **The Barracks now trains
  for real**: Militia (60 Food + 20 Gold) and Archer (50 Wood + 40 Gold),
  queued at the Barracks through the same Huấn luyện tab; both are
  selectable, movable units with 4-direction sprites. Their Attack/Die
  frames (and the Archer's loose arrow sprite, `assets/arrow.png`) are
  extracted and ready for P3 combat.
- **Building**: HUD "Xây dựng" tab → House (30 Wood, 2×2, +5 pop), Barracks
  (100 Wood, 3×3, trains all unit types), **Mining Camp** (100 Wood, 3×3 —
  a drop-off point for **Stone and Gold**), **Watch Tower** (50 Wood + 100
  Stone, 2×2 — shoots arrows at enemies in range since P3),
  **Blacksmith** (150 Wood, 3×3 — visual only, research lands with the
  tech pass), **Lumber Camp** (100 Wood, 3×3 — drop-off for **Wood**),
  **Storage** (100 Wood, 3×3 — drop-off for **all** resource types),
  **Market** (150 Wood, 3×3 — resource exchange, see below) and **Dock**
  (150 Wood, 3×3 — shoreline only, see below). Drop-off routing is
  uniform: a returning villager deposits at the **nearest completed
  building that accepts the load** — the Town Center and Storage accept
  everything, Mining Camps take Stone/Gold, Lumber Camps take Wood.
  Placement ghost follows the cursor and previews the real tier art
  (green = valid, red = invalid). Costs are deducted when you enter
  placement mode and **refunded if you cancel** (Esc / right-click);
  click a valid spot to place — the nearest idle villager walks over
  and builds with a progress bar.
- **Market exchange**: select a completed Market and its info chip grows
  two button rows — **sell 100 Food / Wood / Stone → +40 Gold** each, or
  **buy 100 of any of them for 60 Gold** (fixed rates:
  `MARKET_TRADE_AMOUNT` / `MARKET_SELL_GOLD` / `MARKET_BUY_GOLD` in
  `main.gd`). Buttons grey out when the stock or gold is short; a
  successful trade flashes a gold glint over the Market.
- **Dock placement rule**: a Dock can only be built **at the shoreline**
  — at least one footprint cell must sit next to a water cell (the
  footprint itself stays on buildable land); anywhere else the ghost is
  red and confirming is refused with a message. The Dock is the shipyard:
  it trains the three hulls in the **Naval** section below.
- **HUD (glass rework)**: one frosted-glass HUD system, layout following the
  reference match screen. Top glass bar: player chip (emblem, name, progress
  bar = fraction of the 3 match objectives), gold age badge "I / Thời đại
  Hắc ám", five resource chips with real gather rates, population chip,
  match timer (MM:SS), and round buttons (chat/friends greyed out —
  multiplayer is P4; gear opens the "Khác" panel). Left glass quest panel
  ("Nhiệm vụ", collapsible) with 3 live objectives: build a Barracks, train
  2 more Villagers, destroy the enemy Town Center (real since P3).
  Bottom-left live minimap (terrain, resource dots, building squares, unit
  dots, camera viewport rectangle; click/drag to move the camera) with flag /
  crosshair / layers buttons beside it. Bottom-right four gold-accent glass
  buttons — Xây dựng, Huấn luyện, Công nghệ (the Feudal research card is
  live since P3), Khác (pause/resume, restart match, disabled multiplayer row) — each
  opening a glass sub-panel above them, one at a time. A slim glass chip
  bottom-center shows the current selection. Large panels use a real
  screen-texture blur shader over a translucent navy stylebox
  (`HUD.USE_BLUR` switches the blur off for a plain translucent fallback).

## Sprites & environment (asset pass, 2026-11-07)

- **Villager (new sheet, replaces the straw-hat one)**: Idle/Walk/Work/
  Harvest/Build/Carry/Die extracted from Tín's animation sheet. Direction
  mapping: down = the real front-facing cycles; up = back pose and
  left/right = side poses from the 8-dir sheet (the animation sheet only
  has front cycles, so side/up are static poses — least-awkward choice);
  while returning with a load the Carry cycle plays (flipped by travel
  direction); gathering Food plays Harvest, building plays Build.
- **Militia / Archer (new sheets)**: each source row is one direction
  (Militia: down/left/right/up; Archer: down/right/up/left), segmented by
  measured x-bands into idle/walk/attack/hurt/die and recomposed as
  [down, left, right, up] frame groups. The sheets are AI-drawn, not on an
  exact uniform grid — the extractor cuts by connected components and
  splits merged figures at alpha valleys. Die frames keep raw merged
  components (some frames hold an intact body pair) to avoid shredding
  lying bodies; re-check when combat lands in P3.
- **Building art (official tier charts, 2026-11-08)**: all six building
  families — Town Center, House, Barracks, Mining Camp, Watch Tower,
  Blacksmith — have all four tiers cut from Tín's 4-level charts with
  `tools/extract_buildings.py` (white flood-filled to alpha; the 4
  buildings are each chart's 4 largest components — plaques and arrows
  excluded) into `assets/buildings/<family>_t1.png` … `_t4.png`. Four
  more families — **Lumber Camp, Storage, Market, Dock** — were cut the
  same day by `tools/recut_new_buildings.py`, which generalises the
  matte to each chart's corner-sampled background colour (white
  for the Lumber Camp chart, black for the other three) and removes
  each chart's ground base — the grass plot under Lumber/Storage/
  Market and the blue water puddle under the Dock (pier deck and posts
  kept whole, reaching the sprite's bottom edge); the beige "Lv.x"
  label pills are excluded as separate components. **That first cut
  was redone clean the same day** (Tín rejected it at 4× zoom: dark
  JPEG-ringing halo on the black charts, plot-outline strokes and
  floating slabs around the bases, flood-eaten footings, a severed
  Lumber ridge neck). The tool now derives a strict silhouette
  (ground flood → repair of non-ground pixels at/above a smoothed
  structural base line → main-component-only discipline with a
  printed audit → per-column base-line trim on the grass families →
  stray-run pruning of plot-outline hooks) and mattes it with a
  choked signed-distance alpha (coverage reaches 1 only ~2.4 px
  inside the silhouette, so the contaminated shell contributes
  nothing; a bridge boost keeps thin connectors — ridge neck, crane
  ropes, lantern chains — intact). Every shipped sprite is a single
  component; the older six families keep their accepted v4 cut. The
  displayed tier follows the match age (`Main.age`, age I → t1; tiers
  3–4 wait for later ages). **Scale rule (Tín)**: art is drawn at
  **1.5× the footprint**, anchored at the footprint's bottom-centre and
  overflowing upward; collision, placement and the minimap keep using
  the footprint (AoE style), units keep their size. Draw order is
  y-sorted in z bands (a building sorts by its footprint's bottom row, a
  unit by its feet row), so a unit north of a building is covered by its
  roof and a unit south of it draws in front of its base. The name label
  sits at the top of the drawn art, clear of the roof. Under
  construction a building keeps the scaffold look and the sprite is
  revealed on completion; the placement ghost previews the scaled tier
  art tinted green/red. The earlier camp-compound extraction is kept as
  a spare, unwired asset (`assets/buildings/camp_compound.png`).
- **Art cleanup pass (2026-11-08)**: the buildings no longer carry the
  charts' baked-in ground. `tools/extract_buildings.py` now floods the
  flat grass/dirt slab from the sprite's bottom rows (colour-tested:
  plot grass, path dirt, pale rim) and drops the enclosed slab remnants,
  so every tier sprite ends at the building's own base — stone
  foundation, wooden base, the Mining Camp's rock base, the Watch
  Tower's footings — and sits directly on the map terrain (props like
  barrels, anvils, racks and mine rocks are kept; the compound keeps
  its interior courtyard, only its outer apron is removed). The
  character sheets are cleaned by `tools/defringe_characters.py`: the
  art's opaque light-grey contact shadow becomes a translucent black
  shadow, the nearly-opaque white-blended rim gets a coverage estimate
  against the interior colour (alpha scaled, colour restored), the
  semi-transparent ring is unblended from the white matte and bled from
  neighbouring opaque colours, and ≤4 px dust islands are dropped.
  Verified per tier on contact sheets over grass/navy; screenshots:
  `shots/empire_age_buildings.png` (base on bare terrain),
  `shots/empire_age_units_clean.png` (unit trio at 2.4× zoom).
- **Smooth-edge pass v3 (2026-11-08)**: the defringe above only patched
  the binary cuts — the edges still stepped and speckled in game. The
  characters are now RE-CUT from the original JPGs by
  `tools/recut_smooth.py` with proper alpha matting: per-pixel coverage
  from the whiteness ratio against the nearest interior colour,
  gaussian-smoothed over a 3 px support band, RGB unblended from white
  and bled from the interior, all resizes in premultiplied space. Frame
  geometry is unchanged (same detection, bboxes, cells, manifests).
  Two kinds of baked paint are removed with the page: the grey contact
  shadow (units now draw a soft code ellipse shadow in `unit.gd`) and
  the white swing-swoosh/dust effects in the Work-style frames (the
  game has its own VFX layer). Unit sprites render
  LINEAR_WITH_MIPMAPS with `mipmaps/generate=true`, so fractional
  scales stay smooth. Buildings got the lighter touch
  (`tools/derim_buildings.py`): rim unblend + bleed only, crisp
  outlines and NEAREST kept; opaque pale rim pixels dropped ~97%
  (e.g. tower_t4 448 -> 1). Edge-ring luminance on navy (defringe
  metric): archer 48.1 -> 33.5, militia 28.6 -> 20.5; the villager's
  total (37.1 -> 39.8) is dominated by its action rows, whose rings
  are the true bright colours of wheat/cream/axe edges — its idle row
  measures 27.1 vs 26.9 before, with the speckle itself gone.
  Screenshots: `shots/empire_age_units_v3.png`,
  `shots/empire_age_buildings_v3.png`, `shots/zoom_v3_*.png` (6× crops).
- **Smooth-edge pass v4 — buildings (2026-11-08)**: the derim touch
  above still left the buildings' binary alpha stepping at fractional
  scale, so all 25 building sprites are now RE-CUT from the tier
  charts by `tools/recut_buildings_smooth.py` with the same smooth
  alpha matting as the characters (whiteness-ratio coverage,
  gaussian feather over a 3 px support band, white unblend +
  interior bleed, premultiplied downscale). The slab removal and the
  detached props carry over unchanged (visible grass-coloured pixel
  counts are identical to the derimmed cuts — zero slab
  resurrection), and the matte adds a forbidden zone over the cut
  slab so the feather cannot reach the chart grass. Near-white
  regions are classified: page HOLES (touching the silhouette
  outside, or a large flat page-white expanse) stay transparent —
  this also removes page-white wedges the binary cut had kept opaque
  inside the Watch Tower t1 frame and the Mining Camp t4 crane —
  while enclosed pale paint (sunlit stone-top highlights) is firmed
  back to opaque (interior-loss guard: 0 px on all 25 sprites).
  `building.gd` renders the art LINEAR_WITH_MIPMAPS with
  `mipmaps/generate=true`, like the units; the placement ghost uses
  the same textures and stays legible under its tint
  (`shots/empire_age_ghost_v4.png`). Edge-ring luminance on navy
  improved on all 25 sprites (total 1201.9 -> 985.6, e.g.
  towncenter_t2 42.0 -> 30.7, miningcamp_t4 46.7 -> 37.1); the
  opaque pale-rim count rose on the light-grey stone families
  (miningcamp 80-122/sprite) because the true painted stone edge is
  itself pale — on navy contact sheets there is no white speckle.
  Screenshots: `shots/empire_age_buildings_v4.png`,
  `shots/zoom_v4_*.png` (6× crops). Tests stay 102/102.
- **Terrain tileset (2026-11-08)**: the flat code-drawn checker ground is
  replaced by Tín's terrain sheet, sliced by `tools/extract_tiles.py`
  (dark-gutter band detection) into `assets/tiles/` (96 PNGs incl.
  pre-rotated shore variants + `manifest.json`). `world.gd` picks tiles
  per cell by a deterministic hash: grass in 3 variants (78/14/6), rare
  dirt accents (~2%, away from the bases), water in 3 variants. The lake
  shore uses the **sand** shore set on the water cells (straight pieces
  by land direction, compass corners for two-sided land; open water
  underneath), which reads as a bright beach rim at 32 px; grass/stone
  shore sets and the plateau-edge + cliff tiles are sliced and stored
  but unused (no elevation in the current map). Gameplay is untouched:
  same lake shape, obstacle grid and A*; the minimap still derives its
  colours from the `water` dict. Screenshot: `shots/empire_age_terrain.png`
  (base and lake are ~36 cells apart, so it frames the lake shore).
- **Seamless ground (2026-11-08)**: the sheet's tiles are rounded
  "cushions" (bright bevel top/left, dark shadow ~12% along the
  bottom), which read as a quilted grid when placed. `tools/
  make_seamless_tiles.py` crops a uniform 12% rim off every used tile
  into `assets/tiles_seamless/` (shore tiles get the same fractional
  crop, so the sand/water boundary keeps its relative position) and
  matches each variant family's mean luminance so variant swaps do not
  draw rectangles. `world.gd` loads the seamless set and draws full
  tiles with checkerboard mirror flipping (flip X on odd columns, Y on
  odd rows, variants pre-built at load), so neighbours share edge
  columns by construction; shore tiles keep their orientation. The
  ground now reads as one continuous surface — no per-tile rims.
- **Painted HUD icons (2026-11-08)**: Tín's painted icon set is cut by
  `tools/extract_icons.py` (white flood-filled to alpha; every icon is
  one component, the 3 sheet badges by area, age 4 from its own image)
  into `assets/icons/` — the 5 resources, population, stopwatch, chat,
  friends, gear, build/train/tech, and `age_1.png` … `age_4.png` age
  badges. `hud.gd`'s `_pic()` shows the painted texture (LINEAR-filtered
  `TextureRect`) wherever one exists and falls back to the code-drawn
  `scripts/icons.gd` otherwise: resource + population chips, the match
  timer (stopwatch), the round chat/friends/gear buttons, the bottom
  Xây dựng / Huấn luyện / Công nghệ buttons, and the sub-panel cards
  (military cards share the painted crossed swords). The header age
  badge is now the painted shield texture for `Main.age` (the Khác
  button, minimap side buttons, quest chevrons and the player emblem
  keep their code-drawn icons). Screenshot: `shots/empire_age_icons.png`.
- **CraftPix environment**: trees are wood nodes in 5 artwork variants;
  top-down rocks are stone nodes; red-flower bushes are Food nodes; ruins
  and flat rocks are blocking decoration; deer/fox wander as decoration
  (hunting is P3); 5 soft cloud shadows drift across the map.

## VFX (effects pass, 2026-11-08)

`scripts/vfx.gd` is a shared effects layer owned by Main (z 95): plain
Sprite2Ds with runtime-generated soft textures (radial dot, ring, spark
streak, 4-point star), hand-animated in `_process`, hard-capped at 240
live effects with oldest-first recycling; every effect frees itself and
everything freezes while the match is paused. Two palettes are defined:
PLAYER (warm gold/red) and ENEMY (deep blue/silver, for P3).

- **Water (the lake is alive)**: shore foam blobs breathe along every
  shore cell (staggered round-robin phases, offset toward open water);
  surface shimmer glints spawn on in-view water cells; an expanding
  ripple ring appears at a random lake cell every ~2.5–4 s.
- **Wired to real events today**: gather ticks burst per resource
  (green leaf flecks on trees, grey sparks on stone, gold sparks + a
  glint on gold, pink sparkle on berry bushes); node depletion pops
  bigger (leaf burst + dust for trees, grey crumble puff for rocks);
  construction blows periodic dust puffs at the site base with hammer
  glints at the builder; building completion fires a flash + dust ring;
  training completion sparkles gold at the spawn point; deposits glint
  in the resource colour at the drop-off; a completed Blacksmith puffs
  chimney smoke every ~0.7 s with rare ember glints.
- **Combat-ready, not yet wired** (no combat until P3): `hit_spark`,
  `death_smoke` and `arrow_trail` take a palette and are exercised by
  the test suite (spawn + clean self-free). Screenshots:
  `shots/empire_age_vfx_water.png`, `shots/empire_age_vfx_base.png`.

## P3 — Combat, enemy faction + AI, Feudal age-up, Fog of War, win/lose (2026-11-08)

- **Combat core** (`scripts/stats.gd` is the single stats place): every
  unit and building has HP. Villager 50 HP / 3 atk, Militia 110 / 8,
  Archer 75 / 6 with ~5-tile range; buildings: Town Center 1200, Barracks
  650, House 350, camps/tower 500, Blacksmith 600, Market/Dock 550.
  Melee units path to their target and strike on cooldown; the Archer
  stops in range and looses a **visible arrow projectile** (homing
  sprite + team-coloured trail VFX) — damage lands on impact. Deaths
  play the Die frames, puff team-coloured death smoke and fade; hits
  spark in the victim's team palette. Damaged units/buildings show a
  small team-coloured HP bar (green = player, blue = enemy).
  **Counter table** (constants in `stats.gd`): Militia ×1.5 vs
  Archer-class, Archer ×1.25 vs Villager-class, and vs buildings
  Archers deal ×0.5 while Militia deal full ×1.0 (the siege role until
  the Battering Ram arrives). **Watch Towers shoot** for both teams
  (range 5.5 tiles, arrows from the tower top).
- **Targeting**: right-click an enemy unit/building with units
  selected = attack order (they swat hostiles met on the way when the
  target is a building). Military units **auto-engage** hostiles inside
  their sight range but are **leashed** to their guard post (spawn
  point / last move destination), so nobody chases across the map.
  Villagers never auto-engage — and honestly, they don't flee either:
  they just take the hits (fleeing is not implemented).
- **Enemy faction (Bé-designed)**: deep blue + silver. Produced offline
  by `tools/recolor_enemy.py`, which hue-rotates only red-dominant
  pixels to deep blue — skin, wood and stone stay natural (verified on
  a contact sheet). Sheets for Villager/Militia/Archer and tier art for
  Town Center / Barracks / House / Watch Tower live in `assets/enemy/`;
  the enemy TC flies a blue flag. Known cosmetic side effect: the
  enemy villager's reddish-brown hair and vest also shift blue — it
  reads clearly as "enemy" and no separate art exists yet.
- **Enemy AI** (`scripts/enemy_ai.gd`, one normal difficulty): keeps
  its **own resource ledger fed only by its villagers' real deposits**
  (no free trickle). Its villagers gather wood/food/gold/stone from the
  nodes around its base; its TC trains villagers up to 6; its Barracks
  alternates Militia/Archer up to a growing cap. It defends its base
  radius, and launches an **attack wave every ~3.5 minutes** (first at
  ~4 min): wave sizes grow 2, 3, 4, … and march on the player Town
  Center. When its **second wave launches, the AI ages up to Feudal**.
  Beatable by a player who raises towers + a few soldiers.
- **Feudal age-up**: research at the Town Center from the Công nghệ
  tab — **500 Food, 60 s**, requires **≥ 2 completed non-TC buildings**
  (the card states the requirement and greys out otherwise; progress
  shows in the card and in the TC's selection chip). On completion all
  player buildings swap to tier-2 art, the HUD badge swaps to the
  Feudal badge and the age label reads "Thời đại Feudal". Mechanical
  unlock today: **Watch Tower damage 10 → 14**. New Feudal units await
  Tín's Spearman/Cavalry sprites — nothing is faked meanwhile.
- **Fog of War** (`scripts/fog.gd`, tile grid, refreshed 2×/s):
  unexplored = solid black, explored-not-visible = dimmed terrain
  (enemy buildings stay as last-seen stills, but their HP/state is not
  updated — you must scout again), visible = full. Enemy units render
  only on visible tiles. The **minimap is fogged the same way** — the
  enemy base stays hidden until scouted.
- **Win / Lose**: destroy the enemy Town Center → glass **CHIẾN THẮNG**
  panel with the match time, quest objective 3 ticks, simulation
  pauses, "Chơi lại" restarts. Lose your own Town Center → **THẤT BẠI**
  likewise. Screenshots: `shots/empire_age_p3_combat_v1.png`,
  `shots/empire_age_p3_enemybase_v1.png`, `shots/empire_age_p3_fog_v1.png`,
  `shots/empire_age_p3_victory_v1.png`.

## New assets — Bé-drawn pass (2026-11-08)

Tín ran out of asset charts and authorised Bé to draw the remaining
pieces in the game's established style ("Bạn dựa theo style đó mà
vẽ"). Every piece was generated with the existing charts/sprites as
style references, passed a **style gate** (side-by-side contact sheet
at game scale against accepted families — see
`shots/empire_age_newart_contact_v1.png`), then extracted with the
same smooth-matte pipeline as Tín's charts (sources kept in `gen/`,
extraction in `tools/extract_new_assets.py` + `tools/build_unit_sheets.py`).

Style-gate outcome per piece:

- **Farm chart (4 tiers)** — PASS, first attempt. Farmhouse + well →
  windmill + silo manor; reads as a sibling of the Lumber Camp family.
- **Crop-field sheet (4 growth stages)** — PASS. Bare furrows →
  sprouts → green crop → golden ripe, one fenced plot.
- **Castle chart (4 tiers)** — PASS. Keep → multi-tower castle with
  gold trim; unmistakably the Age-III centrepiece.
- **Wall + Gate set** — PASS WITH NOTE. Wood + Stone materials ×
  (straight, corner, gate). The render is slightly flatter / more
  vector than the painted charts, but outline weight and palette
  match and at 1-tile game scale it reads in-family.
- **Spearman sheet** — PASS. Same chibi soldier family as the
  Militia: steel helmet, red plume, red tabard, round wooden shield,
  long spear. Full 4-direction idle/walk/attack/die rows.
- **Cavalry sheet** — PASS WITH CAVEATS. Style matches (rider +
  horse, red barding). The generated sheet's rows were tangled, so
  the left-facing row is a baked mirror of the right-facing row and
  the front idle is a front horse view; walk cycles alternate the
  cleanest poses per direction.
- **Battering Ram** — PASS as a single view. One strong side view
  (wood frame, hide roof, chained log, iron ram-head, red banner);
  ships as a **single-facing unit that flips horizontally** — the
  sanctioned fallback; up/down travel keeps the side view.

Gameplay wired in this pass:

- **Farm (100 Wood, 3×3)** + **field plots** (30 Wood, 1 tile, max 8
  per Farm, within 6 tiles of a completed Farm): a villager tends a
  plot — it grows one stage per 2 s work tick, ripe plots yield
  10 Food per harvest, regrow while harvests remain (3), then lie
  bare until re-tilled. Numbers in `Stats` (FIELD_*).
- **Walls & Gates** per tile: Wood wall 15 Wood / Stone wall 30
  Stone, gates 50 of the material. Walls block A* for both teams;
  **gates pass only the owner's units** (per-team A* grids in
  `world.gd`). Segment art (straight/corner) follows adjacency;
  segments carry HP and can be attacked/destroyed. Wall segments
  show no name label (a label per tile smeared along the wall).
- **Age III — Castle Age**: research at the TC after Feudal —
  800 Food + 200 Gold, 90 s, needs a completed Barracks + a
  Blacksmith or Market. All buildings swap to tier-3 art, HUD badge
  III, unlocks Castle + Ram. The enemy AI reaches Age III on its
  4th wave and fields Cavalry from Feudal on.
- **Castle (300 Wood + 200 Stone, 4×4, 1600 HP, Age III)**: fires
  arrows like a super-tower (range 6 tiles, 16 dmg).
- **New units at the single Barracks**: Spearman 50F+25W (Age I,
  pikes ×2 vs Cavalry; Archers ×1.25 vs Spearman), Cavalry 80F+40G
  (Feudal+, speed ×1.6 of a villager, ×1.5 vs Archer/Villager),
  Battering Ram 120W+40G (Age III, ×6 vs buildings, ×0.1 vs units,
  arrows ×0.25 vs it, 220 HP, very slow). Train cards show the
  units' own art; enemy variants come from `tools/recolor_enemy.py`.
- The Build page outgrew its panel and now scrolls (height capped);
  wall/gate/farm/castle/field cards added there.
- **Unit display ruler** (scale pass): the armoured infantry render
  at H ≈ 34.3 world px tall (±5%) — about the House art's door
  height; the whole ruler came down a uniform ×0.72 from the first
  pass (the cast still read house-sized at H ≈ 47.6) —
  Spearman 0.434, Cavalry ≈ 1.30*H tall / ~1.3 tiles long (0.36),
  Battering Ram ~2.2 tiles long / 1.30*H tall (0.36).
  Villager exception: the civilian carries its own smaller scale
  (0.46) — ≈0.95× the Militia's height and no wider than the
  Militia — so the villager reads as the smallest person on the
  field; see `Unit.DISPLAY_SCALES`.

## Biomes, layouts & water features (2026-11-08)

Three biomes × six layouts, chosen on the boot map panel (biome
cards + layout chips + "Vào trận"); the choice is a Main-level
setting (`Main.chosen_biome` / `Main.chosen_layout`) so P4 can pass
it from a lobby later. "Ngẫu nhiên" re-rolls per match.

**Biomes** (`scripts/biomes.gd` is the single definition table).
Asset provenance — nothing here is AI-generated:

| Piece | Source |
|---|---|
| Desert/snow ground tiles | **Derived**: pointwise colour grades of the seamless grassland set (`tools/make_biome_tiles.py` → `assets/tiles_desert/`, `assets/tiles_snow/`), same filenames + 12%-crop structure, so the seamless/mirror system is untouched |
| Palms, cacti, snow pines, snow bushes | **CraftPix pack art** already on disk, extracted + graded (`tools/extract_biome_env.py` → `assets/env/`) |
| Sandstone / snow-capped rocks | **Derived**: warm / snow grades of the existing rock sprites |
| Cliff band (waterfalls) | **Pack art**: the original tileset's `cliff_grass/sand/stone` variants (`assets/tiles/`), previously unused |
| Waterfall water column | **Derived**: slices of the active biome's own water tile, scrolled downward by `scripts/falls_layer.gd` (no new art) |

Desert = sand ground, oasis lake with a palm ring, cactus-fruit
bushes as the Food source, sandstone rocks, drifting sand glints.
Snow = snow ground, the lake FROZEN (ice tiles, still blocking),
snow pines, falling snow. Grassland unchanged.

**Stat modifiers** (Grassland is the ×1.00 identity baseline; yields
apply per trip at deposit time, growth divides the field stage
interval):

| Modifier | Desert | Snow |
|---|---|---|
| Movement | ×0.95 | ×0.90 |
| Cavalry (extra) | ×1.10 | ×0.85 |
| Wood yield | ×0.80 | ×1.30 |
| Food (bush) yield | ×1.00 | ×0.90 |
| Gold yield | ×1.30 | ×1.00 |
| Stone yield | ×1.20 | ×1.00 |
| Field growth | ×0.70 | ×0.60 |
| Field yield | ×0.80 | ×1.00 |

**Layouts** (`World.LAYOUTS`, combined with any biome): Đồng bằng
(original), Sông đôi (river + 2 land crossings + waterfall source),
Quần đảo (archipelago — bases on separate islands, the one layout
with no land path by design), Thung lũng (two 3-row decor bands,
one central valley with river + waterfall), Đấu trường (open
centre, rich gold/stone ring, symmetric ponds + corner mini-lakes),
Bờ biển (sea along the south edge, inland bases, lake → river →
sea with 2 bridges).

**Water features** are shared gen primitives (`_carve_blob`,
`_carve_river_h/v`, `_place_waterfall_h/v`, sea fill) registered in
`World.features` (ponds/lake/river/sea/waterfalls) — minimum
distribution per layout: Đồng bằng = lake + 2 ponds + waterfall ·
Sông đôi = river + waterfall + 2 ponds · Quần đảo = sea + island
pond · Thung lũng = river + waterfall + pond · Đấu trường = 2
ponds + 2 corner mini-lakes · Bờ biển = sea + river + lake.
Waterfalls block movement like water; VFX plays foam ripples +
mist at each fall's base (`World.falls_foam_points()`).

**Minimap privacy rule**: the minimap NEVER renders other teams —
no enemy units, no enemy buildings, not even scouted/last-seen
ones (the main view's explored silhouettes are unaffected). It
shows explored terrain, neutral resources and the player's own
team only (`Minimap.marker_color_at` mirrors the rule for tests).

## Naval (ships)

Trained at a completed **Dock** (select it — the selection chip gains a
shipyard row with one button per hull). Ships are team-owned, live
**only on water cells** (their own A* grid is the inverse of the land
grid, so a hull can never enter land) and do not count toward the land
population cap. Art is Bé-drawn in the house family (single side view +
horizontal flip, like the Battering Ram); enemy hulls come from the
faction recolor (red accents → deep blue).

| Ship | Cost | Role |
|---|---|---|
| Fishing Boat | 75 Wood | Gathers Food at fish spots, hauls 20/trip back to a Dock |
| Transport | 125 Wood | Carries up to 5 land units between shores |
| War Ship | 150 Wood + 50 Gold | Floating archer: 6-damage arrows, 5-tile range |

- **Fish spots**: every sizable water body (lake, sea, wide river)
  holds 2–4 fish spots (1 on a small pond), marked by subtle ripple
  rings and an occasional leaping fish. A spot holds 500 Food. Order a
  Fishing Boat onto a spot (select the boat, right-click the spot) and
  it works the spot and deposits at its Dock in 20-Food trips, like a
  villager on water, until the spot runs dry; then it moves to the
  next spot.
- **Transport flow**: select your units, right-click the Transport to
  board (the ship must be at a shore cell and the units at the water's
  edge — units too far away walk to the shore beside it first). Select
  the loaded ship and right-click a shore to sail there; right-click a
  land cell by the shore to put everyone ashore. **Cargo is hidden and
  invulnerable while aboard — but if the ship sinks, everyone aboard
  dies with it.**
- **War Ships** auto-engage enemy ships and shore-side units inside
  their sight, and can be ordered onto land targets near the shore;
  their arrows fly through the normal projectile system with faction
  trail colours.
- **Frozen water (Snow biome)**: water is ice — **not navigable**.
  Docks can still be built on the shore, but ships cannot launch and
  no water path exists, so there is no fishing and no naval combat on
  Snow maps.
- **Enemy navy**: on the water-heavy layouts (Quần đảo / Bờ biển) the
  enemy base includes a Dock, and from the third wave on the AI keeps
  up to two War Ships that patrol toward the player's shore. On land
  layouts the AI skips the navy entirely.
- Fog and the minimap treat ships like units: enemy ships only render
  on currently visible tiles, and the minimap shows **own ships only**
  (the standing privacy rule).

## Wild beasts

Team-neutral hostiles that extend the wandering-animal system. They
attack **both** teams' units, are leashed to a territory anchor away
from the bases (a hunt is abandoned after ~6 tiles of chase, and any
hunt that drags a beast toward a base clearing is dropped at once —
beasts never enter base clearings). Any unit, villagers included, can
be **ordered** to attack a beast (right-click it); villagers never
auto-engage. A dead beast leaves a **meat node** on its cell that
villagers gather as Food through the normal node/deposit loop.

| Beast | HP / ATK | Behaviour | Carcass |
|---|---|---|---|
| Wolf | 40 / 6 | Packs of 3–4 at dens; aggros anything within ~2.5 tiles; fast | 75 Food |
| Bear | 180 / 14 | Solitary, near forests; aggros within ~1.5 tiles; slow bruiser | 150 Food |
| Boar | 80 / 8 | Neutral grazer — never aggros; fights back only when damaged | 100 Food |

Balance guard: a lone villager **loses** to a wolf; two Militia kill
a bear but expect to lose one of them. Distribution per biome:

| Biome | Beasts |
|---|---|
| Grassland | Wolf packs, bears, boars |
| Snow | Wolves (white-furred), bears |
| Desert | Wolves (sand-furred), boars |

## Sky — real clouds (2026-11-08)

The cloud sprites are Tín's own CraftPix cloud pack
(`assets-src/craftpix/clouds`), extracted to `assets/env/cloud_{w,g,s}*.png`
(white / grey / black-shadow variants of 4 shapes). Each cloud drifts
on a dedicated sky layer — the topmost world layer, below the HUD —
paired with its soft black shadow offset (+120, +150) on the ground,
at one shared wind (9 px/s, wrapping at the map edges). Counts and
sizes are named constants per biome (`World.CLOUD_COUNT` /
`CLOUD_SCALE`): Grassland 8, Desert 4 and smaller, Snow 10 in grey.
Clouds ignore Fog of War (they are sky), and the whole layer hides
while a full-screen modal is open (`World.set_sky_active`, wired to
the boot map-choice panel in Main).

## Ground rendering — baked, not tiled (2026-11-08)

The ground is no longer drawn per tile (the old variant tiles swapped
whole-cell colours and quilted the map into light/dark rectangles).
At `generate()` the world bakes the entire 64×64 ground into ONE
2048×2048 texture (`World.bake_ground`): land is composed per cell
from **all** native land variants (grass_0/1/2 of the biome set),
each **tone-matched** to the base variant's mean colour (per-channel
DC correction, texture untouched), in all **eight orientations**,
plus 50% pair-blend variants so the meadow art's flower flecks never
settle into a repeat lattice — and there is **no blur pass** on land
(an earlier downscale/upscale "soft pass" smeared all pixel detail;
Tín: "nền cỏ cứ thấy lem lem"). Water is **one flat tone** per biome
(`World.WATER_TONES`: a deep, saturated blue — glacier blue on
snow — so water always stands out from land; measured on the bake,
the luminance gap vs adjacent land is 53–60% and snow's saturation
ratio is ~17×) with only large soft blotches (radius ≥ 3 tiles,
alpha ≤ 0.17) — its per-tile variant alternation read as a blue
checkerboard, so no tile pattern is baked into water at all.
Land and water are composited through a **signed-distance-field
water mask** (`blend_rect_mask`): alpha follows each pixel's true
distance to the shoreline (saturating 0.62 tiles inside the water,
0.38 onto the land), and the shore rim + foam line are painted from
that **same mask** (rim = the mask's mid band on the land side,
a dark wet-contour band ~0.25 tile wide — the water tone darkened —
just inside the water edge, foam = a thin band inside that), so bank, foam and
water share one geometry and can never sit offset from each other.
Accents are soft-alpha **decal sprites** at continuous random
positions: tuft patches, dirt as irregular radial-falloff blobs
(0.7–1.6 tiles per axis, non-uniform scale), and flowers as tiny
blossom crops (cut from the flower tile at real blossom pixels)
sprinkled in organic clumps of 3–7 — no grid, rows or crosses.
Clouds are hard-capped at 320 world px wide with the sky layer at
0.9 alpha. The minimap samples the baked image down, so its
terrain matches.
Rendering only — every walk/water grid and gameplay datum is
unchanged. Pond/lake outlines are organic: the generator carves
them as unions of 2–4 overlapping jittered ellipses
(`World._carve_organic`, ragged outer band) and the distance-field
mask rounds every corner by ~1 tile of feather, so water bodies
read as natural blobs — no straight edge longer than ~1 tile, no
square corners — while the visible water never overhangs walkable
land by more than ~0.4 tile and rim/foam stay glued to the shore.

**Dry-base placement guard** (same pass): because the mask feathers
water ~0.38 tile onto land, a scatter placement on a shore cell can
stand in *painted* water even on a dry grid cell — Tín caught oasis
palms growing out of the lake. The desert palm ring now plants on
the **second** land ring from the water, and after the bake every
node/decor is validated against the baked texture itself
(`World.baked_is_water_toned` / `placement_base_dry`): offenders are
nudged to the nearest dry land cell under the usual placement
guards, or dropped. Tests z1–z6 assert zero water-toned bases
across biomes × layouts × seeds.
`shots/empire_age_grass_crisp_v3.png` (crisp grass),
`shots/empire_age_oasis_trees_fix_v2.png` (palms on dry sand).

### Grass smear fix — measured diagnosis (13e, 2026-11-09)

Tín: "nền cỏ nó vẫn lem lem" — diagnosed with numbers, not vibes
(probe: `tests/probe_grass.tscn` dumps the bake + land mask +
renders; sharpness = per-tile high-frequency "motif" energy,
variance of the σ≈1.2px high-pass band). Three stages measured:
the source→32px downscale was **innocent** (Godot's tile output ≥
a LANCZOS reference) and the renderer was **innocent** (renders
measured ≥ the bake at z1.0 and z0.55). The smear was in the
**bake's tile pool**: (1) half the pool was **50% pair blends** —
averaging two unrelated flower-fleck motifs ghosts both and cuts
motif energy to 25–50% of the stronger parent; (2) the base
variant **grass_0 is intrinsically a near-flat wash** (motif
energy 0.00012 vs grass_1's 0.0043, ~35× weaker) yet filled a
third of all tiles and half of every blend. Result: mean motif
energy 0.00136/tile, and a quarter of the map sat at ≤0.00048 —
the flat watercolour patches Tín saw.

Fix (rendering only; gen/layout/grids untouched): tiles now
compose at **48px per cell** (bake 3072²; sources squeezed ~2.4×
instead of ~3.6×); **grass_0 only sets the target mean** (map
colour unchanged — before/after mean RGB identical) and never
appears as pixels; pair blends are **frequency-split**
(`World._split_blend`: low frequencies averaged, high frequencies
taken from one parent at full contrast — no ghosting). The baked
texture now carries **mipmaps** and the World samples it
`LINEAR_WITH_MIPMAPS`. Measured after: mean motif energy
**0.00274 (×2.0)**, median ×2.6, p25 **×3.9**, floor (p10)
**×15.7** — the flat tiles are gone.
`shots/empire_age_grass_fix_v1.png` (same patch before/after).

Perf note: a first cut at 4096² (64px/cell) measured the same
motif numbers but pushed MP client startup past the lockstep
smoke's timing margin (the phase-2 corruption hook keys on the
server tick while a slower client is still building) — 3072²
keeps the full quality gain at ~56% of the pixel cost. The bake
was also profiled and trimmed (shore bands pre-composited into
one overlay and clipped to the water bounding box, sea composed
at quarter res, SDF mask sampled at 256², rim stamps built at
48px): SP suite 356/356, `mp_smoke.sh` and `ranked_smoke.sh`
ALL PASS, water-contrast probe still PASS on all biomes
(luminance gap 48–53%).

## P4 — Multiplayer foundation: Go relay + lockstep (2026-11-08)

Real online matches for **2–4 players only** (Tín's hard rule: 1v1,
2v2, FFA 3–4 — no 6/8-player modes). Architecture this pass is a
**deterministic lockstep over a dumb relay**:

- `../server/` — a dependency-free Go WebSocket relay (rooms with
  5-char codes, guest names, ready flags, host start, team tables
  [0,1] / [0,1,2] / [0,0,1,1], a 10 ticks/s clock, commands relayed
  to everyone stamped exec = receipt tick + 2, checksum comparison
  with DESYNC broadcast, disconnect handling). It holds **no game
  state** — see `../server/README.md`.
- `scripts/net.gd` (autoload `Net`) — the client wrapper + lobby
  protocol + an automated smoke-test driver (`--mp-auto`,
  `--mp-shot-lobby`, `--mp-scout-shot`).
- `scripts/lobby.gd` — glass lobby reached from the start panel's
  new **"Chơi mạng"** button: name/address fields, Tạo phòng (host
  config = the start panel's biome/layout picks, "random" resolved
  concretely), Vào phòng by code, player rows with slot/team/ready,
  Ready toggle, host Start (≥2 players, all ready). No chat yet.
- Match integration in `main.gd`: every entity carries `net_id` +
  `owner_id` (player slot; == team in SP). Per-slot wallets, ages,
  rally points and pop counts; up to 4 bases from
  `world.base_centres` (2-player matches keep the exact SP
  placement; 3/4-player matches use the mirrored corners, Quần đảo
  grows an island per extra base). Fog + minimap render for the
  **local player's team** (`fog.local_team`, `view_team()`); the
  enemy AI never runs in MP. Local orders are NOT applied at click
  time — they ride the relay and are applied by every client at the
  stamped tick via the same order-entry logic SP uses
  (`apply_order_for` / `apply_ship_order_for`); build / field /
  train / train-ship / age-up / market / rally are commands too.
  The sim only advances in fixed steps handed out by server ticks
  (3 frames of 1/30 s per tick, tree frozen between ticks), the
  match seed seeds world gen + beast wander, and a state checksum
  (entities by net_id, wallets, ages) is reported every 30 ticks.
- Win/lose: a player whose Town Center falls is **eliminated**
  (defeat panel; the match continues for the rest); the last team
  standing wins. A player who disconnects mid-match has their
  entities **frozen inert** and counts as eliminated.
- Verification: `tests/mp_smoke.sh` runs the server + two headless
  clients — same world hash, the slot-0 move order applied on both
  clients at the same tick, checksums agreeing at ticks 30/60/90
  (and changing as the sim advances), scripted TC kill at tick 120
  → slot 1 eliminated, A victory / B defeat, zero DESYNC. The full
  SP suite is 324/324 (318 + the 6 dry-base tests of the oasis-palm
  fix); SP behaviour is unchanged (MP code paths are inert unless
  a match boots through the lobby). Lobby screenshot:
  `shots/empire_age_lobby_v3.png`. In-match frame from client B:
  `shots/empire_age_mp_match_v3.png` (a real MP match — B's own
  base under B's fog, B's scout group selected, its explored trail
  on the minimap). A frame with the enemy base fully scouted could
  not be rendered in this sandbox: a windowed client under Xvfb
  software rendering steps ~5× slower than the tick stream and its
  sim drifts from the headless host once units move, so scripted
  scouts die en route; the scout → fog-reveal → capture flow itself
  is verified end-to-end with headless clients (the driver's
  "scout shot saved" fired on five different world seeds).
- Honest limits: dumb relay (not authoritative — the Master doc's
  authoritative simulation is a later stage), guest names (no
  accounts), desync = detected + warned with no resync yet, no
  in-match chat, MP clients should run `--fixed-fps 30`.

## P4 stage 2 — Chat + accounts + resync (2026-11-09)

- **Chat** (pure relay, never part of lockstep state): the lobby
  room view gains a chat box under the player list (scope `lobby`);
  in-match, the top-bar chat button (locked since the HUD pass)
  unlocks and opens a glass chat panel with scrollable history,
  input, and a **Tất cả / Đồng minh** scope toggle (team scope
  hidden in 1v1/FFA — no allies). Enter sends; incoming messages
  also flash as a HUD toast when the panel is closed. Server-side:
  200-rune truncation, 5 msgs / 2 s rate limit, team scope routed
  by the server's own team table.
- **Accounts** (optional — guests unchanged): the lobby menu gains
  a login/register block; when logged in, the name field locks to
  the account name and player rows show a **Tài khoản / Khách**
  column. Passwords: PBKDF2-HMAC-SHA256, 120k iterations (stdlib
  implementation server-side); session tokens are 32 random bytes,
  stored hashed, 30-day expiry; token re-login supported. The host
  reports the match result at match end and the server banks W/L
  per account (trust model + the file-backed `Store` interface —
  PostgreSQL drops in later — are documented in
  `../server/README.md`). A **Bảng xếp hạng** panel in the lobby
  shows the top 20 (wins, then winrate).
- **Resync**: on checksum divergence the server picks the majority
  hash (host's hash wins ties), one holder serves a full-state
  snapshot (`"v":1` — entities by net_id with task essentials,
  buildings + queues, ships + cargo, fields, node/fish amounts,
  beast state + wander RNG as a string, wallets/ages/rally/
  elimination) taken at a tick boundary; diverged clients freeze
  behind a "Đang đồng bộ lại…" overlay with input locked, rebuild
  at that boundary, re-apply post-boundary commands from their
  local log, and resume. Mid-task units are re-ordered onto their
  task target; mid-path units restart their path from the snapshot
  position; projectiles/animals/VFX/fog are not serialized.
  `tests/mp_smoke.sh` phase 2 forces a +1px divergence at tick 60
  (`--mp-corrupt`) and asserts: DESYNC at 60 → snapshot served →
  rebuild → checksums agree again at tick 90 → the scripted
  elimination completes with exactly one desync total.
- New driver hooks: `--mp-account=user:pass` (register, falling
  back to login), `--mp-shot-account=<path>` (logged-in lobby +
  leaderboard capture), `--mp-chat-shot=<path>` / `--mp-chat-peer`
  (scripted in-match chat capture), `--mp-corrupt`.
  `tests/capture_mp2.sh` plays a real account-vs-account match to
  bank W/L, restarts the relay on the same store (persistence),
  then captures `shots/empire_age_account_lobby_v1.png`
  (leaderboard open: TinPro 1W/100%, MinhAnh 1L) and
  `shots/empire_age_chat_v1.png` (chat panel with both scripted
  messages + toast).
- Verification: SP suite 346/346 (MP paths inert in SP), Go tests
  pass (chat/accounts/resync suites included), `mp_smoke.sh`
  phase 1 + phase 2 ALL PASS.
- Honest limits: results are host-reported (a modified host could
  lie — closing that needs the authoritative stage); the account
  store is file-backed JSON for now; a windowed client under Xvfb
  still steps slower than headless (environment limit, unchanged).

## P4 stage 3 — Ranked matchmaking + dedicated referee (2026-11-09)

The final Master-document stage: **ghép cặp + xếp hạng** (queue,
MMR, authoritative results). Server-side design (queue windows,
Elo, referee orchestration, token auth) lives in
`../server/README.md`; the client half:

- **Lobby**: the menu gains a **Đấu xếp hạng** button (disabled
  with an explanatory hint for guests — ranked requires login) and
  the account line now shows **MMR**. Pressing it joins the 1v1
  queue; a queue view shows "Đang tìm đối thủ…" with an elapsed
  timer and **Hủy tìm trận**. On `match_found` the lobby drops
  into the ranked room view — ready/start are hidden there because
  the server starts ranked matches itself (referee attached + both
  players in → 3-2-1 countdown delivered as chat system messages).
- **Leaderboard**: the panel gains a mode toggle — **Xếp hạng
  (MMR)** (ranked board: MMR desc, W/L shown) vs **Thắng/Thua**
  (the original stage-2 board).
- **Referee mode** (`--referee`, spawned by the server per ranked
  match): the same project runs headless, authenticates to its
  room with the one-time token, and on `match_start` boots Main
  with `mp_referee` set — the full sim runs with **no local
  player** (it views through slot 0; fog/HUD are inert headless),
  commands are applied through the normal `_mp_apply_*` validators
  (illegal ones are dropped + counted in its log), checksums are
  reported every 30 ticks like any participant, snapshot requests
  are served from its state (it is the ranked room's permanent
  resync source), and at match end **the referee** reports
  `{winner_team, reason}` — `_mp_check_winner` branches on
  `referee_mode`, and ranked clients never report (the server
  ignores player-sent ranked results anyway). A ranked disconnect
  is *not* an instant elimination in the referee: the slot freezes
  and gets a **30 s grace** (300 ticks); expiry eliminates it with
  reason `disconnect`. The referee exits ~10 s after reporting.
- **Ranked clients** play exactly like custom-room clients
  (lockstep, local sim); only two differences: no host reporting,
  and a post-snapshot winner re-evaluation so a client rebuilt
  from the referee into an already-finished match still gets its
  victory/defeat panel.
- New driver hooks: `--mp-ranked` (authed queue → match → scripted
  move; pair with `--mp-nokill` — the kill hook lives in the
  referee via `--referee-test-kill=<tick>` /
  `--referee-test-kill-slot=<n>`), `--mp-lbcheck` (dump the ranked
  board as MPLOG lines), `--mp-shot-ranked=<path>` (queue-view
  capture; harness `tests/capture_ranked.sh` →
  `shots/empire_age_ranked_queue_v1.png`).
- Verification: SP suite **346/346**; Go tests incl. the new
  ranked suite pass; `tests/mp_smoke.sh` ALL PASS (unchanged);
  `tests/ranked_smoke.sh` **ALL PASS** — two fresh accounts
  (MMR 1000) queue → pair → real referee process spawns/joins →
  move applies on A, B *and* the referee → referee-only TC kill at
  tick 120 diverges both clients → both resync from the referee →
  tick-150 checksums agree three ways (A = B = referee) → referee
  reports → exact Elo banked (**1016 / 984**) → leaderboard probe
  confirms the ranked board order.
- Honest limits: ranked is **1v1 only** this stage; the referee is
  **one process per match** (friends-scale, not a pooled fleet);
  ranked clients still simulate locally — the referee is canonical
  + resync source + sole reporter, not a thin-client streamer;
  the account store is still file-backed JSON (PostgreSQL remains
  one more `Store` implementation away).

## P4 stage 4 — Seasonal rank ladder, Liên Quân-style (2026-11-09)

The visible ladder Tín asked for ("làm hệ thống rank như liên quân ấy
leo rank theo mùa"), renamed per his follow-up order to fit the
medieval empire theme ("Đổi tên rank cho phù hợp game") — Liên Quân
supplies only the structure. MMR stays the hidden matchmaking number;
the ladder is what players see, and both evolve from the same
referee-reported results, independently. Server side is documented in
`server/README.md` ("Seasonal rank ladder"); the client surface:

- **Tiers low→high**: Tân Binh (leather brown) → Chiến Binh (iron
  grey) → Kỵ Sĩ (steel silver-blue) → Nam Tước (bronze-green) → Bá
  Tước (purple) → Hầu Tước (deep crimson) → Công Tước (gold, no
  divisions — pure star count) → Hoàng Đế (radiant red-gold, a
  computed status: top 50 Công Tước accounts by stars, then MMR).
  Tân Binh→Bá Tước: divisions III→II→I at 3 stars each; Hầu Tước:
  divisions at 5 stars each. Win +1 star, win streak ≥3 earns +1
  bonus star (once per match); a win at full stars promotes and
  lands at 1 star in the new division; loss −1 star, demotion lands
  at cap−1; Tân Binh III at 0 stars is the hard floor. New accounts
  start Tân Binh III · 0 sao. No protection cards in v1.
- **Seasons**: 90 days by default (server `-season-days`); on any
  account touch the season reset applies first — final tier maps
  down (Công Tước/Hoàng Đế→Bá Tước III, Hầu Tước→Nam Tước II, Bá
  Tước→Nam Tước III, Nam Tước→Kỵ Sĩ II, Kỵ Sĩ→Kỵ Sĩ III, Chiến
  Binh→Chiến Binh III, Tân Binh→Tân Binh III), stars 0, MMR halves
  toward 1000, and the finished season is archived with its peak
  rank tracked on every promotion.
- **`scripts/rank_badge.gd`** (`RankBadge`): a drawn shield tinted
  per tier with a row of star polygons (filled gold / dim empty) —
  no textures, no emoji; mini mode (shield only) for leaderboard
  rows, a crown spark for Hoàng Đế.
- **Lobby**: the account block shows badge + "Kỵ Sĩ II · 2 sao" +
  "Đỉnh mùa: …" + "Mùa trước (Mùa N): …"; the queue panel repeats
  badge + rank; the ranked leaderboard is headed by the viewer's own
  rank row and its rows are mini-badge + name + tier-coloured rank
  text + MMR/W/L, sorted by (tier, division, stars, MMR) — the
  toggle is now simply "Xếp hạng".
- **End panel**: after a ranked match the server pushes a personal
  `rank_result` (before/after rank, star delta, bonus/promotion/
  demotion flags, MMR before/after); the panel shows "+1 sao" /
  "+2 sao (chuỗi thắng)" / "-1 sao" / "Không đổi sao", the new rank,
  the MMR line, and a banner — "Lên hạng …!" in gold, "Xuống hạng …"
  in red. Guests still cannot queue ranked.
- Verification: Go tests cover the whole ladder + season tables;
  `tests/ranked_smoke.sh` (33 assertions) additionally asserts the
  queue payload carries "Tân Binh III · 0 sao", the server banks
  +1 star / floored 0, both clients receive `rank_result`, the
  winner's end panel carries the rank lines, and the board shows the
  ladder text. `tests/capture_ranklb.sh` seeds five accounts and
  captures `shots/empire_age_rank_lobby_v1.png` — the ranked board
  headed by the viewer's Kỵ Sĩ II badge over Hoàng Đế / Bá Tước /
  Kỵ Sĩ / Chiến Binh / Tân Binh rows. SP suite stays 356/356.

## Age IV — Imperial (gameplay completion pass, 2026-11-09)

The fourth age is researched at the Town Center from the Công nghệ
tab, exactly like II and III:

- **Cost / time:** 1000 Food + 350 Gold, 120 s (`Stats.AGE4_UP_COST`
  / `Stats.AGE4_UP_TIME`).
- **Requirements:** Age III reached + a completed **Castle** +
  (**Blacksmith** or **Market** — the same either/or pattern as
  Age III).
- **On completion:** every building of that side swaps to its
  **tier-4 art** (`set_team_age` already drives tiers 1–4; the t4
  files existed unused since the art passes). Families with a t4
  file: Town Center, House, Barracks, Blacksmith, Castle, Dock,
  Farm, Lumber Camp, Mining Camp, Market, Storage, Tower — i.e.
  **every** wired family has one; Walls keep their wood/stone
  material art (they have no age tiers) and Farm fields keep their
  growth-stage art.
- **Combat steps:** Watch Tower damage 14 → **18** (`Stats.TOWER_ATK`
  now carries all four ages), Castle damage 16 → **20**
  (`Stats.castle_atk(age)`), Battering Ram vs buildings ×6 → **×7**
  (`Stats.RAM_VS_BUILDING_IMPERIAL`, applied inside `Stats.damage`
  via the attacker's age).
- **Imperial logistics:** training queues at Town Center, Barracks
  and Dock run 20% faster (`Stats.IMPERIAL_TRAIN_TIME_MULT = 0.8`,
  applied through `Main.train_time_mult(owner)` in `Building`).
- **Enemy AI:** wave 6 *arms* Imperial, but unlike II/III (free, on
  the wave schedule) the AI must **buy** it from its own resource
  ledger at the player's price and research it over the full 120 s;
  if it cannot afford it when wave 6 launches, it buys the moment
  its economy can. A side whose TC has fallen never starts or
  finishes the research.
- Multiplayer: age state is per-slot as before (`age_up` command
  with `to: 4`); the tier-4 swap, damage steps and logistics
  multiplier all key off the per-owner age, so lockstep stays
  deterministic.

## Villager fleeing (gameplay completion pass, 2026-11-09)

- A **villager** that takes damage from a hostile (enemy unit,
  tower/castle arrow, war ship or wild beast) and is **not** under
  a fresh explicit attack order drops its task and **flees**
  (`Unit` states `"flee"` / `"garrison"`): it runs at ×1.15 speed
  (`Stats.FLEE_SPEED_MULT`) toward its nearest drop-off building —
  its own Town Center first, else a Storage, else any drop-off for
  what it carries. (Feedback is the ordinary hit spark that already
  fires on the damaging hit — the codebase has no exclamation
  callout system, and no new UI was invented for this.)
- On arrival it **garrisons**: it despawns into the building
  (invisible, untargetable — towers, units and beasts all skip it),
  and whatever it was carrying is **deposited** on entry, as at any
  drop-off. It stays inside up to 5 s (`Stats.FLEE_GARRISON_MAX`),
  leaving early once no hostile is within 4 tiles of the building
  (after a 0.8 s minimum stay). It then pops out at the building's
  edge and **resumes its interrupted task** if the target is still
  valid (node/building site/field), otherwise it looks for work
  from the haven, exactly like a finished drop-off trip.
- With no drop-off left at all, the villager bolts ~4 tiles directly
  away from its attacker and then re-evaluates.
- **Exceptions:** a villager under an explicit attack order does not
  flee for 10 s (`Stats.ATTACK_ORDER_NO_FLEE`); military units and
  ships never flee. If the haven is destroyed mid-garrison, the
  villager pops out onto the rubble.
- Determinism: fleeing triggers only from damage events inside the
  simulation and uses sim-time deltas like the rest of the sim — no
  wall-clock or unseeded randomness — so multiplayer lockstep is
  unaffected.

## Win conditions — annihilation (gameplay completion pass, 2026-11-09)

Destroying a Town Center no longer ends the match by itself. A
side is **eliminated** when **both** hold:

- its Town Center is destroyed, **and**
- it has **no living villagers** OR **no completed train-capable
  building** (Barracks or Dock — houses, farms etc. don't count).

So a TC-less side that still has villagers *and* a Barracks/Dock
**fights on**: it keeps its army, its Barracks keeps producing, and
the player gets a persistent red HUD warning ("Town Center đã mất —
còn Dân và công trình huấn luyện là còn chiến đấu được!") plus a
one-time message. The moment either leg gives out (last villager
dies, or the last trainer falls), elimination lands: enemy
eliminated → **CHIẾN THẮNG** with the note "Thắng bằng quét sạch
(annihilation)" on the end panel; player eliminated → **THẤT BẠI**.
Quest 3 now reads **"Quét sạch đối thủ"** and ticks on elimination,
not on the TC kill. The enemy AI follows the same rules: with its
TC down its waves stop, it starts no new age-ups and trains no new
villagers, but its Barracks keeps turning out military and its
standing forces keep fighting. Multiplayer applies the identical
rule per slot (a slot is eliminated only when its annihilation
condition holds; the scripted smoke match is unaffected — the
scripted TC kill target has villagers but no Barracks, so it is
still eliminated on the spot).

## Team colours — 4 slots = 4 colours, one sprite set (2026-11-09)

Tín's rule: *"Trận 4 đội thì phải 4 màu nha nhân vật giống nhau hết
nhưng phải chia màu"* — every faction renders from the **same base
sprites**; identity is a per-**slot** team colour dyed onto the
faction-bearing parts only (cloth/tunic, shield faces, capes,
plumes, building flags/banners/red roofs). Skin, hair, armour
metal, weapons and wood/stone are pixel-identical across colours.

| Slot | Colour | Asset set |
|---|---|---|
| 0 | Đỏ (Roman red) | `assets/` (canonical art) |
| 1 | Xanh dương (deep blue) | `assets/enemy/` (the P3 set) |
| 2 | Xanh lá (forest green) | `assets/team2/` |
| 3 | Vàng (amber yellow) | `assets/team3/` |

Colour keys off the **player slot** (`owner_id`), never the faction
team: a 4-player match shows 4 colours even in 2v2, where slots 0+1
share a team. SP is unchanged — the player is slot 0 (red), the AI
slot 1 (blue). Each set mirrors the layout: 6 unit sheets + frames,
the 4 faction-coloured building stems (towncenter / barracks /
house / tower × 4 tiers), 3 ship hulls, and `king.png` (cape +
shield recoloured; asset only — the King is not in gameplay yet).

- **Generation**: `tools/recolor_teams.py` generalises the old
  `recolor_enemy.py` into one canonical palette map (only the red
  hue band rotates; slot 1 uses the original constants). Regenerating
  reproduced 18/25 blue files byte-identically; the 7 that changed
  (spearman + a few house/barracks/tower tiers) differ only in
  edge-adjacent pixels — their red sources had been defringed/recut
  after the blue set was last generated, so the regenerated blue is
  now *more* consistent with the current red art.
- **Runtime**: `scripts/team_colors.gd` (`TeamColors`) is the
  single table — UI colours, minimap shades, VFX palette keys
  (`slot0`–`slot3` in vfx.gd) and asset paths. Unit sheets, building
  tier art, ship hulls, HP bars (units/buildings/ships), selection
  rings, building name labels, lobby player names (plus a "Màu …"
  tag), the rally flag, arrow trails and hit/death VFX all key off
  the owner's slot colour. The minimap paints own-team entities in
  their owners' slot colours; the **privacy law is unchanged** —
  other teams are never drawn.
- **Sim safety**: colours are presentation-only. The lockstep
  checksum covers net_id/position/HP/completion/wallets/ages only,
  and snapshots carry no art — verified by the unchanged
  mp_smoke/ranked_smoke suites.
- **Tests**: SP section (ab) — sheet routing by slot; pixel surveys
  of the militia sheet and the King for slots 1/2/3 (every red-band
  pixel lands in the slot's hue family, every other opaque pixel —
  skin included — is pixel-identical to slot 0); live slot-2/3
  spawns wear the right sheets; a slot-2 House uses the green tier
  art and paints the slot-2 minimap colour. Capture:
  `tests/capture_4colors.tscn` →
  `shots/empire_age_4colors_v1.png` (4 columns: House + Villager /
  Militia / Archer + King per slot, HP bars and one selection ring
  per column in slot colours).

## Stubbed / not in P2

- (Filled in by P3 above: combat, the Feudal age-up, Fog of War, the
  enemy faction + AI and win/lose are all live.)
- (Filled in by the Bé-drawn pass above: Spearman / Cavalry /
  Battering Ram sprites and the Farm / Wall / Gate / Castle charts —
  drawn by Bé in the house style after Tín ran out of charts.)
- (Filled in by the ships + beasts pass: the Dock trains Fishing
  Boats / Transports / War Ships, fish spots feed them, and wolves /
  bears / boars roam as neutral hostiles — see Naval / Wild beasts.)
- (Filled in by P4 above: multiplayer rooms of 2–4 with a Go relay
  + lockstep. Filled in by P4 stage 2: the in-match chat button is
  live in MP matches, accounts + leaderboard exist, and desyncs
  recover via snapshot resync — only the friends button remains
  disabled.)
- No control-group slots yet. Iron is displayed but has no gather source yet.
- Stone is gatherable and tracked, but nothing costs Stone yet.
- Units don't collide with each other; group moves use per-unit destination
  offsets around the target tile instead of flocking.
- Food now also comes from Farm fields (renewable, tended by
  villagers); berry bushes remain the early source.

## Tests

Headless functional tests (selection, obstacle-avoiding move, gather deposit,
training, placement/refund/cap, plus the glass-HUD checks: quest objective
flips when a Barracks completes, training through the HUD path, minimap click
moves the camera, match timer advances, Iron + 5 resource chips, villager
sprite directions/work — plus the asset pass: berry-bush Food deposits
exactly +10 with the Harvest animation, Militia training deducts 60 Food +
20 Gold and spawns a movable unit, Archer training deducts 50 Wood + 40 Gold
and spawns a movable unit, arrow sprite extracted) — plus the building
art pass (every building type completes with its tier-1 sprite visible,
Barracks art measures 1.5× its footprint and is bottom-anchored with the
name label clear of the art top, the Watch Tower's two-resource price is
deducted/refunded as a whole, and a villager hauls Stone to a Mining
Camp placed beside the cluster instead of the Town Center) — plus the
painted-icon pass (all 17 icon textures load; the header age badge
texture follows `Main.age`) — plus the VFX pass (the layer exists,
water emitters produce live effects, a 40-burst flood stays capped at
MAX_LIVE, and the combat entry points `hit_spark`/`death_smoke` spawn
and free themselves cleanly) —
currently **224 checks, ALL PASS** (the P3 section (t) adds combat
damage/death, the counter table, archer projectiles, tower fire, the
enemy recolor + AI economy/production/waves, the Feudal age-up flow
with tier + badge swap, fog states and entity visibility, and the
win/lose conditions on both Town Centers; the Bé-drawn section (u)
adds the new-asset existence + style-gate record, the extended
counter table incl. spearman/cavalry/ram, training + age locks at
the Barracks, the Age III research flow, castle placement + fire,
the farm tend→grow→harvest→exhaust→re-till loop, wall/gate A*
crossing rules for both teams, and the AI's Age III + cavalry).
**Current total after the team-colours pass: 356 checks, ALL
PASS** (section (aa) adds the Age IV research flow + tier-4 swap +
damage/logistics steps, the AI's paid Imperial purchase, the full
flee→garrison→resume cycle + the ordered-attack grace, and the
annihilation win/lose on both sides; sections t2/t10/x18 were
adapted to the flee + annihilation rules; section (ab) adds the
team-colour checks — see the Team colours section above; w11/x14
now assert the slot-0 minimap shades). The MP smoke test still
passes unchanged (`tests/mp_smoke.sh` → MP SMOKE: ALL PASS), and
the ranked end-to-end smoke passes too (`tests/ranked_smoke.sh` →
RANKED SMOKE: ALL PASS — real referee process, exact-Elo banking,
ranked leaderboard probe; see the P4 stage-3 section above).

```sh
godot --headless --path . --import          # once
godot --headless --path . res://tests/test_main.tscn
```

Screenshot capture (needs Xvfb):

```sh
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture.tscn
# writes shots/empire_age_p2.png
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_hud.tscn
# writes shots/empire_age_hud_glass.png (waits for the first wood deposit)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_assets.tscn
# writes shots/empire_age_assets.png (new villager + Militia + Archer + CraftPix map)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_barracks.tscn
# writes shots/empire_age_barracks.png (completed Barracks camp art beside the Town Center)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_terrain.tscn
# writes shots/empire_age_terrain.png (lake with sand shore ring on the new tileset ground)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_buildings.tscn
# writes shots/empire_age_buildings.png (full base, all six buildings at the 1.5x scale,
# units in front of and behind the Barracks) + a Build-panel layout check frame
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_icons.tscn
# writes shots/empire_age_icons.png (base view with the painted icon set in the HUD)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_vfx_water.tscn
# writes shots/empire_age_vfx_water.png (lake alive: shore foam, shimmer glints, ripple rings)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_vfx_base.tscn
# writes shots/empire_age_vfx_base.png (Blacksmith chimney smoke, Barracks under
# construction with builder + dust, gather effects)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_units_clean.tscn
# writes shots/empire_age_units_clean.png (Villager + Militia + Archer parked on
# open grass at 2.4x zoom — the defringe check shot)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_p3_combat.tscn
# writes shots/empire_age_p3_combat_v1.png (live skirmish: HP bars, arrows in flight)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_p3_enemybase.tscn
# writes shots/empire_age_p3_enemybase_v1.png (the blue stronghold, fog lifted by scouts)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_p3_fog.tscn
# writes shots/empire_age_p3_fog_v1.png (visible / explored-dim / black fog + fogged minimap)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_p3_victory.tscn
# writes shots/empire_age_p3_victory_v1.png (CHIẾN THẮNG panel, quest 3 ticked)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_contact.tscn
# writes shots/empire_age_newart_contact_v1.png (every NEW sprite at game scale
# over grass, flanked by Town Center / Villager / Militia references)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_newpass.tscn
# writes shots/empire_age_farm_v1.png (Farm + plots mid-growth, villager tending),
# empire_age_wall_v1.png (wood wall line + gate, enemy cavalry stuck outside),
# empire_age_castle_v1.png (Age-III base: tier-3 TC/Farm + the Castle),
# empire_age_newunits_v1.png (spearman/cavalry/ram in a live skirmish)
xvfb-run -a -s "-screen 0 1152x648x24" godot --path . res://tests/capture_panels.tscn
# writes shots/empire_age_panels_{build,train,tech}_v1.png (new HUD cards layout check)
# xvfb-run -a godot --path . res://tests/capture_ships_beasts.tscn -- ships|beasts
# writes shots/empire_age_ships_v1.png (fishing boat working a spot + war ship +
# transport at the coast dock) and shots/empire_age_beasts_v1.png (wolf pack
# closing on a villager, bear by the trees); tools/contact_ships_beasts.py
# writes shots/empire_age_ships_beasts_contact_v1.png (sprite contact sheet)
# xvfb-run -a godot --path . res://tests/capture_clouds.tscn
# writes shots/empire_age_clouds_v1.png (CraftPix clouds + their shadows)
# xvfb-run -a godot --path . res://tests/capture_ground.tscn -- grass|shore|desert
# writes shots/empire_age_grassland_fix_v1.png / _shore_v1 / desert_fix_v1
# (baked-ground verification frames)
# xvfb-run -a godot --path . res://tests/capture_age4.tscn
# writes shots/empire_age_age4_v1.png (Imperial base: tier-4 art + IV badge)
# xvfb-run -a godot --path . res://tests/capture_flee.tscn
# writes shots/empire_age_flee_v1.png (wolf chasing a villager back to its TC)
# xvfb-run -a godot --path . res://tests/capture_4colors.tscn
# writes shots/empire_age_4colors_v1.png (4 slots = 4 team colours on
# the same sprite set: House + Villager/Militia/Archer + King per slot)
```

## Home Lobby (13g) + Replay (13h)

The game now boots into a **Home Lobby** (`scripts/home_lobby.gd`,
its own CanvasLayer over the unloaded world): a full-bleed
painted Roman coastal panorama (`assets/home_bg.png`), a
top-left profile chip (King-portrait avatar in a gold ring,
account name, mini rank badge + rank text + a gold star-progress
bar; guests read "Chưa xếp hạng"), a top-right row — **friends,
mail (unread badge), settings, ping** (live round-trip latency
measured by Net's ping loop; there is deliberately NO bell —
notifications were cut) — a right-side season banner carousel
(season/ranked banner + custom-rooms banner, dots, 6 s
auto-rotate), and a 4-item bottom nav: **Thành Tích** (profile
popup), **Lịch Sử** (match-history panel), **BXH** (leaderboard),
**Hướng Dẫn** (static guide popup). Friends and mail are real
server features (see the server README): friends list with rank
+ online presence, add-by-exact-username; system letters
(welcome / promotion / season summary) with an unread badge.
The settings gear opens a small server/connection popup — the
game has no standalone settings system yet; that gap is known.
The in-match experience is untouched; SP starts from the setup
view exactly as before.

**Match-entry cluster (13i)** — the two slanted mode buttons
were replaced by the entry cluster from Tín's reference, at the
bottom centre-right: a **rank display** (the shield badge drawn
large in `rank_badge.gd`'s art language, rank name, and the
division's star row — filled gold / empty dark; Công Tước and
Hoàng Đế hide the row, their name line reads "Công Tước · N
sao"; guests get a grey shield, "Chưa xếp hạng" and empty
stars; tapping the display opens Thành Tích) over a big
orange-gold **START** button ("START" + "Đấu hạng" inside it)
that opens the ranked queue via the lobby — guests get the
login prompt there, as before. On START's left, two dark-blue
**diamond buttons** with the label under the diamond: **Tuỳ
chọn** (crossed swords) opens the setup view — the old
map-choice panel, rehomed, plus custom-room entry — and **Đấu
thường** (target icon) starts a normal SP match immediately on
the last-used map configuration (`Main.chosen_biome` /
`chosen_layout`, which every setup pick persists; defaults
grassland · plains). Under START sits the **daily line** —
gift icon + "Đấu hạng mỗi ngày" + a state text for the
server's first-ranked-win-of-the-day bonus star (see the
server README): the offer while unclaimed, "Đã nhận thưởng
hôm nay" dimmed (gift greyed) once claimed, and for guests an
invitation ("Đăng nhập để nhận thưởng ngày") that opens the
account panel. The ranked end panel and the history rows name
the bonus stars a delta is made of — "(chuỗi thắng)",
"(thưởng ngày)", or both joined with " + ".

**Match history panel** (same glass family as the leaderboard):
mode filter (Tất cả / Đấu Hạng / Đấu Thường); ranked rows come
from the server (20 per account, banked at result time with
map, referee-reported duration and replay id), custom-room and
SP rows are recorded locally (`scripts/local_history.gd`,
`user://match_log.json`, cap 20). Cards show mode + relative
time, result with star delta, a biome-coloured map chip with
"Biome · Layout" names, player avatar chips with team-colour
strips, and a details sub-panel; pagination is 5 per page; win
rows carry a gold glow. Each row has a round **play button**
when a replay recording exists (greyed, tooltip "Không có bản
ghi lại", otherwise).

**Leaderboard** (restyled, shared by Home and the lobby):
full-screen dark-blue glass board, 3 slanted tabs — Toàn server
(seasonal ladder), Bạn bè (friends-filtered ladder), Thắng/Thua
(W/L board) — laurel wreaths for the top 3, rank shield badges,
MMR with dot thousand separators, and a sticky "Hạng của tôi"
footer whose position is computed over the full ordering by the
server.

**Replay** (`scripts/replay_bar.gd` + Main's replay mode): the
server records every relayed match (header + full stamped
command log, cap 200 — see the server README). Playback
regenerates the world from the recorded seed/config and feeds
the recorded ticks/commands into the SAME lockstep queues the
network uses, with full-map observer vision and a free camera.
The control bar has play/pause, 1x/2x/4x speeds, a timeline
slider — **seeking re-simulates**: backward seeks reload and
fast-forward the feed from tick 0, forward seeks fast-forward
in place (there are no state snapshots, by design) — a match
clock, per-player chips (team dot, name, resources, age read
from the live sim), an Exit button back to Lịch Sử, and a
result banner at the end. A version guard asks before playing
a replay whose `game_version` differs from the client's.

```sh
bash tests/replay_smoke.sh   # record a scripted match, fetch +
                             # play it back twice headless;
                             # asserts result + determinism
bash tests/capture_home.sh   # shots/empire_age_home_lobby_v1.png
bash tests/capture_home_v3.sh # shots/empire_age_home_lobby_v3.png
                             # (13i entry cluster, same seed)
bash tests/capture_lb2.sh    # shots/empire_age_leaderboard_v2.png
bash tests/capture_history.sh # shots/empire_age_history_v1.png
bash tests/capture_replay.sh # shots/empire_age_replay_v1.png
```

## Main characters — the hero unit (13j)

The unique hero (unit id `king`, displayed as **Nhân vật chính**) is
trained at the **Castle, Age IV only, 500 Food + 300 Gold, 60 s train
(48 s at the Imperial multiplier), 1 pop, one alive per player**
(retrainable after death). Stats (`scripts/stats.gd`): HP 650, atk 26,
range 44, cooldown 1.1, sight 6, speed 112, ×1.3 vs
militia/spearman/villager. The enemy AI fields one too (honest ledger;
it commissions a Castle at Age IV if it has none).

**Roster** (`scripts/characters.gd`): four main characters, each an
8-direction crisp sprite set + a framed portrait avatar —
**ngan_ky** Ngân Kỵ, **kim_hoa** Kim Hoa, **lam_bao** Lam Bào (hair
recoloured blonde→black at pipeline start to match his portrait),
**bach_sa** Bạch Sa. Characters are **randomly assigned per match**
(server draws in MP and ships `char` per slot in match_start; SP draws
locally; the AI draws too) — there is no character picker. Characters
ship **one canonical colour set for every slot** (never team-dyed);
allegiance reads from the **player name over the hero's head**,
tinted with the owner's slot colour (`scripts/hero_overlay.gd`, late
pass, fog-aware). The profile **avatar** is a separate free pick among
the four portraits (account `avatar_id`, default Ngân Kỵ).

**Kits** (`Stats.HERO_KITS`; aura radius 3 tiles; all skill state is
sim state, cast through the lockstep `skill` command, HUD skill
button with a radial cooldown sweep):

| Character | Aura | Active |
|---|---|---|
| Ngân Kỵ | Huyết Bào: allies +15% dmg | Xung Phong (45 s): 5 s +50% speed, +100% dmg |
| Kim Hoa | Sinh Tồn: allies regen +1 HP/2 s | Vương Mệnh Hồi Phục (60 s): heal 80 in radius |
| Lam Bào | Hàn Khí: enemies −15% speed | Băng Phong (60 s): enemies in 2.5 tiles −60% speed, −40% atk speed, 3 s |
| Bạch Sa | Thánh Quang: allies −10% dmg taken | Kết Giới (70 s): fixed zone 8 s, allies inside −30% dmg taken |

**Cosmetic skins**: vo_hiep / bach_y / tu_y are appearance packs only
(no kits — a skinned hero keeps the drawn character's kit, stats and
name). They are premium and **locked**: nobody owns one yet (no shop),
activation is rejected client- and server-side; the lobby's "Nhân vật"
collection shows the roster + the locked skin teasers. AI never wears
skins. Animation is procedural over the single static pose per
direction (breathing/walk bob + lean + step dust, attack lunge + gold
slash, hurt flash, death fall).

### Limb rig + weapons (13n)

The four MAIN characters additionally get a **cutout limb rig**
(`tools/build_hero_rig.py` → `assets/hero_parts/` +
`assets/hero_rig.json`, loader `scripts/hero_rig.gd`): each of the
32 direction sprites is partitioned into jointed parts (back /
under / legs / torso / arms) with per-direction pivots, plus one
**drawn weapon** per character held in the weapon hand across all
8 directions — Ngân Kỵ's longsword (silver blade, gold crossguard,
red-gem pommel), Kim Hoa's flower sceptre, Lam Bào's ice spear,
Bạch Sa's holy staff. Rest-pose reassembly is pixel-exact against
the source sprites (0 px diff, verified by the builder); an
"under" silhouette layer keeps limb rotation from ever opening a
see-through hole. `Unit._rig_pose` drives the parts from the same
state machine as the 13j layer: idle arm sway/breathing, **real
alternating leg swings** around the hip (front/back views add an
alternating foot lift; arms counter-swing, the weapon arm
steadier), keyframed attacks per weapon class on the hero's real
attack cadence (sword slash synced with the gold slash arc, spear
thrust, staff tap), a weapon-raised **cast pose** (`_king_cast_t`,
set at the single `Main.cast_hero_skill` hook so SP, MP-validated
and AI casts all play it), a hurt flinch over the white flash, and
the death topple on the rig root. Per-character tuning (leg/arm
amplitude, cadence, bob) gives the knights a brisk stride and the
gowned characters a low-amplitude glide. Documented per-direction
limits: the gowns show no legs in the source art (their "legs" are
hem panels + shoes), knight capes cover the thighs in back views
(boots only), and Kim Hoa / Bạch Sa have no separable arms in the
back three directions (veil-covered) — there the weapon anchors
on the direction's static hand point and still lifts on
attack/cast. Skins keep the 13j single-sprite path. All of it is
presentation-only (checksums/snapshots untouched — see the
mp_skill_smoke below, and tests af1–af8 in the SP suite).

```sh
bash tests/mp_skill_smoke.sh # hero duel: both heroes cast through
                             # the command pipeline; checksums agree
```

## Layout

```
project.godot          main.tscn (root: scripts/main.gd)
scripts/main.gd        game state, input, selection, orders, placement, training,
                       match timer/pause, deposit log + gather rates, quests, rally point,
                       arrow projectiles, tower fire, age-up research, win/lose
scripts/world.gd       map gen, obstacle grid, AStarGrid2D helpers, terrain tile rendering
scripts/unit.gd        unit state machine (move/gather/return/build + combat:
                       to_attack/attack/dead, HP bar, guard-post auto-engage)
scripts/hero_rig.gd    loader/cache for the 13n hero limb-rig data
                       (assets/hero_rig.json + hero_parts/ textures)
tools/build_hero_rig.py  cuts the 32 hero sprites into jointed parts, draws
                       the 4 weapons, exports hero_rig.json (reassembly
                       verified pixel-exact); tools/build_roster_v2.py
                       renders the roster sheet from the same data
scripts/building.gd    footprints, construction progress, training queue, HP + tower fire
scripts/stats.gd       THE combat stats table (unit/building HP, damage, counters,
                       tower damage by age, age-up cost/time)
scripts/field.gd       farm field plot (growth stages, harvest budget, re-till)
scripts/fog.gd         Fog of War grid + overlay (unexplored black / explored dim)
scripts/enemy_ai.gd    enemy economy ledger, production, base defence, attack waves
assets/enemy/          slot-1 deep-blue variants (unit sheets + TC/Barracks/House/Tower art)
assets/team2/, team3/  slot-2 green / slot-3 yellow variants (same layout + ships + king.png)
scripts/team_colors.gd THE per-slot colour table (UI/minimap/VFX colours + asset paths)
tools/recolor_teams.py red-band hue rotation -> enemy/ + team2/ + team3/ sets (generalises
                       recolor_enemy.py; skin/hair/wood/stone untouched)
scripts/resource_node.gd  tree / gold / stone / berry-bush nodes (CraftPix sprites)
scripts/decor.gd       blocking decoration (ruins, flat rocks)
scripts/animal.gd      wandering deer/fox (decoration, hunting is P3)
assets/                extracted sheets: villager/militia/archer + arrow + env/ (CraftPix)
assets/buildings/      building art: <family>_t1..t4.png for towncenter/house/barracks/
                       miningcamp/tower/blacksmith (tier charts) + camp_compound.png (spare)
assets/icons/          painted HUD icons (resources, ui actions, age_1..age_4 badges)
tools/extract_sprites2.py  cuts the new character sheets into assets/ + manifests
tools/extract_buildings.py white-removal + ground-slab removal for building art -> assets/buildings/
tools/defringe_characters.py (superseded) shadow conversion + rim fix for the old binary cuts
tools/recut_smooth.py  v3 character re-cut: smooth alpha matting from the source JPGs
                       (same frame geometry/manifests), baked shadow + white swoosh/dust
                       effects removed, premultiplied resizes -> assets/{villager,militia,archer}.png
tools/derim_buildings.py (superseded by v4) rim unblend/bleed for the building cuts
tools/recut_buildings_smooth.py v4 building re-cut: smooth alpha matting from the tier
                       charts (slab removal + props preserved, page-hole classification)
                       -> assets/buildings/
tools/extract_tiles.py   slices the terrain tileset sheet -> assets/tiles/ (+ manifest)
tools/extract_icons.py   white-removal + component split for the painted HUD icon set
scripts/rtc_camera.gd  pan / zoom camera, clamped to map, focus_on()
scripts/hud.gd         the glass HUD (top bar, quests, action tabs, selection chip)
scripts/vfx.gd         shared effects layer (water ambience, gather/build/training
                       effects, combat-ready hit/death/trail entry points)
scripts/minimap.gd     live minimap control (terrain/dots/viewport, click-to-move)
scripts/icons.gd       code-drawn fallback HUD icons (no emoji); painted set in assets/icons/
tests/test_main.gd     headless tests
tests/capture.gd       P2 screenshot scene    tests/capture_hud.gd  glass-HUD screenshot scene
shots/empire_age_p2.png        shots/empire_age_hud_glass.png
```
