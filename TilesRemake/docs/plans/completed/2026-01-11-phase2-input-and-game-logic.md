# Phase 2: Input & Game Logic Implementation Plan

## Overview

Add tap detection, scoring, and game over logic to make the game playable. Players tap black tiles to remove them and earn points. Tapping white space or letting a tile scroll off the bottom ends the game.

## Current State Analysis

- `GameScene.swift` handles touch only for starting the game
- `TileNode` is an `SKSpriteNode` with a `column` property
- Tiles tracked in `activeTiles` array
- Game states: `waiting` and `playing`
- Tiles currently just scroll off the bottom with no consequence

## Desired End State

After Phase 2 completion:
- Tapping a black tile removes it and increments score
- Tapping white space (not on a tile) triggers game over
- A tile scrolling off the bottom triggers game over
- Score is displayed during gameplay
- Game over screen shows final score and restart button
- Players can tap any visible tile (not restricted to bottom-most)

### Verification:
- Tapping tiles works correctly and updates score
- Tapping empty space ends the game
- Missing a tile (scrolls off bottom) ends the game
- Score displays correctly
- Restart works and resets everything

## What We're NOT Doing

- Audio feedback (Phase 3)
- Beatmap/song integration (Phase 4)
- High score persistence (Phase 5)
- Animations or visual effects on tap (Phase 5)

## Implementation Approach

1. Add a `gameOver` state to the existing `GameState` enum
2. Expand touch handling to detect tile taps vs empty space taps
3. Add score tracking and display
4. Detect when tiles scroll off bottom (game over condition)
5. Create game over UI with score and restart button

---

## Step 1: Add Game Over State and Score Tracking

### Overview
Extend the game state enum and add score property.

### Changes Required:

#### 1. Update `GameScene.swift` - Add state and score
**File**: `TilesRemake/GameScene.swift`

```swift
// Update the GameState enum to include gameOver:
// - waiting: showing start screen
// - playing: game in progress
// - gameOver: game ended, showing score and restart

// Add a score property:
// - private var score: Int = 0

// Add a score label property:
// - private var scoreLabel: SKLabelNode?
```

---

## Step 2: Add Score Display

### Overview
Show the current score during gameplay.

### Changes Required:

#### 1. Update `GameScene.swift` - Create and update score label
**File**: `TilesRemake/GameScene.swift`

```swift
// Create a function setupScoreLabel():
// - Create an SKLabelNode positioned at the top of the screen
// - Use a readable font (e.g., Helvetica-Bold, size 32)
// - Set fontColor to black
// - Position near the top-center, but leave room for notch/dynamic island
// - Add to scene and store in scoreLabel property
// - Initially hidden or shows "0"

// Create a function updateScoreDisplay():
// - Update scoreLabel.text to show current score

// Call setupScoreLabel() in startGame() after clearing the start button
```

---

## Step 3: Implement Tile Tap Detection

### Overview
Detect when player taps a tile vs empty space.

### Changes Required:

#### 1. Update `GameScene.swift` - Expand touchesBegan
**File**: `TilesRemake/GameScene.swift`

```swift
// Modify touchesBegan to handle playing state:
//
// if gameState == .waiting:
//     startGame() (existing behavior)
//
// else if gameState == .playing:
//     Get touch location in scene coordinates
//     Check if any tile in activeTiles contains this point
//     Use tile.contains(point) or check tile.frame
//
//     If a tile was tapped:
//         Call handleTileTap(tile)
//     Else (tapped empty space):
//         Call triggerGameOver()
//
// else if gameState == .gameOver:
//     Check if restart button was tapped
//     If so, call restartGame()
```

#### 2. Add helper function to find tapped tile
**File**: `TilesRemake/GameScene.swift`

```swift
// Create function findTile(at point: CGPoint) -> TileNode?
// - Iterate through activeTiles
// - For each tile, check if point is within tile's frame
// - Return the first matching tile, or nil if none found
//
// Note: Since tiles can overlap during scroll, you might want to
// prioritize the bottom-most tile (lowest Y) if multiple match,
// but for now any match is fine since user can tap any tile
```

