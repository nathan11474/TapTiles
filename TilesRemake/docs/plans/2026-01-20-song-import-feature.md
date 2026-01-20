# Song Import Feature Implementation Plan

## Overview

Implement a feature that allows users to import MIDI files from their device into the game. Imported songs will be stored persistently on the device and appear in the "Imports" tab. Users will be able to customize the display name and scroll speed, preview the song before finalizing the import, and delete imported songs.

## Current State Analysis

### Existing Architecture:
- **SongManager** (`SongManager.swift`): Singleton that loads songs from the app bundle's `Songs/` directory
- **SongInfo** (`SongInfo.swift`): Data model for song metadata (id, title, url, customSpeed, startFromNote, category)
- **SongSettings** (`SongInfo.swift`): JSON-decodable structure for song configuration
- **MidiParser** (`MidiParser.swift`): Parses MIDI files into `Beatmap` structures
- **SongListScene** (`SongListScene.swift`): Song selection UI with tabs (Songs, Favorites, Imports)
- **GameScene** (`GameScene.swift`): Main gameplay scene that accepts songURL, customSpeed, startFromNote

### Key Integration Points:
- `SongListScene.filterAndRebuildImports()` at line 271 - currently returns empty array with TODO comment
- `GameScene.init(size:songURL:customSpeed:startFromNote:)` at line 34 - accepts song configuration
- `SongListScene.startGame(with:)` at line 799 - transitions to GameScene with song info

### Scroll Speed Calculation (GameScene.swift:131-140):
- If no custom speed: `initialSpeed = estimatedTileHeight * notesPerSecond`
- Where `notesPerSecond = noteCount / totalDuration`
- Typical speeds range from ~900 (slow songs) to ~1700 (fast songs)

## Desired End State

After implementation:
1. Users can tap an "Import" button in the Imports tab to open iOS file picker
2. Users select a MIDI file (.mid/.midi) from their device
3. The file is copied to the app's Documents directory
4. The song appears in the Imports tab with calculated difficulty
5. Users can play imported songs just like bundled songs
6. (Later phases) Users can customize display name, adjust speed, preview before import, and delete songs

### Verification:
- Import a MIDI file through the app
- Verify it appears in the Imports tab
- Play the imported song successfully
- Close and reopen app - imported song persists

## What We're NOT Doing

- Cloud sync of imported songs
- Editing/modifying MIDI files
- Sharing songs between users
- Importing audio files (MP3, WAV, etc.) - MIDI only
- Automatic categorization of imported songs

## Implementation Approach

Phased delivery to allow testing at each stage:

1. **Phase 1**: Basic import functionality (file picker → copy to Documents → display in list → playable)
2. **Phase 2**: Import customization (display name, scroll speed adjustment, preview)
3. **Phase 3**: Song management (delete imported songs, edit settings after import)

---

## Phase 1: Basic Song Import

### Overview
Enable users to import MIDI files that immediately become playable. No customization - uses auto-calculated speed and filename-derived title.

### Changes Required:

#### 1. Create ImportedSongManager
**New File**: `TilesRemake/ImportedSongManager.swift`

```swift
// Create a singleton class ImportedSongManager that:
// - Manages the Documents/ImportedSongs/ directory
// - Stores imported song metadata in imported-songs.json
// - Provides availableImportedSongs: [SongInfo] property
// - Has methods: importSong(from: URL), deleteImportedSong(id:), getImportedSongsDirectory()
//
// Data model for persistence:
// - ImportedSongData struct with: fileName, displayName, importDate, customSpeed (optional)
// - Store as JSON array in Documents/imported-songs.json
//
// On init:
// - Create ImportedSongs directory if needed
// - Load imported-songs.json
// - Build SongInfo array from stored data
// - Validate that referenced files still exist (cleanup orphaned entries)
```

#### 2. Create ImportScene for File Selection
**New File**: `TilesRemake/ImportScene.swift`

```swift
// Create a SpriteKit scene that:
// - Shows a centered "Import MIDI File" button
// - Shows a "< Back" button to return to SongListScene
// - When import button tapped:
//   - Get the view's window and rootViewController
//   - Create UIDocumentPickerViewController for MIDI file types (public.midi-audio)
//   - Present the document picker
//   - Implement UIDocumentPickerDelegate to handle selection
// - On file selection:
//   - Call ImportedSongManager.shared.importSong(from: selectedURL)
//   - Transition back to SongListScene (which will show the new import in Imports tab)
// - Handle picker cancellation gracefully
```

#### 3. Update SongListScene for Import Button
**File**: `TilesRemake/SongListScene.swift`

```swift
// Add property for import button node

// In setupHeader() or new method setupImportButton():
// - Create an "Import" button (use SF Symbol "plus.circle" or text)
// - Position in top-right area of header
// - Only show when on Imports tab

// In switchToTab():
// - Show/hide import button based on current tab

// In touchesBegan():
// - Add hit detection for import button
// - If tapped, transition to ImportScene

// Create transitionToImport() method:
// - Clean up search text field
// - Create ImportScene and present it
```

