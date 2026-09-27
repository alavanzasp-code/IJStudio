# Model Manifest

Every placeholder in this project resolves through `ModelLibrary.SPECS`
(`res://Assets/ModelLibrary.gd`). **Dropping a model at the listed path is all
it takes** — the loader scales it to the target size, centers it, applies the
spec's orientation, and swaps out the primitives. No scene or script edits.

If the file is absent, the caller falls back to its labeled `*_Placeholder`
primitives, so the game always runs.

## How to add a model

1. Put the asset bundle in its own folder under `res://Assets/models/<category>/<key>/`.
   Keep the archive's internal structure — a `.gltf` resolves its `.bin` and
   textures by relative URI, so flattening the folder breaks every texture.
2. Name the entry point `model.gltf`.
3. Check the orientation expectations below and set `rotation` / `offset` in
   `SPECS` if the asset disagrees.
4. Verify: `godot --headless --script Assets/validate_models.gd`

Orientation is the only thing that cannot be automated. The loader normalizes
**scale and centering**, but a model authored nose-up will still render nose-up.

## Status

| Key | Path | Status | Notes |
|---|---|---|---|
| `arrow` | `weapons/arrow/` | **sourced** | 100 tris, tip already at -Z |
| `bow` | `weapons/bow/` | **sourced** | needs the 90° X lift in its spec to stand upright |
| `training_dummy` | `characters/training_dummy/` | **sourced** | 108 tris, 5 animations, unused so far |
| `floor` | `environment/floor/` | **sourced** | flat plane, tiles to exactly 30×30 |
| `wall` | `environment/wall/` | **sourced** | precast concrete panel, tiles to exactly 30×3.8×0.5 |
| `player_body` | `characters/player_body/` | **MISSING** | falls back to the capsule |
| `wall_block` | `environment/wall_block/` | **MISSING** | decor walls stay as boxes |
| `grapple_rope` | `props/grapple_rope/` | **MISSING** | see below |

## Orientation contract

- **`arrow`** — along **+Z**, tip at **-Z**, total length ~1.06 m. This matches
  the flight basis in `Arrow._integrate_forces`, which points local -Z down the
  velocity vector. An arrow authored along +Y will fly sideways.
- **`bow`** — upright on **Y**, gripped near the origin, ~1.22 m tip to tip, and
  the limb plane must be the **sagittal (YZ) plane**: belly facing the aim
  direction, the model's own string facing the archer. The spec applies a
  90/90 lift to achieve this. It matters because `Bow._nock` slides the loaded
  arrow from z=-0.06 to +0.10 — that math already assumes the sagittal plane.
  Note this makes the bow nearly edge-on from directly behind, which is correct:
  the primitive placeholder it replaced was also edge-on from behind.
- **`training_dummy`** / `player_body` — feet at the origin, ~1.8 m tall,
  facing -Z. The loader centers geometry on the origin and then applies the
  spec's `offset`, which lifts a character by +0.9 so its feet meet the floor.
- **`floor`** — a flat plane on XZ. Zero thickness is expected and handled.
- **`wall`** — a **solid** precast panel, ~6 m long × 3.79 m tall × 0.4 m thick.
  "Solid" matters: the tiler spaces copies by the model's AABB, so an asset
  with holes or sparse geometry (a balustrade, a fence, a wall with towers)
  leaves visible gaps no matter how well its numbers fit.

  The arena walls are **3.8 m** tall — one native panel row, zero distortion.
  They used to be 5.9 m, and that height was the whole problem: 5.9 × 0.5 m is
  a *building facade* shape, so the only Sketchfab assets that fitted it were
  cut-outs of real building exteriors (rows of windows, floating with nothing
  behind them). Real wall art is waist-high; the arena now matches the art
  instead of the art being contorted to match the arena.

  Nothing in the mechanics depends on wall height: `grapple_range` is
  horizontal, and wall-slide/wall-jump need a face, not 5.9 m of it. If you do
  want taller walls, stack the panel to 7.6 m and raise the collision to match.
- **`grapple_rope`** — must be a **straight** rope authored along **+Y** at
  exactly **1.0 m**. It is stretched by node scale, so a coiled rope would
  unwind into a spiral. See the caveat below.

## Tiling and the distortion guard

`ModelLibrary.tile_to_fit()` fills a block with whole tiles and absorbs the
remainder, rather than stretching one instance across 30 m and smearing the
texture. It rotates the asset so its long axis follows the block's long axis.

