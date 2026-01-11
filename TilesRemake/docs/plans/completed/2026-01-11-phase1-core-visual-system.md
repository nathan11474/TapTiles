# Phase 1: Core Visual System Implementation Plan

## Overview

Implement the foundational visual system for the Piano Tiles-style rhythm game: a 4-column grid with tiles that scroll continuously from top to bottom. This phase establishes the core gameplay loop visually, using random tile spawning for testing purposes.

## Current State Analysis

- Fresh SpriteKit project with Xcode template boilerplate
- `GameScene.swift` contains demo code (spinny nodes) that will be replaced
- Uses storyboard-based launch with `GameScene.sks` file
- Target: iOS devices (iPhone and iPad)

## Desired End State

After Phase 1 completion:
- Game displays a 4-column layout filling the screen
- Black tiles spawn at the top in random columns (one per row)
- Tiles scroll smoothly downward at a configurable speed
- Visual "hit zone" at the bottom indicates where taps should occur
- Tiles that exit the bottom are removed from the scene
- Basic speed increase over time (placeholder for the full level system)

### Verification:
- App launches and displays the 4-column grid
- Tiles continuously spawn and scroll downward
- Tiles are evenly distributed across columns (one black tile per row)
- No memory leaks (tiles are properly removed when off-screen)
- Smooth 60fps performance

## What We're NOT Doing

- Input/tap detection (Phase 2)
- Scoring or game over logic (Phase 2)
- Audio playback (Phase 3)
- MIDI/beatmap parsing (Phase 4)
- Level progression UI (stars, crowns) (Phase 5)
- The full level speed system (requires song length from beatmaps)

## Implementation Approach

We'll build this using SpriteKit's scene graph and update loop:
1. Replace the template GameScene with our game logic
2. Create a Tile class as an SKSpriteNode subclass
3. Use the `update(_:)` method to move tiles and spawn new rows
4. Track elapsed time to gradually increase speed

---

## Step 1: Game Constants and Configuration

### Overview
Create a configuration structure to hold all game constants, making it easy to tune the game later.

### Changes Required:

#### 1. Create new file: `GameConfig.swift`
**File**: `TilesRemake/GameConfig.swift`

```swift
// Define a struct called GameConfig with static properties/methods:
//
// Constants needed:
// - columnCount: Int = 4 (number of columns in the grid)
// - initialScrollSpeed: CGFloat (starting speed in points per second, ~300)
// - maxScrollSpeed: CGFloat (cap on speed, ~800)
// - speedIncreaseRate: CGFloat (how much speed increases per second, ~5)
//
// Functions needed:
// - tileSize(for screenWidth: CGFloat) -> CGSize
//   Calculate tile width by dividing screen width by column count
//   Tile height should be ~1.5x the width for proper aspect ratio
//
// - spawnInterval(for tileHeight: CGFloat, speed: CGFloat) -> TimeInterval
//   Calculate how often to spawn new rows based on tile height and current speed
//   Should spawn when previous row has moved down by one tile height
```

---

## Step 2: Tile Node Class

### Overview
Create a reusable tile node that knows its column and can be styled.

### Changes Required:

#### 1. Create new file: `TileNode.swift`
**File**: `TilesRemake/TileNode.swift`

```swift
// Create a class TileNode that subclasses SKSpriteNode
//
// Properties:
// - column: Int (which column this tile belongs to, 0-3)
//
// Initializer:
// - Takes column index and size
// - Sets the tile color to black
// - Optionally adds a subtle dark gray border for visual clarity
//
// Note: Must include required init?(coder:) for SKSpriteNode subclass
```

---

## Step 3: Replace GameScene with Core Game Logic

### Overview
Rewrite GameScene to implement the 4-column grid, tile spawning, and scrolling.

### Changes Required:

#### 1. Replace contents of `GameScene.swift`
**File**: `TilesRemake/GameScene.swift`

