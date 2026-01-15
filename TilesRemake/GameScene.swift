//
//  GameScene.swift
//  TilesRemake
//

import SpriteKit

class GameScene: SKScene {

    // MARK: - Game State

    private enum GameState {
        case waiting
        case playing
        case gameOver
    }

    private var gameState: GameState = .waiting

    // MARK: - Song

    private let songURL: URL
    private let customSpeed: CGFloat?  // Optional custom speed override
    private let startFromNote: Int?    // Optional note index to start from

    // MARK: - Initializers

    init(size: CGSize, songURL: URL, customSpeed: CGFloat? = nil, startFromNote: Int? = nil) {
        self.songURL = songURL
        self.customSpeed = customSpeed
        self.startFromNote = startFromNote
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Properties

    private var tileSize: CGSize = .zero
    private var columnPositions: [CGFloat] = []

    private var activeTiles: [TileNode] = []
    private var currentSpeed: CGFloat = 0  // Will be set from beatmap tempo
    private var initialSpeed: CGFloat = 0  // Base speed from song tempo

    private var lastUpdateTime: TimeInterval = 0

    private var playTile: TileNode?
    private var spawnThreshold: CGFloat = 0

    private var score: Int = 0
    private var scoreLabel: SKLabelNode?
    private var tappedTiles: [TileNode] = []

    // Long tile tracking (supports multiple simultaneous holds for double-long-tiles)
    private var heldLongTiles: [TileNode] = []

    // Beatmap properties
    private var beatmap: Beatmap?
    private var currentNoteIndex: Int = 0
    private var songStartTime: TimeInterval = 0

    // Relative thresholds (calculated from song's average gap)
    private var longTileThreshold: TimeInterval = 0.5  // Gaps longer than this become long tiles
    private var segmentDuration: TimeInterval = 0.4    // Duration per long tile segment

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .white
        view.isMultipleTouchEnabled = true  // Enable simultaneous touch detection
        AudioManager.shared.setup()
        loadBeatmap()
        setupLayout()
        showStartScreen()
    }

    private func loadBeatmap() {
        let parser = MidiParser()
        if let loadedBeatmap = parser.parse(url: songURL) {
            beatmap = loadedBeatmap

            // Calculate relative thresholds based on song's average gap
            longTileThreshold = loadedBeatmap.averageGap * GameConfig.longTileGapMultiplier
            segmentDuration = loadedBeatmap.averageGap * GameConfig.tileSegmentMultiplier

            // Use custom speed if provided, otherwise calculate from note density
            if let custom = customSpeed {
                initialSpeed = custom
                print("GameScene: Loaded beatmap '\(loadedBeatmap.title)' - using custom speed: \(String(format: "%.0f", initialSpeed))")
            } else {
                // Calculate initial speed based on note density (notes per second)
                // This ensures songs with sparse notes don't feel too slow
                // and songs with dense notes don't feel too rushed
                let notesPerSecond = CGFloat(loadedBeatmap.notes.count) / CGFloat(loadedBeatmap.totalDuration)
                let estimatedTileHeight = size.height / GameConfig.visibleTileCount

                // Speed = tile height × notes per second
                // This means one tile scrolls past per note on average
                initialSpeed = estimatedTileHeight * notesPerSecond

                print("GameScene: Loaded beatmap '\(loadedBeatmap.title)' - \(loadedBeatmap.notes.count) notes, \(String(format: "%.1f", loadedBeatmap.totalDuration))s, trimmed mean gap: \(String(format: "%.3f", loadedBeatmap.averageGap))s, threshold: \(String(format: "%.3f", longTileThreshold))s, speed: \(String(format: "%.0f", initialSpeed))")
            }
            currentSpeed = initialSpeed

            // Preload all instruments used in the song
            var usedInstruments = Set<UInt8>()
            for note in loadedBeatmap.notes {
                usedInstruments.formUnion(note.instruments)
                if let secondInstruments = note.secondTileInstruments {
                    usedInstruments.formUnion(secondInstruments)
                }
            }
            AudioManager.shared.preloadInstruments(usedInstruments)
        } else {
            print("GameScene: Failed to parse MIDI file at \(songURL)")
            // Fallback to default speed if no beatmap (~2 notes/sec)
            let estimatedTileHeight = size.height / GameConfig.visibleTileCount
            initialSpeed = estimatedTileHeight * 2.0
            currentSpeed = initialSpeed
        }
    }

