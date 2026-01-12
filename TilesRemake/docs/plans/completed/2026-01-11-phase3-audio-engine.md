# Phase 3: Audio Engine Implementation Plan

## Overview

Add piano audio playback so that tapping tiles produces musical notes. This phase implements the core feature that distinguishes Piano Tiles from other rhythm games - the music only plays as you tap, making the player feel like they're actually playing the piano.

## Current State Analysis

- `GameScene.swift` handles tile taps in `handleTileTap()` and long tile segment completion
- `TileNode` tracks tile properties but has no audio-related data
- No audio system exists yet
- Tiles are spawned randomly with no musical association

### Key Integration Points:
- `handleTileTap()` at `GameScene.swift:290-300` - normal tile tap
- `touchesBegan` long tile handling at `GameScene.swift:194-204` - first segment
- `update()` segment completion at `GameScene.swift:496-510` - subsequent segments
- `completeLongTile()` at `GameScene.swift:302-316` - early release

## Desired End State

After Phase 3 completion:
- Tapping a tile plays a piano note
- Each tile has an assigned MIDI note number
- Notes play with low latency (< 10ms perceived)
- Long tiles sustain their note while held
- Releasing a long tile stops the sustained note
- Audio continues working after game restart

### Verification:
- Tapping tiles produces piano sounds
- Different tiles can play different notes
- Long tiles sustain sound while held
- No audio glitches or latency issues
- Audio works correctly across multiple game sessions

## What We're NOT Doing

- MIDI file parsing (Phase 4)
- Beatmap/song integration (Phase 4)
- Multiple instrument support
- Background music
- Sound effects (game over, etc.)
- Audio settings UI

## Implementation Approach

1. Create an `AudioManager` singleton to handle all audio
2. Configure low-latency audio session
3. Set up `AVAudioEngine` with `AVAudioUnitSampler`
4. Load a piano soundfont (.sf2 file)
5. Add MIDI note property to `TileNode`
6. Integrate audio triggers into existing tap handlers
7. Handle note sustain for long tiles

---

## Step 1: Create AudioManager Class [x]

### Overview
Create a singleton class to manage all audio playback using AVAudioEngine and AVAudioUnitSampler.

### Changes Required:

#### 1. Create new file `AudioManager.swift`
**File**: `TilesRemake/AudioManager.swift`

```swift
// Create a singleton class AudioManager with:
// - static let shared = AudioManager()
// - private let engine: AVAudioEngine
// - private let sampler: AVAudioUnitSampler
// - private var isSetup: Bool to track initialization

// Create setup() function that:
// - Guards against multiple setup calls using isSetup flag
// - Calls configureAudioSession()
// - Calls setupAudioEngine()
// - Calls loadSoundFont()
// - Calls startEngine()
// - Sets isSetup = true

// Create configureAudioSession() that:
// - Gets AVAudioSession.sharedInstance()
// - Sets category to .playback
// - Sets preferred IO buffer duration to 0.005 (5ms for low latency)
// - Sets preferred sample rate to 48000
// - Activates the session
// - Handles errors with print statements

// Create setupAudioEngine() that:
// - Attaches sampler to engine
// - Connects sampler to engine.mainMixerNode

// Create loadSoundFont() that:
// - Gets URL for "piano.sf2" from Bundle.main
// - Calls sampler.loadSoundBankInstrument() with:
//   - program: 0 (piano)
//   - bankMSB: kAUSampler_DefaultMelodicBankMSB
//   - bankLSB: 0
// - Handles errors with print statements

// Create startEngine() that:
// - Guards if engine is already running
// - Calls engine.start()
// - Handles errors with print statements

// Create playNote(_ note: UInt8, velocity: UInt8 = 100) that:
// - Calls sampler.startNote(note, withVelocity: velocity, onChannel: 0)

// Create stopNote(_ note: UInt8) that:
// - Calls sampler.stopNote(note, onChannel: 0)

// Create stopAllNotes() that:
// - Loops through notes 0...127 and calls stopNote for each
```