#### 4. Update SongListScene to Display Imported Songs
**File**: `TilesRemake/SongListScene.swift`

```swift
// In filterAndRebuildImports():
// - Get songs from ImportedSongManager.shared.availableImportedSongs
// - Apply search filter if query is not empty
// - Calculate/retrieve difficulty for each song
// - Sort by difficulty, then by name
// - Set filteredSongs and call rebuildSongList()
// - Show empty message if no imports
```

#### 5. Handle Difficulty Caching for Imported Songs
**File**: `TilesRemake/SongManager.swift`

```swift
// The existing SongManager.cacheDifficulty() and getCachedDifficulty()
// should work for imported songs since they use songId as the key
//
// Verify that imported song IDs don't conflict with bundled song IDs
// (they shouldn't since imported files go to a different directory with unique filenames)
```

### Success Criteria:

#### Automated Verification:
- [x] App builds without errors: `xcodebuild build`
- [x] No new compiler warnings related to import feature

#### Manual Verification:
- [ ] "Import" button appears in Imports tab header
- [ ] Tapping "Import" opens iOS file picker
- [ ] Selecting a MIDI file copies it to app storage
- [ ] Imported song appears in Imports tab with correct title (derived from filename)
- [ ] Imported song shows calculated difficulty
- [ ] Tapping play on imported song starts the game
- [ ] Game plays correctly with imported MIDI file
- [ ] Closing and reopening app preserves imported songs
- [ ] Search filter works for imported songs

**Implementation Note**: After completing Phase 1 and all verification passes, pause for user testing before proceeding to Phase 2.

---

## Phase 2: Import Customization & Preview

### Overview
Add the ability to customize display name and scroll speed before importing, plus preview gameplay.

### Changes Required:

#### 1. Create ImportPreviewScene
**New File**: `TilesRemake/ImportPreviewScene.swift`

```swift
// Create a scene that shows after file selection but before final import:
//
// UI Elements:
// - Song title (editable via UITextField, defaults to formatted filename)
// - Calculated speed display (e.g., "Speed: 1200")
// - Speed adjustment slider (UISlider, range: calculatedSpeed * 0.5 to calculatedSpeed * 1.5)
// - Current adjusted speed label that updates with slider
// - "Preview" button - launches preview gameplay
// - "Import" button - finalizes import with current settings
// - "Cancel" button - discards and returns to SongListScene
//
// State:
// - Store the temporary file URL (not yet copied to Documents)
// - Store parsed Beatmap for difficulty/speed calculation
// - Store user-adjusted displayName and customSpeed
//
// On Preview tap:
// - Create GameScene with isPreviewMode = true
// - Pass the temporary URL and current speed setting
//
// On Import tap:
// - Copy file to Documents/ImportedSongs/
// - Save to imported-songs.json with customizations
// - Transition to SongListScene
```

#### 2. Add Preview Mode to GameScene
**File**: `TilesRemake/GameScene.swift`

```swift
// Add new initializer parameter: isPreviewMode: Bool = false
// Add private property to store this flag

// In showStartScreen() or setupLayout():
// - If isPreviewMode, add an "Exit Preview" button in top-left corner
// - Style it to be clearly visible during gameplay

// In touchesBegan():
// - Handle exit preview button tap
// - If tapped, call exitPreview()

// Create exitPreview() method:
// - Stop audio, clean up tiles
// - Transition back to ImportPreviewScene (need to preserve its state somehow)
// - OR: Use a completion handler / delegate pattern to notify ImportPreviewScene

// In showGameOverScreen() and anywhere progress is saved:
// - If isPreviewMode, skip progress saving (don't update high scores, stars, etc.)
// - Maybe show different UI: "Preview Complete" instead of "Game Over"
```

#### 3. Update ImportScene Flow
**File**: `TilesRemake/ImportScene.swift`

```swift
// After file selection from document picker:
// - Instead of immediately importing, transition to ImportPreviewScene
// - Pass the selected file URL to ImportPreviewScene
// - ImportPreviewScene handles the rest of the flow
```

#### 4. Update ImportedSongManager for Custom Settings
**File**: `TilesRemake/ImportedSongManager.swift`

```swift
// Update importSong method signature:
// - importSong(from: URL, displayName: String, customSpeed: CGFloat?)
//
// Store customSpeed in ImportedSongData struct
// Pass customSpeed when creating SongInfo for imported songs
```

### Success Criteria:

#### Automated Verification:
- [ ] App builds without errors
- [ ] No new compiler warnings