    // MARK: - Layout Setup

    private func setupLayout() {
        tileSize = GameConfig.tileSize(for: size)

        // Calculate x-position for center of each column
        let tileWidth = tileSize.width
        columnPositions = (0..<GameConfig.columnCount).map { column in
            tileWidth * CGFloat(column) + tileWidth / 2
        }

        // Add column divider lines
        for i in 1..<GameConfig.columnCount {
            let xPos = tileWidth * CGFloat(i)
            let line = SKShapeNode(rectOf: CGSize(width: 1, height: size.height))
            line.position = CGPoint(x: xPos, y: size.height / 2)
            line.strokeColor = UIColor.lightGray.withAlphaComponent(0.3)
            line.lineWidth = 1
            addChild(line)
        }
    }

    // MARK: - Start Screen

    private func showStartScreen() {
        // Reset note index for new game (or skip to startFromNote if set)
        let startIndex = startFromNote ?? 0
        currentNoteIndex = min(startIndex, (beatmap?.notes.count ?? 1) - 1)

        // Create a "Play" tile at the bottom of the screen
        let column = Int.random(in: 0..<GameConfig.columnCount)

        // Get the starting note from the beatmap
        let firstNote: NoteEvent?
        if let notes = beatmap?.notes, currentNoteIndex < notes.count {
            firstNote = notes[currentNoteIndex]
        } else {
            firstNote = nil
        }
        let midiNotes = firstNote?.midiNotes ?? [GameConfig.randomNote()]

        // Determine tile length based on gap to next note (if beatmap exists)
        let tileLength: Int
        if let note = firstNote, note.gapToNextNote > longTileThreshold {
            let calculatedLength = Int(round(note.gapToNextNote / segmentDuration))
            // If calculation gives < 2, just make it a normal tile
            tileLength = calculatedLength >= 2 ? min(calculatedLength, GameConfig.longTileMaxLength) : 1
        } else {
            tileLength = 1
        }

        // Get note durations for audio decay (individual per note in chord)
        let noteDurations = firstNote?.noteDurations ?? [0.5]
        let instruments = firstNote?.instruments ?? [0]

        // Play tile represents the current note, so advance to the next one
        if beatmap != nil {
            currentNoteIndex += 1
        }

        let tile = TileNode(column: column, size: tileSize, tileLength: tileLength, midiNotes: midiNotes, noteDurations: noteDurations, instruments: instruments)

        // Position at the bottom of the screen (so bottom edge touches screen bottom)
        // For long tiles, the center is higher due to larger size
        tile.position = CGPoint(
            x: columnPositions[column],
            y: tile.size.height / 2
        )

        // Add "Play" label to the first (bottom) segment
        let playLabel = SKLabelNode(text: "Play")
        playLabel.fontName = "Helvetica-Bold"
        playLabel.fontSize = 36
        playLabel.fontColor = .white
        playLabel.verticalAlignmentMode = .center
        playLabel.horizontalAlignmentMode = .center
        playLabel.zPosition = 10
        // Position label at center of first segment (relative to tile center)
        let firstSegmentCenterY = -tile.size.height / 2 + tileSize.height / 2
        playLabel.position = CGPoint(x: 0, y: firstSegmentCenterY)
        tile.addChild(playLabel)

        addChild(tile)
        playTile = tile

        // Spawn tiles above the Play tile (visible but stationary until game starts)
        spawnInitialTiles()
    }