---

## Step 4: Handle Successful Tile Tap

### Overview
Remove tapped tile and increment score.

### Changes Required:

#### 1. Update `GameScene.swift` - Add tile tap handler
**File**: `TilesRemake/GameScene.swift`

```swift
// Create function handleTileTap(_ tile: TileNode):
// - Remove tile from scene: tile.removeFromParent()
// - Remove tile from activeTiles array
// - Increment score by 1
// - Call updateScoreDisplay()
```

---

## Step 5: Detect Missed Tiles (Scrolled Off Bottom)

### Overview
Trigger game over when a tile scrolls off the bottom without being tapped.

### Changes Required:

#### 1. Update `GameScene.swift` - Modify tile removal logic in update()
**File**: `TilesRemake/GameScene.swift`

```swift
// Currently, tiles that scroll off bottom are just removed.
// Change this to trigger game over instead:
//
// In the update() function, where we check tile.position.y < -tileSize.height / 2:
// - Instead of just removing the tile, call triggerGameOver()
// - Don't remove the tile yet (game over will handle cleanup)
// - Use a flag or return early to stop the game loop
//
// Alternative approach:
// - Check BEFORE moving tiles if any tile is about to exit
// - Or check after moving and trigger game over if any tile exited
```

---

## Step 6: Implement Game Over

### Overview
Stop the game, show final score, and provide restart option.

### Changes Required:

#### 1. Update `GameScene.swift` - Add game over function
**File**: `TilesRemake/GameScene.swift`

```swift
// Create function triggerGameOver():
// - Set gameState = .gameOver
// - Stop tile movement (update() already checks gameState)
// - Show game over UI by calling showGameOverScreen()

// Create function showGameOverScreen():
// - Create a semi-transparent overlay (optional, for visual clarity)
// - Create "Game Over" label (large, centered)
// - Create "Score: X" label showing final score
// - Create "Restart" button/label
// - Store restart button reference for tap detection
```

---

## Step 7: Implement Restart

### Overview
Reset everything and start a new game.

### Changes Required:

#### 1. Update `GameScene.swift` - Add restart function
**File**: `TilesRemake/GameScene.swift`

```swift
// Create function restartGame():
// - Remove all tiles from scene and clear activeTiles array
// - Remove game over UI elements
// - Reset score to 0
// - Reset currentSpeed to initialScrollSpeed
// - Reset lastUpdateTime to 0
// - Update score display
// - Set gameState = .playing
// - Call spawnInitialTiles() to start fresh

// Alternative: could go back to waiting state and show start screen again
// But direct restart is more convenient for the player
```

#### 2. Update touchesBegan for restart detection
**File**: `TilesRemake/GameScene.swift`

```swift
// In touchesBegan, when gameState == .gameOver:
// - Check if the touch location is on the restart button
// - If so, call restartGame()
//
// Could also allow tapping anywhere to restart (simpler UX)
```

---

## Success Criteria

### Automated Verification:
- [x] Project builds without errors: `xcodebuild -scheme TilesRemake build`
- [x] No compiler warnings related to the new code

### Manual Verification:
- [x] Tapping a black tile removes it from the screen
- [x] Score increments by 1 for each tile tapped
- [x] Score is visible at top of screen during gameplay
- [x] Tapping white/empty space triggers game over
- [x] Letting a tile scroll off the bottom triggers game over
- [x] Game over screen displays "Game Over" text
- [x] Game over screen shows final score
- [x] Game over screen has a restart button
- [x] Tapping restart begins a new game
- [x] After restart, score is reset to 0
- [x] After restart, tiles start from the top again
- [x] After restart, speed is reset to initial speed

---

## File Summary

| Action | File |
|--------|------|
| Modify | `TilesRemake/GameScene.swift` |

---

## Notes for Future Phases

- **Phase 3** will add audio feedback when tiles are tapped
- **Phase 4** will replace random tiles with beatmap-driven patterns
- **Phase 5** will add visual feedback (tap animations), high score persistence, and polish
