# Phase 4: Beatmap/MIDI System Implementation Plan

## Overview

Replace random tile spawning with song-synchronized tiles driven by MIDI file data. Tiles will spawn at specific times based on MIDI note events. The gap between consecutive notes determines tile type: short gaps produce normal tiles, longer gaps produce long tiles that fill the space. This ensures a continuous stream of tiles with no empty gaps. The MIDI note number determines the audio played, while column position remains random.

## Current State Analysis

- `GameScene.swift` spawns tiles continuously based on scroll position in `spawnRow()`
- Tiles are assigned random MIDI notes from `GameConfig.randomNote()`
- Long tiles are randomly determined by `GameConfig.longTileSpawnChance`
- `TileNode` already has `midiNote` property for audio playback
- No MIDI file parsing exists

### Key Integration Points:
- `spawnRow()` at `GameScene.swift:443-485` - current random spawning
- `spawnInitialTiles()` at `GameScene.swift:426-441` - initial tile setup
- `update()` at `GameScene.swift:489-568` - game loop that triggers spawning
- `TileNode` init accepts `midiNote` parameter

## Desired End State

After Phase 4 completion:
- A MIDI file is bundled with the app
- MIDI file is parsed on game load to extract note events
- Tiles spawn at times matching MIDI note events
- Gap to next note determines tile type (short gap → normal tile, long gap → long tile)
- Long tiles fill the gap, ensuring continuous tile stream with no empty spaces
- MIDI note number is assigned to tile for correct audio playback
- Column position remains random (excluding previous tile's column)
- Game ends when all notes have been played and passed

### Verification:
- Tiles spawn in sync with the song's rhythm
- Long tiles appear during quiet/sparse moments in the music
- There are no gaps - always a tile to tap
- Tapping tiles plays the correct notes from the song
- Game feels musical and rhythmic, not random

## What We're NOT Doing

- Song selection UI (future feature)
- Importing MIDI files from device (future feature)
- Multiple difficulty levels
- Score multipliers based on timing accuracy
- Visual countdown before song starts
- Background music playback (tiles ARE the music)

## Implementation Approach

1. Create a MIDI parser using native AudioToolbox (no external dependencies)
2. Define Beatmap and NoteEvent data structures
3. Bundle a sample MIDI file with the app
4. Modify GameScene to spawn tiles based on beatmap timing
5. Calculate tile type from note duration
6. Handle song completion

---

## Step 1: Create MidiParser Class

### Overview
Create a class to parse MIDI files using Apple's native AudioToolbox framework, extracting note events with timing. After parsing, calculate the gap to each subsequent note to determine tile duration.

### Changes Required:

#### 1. Create new file `MidiParser.swift`
**File**: `TilesRemake/MidiParser.swift`

```swift
// Import AudioToolbox for MIDI parsing capabilities

// Create struct NoteEvent to represent a single note:
// - time: TimeInterval (seconds from song start when note should play)
// - duration: TimeInterval (time until NEXT note - used to determine tile length)
// - midiNote: UInt8 (MIDI note number 0-127 for audio)

// Create struct Beatmap to hold all song data:
// - title: String (song name, extracted from filename)
// - tempo: Double (BPM, used for time conversion)
// - notes: [NoteEvent] (all notes sorted by time)
// - totalDuration: TimeInterval (total song length)

// Create class MidiParser with:
// - func parse(url: URL) -> Beatmap?
//   Main entry point that:
//   - Creates a MusicSequence using NewMusicSequence()
//   - Loads MIDI file using MusicSequenceFileLoad()
//   - Extracts tempo from tempo track
//   - Iterates through all tracks extracting raw note events (time + midiNote only)
//   - Sorts all notes by time
//   - Calls calculateDurations() to compute gap to next note for each
//   - Returns populated Beatmap or nil on failure
//   - Cleans up with DisposeMusicSequence()

// - private func extractTempo(from sequence: MusicSequence) -> Double
//   Gets tempo track and finds first tempo event
//   Returns 120.0 as default if no tempo found

// - private func parseTrack(_ track: MusicTrack, tempo: Double) -> [(time: TimeInterval, midiNote: UInt8)]
//   Creates MusicEventIterator for the track
//   Loops through events looking for kMusicEventType_MIDINoteMessage
//   For each note message:
//   - Converts timestamp from beats to seconds: (timestamp / tempo) * 60
//   - Extracts midiNote from the message
//   - Ignores the MIDI note's own duration (we calculate gap-based duration instead)
//   Disposes iterator and returns collected (time, midiNote) tuples

// - private func calculateDurations(notes: [(time: TimeInterval, midiNote: UInt8)], songEnd: TimeInterval) -> [NoteEvent]
//   For each note at index i:
//   - If i < notes.count - 1: duration = notes[i+1].time - notes[i].time
//   - If i == last note: duration = songEnd - notes[i].time (or a default like 1.0)
//   - Create NoteEvent with time, calculated duration, and midiNote
//   This ensures each note's "duration" represents the gap until the next note
```

---

## Step 2: Add Sample MIDI File to Project

### Overview
Bundle a sample MIDI file with the app for testing and as the default song.

### Changes Required:

#### 1. Obtain a MIDI file
Find a simple piano MIDI file. Recommended sources:
- Create a simple one using a DAW or online MIDI editor
- Download a public domain piano piece
- Use a simple melody with varied note lengths

Requirements for good testing:
- Contains both short notes (for normal tiles) and held notes (for long tiles)
- Moderate tempo (80-140 BPM works well)
- Not too dense (avoid chords, prefer single melody line)

#### 2. Add to Xcode project
1. Rename the file to `song.mid`
2. Drag into TilesRemake folder in Xcode
3. Ensure "Copy items if needed" is checked
4. Ensure "Add to targets: TilesRemake" is checked
5. Verify it appears in Build Phases > Copy Bundle Resources

---

## Step 3: Update GameConfig for Beatmap Settings

### Overview
Add configuration values for beatmap-related settings like the threshold for when gaps become long tiles.

### Changes Required:

#### 1. Update `GameConfig.swift` - Add beatmap config
**File**: `TilesRemake/GameConfig.swift`

```swift
// Add after existing Audio Configuration section:

// MARK: - Beatmap Configuration

// Threshold in seconds - gaps longer than this become long tiles
// A normal tile takes roughly one "beat" of time to pass through
// If the gap to the next note is longer, we fill it with a long tile
// - static let longTileGapThreshold: TimeInterval = 0.5

// How far ahead (in seconds) to spawn tiles before they need to be tapped
// This gives the tile time to scroll from top to bottom of screen
// - static let spawnLeadTime: TimeInterval = 2.0

// Duration of one tile segment in seconds (for calculating long tile length)
// - static let tileSegmentDuration: TimeInterval = 0.4
```

---

## Step 4: Modify GameScene for Beatmap-Driven Spawning

### Overview
Replace the continuous random spawning with timed spawning based on beatmap note events.

### Changes Required:

#### 1. Add beatmap properties to GameScene
**File**: `TilesRemake/GameScene.swift`

```swift
// Add new properties after existing properties section:

// - private var beatmap: Beatmap?
// - private var currentNoteIndex: Int = 0
// - private var songStartTime: TimeInterval = 0
// - private var isSongComplete: Bool = false
```

#### 2. Create loadBeatmap() function
**File**: `TilesRemake/GameScene.swift`

```swift
// Create new function loadBeatmap():
// - Get URL for "song.mid" from Bundle.main
// - Create MidiParser instance
// - Parse MIDI file and store result in beatmap property
// - Print debug info: song title, note count, duration
// - If parsing fails, print error (game won't work without beatmap)
```

#### 3. Update didMove(to:) to load beatmap
**File**: `TilesRemake/GameScene.swift`

```swift
// In didMove(to:), add call to loadBeatmap() after AudioManager.shared.setup()
```

#### 4. Replace spawnInitialTiles() logic
**File**: `TilesRemake/GameScene.swift`

```swift
// Modify spawnInitialTiles():
// - Still set spawnThreshold as before
// - Instead of spawning tiles in a loop based on position:
//   - Reset currentNoteIndex to 0
//   - Pre-spawn any notes that should appear before the song starts
//   - Use spawnLeadTime to determine which notes to pre-spawn
// - The Play tile logic remains the same (it's the first tile)
```

#### 5. Create spawnTileForNote() function
**File**: `TilesRemake/GameScene.swift`

```swift
// Create new function spawnTileForNote(_ note: NoteEvent, at yPosition: CGFloat):
// - Determine column randomly (excluding previous tile's column, same as current logic)
// - Determine tileLength based on note.duration (which is gap to next note):
//   - If duration > GameConfig.longTileGapThreshold:
//     - Calculate length: Int(ceil(duration / GameConfig.tileSegmentDuration))
//     - Clamp between longTileMinLength and longTileMaxLength
//   - Else: tileLength = 1
// - Create TileNode with column, tileSize, tileLength, and note.midiNote
// - Position the tile (same positioning logic as current spawnRow)
// - Add to scene and activeTiles array
//
// Note: The duration represents how long until the next note,
// so long tiles "fill" the quiet space in the music
```

#### 6. Modify update() for beatmap spawning
**File**: `TilesRemake/GameScene.swift`

```swift
// In update(), replace the spawn logic section:
// - Track elapsed time since song started (using songStartTime)
// - Calculate current song time
// - While currentNoteIndex < beatmap.notes.count:
//   - Get next note from beatmap
//   - Calculate when to spawn: note.time - spawnLeadTime
//   - If current time >= spawn time:
//     - Call spawnTileForNote() with appropriate Y position
//     - Increment currentNoteIndex
//   - Else break (notes are sorted, no more to spawn yet)
// - Check if song is complete (all notes spawned and no active tiles)
```

#### 7. Update startGame() to record song start time
**File**: `TilesRemake/GameScene.swift`

```swift
// In startGame() and startGameWithLongPlayTile():
// - Record songStartTime = current time (from update loop)
// - Reset currentNoteIndex if needed
// - The first tile (Play tile) represents the first note in the beatmap
```

#### 8. Handle song completion
**File**: `TilesRemake/GameScene.swift`

```swift
// Add song completion check in update():
// - If all notes spawned AND no active tiles remain AND not already complete:
//   - Set isSongComplete = true
//   - Show victory screen (similar to game over but celebratory)
//
// Create showVictoryScreen() function:
// - Similar to showGameOverScreen() but with "Song Complete!" message
// - Show final score
// - Show restart button
```

#### 9. Update restartGame() to reset beatmap state
**File**: `TilesRemake/GameScene.swift`

```swift
// In restartGame(), add:
// - currentNoteIndex = 0
// - songStartTime = 0
// - isSongComplete = false
// - Remove victory screen elements if present
```

---

## Step 5: Assign First Note to Play Tile

### Overview
The Play tile should use the first note from the beatmap instead of a random note.

### Changes Required:

#### 1. Update showStartScreen()
**File**: `TilesRemake/GameScene.swift`

```swift
// In showStartScreen():
// - Get the first note from beatmap (beatmap?.notes.first)
// - Use its midiNote for the Play tile instead of GameConfig.randomNote()
// - Determine if Play tile should be long based on first note's duration:
//   - duration = gap until second note
//   - If gap is large, first tile is a long tile
// - Increment currentNoteIndex to 1 (first note is now the Play tile)
```

---

## Step 6: Remove Random Note Assignment

### Overview
Remove the random note assignment since notes now come from the beatmap.

### Changes Required:

#### 1. Clean up GameConfig
**File**: `TilesRemake/GameConfig.swift`

```swift
// The randomNote() function and availableNotes array can remain for fallback
// but will no longer be used in normal gameplay
// Consider adding a comment noting they're for fallback/endless mode only
```

---

## Success Criteria

### Automated Verification:
- [x] Project builds without errors: `xcodebuild -scheme TilesRemake build`
- [x] No compiler warnings related to MIDI parsing code
- [x] `song.mid` file is included in bundle (check Build Phases)
- [x] MidiParser successfully parses the bundled MIDI file

### Manual Verification:
- [ ] Game loads without errors (check console for beatmap load messages)
- [ ] Play tile appears and represents the first note of the song
- [ ] Tiles spawn at rhythmically appropriate times
- [ ] Long tiles appear during gaps/quiet moments in the music
- [ ] There are no empty gaps - always a tile to interact with
- [ ] Tapping tiles plays notes that sound like a coherent melody
- [ ] Game shows "Song Complete" when all tiles are tapped
- [ ] Restart works correctly and replays the same song
- [ ] Song feels musical - tiles match the rhythm of the underlying song

---

## File Summary

| Action | File |
|--------|------|
| Create | `TilesRemake/MidiParser.swift` |
| Add    | `TilesRemake/song.mid` (MIDI file) |
| Modify | `TilesRemake/GameConfig.swift` |
| Modify | `TilesRemake/GameScene.swift` |

---

## Notes for Future Phases

- **Phase 5** could add song selection UI with multiple bundled songs
- **Phase 5** could add MIDI import from Files app
- Future: Score based on timing accuracy (early/perfect/late)
- Future: Visual preview of upcoming notes (note highway)
- Future: Difficulty levels that filter/simplify complex MIDI files

---

## Appendix: MIDI File Recommendations

### Creating a Test MIDI File
If you need to create a simple test MIDI file:

1. **Online MIDI Editor**: Use onlinesequencer.net or signal.vercel.app
2. **Create a simple melody**:
   - 15-30 notes for a good test
   - Mix of fast passages (notes close together) and slow passages (gaps between notes)
   - Tempo around 100-120 BPM
   - Single melody line (no chords)
3. **Export as .mid file**
4. **Rename to song.mid**

### Good Characteristics for Piano Tiles:
- Clear melody with varying rhythm
- Some fast sections (rapid notes → many normal tiles)
- Some slow sections (gaps between notes → long tiles fill the space)
- Moderate tempo (80-140 BPM)
- Recognizable melody
- 1-3 minutes duration

### How Gaps Map to Tiles:
- Notes < 0.5 seconds apart → Normal tiles in quick succession
- Notes 0.5-1.0 seconds apart → Long tile (2 segments) fills the gap
- Notes 1.0-1.5 seconds apart → Long tile (3 segments) fills the gap
- The player always has something to tap - no empty waiting
