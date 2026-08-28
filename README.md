# Hex Realms

An asset-free, turn-based strategy foundation built with Godot 4. It renders a seeded isometric hex world, generates all terrain textures at runtime, and pits a cyan player faction against a simple red AI faction.

## Current playable slice

- Deterministic 18×13 odd-q hex map generated from a visible world seed.
- Island-shaped elevation created from layered `FastNoiseLite` fields and radial falloff.
- Four terrain types: Sea, Plains, Hills, and Mountains.
- Runtime-generated pixel textures plus coordinate-seeded vector details; there are no image assets.
- Elevated top and side faces for an isometric 2D look.
- Procedurally drawn Settler, Warrior, and City visuals.
- Player → AI round phases with separate movement resets and input locking.
- A simple AI that founds a city, pathfinds toward the nearest player target, and attacks when adjacent.
- Settlers found named cities and are consumed in the process.
- Unit selection, terrain movement costs, multi-hex pathfinding, movement animation, health, and melee attacks.
- Pan, middle-mouse drag, zoom, hover inspection, and random map regeneration.

## Run it

1. Install Godot 4.3 or newer.
2. Import this folder by selecting `project.godot` in the Godot Project Manager.
3. Press **F6/F5** or click **Run Project**.

No imports or third-party packages are required.

## Controls

| Input | Action |
| --- | --- |
| Left click | Select, move to a green hex, or attack a red hex |
| Right click / Esc | Clear selection |
| C / Found City | Consume the selected Settler and found a city |
| Space | End the player phase and run the AI phase |
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

Warriors have 3 health, deal 1 adjacent damage, and spend 1 movement point per attack. Settlers have 1 health and cannot attack. A city must be founded on Plains or Hills and at least three hexes from every existing city.

## Round and AI logic

1. The player moves, attacks, or founds a city with cyan units.
2. Ending the phase locks player input and restores the red faction's movement.
3. The AI Settler founds on a legal tile or paths toward the nearest legal city site.
4. The AI Warrior uses terrain-aware Dijkstra pathfinding toward the closest player unit, falling back to a player city.
5. If the Warrior reaches an adjacent enemy unit with movement remaining, it attacks.
6. Control returns to the player, the round counter advances, and cyan movement is restored.

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
scripts/game.gd                  Round phases, AI, city founding, combat and movement
scripts/map_generator.gd         Seeded terrain data generation and hex coordinate helpers
scripts/hex_map.gd               Isometric renderer, runtime textures, picking and highlights
scripts/procedural_unit.gd       Asset-free unit art and movement rules
scripts/procedural_city.gd       Asset-free faction city renderer
scripts/camera_controller.gd     Strategy camera controls and map framing
tests/map_generator_test.gd      Headless generator smoke test
tests/game_smoke_test.gd         Player move, city founding and full AI phase test
```

## Smoke test

With a Godot 4 binary available:

```bash
godot --headless --path . --script tests/map_generator_test.gd
godot --headless --path . --script tests/game_smoke_test.gd
```

## Deliberate limits of this foundation

There is no city production, territorial ownership, city capture, fog of war, save system, diplomacy, or multiplayer yet. Combat is intentionally minimal: one adjacent attack value and health pool, with no counterattack or unit classes beyond Settler and Warrior.
