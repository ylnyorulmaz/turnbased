# Hex Realms

An asset-free, turn-based strategy foundation built with Godot 4. It renders a seeded isometric hex world, generates all terrain textures at runtime, and starts with a playable Settler and Warrior.

## Current playable slice

- Deterministic 18×13 odd-q hex map generated from a visible world seed.
- Island-shaped elevation created from layered `FastNoiseLite` fields and radial falloff.
- Four terrain types: Sea, Plains, Hills, and Mountains.
- Runtime-generated pixel textures plus coordinate-seeded vector details; there are no image assets.
- Elevated top and side faces for an isometric 2D look.
- Procedurally drawn Settler and Warrior units.
- Unit selection, terrain movement costs, multi-hex pathfinding, movement animation, and turn reset.
- Pan, middle-mouse drag, zoom, hover inspection, and random map regeneration.

## Run it

1. Install Godot 4.3 or newer.
2. Import this folder by selecting `project.godot` in the Godot Project Manager.
3. Press **F6/F5** or click **Run Project**.

No imports or third-party packages are required.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select a unit or move to a highlighted hex |
| Right click / Esc | Clear selection |
| Space | End turn |
| WASD / arrow keys | Pan camera |
| Middle-mouse drag | Pan camera |
| Mouse wheel | Zoom |
| Generate New Map | Create a new world seed and rebuild the map |

## Terrain rules

| Terrain | Settler | Warrior |
| --- | ---: | ---: |
| Sea | Impassable | Impassable |
| Plains | 1 movement | 1 movement |
| Hills | 2 movement | 2 movement |
| Mountains | Impassable | 2 movement |

## Map generation pipeline

1. Convert the rectangular odd-q map into axial hex coordinates.
2. Blend continental FBM noise, detail noise, and an island falloff into one elevation score.
3. Force the outer rim below sea level so every normal-sized map has a coastline.
4. Classify elevation into Sea, Plains, Hills, and Mountains.
5. Generate a separate moisture field for per-tile color variation.
6. Reserve a seven-hex plains clearing at the center for safe initial spawns.
7. Guarantee all four terrain categories are represented, even for pathological seeds.
8. Build four 64×64 `ImageTexture` resources in memory and add deterministic per-hex detail during custom drawing.

The same seed always reproduces the same terrain data and procedural texture family.

## Structure

```text
scenes/main.tscn                 Main world and HUD
scripts/game.gd                  Turn state, selection, Dijkstra reachability, movement
scripts/map_generator.gd         Seeded terrain data generation and hex coordinate helpers
scripts/hex_map.gd               Isometric renderer, runtime textures, picking and highlights
scripts/procedural_unit.gd       Asset-free unit art and movement rules
scripts/camera_controller.gd     Strategy camera controls and map framing
tests/map_generator_test.gd      Headless generator smoke test
```

## Smoke test

With a Godot 4 binary available:

```bash
godot --headless --path . --script tests/map_generator_test.gd
godot --headless --path . --script tests/game_smoke_test.gd
```

## Deliberate limits of this foundation

There is no combat, city founding, production, AI opponent, fog of war, save system, or multiplayer yet. Those systems should be added after the map, movement, and turn loop are stable rather than mixed into the first slice.
