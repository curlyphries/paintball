# Map Authoring Guide

A short guide for adding or refreshing maps. The theming kit (palette,
lights, sky) does the visual heavy lifting; you focus on layout and play.

## Anatomy of a map scene

```
SomeMap (Node3D, root)
├── MapEnvironment (instance of res://scenes/maps/_environment.tscn)
│   └── theme = preload("res://assets/themes/<theme>.tres")
├── NavigationRegion3D
│   ├── Floor       (group: floor)
│   ├── WallNorth   (group: wall)
│   ├── ...
│   ├── Cover1      (group: cover)
│   └── Landmark1   (group: landmark)
└── SpawnPoints
    ├── Spawn1 (Marker3D, group: spawn_point)
    └── ...
```

## Three rules

1. **Always instance `_environment.tscn` at the top.** It supplies sky,
   directional light, ambient, fog, glow. Don't add a second
   `DirectionalLight3D` to the map. Set its `theme` export to one of
   `assets/themes/*.tres` to tint.

2. **Every spawn point goes in the `spawn_point` group.** The runtime
   reads spawns from this group. Minimum 8 per map. None within 4m of
   each other. None with a direct sightline to another spawn — put cover
   within 3m.

3. **Use modular `.glb` props for cover.** `wall_low.glb`,
   `wall_high.glb`, `platform.glb`, `platform_large.glb` look
   substantially better than CSG boxes. Keep CSG only for floors,
   ceilings, perimeter walls, and disposable filler.

## Theming via groups

Add nodes to one of these groups and the `MapThemeApplier` (optional helper)
or your own setup colors them per the chosen theme:

| Group        | Used for                                        |
|--------------|-------------------------------------------------|
| `floor`      | floor + ground geometry (kept dim for splats)   |
| `wall`       | perimeter and major dividing walls              |
| `wall_accent`| inner walls / contrast bands                    |
| `cover`      | crates, low cover, hedges                       |
| `landmark`   | the big named centerpiece                       |
| `accent`     | small highlight props                           |
| `emission`   | glowing signs, neon strips, pads                |

## Verticality minimum

At least one route in the map requires a jump or ramp to a platform that
oversees significant ground. Catwalks count. The arena's spire counts.
Without this, paintball flattens into pillar-camping.

## Landmark rule

Every map gets one ≥ 6m-tall named centerpiece visible from all spawns.
"The Silo" (warehouse), "The Fountain" (courtyard), "The Spire" (arena).
Landmarks anchor callouts and orientation.

## Spawn point conventions

- Use `Marker3D` nodes
- Place at floor + 0.5 Y so players don't clip
- Group `spawn_point` (not `Spawn` or `spawnpoint`)
- Distribute: corners + mid-edges; never all on one side
- Minimum 8

## Scale targets

Active play area | Footprint range
-----------------|----------------
Small (4-6 player) | 30 × 30 to 40 × 30
Medium (6-8 player) | 50 × 40 to 60 × 45
Large (8+ player)  | 70 × 50 +

Bigger doesn't mean emptier — cover density must scale with area.

## Registering a new map

After authoring `scenes/maps/yourmap.tscn`, register it:

```
# scripts/game_settings.gd
const AVAILABLE_MAPS: Dictionary = {
    ...
    "yourmap": {
        "name": "Your Map",
        "scene": "res://scenes/maps/yourmap.tscn",
        "description": "...",
    },
}
```

That's it. The lobby pool, rotation system, and vote UI auto-pick it up.

## Lighting cautions

- Tonemap is filmic + white = 6.0. Materials that look right under
  unlit shaders may look washed out; rely on the editor preview, not raw
  hex codes.
- Glow is on at intensity 0.4. Emissive materials at energy 2+ will
  bloom hard — that's intentional for accent pads. Don't apply emission
  to walls or floors or the whole scene will glow.
- One `DirectionalLight3D` only (in the env scene). Use `OmniLight3D`
  sparingly for accent pools, energy ≤ 1.0.

## Don'ts

- Don't `preload()` map scenes from each other; they're loaded
  dynamically by `main_game.gd`.
- Don't put gameplay logic in the map — keep it geometry + spawns +
  environment. Logic lives in scripts/.
- Don't disable collision on cover — bots and players need to physically
  bump into things.
- Don't use FlatColor materials on hero geometry; instance the modular
  `.glb` and override `material_override.albedo_color`.
