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

    // MARK: - Properties

    private var tileSize: CGSize = .zero
    private var columnPositions: [CGFloat] = []

    private var activeTiles: [TileNode] = []
    private var currentSpeed: CGFloat = GameConfig.initialScrollSpeed

    private var lastUpdateTime: TimeInterval = 0

    private var startButton: SKLabelNode?
    private var spawnThreshold: CGFloat = 0

    private var score: Int = 0
    private var scoreLabel: SKLabelNode?
    private var tappedTiles: [TileNode] = []

    // Long tile tracking
    private var heldLongTile: TileNode?
    private var heldTouchLocation: CGPoint = .zero  // Where the finger is during hold

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .white
        setupLayout()
        showStartScreen()
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
        let button = SKLabelNode(text: "Start")
        button.fontName = "Helvetica-Bold"
        button.fontSize = 48
        button.fontColor = .black
        button.position = CGPoint(x: size.width / 2, y: size.height / 2)
        button.name = "startButton"
        addChild(button)
        startButton = button
    }

    private func startGame() {
        startButton?.removeFromParent()
        startButton = nil
        gameState = .playing
        setupScoreLabel()
        spawnInitialTiles()
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
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        switch gameState {
        case .waiting:
            startGame()

        case .playing:
            // First check if tapping a long tile's bottom segment
            if let longTile = findLongTileBottomSegment(at: location) {
                // Start holding the long tile
                longTile.isBeingHeld = true
                longTile.fingerY = location.y
                heldLongTile = longTile
                heldTouchLocation = location

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

        case .gameOver:
            if let restartButton = childNode(withName: "restartButton"),
               restartButton.contains(location) {
                restartGame()
            }
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
        // Make tile transparent
        tile.makeTransparent()

        // Move from active to tapped tiles
        activeTiles.removeAll { $0 === tile }
        tappedTiles.append(tile)

        score += 1
        updateScoreDisplay()
    }

    private func completeLongTile(_ tile: TileNode) {
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
    }

    // MARK: - Restart

    private func restartGame() {
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

        // Reset game state
        score = 0
        currentSpeed = GameConfig.initialScrollSpeed
        lastUpdateTime = 0
        updateScoreDisplay()

        // Start playing again
        gameState = .playing
        spawnInitialTiles()
    }

    // MARK: - Tile Spawning

    private func spawnInitialTiles() {
        // Set spawn threshold - spawn new tile when topmost tile drops below this Y
        spawnThreshold = size.height - tileSize.height / 2

        // Spawn a few rows at the top so user has time to react
        let initialRowCount = 2

        var currentY = size.height + tileSize.height / 2
        for _ in 0..<initialRowCount {
            let tileUnits = spawnRow(at: currentY)
            currentY += tileSize.height * CGFloat(tileUnits)  // Move UP for next tile (higher Y = enters screen later)
        }
    }

    private func spawnRow(at yPosition: CGFloat) -> Int {
        // Find the topmost tile (highest Y) to avoid spawning in same column
        let topmostTile = activeTiles.max(by: { $0.position.y < $1.position.y })

        // Randomly select column, excluding the topmost tile's column
        var availableColumns = Array(0..<GameConfig.columnCount)
        if let excludeColumn = topmostTile?.column {
            availableColumns.removeAll { $0 == excludeColumn }
        }
        let blackTileColumn = availableColumns.randomElement()!

        // Determine if this should be a long tile
        let isLongTile = CGFloat.random(in: 0...1) < GameConfig.longTileSpawnChance
        let tileLength: Int
        if isLongTile {
            tileLength = Int.random(in: GameConfig.longTileMinLength...GameConfig.longTileMaxLength)
        } else {
            tileLength = 1
        }

        let tile = TileNode(column: blackTileColumn, size: tileSize, tileLength: tileLength)

        // Position tile - for long tiles, the center is higher due to larger size
        let tileCenterY = yPosition + (CGFloat(tileLength - 1) * tileSize.height) / 2
        tile.position = CGPoint(
            x: columnPositions[blackTileColumn],
            y: tileCenterY
        )

        addChild(tile)
        activeTiles.append(tile)

        // Return the number of tile units spawned (for spawn threshold adjustment)
        return tileLength
    }

    // MARK: - Game Loop

    override func update(_ currentTime: TimeInterval) {
        guard gameState == .playing else { return }

        // Calculate delta time
        let deltaTime: TimeInterval
        if lastUpdateTime == 0 {
            deltaTime = 0
        } else {
            deltaTime = currentTime - lastUpdateTime
        }
        lastUpdateTime = currentTime

        guard deltaTime > 0 else { return }

        // Increase speed over time
        currentSpeed = min(
            currentSpeed + GameConfig.speedIncreaseRate * CGFloat(deltaTime),
            GameConfig.maxScrollSpeed
        )

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
        for tile in activeTiles {
            if tile === heldLongTile {
                continue  // Skip held tile
            }
            let tileTop = tile.position.y + tile.size.height / 2
            if tileTop < 0 {
                triggerGameOver()
                return
            }
        }

        // Spawn new tile when topmost tile has moved down enough
        if let topmostTile = activeTiles.max(by: { $0.position.y < $1.position.y }) {
            // Use the top edge of the topmost tile
            let topmostTileTop = topmostTile.position.y + topmostTile.size.height / 2
            if topmostTileTop <= spawnThreshold + tileSize.height / 2 {
                // Spawn at the top of the topmost tile
                let newY = topmostTileTop + tileSize.height / 2
                _ = spawnRow(at: newY)
            }
        }
    }
}
