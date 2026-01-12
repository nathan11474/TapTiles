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

    // Long tile tracking
    private var heldLongTile: TileNode?
    private var heldTouchLocation: CGPoint = .zero  // Where the finger is during hold

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

        // Get note duration for audio decay
        let noteDuration = firstNote?.noteDuration ?? 0.5

        // Play tile represents the current note, so advance to the next one
        if beatmap != nil {
            currentNoteIndex += 1
        }

        let tile = TileNode(column: column, size: tileSize, tileLength: tileLength, midiNotes: midiNotes, noteDuration: noteDuration)

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
            AudioManager.shared.playShortNotes(tile.midiNotes, duration: tile.noteDuration)
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

    private func startGameWithLongPlayTile(_ tile: TileNode, touchLocation: CGPoint) {
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
        heldLongTile = tile
        heldTouchLocation = touchLocation

        // Play the sustained notes (lasts until tile is released)
        AudioManager.shared.playSustainedNotes(tile.midiNotes)

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
                    startGameWithLongPlayTile(tile, touchLocation: location)
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
                handlePlayingTouch(at: location)

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
    private func handlePlayingTouch(at location: CGPoint) {
        // First check if tapping a long tile's bottom segment
        if let longTile = findLongTileBottomSegment(at: location) {
            // Start holding the long tile
            longTile.isBeingHeld = true
            longTile.fingerY = location.y
            heldLongTile = longTile
            heldTouchLocation = location

            // Play the sustained notes (lasts until tile is released)
            AudioManager.shared.playSustainedNotes(longTile.midiNotes)

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
            // Touching the currently held long tile - ignore
        } else {
            triggerGameOver()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard gameState == .playing, let heldTile = heldLongTile else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Don't update heldTouchLocation - segment completion is based on initial touch position
        // Only check X bounds to ensure finger stays in the tile's column
        let tileLeft = heldTile.position.x - heldTile.size.width / 2 - TileNode.hitboxPadding
        let tileRight = heldTile.position.x + heldTile.size.width / 2 + TileNode.hitboxPadding

        if location.x < tileLeft || location.x > tileRight {
            // Finger left the tile's column - game over
            heldTile.isBeingHeld = false
            heldLongTile = nil
            triggerGameOver()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard gameState == .playing, let heldTile = heldLongTile else { return }

        // Released the long tile - complete it (user loses remaining points but no game over)
        completeLongTile(heldTile)
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
        guard let heldTile = heldLongTile else { return false }
        return heldTile.hitboxFrame.contains(point)
    }

    private func handleTileTap(_ tile: TileNode) {
        // For double tile pairs: first tap plays first note, second tap plays second note
        // This ensures musical order is preserved regardless of which physical tile is tapped first
        if tile.isDoubleTilePair, let pairNotes = tile.pairNotes, let pairDurations = tile.pairDurations {
            // Check if sibling is still in activeTiles
            let siblingStillActive = tile.siblingTile.map { sibling in
                activeTiles.contains(where: { $0 === sibling })
            } ?? false

            if siblingStillActive {
                // First tap of the pair - play the first note in musical order
                AudioManager.shared.playShortNotes(pairNotes[0], duration: pairDurations[0])
            } else {
                // Second tap of the pair - play the second note in musical order
                AudioManager.shared.playShortNotes(pairNotes[1], duration: pairDurations[1])
            }
        } else {
            // Normal tile - play its assigned notes
            AudioManager.shared.playShortNotes(tile.midiNotes, duration: tile.noteDuration)
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
        // If tile was fully completed, let the notes decay naturally
        // If released early, stop immediately
        if tile.isFullyCompleted() {
            AudioManager.shared.stopNotesAfterDelay(tile.midiNotes, delay: tile.noteDuration)
        } else {
            AudioManager.shared.stopNotes(tile.midiNotes)
        }

        // Tile is already transparent from segment completion
        tile.makeTransparent()

        // Move from active to tapped tiles
        activeTiles.removeAll { $0 === tile }
        tappedTiles.append(tile)

        // Clear held tile reference
        tile.isBeingHeld = false
        heldLongTile = nil

        // Points already awarded per segment, no additional points needed
        updateScoreDisplay()
    }

    // MARK: - Game Over

    private func triggerGameOver() {
        // Stop any sustained notes if holding a long tile
        if let heldTile = heldLongTile {
            AudioManager.shared.stopNotes(heldTile.midiNotes)
            heldLongTile = nil
        }

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

        // Clear held long tile
        heldLongTile = nil

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

            // Store both notes in musical order - first tap plays first note, second tap plays second
            let pairNotes: [[UInt8]] = [note.midiNotes, secondNotes]
            let pairDurations: [TimeInterval] = [note.noteDuration, note.secondTileNoteDuration ?? 0.5]

            let firstTile = TileNode(
                column: columns[0],
                size: tileSize,
                tileLength: 1,
                midiNotes: note.midiNotes,
                noteDuration: note.noteDuration
            )
            firstTile.pairNotes = pairNotes
            firstTile.pairDurations = pairDurations
            firstTile.position = CGPoint(x: columnPositions[columns[0]], y: yPosition)
            addChild(firstTile)
            activeTiles.append(firstTile)

            let secondTile = TileNode(
                column: columns[1],
                size: tileSize,
                tileLength: 1,
                midiNotes: secondNotes,
                noteDuration: note.secondTileNoteDuration ?? 0.5
            )
            secondTile.pairNotes = pairNotes
            secondTile.pairDurations = pairDurations
            secondTile.position = CGPoint(x: columnPositions[columns[1]], y: yPosition)
            addChild(secondTile)
            activeTiles.append(secondTile)

            // Link them as siblings
            firstTile.siblingTile = secondTile
            secondTile.siblingTile = firstTile

            return 1
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

        let tile = TileNode(column: column, size: tileSize, tileLength: tileLength, midiNotes: note.midiNotes, noteDuration: note.noteDuration)

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

        // Update held long tile - check for segment completion
        if let heldTile = heldLongTile {
            // Update segments based on finger position
            let completedCount = heldTile.updateSegmentsForHold(fingerY: heldTouchLocation.y)

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
        // Skip the currently held tile - its completion is handled by segment logic
        // For long tiles, check the top of the first (bottom) segment, not the whole tile
        for tile in activeTiles {
            if tile === heldLongTile {
                continue  // Skip held tile
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