---

## Step 2: Add Soundfont to Project

### Overview
Add a piano soundfont file to the Xcode project bundle.

### Changes Required:

#### 1. Obtain a soundfont file
Download a free piano soundfont. Recommended options:
- **GeneralUser GS.sf2** (~30MB) - good balance of quality and size
- **FluidR3_GM.sf2** (~140MB) - high quality, larger file
- Any piano-specific .sf2 file (typically 5-20MB)

#### 2. Add to Xcode project
1. Drag the .sf2 file into the TilesRemake folder in Xcode
2. Rename it to `piano.sf2`
3. Ensure "Copy items if needed" is checked
4. Ensure "Add to targets: TilesRemake" is checked
5. Verify it appears in Build Phases > Copy Bundle Resources

---

## Step 3: Add MIDI Note to TileNode [x]

### Overview
Each tile needs to know which MIDI note to play when tapped.

### Changes Required:

#### 1. Update `TileNode.swift` - Add note property
**File**: `TilesRemake/TileNode.swift`

```swift
// Add property after existing properties (around line 27):
// - var midiNote: UInt8 = 60 (default to middle C)

// Update init signature to accept midiNote parameter:
// - init(column: Int, size: CGSize, tileLength: Int = 1, midiNote: UInt8 = 60)
// - Assign self.midiNote = midiNote in the initializer
```

---

## Step 4: Update GameConfig for Note Generation [x]

### Overview
Add configuration for which notes to use. For Phase 3 (without beatmaps), we'll use a simple pattern.

### Changes Required:

#### 1. Update `GameConfig.swift` - Add audio config
**File**: `TilesRemake/GameConfig.swift`

```swift
// Add after existing config (around line 25):

// Add static array of available notes (C major pentatonic scale across 3 octaves):
// - Contains notes: 48, 50, 52, 55, 57 (C3 to A3)
// -                 60, 62, 64, 67, 69 (C4 to A4)
// -                 72, 74, 76, 79, 81 (C5 to A5)
// Pentatonic scale sounds pleasant even with random selection

// Add static function randomNote() -> UInt8 that:
// - Returns a random element from availableNotes array
// - Falls back to 60 (middle C) if array is somehow empty
```

---

## Step 5: Initialize AudioManager [x]

### Overview
Set up audio when the game scene loads.

### Changes Required:

#### 1. Update `GameScene.swift` - Initialize audio in didMove
**File**: `TilesRemake/GameScene.swift`

```swift
// In didMove(to:) around line 43:
// - Add call to AudioManager.shared.setup() before setupLayout()
```

---

## Step 6: Assign Notes When Spawning Tiles [x]

### Overview
Assign a MIDI note to each tile when it's created.

### Changes Required:

#### 1. Update `GameScene.swift` - Modify showStartScreen()
**File**: `TilesRemake/GameScene.swift`

```swift
// In showStartScreen(), when creating the Play tile (around line 86):
// - Add midiNote: GameConfig.randomNote() parameter to TileNode init
```

#### 2. Update `GameScene.swift` - Modify spawnRow()
**File**: `TilesRemake/GameScene.swift`

```swift
// In spawnRow(), when creating a new tile (around line 448):
// - Add midiNote: GameConfig.randomNote() parameter to TileNode init
```

---

## Step 7: Play Notes on Tile Tap [x]

### Overview
Trigger audio when tiles are tapped.

### Changes Required:

#### 1. Update `GameScene.swift` - Modify handleTileTap()
**File**: `TilesRemake/GameScene.swift`

```swift
// In handleTileTap() around line 290:
// - Add call to AudioManager.shared.playNote(tile.midiNote) at the start
```

#### 2. Update `GameScene.swift` - Modify startGame() for Play tile
**File**: `TilesRemake/GameScene.swift`

```swift
// In startGame() around line 115:
// - Add call to AudioManager.shared.playNote(tile.midiNote) when handling the play tile
```

---

## Step 8: Handle Long Tile Audio [x]

### Overview
Long tiles should start playing when first tapped and stop when released or completed.