    private func startGame() {
        // Handle the play tile like a normal tile tap (for non-long tiles)
        if let tile = playTile {
            AudioManager.shared.playShortNotes(tile.midiNotes, durations: tile.noteDurations, instruments: tile.instruments)
            tile.makeTransparent()
            tappedTiles.append(tile)
            score += 1
        }
        playTile = nil

        gameState = .playing
        songStartTime = 0  // Will be set on first update
        setupScoreLabel()
        updateScoreDisplay()
    }

    private func startGameWithLongPlayTile(_ tile: TileNode, touchLocation: CGPoint, touch: UITouch) {
        // Start the game
        gameState = .playing
        songStartTime = 0  // Will be set on first update
        setupScoreLabel()

        // Add Play tile to active tiles so it's tracked during gameplay
        activeTiles.append(tile)
        playTile = nil

        // Start holding the long tile (same as normal long tile behavior)
        tile.isBeingHeld = true
        tile.fingerY = touchLocation.y
        tile.holdingTouch = touch
        tile.currentlyPlayingNotes = tile.midiNotes
        tile.currentlyPlayingDurations = tile.noteDurations
        tile.currentlyPlayingInstruments = tile.instruments
        heldLongTiles.append(tile)

        // Play the sustained notes (lasts until tile is released)
        AudioManager.shared.playSustainedNotes(tile.midiNotes, instruments: tile.instruments)

        // Complete the first segment and award 1 point
        tile.completeFirstSegment()
        score += 1
        updateScoreDisplay()
    }

    // MARK: - Score Display

    private func setupScoreLabel() {
        let label = SKLabelNode(text: "0")
        label.fontName = "Helvetica-Bold"
        label.fontSize = 32
        label.fontColor = .red
        label.position = CGPoint(x: size.width / 2, y: size.height - 80)
        label.zPosition = 100
        addChild(label)
        scoreLabel = label
    }

    private func updateScoreDisplay() {
        scoreLabel?.text = "\(score)"
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch gameState {
        case .waiting:
            // Only need first touch for starting the game
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)

            guard let tile = playTile else { return }

            if tile.isLongTile {
                // Long Play tile - must tap bottom segment and hold like normal long tiles
                if tile.isBottomSegmentTapped(at: location) {
                    startGameWithLongPlayTile(tile, touchLocation: location, touch: touch)
                }
            } else {
                // Normal Play tile - single tap to start
                if tile.hitboxFrame.contains(location) {
                    startGame()
                }
            }

        case .playing:
            // Process ALL touches to handle simultaneous taps (e.g., double tiles)
            for touch in touches {
                let location = touch.location(in: self)
                handlePlayingTouch(at: location, touch: touch)

                // Stop processing if game ended
                if gameState != .playing { break }
            }

        case .gameOver:
            // Only need first touch for buttons
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)