#### Manual Verification:
- [ ] After selecting file, ImportPreviewScene appears
- [ ] Display name field shows formatted filename, is editable
- [ ] Speed slider shows calculated speed as default
- [ ] Adjusting slider updates speed display
- [ ] "Preview" button launches gameplay in preview mode
- [ ] "Exit Preview" button appears during preview gameplay
- [ ] Exiting preview returns to ImportPreviewScene with settings preserved
- [ ] Preview mode does NOT save progress/high scores
- [ ] "Import" saves song with custom display name
- [ ] "Import" saves song with adjusted speed if changed
- [ ] Imported song plays at the custom speed
- [ ] "Cancel" discards file and returns to song list

**Implementation Note**: After completing Phase 2 and all verification passes, pause for user testing before proceeding to Phase 3.

---

## Phase 3: Song Management

### Overview
Add ability to delete imported songs and edit their settings after import.

### Changes Required:

#### 1. Add Delete Functionality to Imported Song Rows
**File**: `TilesRemake/SongListScene.swift`

```swift
// For imported songs only, add a delete button (trash icon) to each row
// - Position it appropriately (maybe left of the heart icon, or use swipe-to-delete)
//
// In touchesBegan() or new gesture handler:
// - Detect delete button tap
// - Show confirmation alert (UIAlertController)
// - On confirm, call ImportedSongManager.shared.deleteImportedSong(id:)
// - Rebuild the imports list
//
// Need to track which songs are imported vs bundled in the UI
// - Could add a property to SongInfo: isImported: Bool
// - Or check if song.id exists in ImportedSongManager
```

#### 2. Add Edit Functionality for Imported Songs
**File**: `TilesRemake/SongListScene.swift`

```swift
// For imported songs, add an edit button (pencil icon or gear icon)
//
// On edit tap:
// - Transition to ImportPreviewScene (or new EditImportedSongScene)
// - Pre-populate with existing settings
// - Allow changing display name and speed
// - "Save" updates the existing entry
// - "Cancel" discards changes
```

#### 3. Update ImportedSongManager for Edit/Delete
**File**: `TilesRemake/ImportedSongManager.swift`

```swift
// Add deleteImportedSong(id: String) method:
// - Remove entry from imported-songs.json
// - Delete the MIDI file from Documents/ImportedSongs/
// - Remove from availableImportedSongs array
// - Clear any cached difficulty for this song
//
// Add updateImportedSong(id: String, displayName: String, customSpeed: CGFloat?) method:
// - Update entry in imported-songs.json
// - Rebuild the corresponding SongInfo in availableImportedSongs
```

#### 4. Visual Distinction for Imported Songs
**File**: `TilesRemake/SongListScene.swift`

```swift
// In createSongRow(), if song is imported:
// - Show edit and delete buttons
// - Optionally show a small "Imported" badge or different category label
// - Could use a slightly different background color for visual distinction
```

### Success Criteria:

#### Automated Verification:
- [ ] App builds without errors
- [ ] No new compiler warnings

#### Manual Verification:
- [ ] Delete button appears only on imported song rows
- [ ] Delete button shows confirmation dialog
- [ ] Confirming delete removes song from list
- [ ] Deleted song file is removed from device storage
- [ ] App restart confirms song is permanently deleted
- [ ] Edit button appears only on imported song rows
- [ ] Edit screen shows current settings
- [ ] Saving edits updates display name in list
- [ ] Saving edits updates custom speed for gameplay
- [ ] Canceling edit preserves original settings

---

## Testing Strategy

### Unit Tests:
- ImportedSongManager: file operations, JSON persistence, song list building
- File path handling: unique filename generation, path validation

### Integration Tests:
- Full import flow: select → preview → customize → import → play
- Persistence: import song, close app, reopen, verify song exists
- Delete flow: delete song, verify removed from storage and UI

### Manual Testing Steps:
1. Import a simple MIDI file (few notes, short duration)
2. Import a complex MIDI file (many notes, long duration)
3. Import a file with special characters in name
4. Try to import a non-MIDI file (should fail gracefully)
5. Import multiple songs, verify all appear correctly
6. Delete an imported song mid-list, verify UI updates
7. Edit imported song settings, verify changes persist
8. Test on device with limited storage (edge case)

## Performance Considerations

- **File Copying**: Use FileManager.copyItem for efficient file copy
- **MIDI Parsing**: Parse asynchronously to avoid blocking UI during difficulty calculation
- **Large Files**: Consider file size limits or warnings for very large MIDI files
- **Storage**: Display storage usage in Imports tab header (optional, future enhancement)

## Migration Notes

- No migration needed for Phase 1 (new feature)
- Future imports schema changes should version the JSON format
- Include schema version in imported-songs.json for future compatibility

## References

- Scene transitions pattern: `SongListScene.swift:790-806`
- UITextField integration with SpriteKit: `SongListScene.swift:305-330`
- Song row creation: `SongListScene.swift:460-600`
- GameScene initialization: `GameScene.swift:34-43`
- Scroll speed calculation: `GameScene.swift:131-145`
- Song settings JSON format: `Songs/song-settings.json`