### Changes Required:

#### 1. Update `GameScene.swift` - Add audio to long tile handling in touchesBegan
**File**: `TilesRemake/GameScene.swift`

```swift
// In touchesBegan, .playing case, where long tile bottom segment is tapped (around line 194):
// - Add call to AudioManager.shared.playNote(longTile.midiNote) after setting up the hold
```

#### 2. Update `GameScene.swift` - Add audio to startGameWithLongPlayTile()
**File**: `TilesRemake/GameScene.swift`

```swift
// In startGameWithLongPlayTile() around line 129:
// - Add call to AudioManager.shared.playNote(tile.midiNote) after setting up the hold
```

#### 3. Update `GameScene.swift` - Stop note in completeLongTile()
**File**: `TilesRemake/GameScene.swift`

```swift
// In completeLongTile() around line 302:
// - Add call to AudioManager.shared.stopNote(tile.midiNote) at the start of the function
```

#### 4. Update `GameScene.swift` - Stop note on game over while holding
**File**: `TilesRemake/GameScene.swift`

```swift
// In triggerGameOver() around line 320:
// - Check if heldLongTile exists
// - If so, call AudioManager.shared.stopNote(heldTile.midiNote)
// - Then set heldLongTile = nil
```

---

## Step 9: Clean Up Audio on Restart [x]

### Overview
Ensure audio state is clean when restarting.

### Changes Required:

#### 1. Update `GameScene.swift` - Add audio cleanup to restartGame()
**File**: `TilesRemake/GameScene.swift`

```swift
// In restartGame() around line 366:
// - Add call to AudioManager.shared.stopAllNotes() at the start of the function
```

---

## Success Criteria

### Automated Verification:
- [x] Project builds without errors: `xcodebuild -scheme TilesRemake build`
- [x] No compiler warnings related to audio code
- [ ] `piano.sf2` file is included in bundle (check Build Phases)

### Manual Verification:
- [ ] Tapping a normal tile plays a piano note
- [ ] Different tiles play different notes (listen for variety)
- [ ] Long tiles sustain their note while finger is held down
- [ ] Releasing a long tile stops the sustained note
- [ ] Completing a long tile (all segments) stops the sustained note
- [ ] No audio delay is perceptible (< 10ms feels instant)
- [ ] Game over stops any playing notes
- [ ] Restart clears audio and new tiles play correctly
- [ ] Audio works on second, third, etc. game sessions
- [ ] No audio glitches, pops, or clicks

---

## File Summary

| Action | File |
|--------|------|
| Create | `TilesRemake/AudioManager.swift` |
| Add    | `TilesRemake/piano.sf2` (soundfont file) |
| Modify | `TilesRemake/TileNode.swift` |
| Modify | `TilesRemake/GameConfig.swift` |
| Modify | `TilesRemake/GameScene.swift` |

---

## Notes for Future Phases

- **Phase 4** will add MIDI file parsing to replace random notes with actual song data
- **Phase 4** will introduce a `Beatmap` structure that assigns specific notes to tiles based on song timing
- **Phase 5** may add audio settings, volume control, and additional sound effects

---

## Appendix: Obtaining a Soundfont

### Option A: Small Piano-Only Soundfont (Recommended for Testing)
Search for "piano soundfont sf2" - many free options under 10MB exist.

### Option B: GeneralUser GS (Recommended for Quality)
1. Visit: https://schristiancollins.com/generaluser.php
2. Download "GeneralUser GS" (about 30MB)
3. Extract and rename to `piano.sf2`

### Option C: FluidR3 (High Quality, Large)
1. Search for "FluidR3_GM.sf2"
2. This is the full General MIDI soundfont (~140MB)
3. Excellent quality but large file size

### Adding to Xcode:
1. Drag the .sf2 file into the TilesRemake folder in Xcode's navigator
2. In the dialog, check "Copy items if needed"
3. Ensure "Add to targets: TilesRemake" is checked
4. Click "Finish"
5. Verify the file appears in the project navigator
