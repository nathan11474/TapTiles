import SpriteKit

// MARK: - Home Scene

/// Home screen with checkerboard tiles and play button
class HomeScene: SKScene {

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .white
        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        let tileWidth = size.width / 2
        let tileHeight = size.height / 2

        // Top-left: Black tile with "Tap"
        let topLeftTile = SKShapeNode(rectOf: CGSize(width: tileWidth, height: tileHeight))
        topLeftTile.fillColor = .black
        topLeftTile.strokeColor = .clear
        topLeftTile.position = CGPoint(x: tileWidth / 2, y: size.height - tileHeight / 2)
        addChild(topLeftTile)

        let tapLabel = SKLabelNode(text: "Tap")
        tapLabel.fontName = "Helvetica-Bold"
        tapLabel.fontSize = 64
        tapLabel.fontColor = .white
        tapLabel.verticalAlignmentMode = .center
        tapLabel.horizontalAlignmentMode = .center
        tapLabel.position = CGPoint(x: tileWidth / 2, y: size.height - tileHeight / 2)
        addChild(tapLabel)

        // Top-right: White tile with "Tiles"
        let topRightTile = SKShapeNode(rectOf: CGSize(width: tileWidth, height: tileHeight))
        topRightTile.fillColor = .white
        topRightTile.strokeColor = .clear
        topRightTile.position = CGPoint(x: size.width - tileWidth / 2, y: size.height - tileHeight / 2)
        addChild(topRightTile)

        let tilesLabel = SKLabelNode(text: "Tiles")
        tilesLabel.fontName = "Helvetica-Bold"
        tilesLabel.fontSize = 64
        tilesLabel.fontColor = .black
        tilesLabel.verticalAlignmentMode = .center
        tilesLabel.horizontalAlignmentMode = .center
        tilesLabel.position = CGPoint(x: size.width - tileWidth / 2, y: size.height - tileHeight / 2)
        addChild(tilesLabel)

        // Bottom-left: White tile (empty)
        let bottomLeftTile = SKShapeNode(rectOf: CGSize(width: tileWidth, height: tileHeight))
        bottomLeftTile.fillColor = .white
        bottomLeftTile.strokeColor = .clear
        bottomLeftTile.position = CGPoint(x: tileWidth / 2, y: tileHeight / 2)
        addChild(bottomLeftTile)

        // Bottom-right: Black tile (empty)
        let bottomRightTile = SKShapeNode(rectOf: CGSize(width: tileWidth, height: tileHeight))
        bottomRightTile.fillColor = .black
        bottomRightTile.strokeColor = .clear
        bottomRightTile.position = CGPoint(x: size.width - tileWidth / 2, y: tileHeight / 2)
        addChild(bottomRightTile)

        // Green "Play" button centered on screen
        let playButton = createPlayButton()
        playButton.position = CGPoint(x: size.width / 2, y: size.height * 0.35)
        playButton.zPosition = 10
        addChild(playButton)
    }

    private func createPlayButton() -> SKNode {
        let container = SKNode()
        container.name = "playButton"

        let buttonWidth: CGFloat = 200
        let buttonHeight: CGFloat = 60
        let cornerRadius: CGFloat = 30
        let greenColor = UIColor(red: 0.18, green: 0.8, blue: 0.44, alpha: 1.0)

        // Green rounded button background
        let background = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: cornerRadius)
        background.fillColor = greenColor
        background.strokeColor = .clear
        container.addChild(background)

        // Button label
        let label = SKLabelNode(text: "Play")
        label.fontName = "Helvetica-Bold"
        label.fontSize = 28
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        container.addChild(label)

        return container
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        if let playButton = childNode(withName: "playButton"),
           playButton.contains(location) {
            transitionToSongList()
        }
    }

    // MARK: - Navigation

    private func transitionToSongList() {
        let songListScene = SongListScene(size: size)
        songListScene.scaleMode = scaleMode
        view?.presentScene(songListScene)
    }
}
