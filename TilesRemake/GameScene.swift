//
//  GameScene.swift
//  TilesRemake
//

import SpriteKit
import UIKit

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

    /// Song identifier for progress tracking
    private var songId: String {
        return songURL.deletingPathExtension().lastPathComponent
    }

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

    // MARK: - Progression System

    private enum ProgressionTier {
        case stars      // First playthrough: earn 1-3 stars
        case crowns     // Second playthrough: earn 1-3 crowns
        case endless    // After 3 crowns: no more levels
    }

    private var progressionTier: ProgressionTier = .stars
    private var currentStars: Int = 0           // 0-3 stars earned
    private var currentCrowns: Int = 0          // 0-3 crowns earned
    private var loopCount: Int = 0              // How many times song has fully looped
    private var notesPlayedInCurrentLoop: Int = 0  // Notes played in current loop iteration
    private var totalNotesInSong: Int = 0       // Cached note count for easy access

    // Gap period after 3 stars (pause before crowns phase)
    private var isInGapPeriod: Bool = false
    private var gapStartTime: TimeInterval = 0
    private let gapDuration: TimeInterval = 3.0  // 3 second gap for animation (must be longer than level-up animation ~2.75s)

    // UI elements for progression display
    private var progressionContainer: SKNode?
    private var starNodes: [SKNode] = []
    private var crownNodes: [SKNode] = []

    // Song info bar (shown before game starts)
    private var songInfoBar: SKNode?
    private let songInfoBarHeight: CGFloat = 150

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
            totalNotesInSong = loadedBeatmap.notes.count

            // Calculate relative thresholds based on song's average gap
            longTileThreshold = loadedBeatmap.averageGap * GameConfig.longTileGapMultiplier
            segmentDuration = loadedBeatmap.averageGap * GameConfig.tileSegmentMultiplier

            // Use custom speed if provided, otherwise calculate from note density
            if let custom = customSpeed {
                initialSpeed = custom
                #if DEBUG
                print("GameScene: Loaded beatmap '\(loadedBeatmap.title)' - using custom speed: \(String(format: "%.0f", initialSpeed))")
                #endif
            } else {
                // Calculate initial speed based on note density (notes per second)
                // This ensures songs with sparse notes don't feel too slow
                // and songs with dense notes don't feel too rushed
                let notesPerSecond = CGFloat(loadedBeatmap.notes.count) / CGFloat(loadedBeatmap.totalDuration)
                let estimatedTileHeight = size.height / GameConfig.visibleTileCount

                // Speed = tile height × notes per second
                // This means one tile scrolls past per note on average
                initialSpeed = estimatedTileHeight * notesPerSecond

                #if DEBUG
                print("GameScene: Loaded beatmap '\(loadedBeatmap.title)' - \(loadedBeatmap.notes.count) notes, \(String(format: "%.1f", loadedBeatmap.totalDuration))s, trimmed mean gap: \(String(format: "%.3f", loadedBeatmap.averageGap))s, threshold: \(String(format: "%.3f", longTileThreshold))s, speed: \(String(format: "%.0f", initialSpeed))")
                #endif
            }
            currentSpeed = initialSpeed

        } else {
            #if DEBUG
            print("GameScene: Failed to parse MIDI file at \(songURL)")
            #endif
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
            let line = SKSpriteNode(color: UIColor.lightGray.withAlphaComponent(0.3), size: CGSize(width: 1, height: size.height))
            line.position = CGPoint(x: xPos, y: size.height / 2)
            addChild(line)
        }
    }

    // MARK: - Start Screen

    private func showStartScreen() {
        // Create song info bar at bottom
        createSongInfoBar()

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
        let gapToNextNote = firstNote?.gapToNextNote ?? 0.5
        let sustainPedalOn = firstNote?.sustainPedalOn ?? false

        // Play tile represents the current note, so advance to the next one
        if beatmap != nil {
            currentNoteIndex += 1
        }

        let tile = TileNode(column: column, size: tileSize, tileLength: tileLength, midiNotes: midiNotes, noteDurations: noteDurations, gapToNextNote: gapToNextNote, sustainPedalOn: sustainPedalOn)

        // Position above the song info bar (so bottom edge touches top of bar)
        tile.position = CGPoint(
            x: columnPositions[column],
            y: songInfoBarHeight + tile.size.height / 2
        )

        // Add "Play" label to the first (bottom) segment
        let playLabel = SKLabelNode(text: "Play")
        playLabel.name = "playLabel"
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

    private func createSongInfoBar() {
        let bar = SKNode()
        bar.zPosition = 50

        // Background (white)
        let background = SKSpriteNode(color: .white, size: CGSize(width: size.width, height: songInfoBarHeight))
        background.anchorPoint = CGPoint(x: 0, y: 0)
        background.position = .zero
        bar.addChild(background)

        // Top border (black line)
        let borderHeight: CGFloat = 2
        let border = SKSpriteNode(color: .black, size: CGSize(width: size.width, height: borderHeight))
        border.anchorPoint = CGPoint(x: 0, y: 0)
        border.position = CGPoint(x: 0, y: songInfoBarHeight - borderHeight)
        bar.addChild(border)

        let leftPadding: CGFloat = 20
        let iconSize = CGSize(width: 24, height: 24)
        let iconTextSpacing: CGFloat = 10
        let rowSpacing: CGFloat = 30  // Vertical spacing between rows

        // Music note icon for song title (light purple, matching long tile fill color)
        let iconColor = TileNode.longTileFillColor
        if let musicIcon = renderSongInfoIcon(symbolName: "music.note", color: iconColor, size: iconSize) {
            let musicIconNode = SKSpriteNode(texture: musicIcon)
            musicIconNode.position = CGPoint(x: leftPadding + iconSize.width / 2, y: songInfoBarHeight / 2 + rowSpacing)
            bar.addChild(musicIconNode)
        }

        // Song title (use displayName from config if available, otherwise format from filename)
        let songTitle = SongManager.shared.availableSongs.first(where: { $0.id == songId })?.title ?? SongInfo.formatTitle(from: songId)
        let titleLabel = SKLabelNode(text: songTitle)
        titleLabel.fontName = "Helvetica"
        titleLabel.fontSize = 22
        titleLabel.fontColor = .black
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: leftPadding + iconSize.width + iconTextSpacing, y: songInfoBarHeight / 2 + rowSpacing)

        // Truncate if too long
        let maxWidth = size.width - leftPadding - iconSize.width - iconTextSpacing - 20  // 20px right padding
        truncateLabelIfNeeded(titleLabel, maxWidth: maxWidth)

        bar.addChild(titleLabel)

        // Trophy icon for high score (purple, matching long tile color)
        if let trophyIcon = renderSongInfoIcon(symbolName: "trophy.fill", color: iconColor, size: iconSize) {
            let trophyIconNode = SKSpriteNode(texture: trophyIcon)
            trophyIconNode.position = CGPoint(x: leftPadding + iconSize.width / 2, y: songInfoBarHeight / 2 - rowSpacing)
            bar.addChild(trophyIconNode)
        }

        // High score
        let progress = ProgressManager.shared.getProgress(for: songId, fileURL: songURL)
        let highScoreText = progress.highScore > 0 ? "High Score: \(progress.highScore)" : "No high score yet"
        let highScoreLabel = SKLabelNode(text: highScoreText)
        highScoreLabel.fontName = "Helvetica"
        highScoreLabel.fontSize = 22
        highScoreLabel.fontColor = .black
        highScoreLabel.horizontalAlignmentMode = .left
        highScoreLabel.verticalAlignmentMode = .center
        highScoreLabel.position = CGPoint(x: leftPadding + iconSize.width + iconTextSpacing, y: songInfoBarHeight / 2 - rowSpacing)
        bar.addChild(highScoreLabel)

        addChild(bar)
        songInfoBar = bar
    }

    private func renderSongInfoIcon(symbolName: String, color: UIColor, size: CGSize) -> SKTexture? {
        let config = UIImage.SymbolConfiguration(pointSize: size.height, weight: .regular)
        guard let symbolImage = UIImage(systemName: symbolName, withConfiguration: config) else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            // Draw symbol stretched to fill the square bounds
            let drawRect = CGRect(origin: .zero, size: size)
            symbolImage.draw(in: drawRect, blendMode: .normal, alpha: 1.0)
            context.fill(drawRect, blendMode: .sourceIn)
        }
        return SKTexture(image: image)
    }

    private func truncateLabelIfNeeded(_ label: SKLabelNode, maxWidth: CGFloat) {
        guard var text = label.text, label.frame.width > maxWidth else { return }

        while label.frame.width > maxWidth && text.count > 1 {
            text = String(text.dropLast())
            label.text = text + "..."
        }
    }

    private func hideSongInfoBar() {
        // Bar will scroll away with the game movement in update()
        // Just mark it for removal once off-screen
    }

    private func startGame() {
        // Hide the song info bar
        hideSongInfoBar()

        // Handle the play tile like a normal tile tap (for non-long tiles)
        if let tile = playTile {
            // Remove the "Play" label
            tile.childNode(withName: "playLabel")?.removeFromParent()

            // Set sustain pedal state before playing
            AudioManager.shared.prepareSustainPedal(for: tile.sustainPedalOn)
            let adjustedDurations = adjustDurations(tile.noteDurations, tile: tile)
            AudioManager.shared.playShortNotes(tile.midiNotes, durations: adjustedDurations)
            tile.makeTransparent()
            tappedTiles.append(tile)
            score += 1
            onNoteCompleted()  // Play tile counts as first note
        }
        playTile = nil

        gameState = .playing
        songStartTime = 0  // Will be set on first update
        setupScoreLabel()
        setupProgressionUI()
        updateScoreDisplay()
    }

    private func startGameWithLongPlayTile(_ tile: TileNode, touchLocation: CGPoint, touch: UITouch) {
        // Hide the song info bar
        hideSongInfoBar()

        // Remove the "Play" label
        tile.childNode(withName: "playLabel")?.removeFromParent()

        // Start the game
        gameState = .playing
        songStartTime = 0  // Will be set on first update
        setupScoreLabel()
        setupProgressionUI()

        // Add Play tile to active tiles so it's tracked during gameplay
        activeTiles.append(tile)
        playTile = nil

        // Start holding the long tile (same as normal long tile behavior)
        tile.isBeingHeld = true
        tile.fingerY = touchLocation.y
        tile.holdingTouch = touch
        tile.currentlyPlayingNotes = tile.midiNotes
        tile.currentlyPlayingDurations = tile.noteDurations
        heldLongTiles.append(tile)

        // Set sustain pedal state and play the sustained notes (lasts until tile is released)
        AudioManager.shared.prepareSustainPedal(for: tile.sustainPedalOn)
        AudioManager.shared.playSustainedNotes(tile.midiNotes)

        // Complete the first segment (points awarded on completion)
        tile.completeFirstSegment()
        updateScoreDisplay()
    }

    // MARK: - Score Display

    private func setupScoreLabel() {
        let label = SKLabelNode(text: "0")
        label.fontName = "Helvetica-Bold"
        label.fontSize = 32
        label.fontColor = .red
        label.position = CGPoint(x: size.width / 2, y: size.height - 120)
        label.zPosition = 100
        addChild(label)
        scoreLabel = label
    }

    private func updateScoreDisplay() {
        scoreLabel?.text = "\(score)"
    }

    // MARK: - Progression UI

    // Spacing and positioning for progression icons
    private let progressionSpacing: CGFloat = 55
    private var progressionStartX: CGFloat { -progressionSpacing }  // Center 3 icons

    private func setupProgressionUI() {
        // Create container for progression icons (invisible by default)
        let container = SKNode()
        container.position = CGPoint(x: size.width / 2, y: size.height - 70)
        container.zPosition = 150  // Above score label (which is at 100)
        addChild(container)
        progressionContainer = container

        // Create 3 star slots (each has outline + filled, both invisible)
        starNodes.removeAll()

        for i in 0..<3 {
            let starNode = createStarSlot()
            starNode.position = CGPoint(x: progressionStartX + CGFloat(i) * progressionSpacing, y: 0)
            starNode.name = "star_\(i)"
            container.addChild(starNode)
            starNodes.append(starNode)
        }
    }

    /// Helper to render a colored SF Symbol
    private func renderColoredSymbol(symbolName: String, color: UIColor, size: CGSize) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: size.height, weight: .regular)
        guard let symbolImage = UIImage(systemName: symbolName, withConfiguration: config) else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()

            // Calculate scaling to fit symbol within square bounds while maintaining aspect ratio
            let symbolSize = symbolImage.size
            let scale = min(size.width / symbolSize.width, size.height / symbolSize.height)
            let scaledWidth = symbolSize.width * scale
            let scaledHeight = symbolSize.height * scale

            // Center the symbol within the square
            let x = (size.width - scaledWidth) / 2
            let y = (size.height - scaledHeight) / 2
            let drawRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)

            symbolImage.draw(in: drawRect, blendMode: .normal, alpha: 1.0)
            context.fill(CGRect(origin: .zero, size: size), blendMode: .sourceIn)
        }
    }

    /// Creates a star slot with both outline (greyed) and filled versions
    private func createStarSlot() -> SKNode {
        let container = SKNode()

        // Golden color for stars
        let goldenColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
        let iconSize = CGSize(width: 30, height: 30)

        // Outline star (greyed) - shown as placeholder
        if let outlineImage = renderColoredSymbol(symbolName: "star", color: .lightGray, size: iconSize) {
            let outlineTexture = SKTexture(image: outlineImage)
            let outline = SKSpriteNode(texture: outlineTexture)
            outline.size = iconSize
            outline.name = "outline"
            outline.alpha = 0  // Start invisible
            container.addChild(outline)
        }

        // Filled star (golden) - shown when earned
        if let filledImage = renderColoredSymbol(symbolName: "star.fill", color: goldenColor, size: iconSize) {
            let filledTexture = SKTexture(image: filledImage)
            let filled = SKSpriteNode(texture: filledTexture)
            filled.size = iconSize
            filled.name = "filled"
            filled.alpha = 0  // Start invisible
            container.addChild(filled)
        }

        return container
    }

    /// Creates a crown slot with both greyed and filled versions
    private func createCrownSlot() -> SKNode {
        let container = SKNode()

        // Golden color for crowns
        let goldenColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
        let iconSize = CGSize(width: 30, height: 30)

        // Greyed crown - shown as placeholder (using outline version)
        if let outlineImage = renderColoredSymbol(symbolName: "crown", color: .lightGray, size: iconSize) {
            let outlineTexture = SKTexture(image: outlineImage)
            let outline = SKSpriteNode(texture: outlineTexture)
            outline.size = iconSize
            outline.name = "outline"
            outline.alpha = 0  // Start invisible
            container.addChild(outline)
        }

        // Filled crown (golden) - shown when earned
        if let filledImage = renderColoredSymbol(symbolName: "crown.fill", color: goldenColor, size: iconSize) {
            let filledTexture = SKTexture(image: filledImage)
            let filled = SKSpriteNode(texture: filledTexture)
            filled.size = iconSize
            filled.name = "filled"
            filled.alpha = 0  // Start invisible
            container.addChild(filled)
        }

        return container
    }

    // Cached textures for flying star/crown animations (avoid recreating on each earn)
    private static var cachedStarTexture: SKTexture?
    private static var cachedCrownTexture: SKTexture?
    private static let flyingIconSize = CGSize(width: 30, height: 30)
    private static let goldenColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)

    /// Creates a flying star for the animation
    private func createFlyingStar() -> SKSpriteNode {
        if GameScene.cachedStarTexture == nil {
            if let image = renderColoredSymbol(symbolName: "star.fill", color: GameScene.goldenColor, size: GameScene.flyingIconSize) {
                GameScene.cachedStarTexture = SKTexture(image: image)
            }
        }
        let star = SKSpriteNode(texture: GameScene.cachedStarTexture)
        star.size = GameScene.flyingIconSize
        return star
    }

    /// Creates a flying crown for the animation
    private func createFlyingCrown() -> SKSpriteNode {
        if GameScene.cachedCrownTexture == nil {
            if let image = renderColoredSymbol(symbolName: "crown.fill", color: GameScene.goldenColor, size: GameScene.flyingIconSize) {
                GameScene.cachedCrownTexture = SKTexture(image: image)
            }
        }
        let crown = SKSpriteNode(texture: GameScene.cachedCrownTexture)
        crown.size = GameScene.flyingIconSize
        return crown
    }

    private func transitionToCrownsUI() {
        guard let container = progressionContainer else { return }

        // Remove stars (they should already be faded out)
        let removeStars = SKAction.run { [weak self] in
            self?.starNodes.forEach { $0.removeFromParent() }
            self?.starNodes.removeAll()
        }

        // Create crown slots (invisible, will animate in when earned)
        let createCrowns = SKAction.run { [weak self] in
            guard let self = self else { return }

            for i in 0..<3 {
                let crownNode = self.createCrownSlot()
                crownNode.position = CGPoint(x: self.progressionStartX + CGFloat(i) * self.progressionSpacing, y: 0)
                crownNode.name = "crown_\(i)"
                container.addChild(crownNode)
                self.crownNodes.append(crownNode)
            }
        }

        container.run(SKAction.sequence([removeStars, createCrowns]))
    }

    private func hideProgressionUI() {
        progressionContainer?.run(SKAction.fadeOut(withDuration: 0.5))
    }

    private func animateLevelUp(level: Int, isStar: Bool) {
        guard let container = progressionContainer else { return }
        let nodes = isStar ? starNodes : crownNodes
        guard level > 0 && level <= nodes.count else { return }

        // Calculate the target position for this level (relative to container)
        let targetX = progressionStartX + CGFloat(level - 1) * progressionSpacing

        // Calculate spawn position: center horizontally, near the score (which is at y: size.height - 120)
        // Container is at y: size.height - 70, so relative to container, score is at y: -50
        let spawnPosition = CGPoint(x: 0, y: -50)
        let targetPosition = CGPoint(x: targetX, y: 0)

        // Step 1: Fade in all outlines (greyed placeholders)
        for node in nodes {
            if let outline = node.childNode(withName: "outline") as? SKSpriteNode {
                // For crowns, show at 0.3 alpha; for stars, show at 1.0
                let targetAlpha: CGFloat = isStar ? 1.0 : 0.3
                outline.run(SKAction.fadeAlpha(to: targetAlpha, duration: 0.2))
            }
        }

        // Step 2: Also show previously earned filled icons
        for i in 0..<(level - 1) {
            if let filled = nodes[i].childNode(withName: "filled") as? SKSpriteNode {
                filled.run(SKAction.fadeIn(withDuration: 0.2))
            }
            // Hide outline for already-earned slots
            if let outline = nodes[i].childNode(withName: "outline") as? SKSpriteNode {
                outline.run(SKAction.fadeOut(withDuration: 0.2))
            }
        }

        // Step 3: Create the flying icon
        let flyingIcon: SKSpriteNode
        if isStar {
            flyingIcon = createFlyingStar()
        } else {
            flyingIcon = createFlyingCrown()
        }
        flyingIcon.position = spawnPosition
        flyingIcon.alpha = 0
        flyingIcon.setScale(2.5)  // Start much larger, shrinks as it moves to slot
        flyingIcon.zPosition = 50  // Appear on top of score label
        container.addChild(flyingIcon)

        // Animation sequence:
        // 1. Wait for outlines to appear
        // 2. Fade in the flying icon
        // 3. Pause while stationary (let user see it)
        // 4. Move and shrink into the slot
        let initialDelay = SKAction.wait(forDuration: 0.15)  // Wait for outlines to appear
        let fadeIn = SKAction.fadeIn(withDuration: 0.2)
        let stationaryPause = SKAction.wait(forDuration: 0.3)  // Stay in place briefly
        let moveAndScale = SKAction.group([
            SKAction.move(to: targetPosition, duration: 0.4),
            SKAction.scale(to: 1.0, duration: 0.4)
        ])
        moveAndScale.timingMode = .easeOut

        // When flying icon arrives, show the filled version in the slot and hide outline
        let showFilledInSlot = SKAction.run { [weak self] in
            guard let self = self else { return }
            let targetNode = nodes[level - 1]
            if let filled = targetNode.childNode(withName: "filled") as? SKSpriteNode {
                filled.alpha = 1.0
            }
            if let outline = targetNode.childNode(withName: "outline") as? SKSpriteNode {
                outline.alpha = 0
            }
            // Remove the flying icon (it's now "in" the slot)
            flyingIcon.removeFromParent()

            // Schedule the fade out on the container (since flyingIcon will be removed)
            let pause = SKAction.wait(forDuration: 1.2)  // Wait longer before fading out
            let fadeOutAll = SKAction.run {
                let fadeOut = SKAction.fadeOut(withDuration: 0.5)
                for i in 0..<level {
                    nodes[i].childNode(withName: "filled")?.run(fadeOut)
                    nodes[i].childNode(withName: "outline")?.run(fadeOut)
                }
                // Also fade out unfilled outlines
                for i in level..<nodes.count {
                    nodes[i].childNode(withName: "outline")?.run(fadeOut)
                }
            }
            container.run(SKAction.sequence([pause, fadeOutAll]))
        }

        flyingIcon.run(SKAction.sequence([initialDelay, fadeIn, stationaryPause, moveAndScale, showFilledInSlot]))
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
            if longTile.isDoubleTilePair, let pairNotes = longTile.pairNotes, let pairDurations = longTile.pairDurations {
                let pairSustainStates = longTile.pairSustainStates ?? [false, false]
                // Check if sibling is NOT yet being held (i.e., we're the first to be tapped)
                // For long tiles, we check heldLongTiles rather than activeTiles because
                // long tiles stay in activeTiles while being held
                let siblingNotYetHeld = longTile.siblingTile.map { sibling in
                    !heldLongTiles.contains(where: { $0 === sibling })
                } ?? true

                if siblingNotYetHeld {
                    // First tap - play first notes
                    longTile.currentlyPlayingNotes = pairNotes[0]
                    longTile.currentlyPlayingDurations = pairDurations[0]
                    AudioManager.shared.prepareSustainPedal(for: pairSustainStates[0])
                    AudioManager.shared.playSustainedNotes(pairNotes[0])
                } else {
                    // Second tap - play second notes
                    longTile.currentlyPlayingNotes = pairNotes[1]
                    longTile.currentlyPlayingDurations = pairDurations[1]
                    AudioManager.shared.prepareSustainPedal(for: pairSustainStates[1])
                    AudioManager.shared.playSustainedNotes(pairNotes[1])
                }
            } else {
                // Normal long tile - play its notes
                longTile.currentlyPlayingNotes = longTile.midiNotes
                longTile.currentlyPlayingDurations = longTile.noteDurations
                AudioManager.shared.prepareSustainPedal(for: longTile.sustainPedalOn)
                AudioManager.shared.playSustainedNotes(longTile.midiNotes)
            }

            // Immediately complete the first segment (points awarded on completion)
            longTile.completeFirstSegment()
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

    // MARK: - Duration Adjustment for Visual Timing

    // Threshold for considering MIDI gap as "intentional silence" vs continuous notes
    private let silenceGapThreshold: TimeInterval = 0.1  // 100ms

    /// Find the next tile that will be tapped (the one above this tile, excluding siblings)
    private func findNextTile(after tile: TileNode) -> TileNode? {
        // Sort active tiles by Y position (higher Y = will be tapped later)
        let sortedTiles = activeTiles.sorted { $0.position.y < $1.position.y }

        // Find current tile's index
        if let currentIndex = sortedTiles.firstIndex(where: { $0 === tile }) {
            // Current tile is in activeTiles - find the next one
            for i in (currentIndex + 1)..<sortedTiles.count {
                let candidate = sortedTiles[i]
                // Skip sibling tiles (they're tapped together, not sequentially)
                if candidate === tile.siblingTile {
                    continue
                }
                return candidate
            }
        } else {
            // Current tile not in activeTiles (e.g., Play tile)
            // Return the first active tile (lowest Y = next to be tapped)
            return sortedTiles.first
        }

        return nil  // No next tile found (user is tapping the topmost tile)
    }

    /// Calculate visual gap time to next tile based on scroll speed
    private func visualGapTime(from tile: TileNode, to nextTile: TileNode) -> TimeInterval {
        // Distance from current tile center to next tile center
        let distance = nextTile.position.y - tile.position.y
        // Time = distance / speed
        return TimeInterval(distance / currentSpeed)
    }

    /// Adjust durations based on visual timing
    /// Only extends if: MIDI duration < visual gap AND MIDI gap is small (continuous notes)
    private func adjustDurations(_ durations: [TimeInterval], tile: TileNode) -> [TimeInterval] {
        // Find next tile
        guard let nextTile = findNextTile(after: tile) else {
            return durations
        }

        let visualGap = visualGapTime(from: tile, to: nextTile)
        let midiGap = tile.gapToNextNote

        // Only adjust if MIDI gap is small (indicating continuous notes, not intentional silence)
        guard midiGap < silenceGapThreshold else {
            return durations
        }

        // Adjust each duration: extend to visual gap if shorter, but cap at 90% of visual gap
        // to leave a tiny space before the next tile
        let targetDuration = visualGap * 0.9

        return durations.map { duration in
            if duration < targetDuration {
                return targetDuration
            }
            return duration
        }
    }

    private func handleTileTap(_ tile: TileNode) {
        // Track whether this completes a note event for progression
        var completesNoteEvent = true

        // For double tile pairs: first tap plays first note, second tap plays second note
        // This ensures musical order is preserved regardless of which physical tile is tapped first
        if tile.isDoubleTilePair, let pairNotes = tile.pairNotes, let pairDurations = tile.pairDurations {
            let pairSustainStates = tile.pairSustainStates ?? [false, false]
            // Check if sibling is still in activeTiles
            let siblingStillActive = tile.siblingTile.map { sibling in
                activeTiles.contains(where: { $0 === sibling })
            } ?? false

            if siblingStillActive {
                // First tap of the pair - play the first notes
                AudioManager.shared.prepareSustainPedal(for: pairSustainStates[0])
                let adjustedDurations = adjustDurations(pairDurations[0], tile: tile)
                AudioManager.shared.playShortNotes(pairNotes[0], durations: adjustedDurations)
                completesNoteEvent = false  // Wait for second tile to complete the note event
            } else {
                // Second tap of the pair - play the second notes
                AudioManager.shared.prepareSustainPedal(for: pairSustainStates[1])
                let adjustedDurations = adjustDurations(pairDurations[1], tile: tile)
                AudioManager.shared.playShortNotes(pairNotes[1], durations: adjustedDurations)
                completesNoteEvent = true  // Both tiles tapped, note event complete
            }
        } else {
            // Normal tile - play its assigned notes
            AudioManager.shared.prepareSustainPedal(for: tile.sustainPedalOn)
            let adjustedDurations = adjustDurations(tile.noteDurations, tile: tile)
            AudioManager.shared.playShortNotes(tile.midiNotes, durations: adjustedDurations)
        }

        // Make tile transparent
        tile.makeTransparent()

        // Move from active to tapped tiles
        activeTiles.removeAll { $0 === tile }
        tappedTiles.append(tile)

        score += 1
        updateScoreDisplay()

        // Track progression (only when a full note event is completed)
        if completesNoteEvent {
            onNoteCompleted()
        }
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

        // Handle visual completion based on whether tile was fully completed
        if tile.isFullyCompleted() {
            // Fully completed: animate fill fading out smoothly
            tile.animateFillFadeOut()
        }
        // Prematurely released: leave fill where it is (no visual change)

        // Track whether this completes a note event for progression
        // For double-long-tile pairs, only count when the second tile is completed
        var completesNoteEvent = true
        if tile.isDoubleTilePair {
            // Check if sibling is still being held or active (not yet in tappedTiles)
            let siblingStillActive = tile.siblingTile.map { sibling in
                activeTiles.contains(where: { $0 === sibling }) || heldLongTiles.contains(where: { $0 === sibling })
            } ?? false
            completesNoteEvent = !siblingStillActive  // Only complete when sibling is also done
        }

        // Move from active to tapped tiles
        activeTiles.removeAll { $0 === tile }
        tappedTiles.append(tile)

        // Clear held tile reference
        tile.isBeingHeld = false
        tile.holdingTouch = nil
        heldLongTiles.removeAll { $0 === tile }

        // Award points: full points if completed, 1 point if released early
        if tile.isFullyCompleted() {
            score += tile.tileLength
            showPointsAnimation(points: tile.tileLength, on: tile)
        } else {
            score += 1
        }
        updateScoreDisplay()

        // Track progression (only when a full note event is completed)
        if completesNoteEvent {
            onNoteCompleted()
        }
    }

    // MARK: - Progression System

    /// Called when a note event is completed (tile tapped or long tile finished)
    /// For double tiles, only call when the SECOND tile of the pair is tapped
    private func onNoteCompleted() {
        guard totalNotesInSong > 0 else { return }
        guard !isInGapPeriod else { return }

        notesPlayedInCurrentLoop += 1

        // Check for progression thresholds based on current tier
        switch progressionTier {
        case .stars:
            checkStarProgression()
        case .crowns:
            checkCrownProgression()
        case .endless:
            // No more levels to track
            break
        }
    }

    private func checkStarProgression() {
        let progress = Double(notesPlayedInCurrentLoop) / Double(totalNotesInSong)

        // Check star thresholds: 33%, 66%, 100%
        let newStars: Int
        if progress >= 1.0 {
            newStars = 3
        } else if progress >= 0.66 {
            newStars = 2
        } else if progress >= 0.33 {
            newStars = 1
        } else {
            newStars = 0
        }

        if newStars > currentStars {
            currentStars = newStars
            animateLevelUp(level: currentStars, isStar: true)

            // Save progress
            ProgressManager.shared.updateStars(for: songId, stars: currentStars, fileURL: songURL)

            // After 3 stars, start gap period before crowns
            if currentStars == 3 {
                startGapPeriod()
            }
        }
    }

    private func checkCrownProgression() {
        let progress = Double(notesPlayedInCurrentLoop) / Double(totalNotesInSong)

        // Check crown thresholds: 33%, 66%, 100%
        let newCrowns: Int
        if progress >= 1.0 {
            newCrowns = 3
        } else if progress >= 0.66 {
            newCrowns = 2
        } else if progress >= 0.33 {
            newCrowns = 1
        } else {
            newCrowns = 0
        }

        if newCrowns > currentCrowns {
            currentCrowns = newCrowns
            animateLevelUp(level: currentCrowns, isStar: false)

            // Save progress
            ProgressManager.shared.updateCrowns(for: songId, crowns: currentCrowns, fileURL: songURL)

            // After 3 crowns, enter endless mode
            if currentCrowns == 3 {
                enterEndlessMode()
            }
        }
    }

    private func startGapPeriod() {
        isInGapPeriod = true
        gapStartTime = lastUpdateTime
    }

    private func endGapPeriod() {
        isInGapPeriod = false
        progressionTier = .crowns
        notesPlayedInCurrentLoop = 0
        loopCount += 1
        currentNoteIndex = 0  // Reset to beginning for crowns phase

        // Switch UI from stars to crowns
        transitionToCrownsUI()
    }

    private func enterEndlessMode() {
        progressionTier = .endless
        // Delay hiding the UI to let the 3rd crown animation complete
        // Animation takes ~2.75s (0.15 delay + 0.2 fade + 0.3 stationary + 0.4 move + 1.2 pause + 0.5 fade out)
        let delay = SKAction.wait(forDuration: 2.8)
        let hide = SKAction.run { [weak self] in
            self?.hideProgressionUI()
        }
        progressionContainer?.run(SKAction.sequence([delay, hide]))
    }

    /// Called when the song loops (all notes have been spawned and we reset to beginning)
    private func onSongLoop() {
        // This is called when SPAWNING loops, not when PLAYING loops
        // Don't reset notesPlayedInCurrentLoop here - it tracks player progress, not spawning
        // During crowns phase, let the player finish tapping to earn all 3 crowns
        // During endless mode, we can reset for tracking purposes
        if progressionTier == .endless {
            notesPlayedInCurrentLoop = 0
        }
        loopCount += 1
    }

    // MARK: - Point Animation

    private func showPointsAnimation(points: Int, on tile: TileNode) {
        let label = SKLabelNode(text: "+\(points)")
        label.fontName = "Helvetica-Bold"
        label.fontSize = 28
        label.fontColor = TileNode.longTileColor
        // Position above the tile (relative to tile's center)
        label.position = CGPoint(x: 0, y: tile.size.height / 2 + 20)
        label.zPosition = 150
        label.alpha = 0

        tile.addChild(label)

        // Animation: fade in (to 75% opacity), move up, fade out
        let fadeIn = SKAction.fadeAlpha(to: 0.75, duration: 0.1)
        let moveUp = SKAction.moveBy(x: 0, y: 60, duration: 0.5)
        let fadeOut = SKAction.fadeOut(withDuration: 0.2)
        let remove = SKAction.removeFromParent()

        let moveAndFade = SKAction.group([moveUp, SKAction.sequence([
            SKAction.wait(forDuration: 0.3),
            fadeOut
        ])])

        label.run(SKAction.sequence([fadeIn, moveAndFade, remove]))
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
        // Save high score
        ProgressManager.shared.updateHighScore(for: songId, score: score, fileURL: songURL)

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

        // Reset progression state
        progressionTier = .stars
        currentStars = 0
        currentCrowns = 0
        loopCount = 0
        notesPlayedInCurrentLoop = 0
        isInGapPeriod = false

        // Remove progression UI
        progressionContainer?.removeFromParent()
        progressionContainer = nil
        starNodes.removeAll()
        crownNodes.removeAll()

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
        view?.presentScene(songListScene)
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
            let pairSustainStates: [Bool] = [note.sustainPedalOn, note.secondTileSustainPedalOn ?? note.sustainPedalOn]

            // Position for long tiles - center is higher due to larger size
            let tileCenterY = yPosition + (CGFloat(tileLength - 1) * tileSize.height) / 2

            let firstTile = TileNode(
                column: columns[0],
                size: tileSize,
                tileLength: tileLength,
                midiNotes: note.midiNotes,
                noteDurations: note.noteDurations,
                gapToNextNote: note.gapToNextNote,
                sustainPedalOn: note.sustainPedalOn
            )
            firstTile.pairNotes = pairNotes
            firstTile.pairDurations = pairDurations
            firstTile.pairSustainStates = pairSustainStates
            firstTile.position = CGPoint(x: columnPositions[columns[0]], y: tileCenterY)
            addChild(firstTile)
            activeTiles.append(firstTile)

            let secondTile = TileNode(
                column: columns[1],
                size: tileSize,
                tileLength: tileLength,
                midiNotes: secondNotes,
                noteDurations: note.secondTileNoteDurations ?? [0.5],
                gapToNextNote: note.gapToNextNote,
                sustainPedalOn: note.secondTileSustainPedalOn ?? note.sustainPedalOn
            )
            secondTile.pairNotes = pairNotes
            secondTile.pairDurations = pairDurations
            secondTile.pairSustainStates = pairSustainStates
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

        let tile = TileNode(column: column, size: tileSize, tileLength: tileLength, midiNotes: note.midiNotes, noteDurations: note.noteDurations, gapToNextNote: note.gapToNextNote, sustainPedalOn: note.sustainPedalOn)

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

        // Move song info bar with the scroll (if still visible)
        if let bar = songInfoBar {
            bar.position.y -= moveDistance
            // Remove once fully off-screen
            if bar.position.y < -songInfoBarHeight {
                bar.removeFromParent()
                songInfoBar = nil
            }
        }

        // Update all held long tiles - check for segment completion
        for heldTile in heldLongTiles {
            // Update segments based on finger position (stored on tile)
            _ = heldTile.updateSegmentsForHold(fingerY: heldTile.fingerY)

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

        // Handle gap period timing
        if isInGapPeriod {
            let gapElapsed = currentTime - gapStartTime
            if gapElapsed >= gapDuration {
                endGapPeriod()
            }
            // During gap: tiles continue moving but no spawning
            return
        }

        // Beatmap-driven spawning
        if let beatmap = beatmap {
            // During stars phase, don't spawn beyond the first loop
            // This prevents extra notes appearing after 3 stars
            let canSpawn = progressionTier != .stars || currentNoteIndex < beatmap.notes.count

            // Spawn tiles when topmost tile has moved down enough and there are more notes
            while canSpawn && currentNoteIndex < beatmap.notes.count {
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

            // Loop the song when all notes have been spawned (only after stars phase)
            if currentNoteIndex >= beatmap.notes.count && progressionTier != .stars {
                currentNoteIndex = 0  // Reset to beginning for infinite loop
                onSongLoop()
            }
        }
    }

}
