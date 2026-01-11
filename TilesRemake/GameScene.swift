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
        label.fontColor = .black
        label.position = CGPoint(x: size.width / 2, y: size.height - 60)
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
            if let tile = findTile(at: location) {
                handleTileTap(tile)
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

    private func findTile(at point: CGPoint) -> TileNode? {
        for tile in activeTiles {
            if tile.frame.contains(point) {
                return tile
            }
        }
        return nil
    }

    private func handleTileTap(_ tile: TileNode) {
        tile.removeFromParent()
        activeTiles.removeAll { $0 === tile }
        score += 1
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

        for row in 0..<initialRowCount {
            let yPosition = size.height + tileSize.height / 2 - CGFloat(row) * tileSize.height
            spawnRow(at: yPosition)
        }
    }

    private func spawnRow(at yPosition: CGFloat) {
        // Find the topmost tile (highest Y) to avoid spawning in same column
        let topmostTile = activeTiles.max(by: { $0.position.y < $1.position.y })

        // Randomly select column, excluding the topmost tile's column
        var availableColumns = Array(0..<GameConfig.columnCount)
        if let excludeColumn = topmostTile?.column {
            availableColumns.removeAll { $0 == excludeColumn }
        }
        let blackTileColumn = availableColumns.randomElement()!

        let tile = TileNode(column: blackTileColumn, size: tileSize)
        tile.position = CGPoint(
            x: columnPositions[blackTileColumn],
            y: yPosition
        )

        addChild(tile)
        activeTiles.append(tile)
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

        // Check if any tile has scrolled off the bottom - triggers game over
        for tile in activeTiles {
            if tile.position.y < -tileSize.height / 2 {
                triggerGameOver()
                return
            }
        }

        // Spawn new tile when topmost tile has moved down enough
        if let topmostTile = activeTiles.max(by: { $0.position.y < $1.position.y }) {
            if topmostTile.position.y <= spawnThreshold {
                // Spawn exactly one tile height above the current topmost tile
                let newY = topmostTile.position.y + tileSize.height
                spawnRow(at: newY)
            }
        }
    }
}