```swift
// GameScene class extending SKScene
//
// Properties needed:
// - tileSize: CGSize (calculated from screen width)
// - columnPositions: [CGFloat] (x-coordinate for center of each column)
// - activeTiles: [TileNode] (array to track all tiles currently on screen)
// - currentSpeed: CGFloat (starts at initial speed, increases over time)
// - lastUpdateTime: TimeInterval (for calculating delta time)
// - timeSinceLastSpawn: TimeInterval (tracks when to spawn next row)
//
// didMove(to view:) - Scene setup:
// - Set background color to white
// - Call setupLayout() to calculate column positions
// - Call spawnInitialTiles() to fill screen with starting tiles
//
// setupLayout():
// - Calculate tileSize using GameConfig
// - Calculate x-position for center of each of the 4 columns
// - Add a horizontal "hit zone" line near the bottom (about 1 tile height up)
// - Add vertical column divider lines (light gray, subtle)
//
// spawnInitialTiles():
// - Calculate how many rows fit on screen
// - Spawn that many rows, positioned from top to bottom
//
// spawnRow(at yPosition:):
// - Randomly pick one column (0-3) for the black tile
// - Create a TileNode at that column's x-position and the given y-position
// - Add to scene and append to activeTiles array
//
// update(_ currentTime:) - Game loop:
// - Calculate deltaTime from lastUpdateTime
// - Increase currentSpeed gradually (capped at maxScrollSpeed)
// - Move all tiles down by (currentSpeed * deltaTime)
// - Remove any tiles that have scrolled off the bottom (y < -tileHeight/2)
// - Check if it's time to spawn a new row, if so spawn at top of screen
```

---

## Step 4: Clean Up Unused Files

### Overview
Remove the template `.sks` scene file and update the view controller to create the scene programmatically.

### Changes Required:

#### 1. Update `GameViewController.swift`
**File**: `TilesRemake/GameViewController.swift`

```swift
// Modify viewDidLoad():
// - Instead of loading scene from "GameScene.sks" file,
//   create GameScene programmatically with size = view.bounds.size
// - Set scaleMode to .resizeFill
// - Present the scene
// - Keep showsFPS and showsNodeCount enabled for debugging
//
// Modify supportedInterfaceOrientations:
// - Return .portrait only (lock to portrait for this game)
//
// Keep prefersStatusBarHidden returning true
```

#### 2. Delete unused template files
- Delete `GameScene.sks` (we're creating the scene programmatically)
- Delete `Actions.sks` (not needed)

---

## Success Criteria

### Automated Verification:
- [x] Project builds without errors: `xcodebuild -scheme TilesRemake build`
- [x] No compiler warnings related to the new code

### Manual Verification:
- [x] App launches on simulator or device
- [x] Screen shows 4 equal-width columns with light gray dividers
- [x] Black tiles appear at the top and scroll downward smoothly
- [x] Each row has exactly one black tile in a random column
- [x] Tiles speed up gradually over time
- [x] Tiles disappear when they exit the bottom of the screen
- [x] Gray "hit zone" line visible near the bottom
- [x] FPS stays at 60 (check debug overlay)
- [x] Node count remains stable (tiles are being removed properly)
- [x] Works in portrait orientation on both iPhone and iPad

---

## File Summary

| Action | File |
|--------|------|
| Create | `TilesRemake/GameConfig.swift` |
| Create | `TilesRemake/TileNode.swift` |
| Replace | `TilesRemake/GameScene.swift` |
| Replace | `TilesRemake/GameViewController.swift` |
| Delete | `TilesRemake/GameScene.sks` |
| Delete | `TilesRemake/Actions.sks` |

---

## Notes for Future Phases

- **Phase 2** will add touch handling to detect taps on tiles and implement hit/miss logic
- **Phase 4** will replace random spawning with beatmap-driven spawning
- The speed system described (stars → crowns → endless) requires knowing song duration, which will be implemented when we add the beatmap system. For now, speed just increases linearly.