            if let restartButton = childNode(withName: "restartButton"),
               restartButton.contains(location) {
                restartGame()
            } else if let exitButton = childNode(withName: "exitButton"),
                      exitButton.contains(location) {
                exitToSongList()
            }
        }
    }

    /// Handle a single touch during gameplay
    private func handlePlayingTouch(at location: CGPoint, touch: UITouch) {
        // First check if tapping a long tile's bottom segment
        if let longTile = findLongTileBottomSegment(at: location) {
            // Start holding the long tile
            longTile.isBeingHeld = true
            longTile.fingerY = location.y
            longTile.holdingTouch = touch
            heldLongTiles.append(longTile)

            // For double-long-tile pairs: first tap plays first note, second tap plays second note
            if longTile.isDoubleTilePair, let pairNotes = longTile.pairNotes, let pairDurations = longTile.pairDurations, let pairInstruments = longTile.pairInstruments {
                // Check if sibling is NOT yet being held (i.e., we're the first to be tapped)
                // For long tiles, we check heldLongTiles rather than activeTiles because
                // long tiles stay in activeTiles while being held
                let siblingNotYetHeld = longTile.siblingTile.map { sibling in
                    !heldLongTiles.contains(where: { $0 === sibling })
                } ?? true

                if siblingNotYetHeld {
                    // First tap - play first notes with their instruments
                    longTile.currentlyPlayingNotes = pairNotes[0]
                    longTile.currentlyPlayingDurations = pairDurations[0]
                    longTile.currentlyPlayingInstruments = pairInstruments[0]
                    AudioManager.shared.playSustainedNotes(pairNotes[0], instruments: pairInstruments[0])
                } else {
                    // Second tap - play second notes with their instruments
                    longTile.currentlyPlayingNotes = pairNotes[1]
                    longTile.currentlyPlayingDurations = pairDurations[1]
                    longTile.currentlyPlayingInstruments = pairInstruments[1]
                    AudioManager.shared.playSustainedNotes(pairNotes[1], instruments: pairInstruments[1])
                }
            } else {
                // Normal long tile - play its notes with their instruments
                longTile.currentlyPlayingNotes = longTile.midiNotes
                longTile.currentlyPlayingDurations = longTile.noteDurations
                longTile.currentlyPlayingInstruments = longTile.instruments
                AudioManager.shared.playSustainedNotes(longTile.midiNotes, instruments: longTile.instruments)
            }

            // Immediately complete the first segment (like tapping a normal tile)
            longTile.completeFirstSegment()
            score += 1
            updateScoreDisplay()
        } else if let tile = findTile(at: location) {
            if tile.isLongTile {
                // Tapped a long tile but NOT at bottom segment - ignore
            } else {
                handleTileTap(tile)
            }
        } else if isTappedTile(at: location) {
            // Tapped a ghost tile - ignore it
        } else if isHeldLongTile(at: location) {
            // Touching a currently held long tile - ignore
        } else {
            triggerGameOver()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard gameState == .playing else { return }

        // Complete tiles whose touches ended
        for touch in touches {
            if let heldTile = heldLongTiles.first(where: { $0.holdingTouch === touch }) {
                completeLongTile(heldTile)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Treat cancelled touches same as ended
        touchesEnded(touches, with: event)
    }

    // Find a long tile where the bottom segment was tapped
    private func findLongTileBottomSegment(at point: CGPoint) -> TileNode? {
        for tile in activeTiles {
            if tile.isLongTile && tile.isBottomSegmentTapped(at: point) {
                return tile
            }
        }
        return nil
    }

    private func findTile(at point: CGPoint) -> TileNode? {
        for tile in activeTiles {
            if tile.hitboxFrame.contains(point) {
                return tile
            }
        }
        return nil
    }

    private func isTappedTile(at point: CGPoint) -> Bool {
        for tile in tappedTiles {
            if tile.hitboxFrame.contains(point) {
                return true
            }
        }
        return false
    }

    private func isHeldLongTile(at point: CGPoint) -> Bool {
        for heldTile in heldLongTiles {
            if heldTile.hitboxFrame.contains(point) {
                return true
            }
        }
        return false
    }

    private func handleTileTap(_ tile: TileNode) {
        // For double tile pairs: first tap plays first note, second tap plays second note
        // This ensures musical order is preserved regardless of which physical tile is tapped first
        if tile.isDoubleTilePair, let pairNotes = tile.pairNotes, let pairDurations = tile.pairDurations, let pairInstruments = tile.pairInstruments {
            // Check if sibling is still in activeTiles
            let siblingStillActive = tile.siblingTile.map { sibling in
                activeTiles.contains(where: { $0 === sibling })
            } ?? false

            if siblingStillActive {
                // First tap of the pair - play the first notes with their instruments
                AudioManager.shared.playShortNotes(pairNotes[0], durations: pairDurations[0], instruments: pairInstruments[0])
            } else {
                // Second tap of the pair - play the second notes with their instruments
                AudioManager.shared.playShortNotes(pairNotes[1], durations: pairDurations[1], instruments: pairInstruments[1])
            }
        } else {
            // Normal tile - play its assigned notes with their instruments
            AudioManager.shared.playShortNotes(tile.midiNotes, durations: tile.noteDurations, instruments: tile.instruments)
        }

        // Make tile transparent
        tile.makeTransparent()

        // Move from active to tapped tiles
        activeTiles.removeAll { $0 === tile }
        tappedTiles.append(tile)

        score += 1
        updateScoreDisplay()
    }

    private func completeLongTile(_ tile: TileNode) {
        // Use the tracked notes (handles double-long-tile pairs correctly)
        let notesToStop = tile.currentlyPlayingNotes ?? tile.midiNotes
        let durations = tile.currentlyPlayingDurations ?? tile.noteDurations
        let maxDuration = durations.max() ?? 0.5

        // If tile was at least half completed, let the notes decay naturally
        // If released too early (< 50%), stop immediately
        if tile.isHalfOrMoreCompleted() {
            AudioManager.shared.stopNotesAfterDelay(notesToStop, delay: maxDuration)
        } else {
            AudioManager.shared.stopNotes(notesToStop)
        }

        // Tile is already transparent from segment completion
        tile.makeTransparent()

        // Move from active to tapped tiles
        activeTiles.removeAll { $0 === tile }
        tappedTiles.append(tile)

        // Clear held tile reference
        tile.isBeingHeld = false
        tile.holdingTouch = nil
        heldLongTiles.removeAll { $0 === tile }

        // Points already awarded per segment, no additional points needed
        updateScoreDisplay()
    }

    // MARK: - Game Over

    private func triggerGameOver() {
        // Stop any sustained notes if holding long tiles
        for heldTile in heldLongTiles {
            let notesToStop = heldTile.currentlyPlayingNotes ?? heldTile.midiNotes
            AudioManager.shared.stopNotes(notesToStop)
            heldTile.isBeingHeld = false
            heldTile.holdingTouch = nil
        }
        heldLongTiles.removeAll()

        gameState = .gameOver
        showGameOverScreen()
    }

    private func showGameOverScreen() {
        // Semi-transparent overlay
        let overlay = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.5), size: size)
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 200
        overlay.name = "gameOverOverlay"
        addChild(overlay)

        // Game Over label
        let gameOverLabel = SKLabelNode(text: "Game Over")
        gameOverLabel.fontName = "Helvetica-Bold"
        gameOverLabel.fontSize = 48
        gameOverLabel.fontColor = .white
        gameOverLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 60)
        gameOverLabel.zPosition = 201
        gameOverLabel.name = "gameOverLabel"
        addChild(gameOverLabel)

        // Final score label
        let finalScoreLabel = SKLabelNode(text: "Score: \(score)")
        finalScoreLabel.fontName = "Helvetica-Bold"
        finalScoreLabel.fontSize = 32
        finalScoreLabel.fontColor = .white
        finalScoreLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        finalScoreLabel.zPosition = 201
        finalScoreLabel.name = "finalScoreLabel"
        addChild(finalScoreLabel)

        // Restart button
        let restartButton = SKLabelNode(text: "Restart")
        restartButton.fontName = "Helvetica-Bold"
        restartButton.fontSize = 36
        restartButton.fontColor = .white
        restartButton.position = CGPoint(x: size.width / 2, y: size.height / 2 - 60)
        restartButton.zPosition = 201
        restartButton.name = "restartButton"
        addChild(restartButton)

        // Exit button
        let exitButton = SKLabelNode(text: "Exit")
        exitButton.fontName = "Helvetica-Bold"
        exitButton.fontSize = 36
        exitButton.fontColor = .white
        exitButton.position = CGPoint(x: size.width / 2, y: size.height / 2 - 120)
        exitButton.zPosition = 201
        exitButton.name = "exitButton"
        addChild(exitButton)
    }

    // MARK: - Restart

    private func restartGame() {
        // Stop all playing notes
        AudioManager.shared.stopAllNotes()

        // Remove all tiles
        for tile in activeTiles {
            tile.removeFromParent()
        }
        activeTiles.removeAll()

        for tile in tappedTiles {
            tile.removeFromParent()
        }
        tappedTiles.removeAll()

        // Clear held long tiles
        heldLongTiles.removeAll()

        // Remove game over UI elements
        childNode(withName: "gameOverOverlay")?.removeFromParent()
        childNode(withName: "gameOverLabel")?.removeFromParent()
        childNode(withName: "finalScoreLabel")?.removeFromParent()
        childNode(withName: "restartButton")?.removeFromParent()
        childNode(withName: "exitButton")?.removeFromParent()

        // Reset game state
        score = 0
        currentSpeed = initialSpeed  // Reset to song's base tempo speed
        lastUpdateTime = 0

        // Reset beatmap state
        currentNoteIndex = 0
        songStartTime = 0

        // Remove score label (will be re-added when game starts)
        scoreLabel?.removeFromParent()
        scoreLabel = nil

        // Go back to waiting state with Play tile
        gameState = .waiting
        showStartScreen()
    }

    // MARK: - Navigation

    private func exitToSongList() {
        AudioManager.shared.stopAllNotes()

        let songListScene = SongListScene(size: size)
        songListScene.scaleMode = scaleMode
        let transition = SKTransition.push(with: .right, duration: 0.3)
        view?.presentScene(songListScene, transition: transition)
    }

    // MARK: - Tile Spawning

    private func spawnInitialTiles() {
        // Set spawn threshold - spawn new tile when topmost tile drops below this Y
        spawnThreshold = size.height - tileSize.height / 2

        guard beatmap != nil, let tile = playTile else { return }

        // Start spawning from just above the Play tile
        let playTileTop = tile.position.y + tile.size.height / 2
        var currentY = playTileTop + tileSize.height / 2

        // Pre-spawn tiles for notes that should be visible at game start
        // Calculate how many seconds of notes should be on screen
        let screenTimeInSeconds = GameConfig.spawnLeadTime

        while currentNoteIndex < beatmap!.notes.count {
            let note = beatmap!.notes[currentNoteIndex]

            // Check if this note should be pre-spawned (visible at start)
            if note.time > screenTimeInSeconds {
                break
            }

            let tileUnits = spawnTileForNote(note, at: currentY)
            currentY += tileSize.height * CGFloat(tileUnits)
            currentNoteIndex += 1
        }

        // Fill any remaining screen space with upcoming notes
        while currentY < size.height + tileSize.height * 3 && currentNoteIndex < beatmap!.notes.count {
            let note = beatmap!.notes[currentNoteIndex]
            let tileUnits = spawnTileForNote(note, at: currentY)
            currentY += tileSize.height * CGFloat(tileUnits)
            currentNoteIndex += 1
        }
    }

    // Column pairs for double tiles
    private static let edgeColumns = [0, 3]    // 1st and 4th columns
    private static let middleColumns = [1, 2]  // 2nd and 3rd columns

    private func spawnTileForNote(_ note: NoteEvent, at yPosition: CGFloat) -> Int {
        // Find the topmost tile(s) to avoid spawning in same column
        // Check both active and tapped tiles (tapped tiles may still be the topmost row)
        let allTiles = activeTiles + tappedTiles
        let topmostY = allTiles.map { $0.position.y }.max() ?? playTile?.position.y ?? -1000
        let topmostTiles = allTiles.filter { abs($0.position.y - topmostY) < 1 }
        let topmostColumns = Set(topmostTiles.map { $0.column })

        // Handle double tile spawning with special column constraints
        if note.isDoubleTile, let secondNotes = note.secondTileMidiNotes {
            // Double tiles spawn either on edges (0,3) or middle (1,2)
            // Must avoid columns used by topmost tiles
            let useEdges: Bool
            if topmostColumns.isEmpty {
                // No previous tiles - pick randomly
                useEdges = Bool.random()
            } else if topmostColumns.contains(0) || topmostColumns.contains(3) {
                // Previous tile(s) on edge - use middle
                useEdges = false
            } else {
                // Previous tile(s) in middle - use edges
                useEdges = true
            }

            let columns = useEdges ? GameScene.edgeColumns : GameScene.middleColumns

            // Check if this double tile should be a long tile (based on gap after the pair)
            let tileLength: Int
            if note.gapToNextNote > longTileThreshold {
                let calculatedLength = Int(round(note.gapToNextNote / segmentDuration))
                tileLength = calculatedLength >= 2 ? min(calculatedLength, GameConfig.longTileMaxLength) : 1
            } else {
                tileLength = 1
            }

            // Store both notes in musical order - first tap plays first notes, second tap plays second notes
            let pairNotes: [[UInt8]] = [note.midiNotes, secondNotes]
            let pairDurations: [[TimeInterval]] = [note.noteDurations, note.secondTileNoteDurations ?? [0.5]]
            let pairInstruments: [[UInt8]] = [note.instruments, note.secondTileInstruments ?? note.instruments]

            // Position for long tiles - center is higher due to larger size
            let tileCenterY = yPosition + (CGFloat(tileLength - 1) * tileSize.height) / 2

            let firstTile = TileNode(
                column: columns[0],
                size: tileSize,
                tileLength: tileLength,
                midiNotes: note.midiNotes,
                noteDurations: note.noteDurations,
                instruments: note.instruments
            )
            firstTile.pairNotes = pairNotes
            firstTile.pairDurations = pairDurations
            firstTile.pairInstruments = pairInstruments
            firstTile.position = CGPoint(x: columnPositions[columns[0]], y: tileCenterY)
            addChild(firstTile)
            activeTiles.append(firstTile)

            let secondTile = TileNode(
                column: columns[1],
                size: tileSize,
                tileLength: tileLength,
                midiNotes: secondNotes,
                noteDurations: note.secondTileNoteDurations ?? [0.5],
                instruments: note.secondTileInstruments ?? note.instruments
            )
            secondTile.pairNotes = pairNotes
            secondTile.pairDurations = pairDurations
            secondTile.pairInstruments = pairInstruments
            secondTile.position = CGPoint(x: columnPositions[columns[1]], y: tileCenterY)
            addChild(secondTile)
            activeTiles.append(secondTile)

            // Link them as siblings
            firstTile.siblingTile = secondTile
            secondTile.siblingTile = firstTile

            return tileLength
        }

        // Single tile spawning - avoid all columns from topmost row
        var availableColumns = Array(0..<GameConfig.columnCount)

        if !topmostColumns.isEmpty {
            availableColumns.removeAll { topmostColumns.contains($0) }
        } else if let excludeColumn = playTile?.column {
            availableColumns.removeAll { $0 == excludeColumn }
        }

        // If all columns are taken (shouldn't happen with 4 columns and max 2 tiles per row)
        // fall back to any column
        let column = availableColumns.randomElement() ?? Int.random(in: 0..<GameConfig.columnCount)

        // Determine tile length based on gap to next note (relative to song's average gap)
        let tileLength: Int
        if note.gapToNextNote > longTileThreshold {
            let calculatedLength = Int(round(note.gapToNextNote / segmentDuration))
            tileLength = calculatedLength >= 2 ? min(calculatedLength, GameConfig.longTileMaxLength) : 1
        } else {
            tileLength = 1
        }

        let tile = TileNode(column: column, size: tileSize, tileLength: tileLength, midiNotes: note.midiNotes, noteDurations: note.noteDurations, instruments: note.instruments)

        // Position tile - for long tiles, the center is higher due to larger size
        let tileCenterY = yPosition + (CGFloat(tileLength - 1) * tileSize.height) / 2
        tile.position = CGPoint(
            x: columnPositions[column],
            y: tileCenterY
        )

        addChild(tile)
        activeTiles.append(tile)

        return tileLength
    }

    // MARK: - Game Loop

    override func update(_ currentTime: TimeInterval) {
        guard gameState == .playing else { return }

        // Calculate delta time
        let deltaTime: TimeInterval
        if lastUpdateTime == 0 {
            deltaTime = 0
            songStartTime = currentTime  // Record song start on first update
        } else {
            deltaTime = currentTime - lastUpdateTime
        }
        lastUpdateTime = currentTime

        guard deltaTime > 0 else { return }

        // Increase speed over time (no cap - speed increases indefinitely)
        currentSpeed += GameConfig.speedIncreaseRate * CGFloat(deltaTime)

        // Move all tiles down
        let moveDistance = currentSpeed * CGFloat(deltaTime)
        for tile in activeTiles {
            tile.position.y -= moveDistance
        }
        for tile in tappedTiles {
            tile.position.y -= moveDistance
        }

        // Update all held long tiles - check for segment completion
        for heldTile in heldLongTiles {
            // Update segments based on finger position (stored on tile)
            let completedCount = heldTile.updateSegmentsForHold(fingerY: heldTile.fingerY)

            // Award points for each newly completed segment
            if completedCount > 0 {
                score += completedCount
                updateScoreDisplay()
            }

            // Check if all segments are complete
            if heldTile.isFullyCompleted() {
                completeLongTile(heldTile)
            }
        }

        // Remove tapped tiles that have scrolled off the bottom
        tappedTiles.removeAll { tile in
            let tileBottom = tile.position.y - tile.size.height / 2
            if tileBottom < -tile.size.height {
                tile.removeFromParent()
                return true
            }
            return false
        }

        // Check if any tile has scrolled off the bottom - triggers game over
        // Skip currently held tiles - their completion is handled by segment logic
        // For long tiles, check the top of the first (bottom) segment, not the whole tile
        for tile in activeTiles {
            if heldLongTiles.contains(where: { $0 === tile }) {
                continue  // Skip held tiles
            }
            if tile.firstSegmentTop < 0 {
                triggerGameOver()
                return
            }
        }

        // Beatmap-driven spawning
        if let beatmap = beatmap {
            // Spawn tiles when topmost tile has moved down enough and there are more notes
            while currentNoteIndex < beatmap.notes.count {
                // Find the topmost tile - check active tiles first, then tapped tiles as fallback
                let topmostActive = activeTiles.max(by: { $0.position.y < $1.position.y })
                let topmostTapped = tappedTiles.max(by: { $0.position.y < $1.position.y })

                // Use whichever is higher (or the one that exists)
                let topmostTile: TileNode?
                if let active = topmostActive, let tapped = topmostTapped {
                    topmostTile = active.position.y > tapped.position.y ? active : tapped
                } else {
                    topmostTile = topmostActive ?? topmostTapped
                }

                if let topTile = topmostTile {
                    let topmostTileTop = topTile.position.y + topTile.size.height / 2
                    if topmostTileTop <= spawnThreshold + tileSize.height / 2 {
                        let note = beatmap.notes[currentNoteIndex]
                        let newY = topmostTileTop + tileSize.height / 2
                        _ = spawnTileForNote(note, at: newY)
                        currentNoteIndex += 1
                    } else {
                        break
                    }
                } else {
                    // No tiles at all - spawn at top of screen
                    let note = beatmap.notes[currentNoteIndex]
                    _ = spawnTileForNote(note, at: size.height + tileSize.height / 2)
                    currentNoteIndex += 1
                }
            }

            // Loop the song when all notes have been spawned
            if currentNoteIndex >= beatmap.notes.count {
                currentNoteIndex = 0  // Reset to beginning for infinite loop
            }
        }
    }

}