Two guards stop a bad fit from shipping:

- **Tile cap** (256) — beyond it, one stretched copy is used instead.
- **Distortion cap** (25%) — if a tile must be scaled more than 25% on any axis
  that is not *thickness*, the swap is **refused** and the placeholder is kept,
  with a one-time warning. A badly squashed model looks worse than a clean box
  and means the wrong asset was chosen for that block.

The arena currently draws **44 environment tiles** (24 floor + 4 walls × 5).
That is acceptable for a blockout; a shipping arena should use a tiling
*texture* on large flat surfaces and reserve models for silhouette.

### `grapple_rope` is not a normal model

Stretching a detailed rope mesh distorts the twist. The honest options are:

1. A purpose-built straight rope mesh, authored as a repeatable unit segment.
2. A chain of short segments distributed along the line, so no single mesh is
   stretched — this is what a shipping game would do.
3. Keep the current cylinder, which is why the fallback is still wired up.

The rope is the one requested item with no acceptable asset on Sketchfab:
searches for a straight rope returned only museum scans and unrelated vehicles.

## Licencing

All sourced models are **CC Attribution (CC-BY)** — commercial use is permitted
with attribution, but **the credit is legally required in your game's credits
screen**. Per-asset records are in each folder's `ATTRIBUTION.json`.

Nothing CC-BY-NC, CC-BY-ND, CC-BY-SA or Sketchfab "Free Standard" was accepted;
`tools/fetch_sketchfab_model.py` hard-refuses those licenses so a
non-commercial model cannot reach the project by accident.

### Required credits

- *Low-Poly Arrow v2.0* by Teslov — CC-BY — <https://sketchfab.com/3d-models/7a8542971fd0460aaae5bdd24790881b>
- *Bow of the Pack Hunter* by Peter Nox — CC-BY — <https://sketchfab.com/3d-models/8e27516a119941218def8076850800ec>
- *The Practice Dummy* by Tolden Forge — CC-BY — <https://sketchfab.com/3d-models/e9f8055b88d043c38475c8c490587704>
- *Stylized Tileable Stone Floor Texture* by Igor Skugar — CC-BY — <https://sketchfab.com/3d-models/554b688435e14a5bb13087f79214087b>
- *Concrete Sleeper Retaining Wall* by agrant2 — CC-BY — <https://sketchfab.com/3d-models/bcaadd18d8b94e91a5f9d8ff39dc9b79>
- *Modular house wall* by Yury Misiyuk — CC-BY — <https://sketchfab.com/3d-models/4dcf4bf0a1ba4a8bb96453555176885f> *(retired — kept here only so the credit trail is complete; the asset is no longer in the project)*

## Sourcing more models

```sh
export SKETCHFAB_TOKEN=...                       # from Sketchfab → Settings → API
python3 tools/sketchfab_find.py "arrow" "rope"   # search, licenses filtered
python3 tools/fetch_sketchfab_model.py <uid> Assets/models/<cat>/<key>
```

`sketchfab_find.py` reports triangle counts and animation counts so you can
avoid museum scans masquerading as game assets — a search for "arrow" on
Sketchfab otherwise returns *Teddy bears* and a *Ford Mustang*.

For architecture specifically, **Kenney**, **Quaternius** and **ambientCG** are
better sources than Sketchfab: they are CC0 (no attribution owed), download
without a token, and are built as modular kits with consistent proportions.
Sketchfab's "downloadable" filter is dominated by photogrammetry scans.

## Verifying changes

```sh
godot --headless --import                            # re-import new assets
godot --headless --script Assets/validate_models.gd  # sizes, centering, tiling
godot --headless --script Assets/verify_scene.gd     # what the scene really contains
godot --headless --script Assets/test_arrow_damage.gd  # damage regression, exits non-zero on failure
```

`validate_models.gd` catches a wrong target size or a bad orientation; both are
invisible in code review and only show up as "the arrow flies sideways" in play.

## Draw animation caveat

The bow model carries its own string, so the primitive `String_Placeholder` is
only built on the no-asset fallback path. The visible draw feedback is therefore
the **nocked arrow sliding back** (`_nock` z: -0.06 -> +0.10); the model's own
string does not flex. Making the string track the draw needs either a skinned
bow or a separate string mesh driven alongside `_draw`.
