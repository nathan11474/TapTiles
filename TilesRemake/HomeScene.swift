import SpriteKit

// MARK: - Home Scene

/// Home screen with game title and play button
class HomeScene: SKScene {

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .white
        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // "Tap Tiles" title
        let titleLabel = SKLabelNode(text: "Tap Tiles")
        titleLabel.fontName = "Helvetica-Bold"
        titleLabel.fontSize = 48
        titleLabel.fontColor = .black
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.65)
        addChild(titleLabel)

        // Play button
        let playButton = createButton(text: "Play", name: "playButton")
        playButton.position = CGPoint(x: size.width / 2, y: size.height * 0.4)
        addChild(playButton)
    }

    private func createButton(text: String, name: String) -> SKNode {
        let container = SKNode()
        container.name = name

        // Button background
        let background = SKShapeNode(rectOf: CGSize(width: 160, height: 60), cornerRadius: 10)
        background.fillColor = .black
        background.strokeColor = .clear
        container.addChild(background)

        // Button label
        let label = SKLabelNode(text: text)
        label.fontName = "Helvetica-Bold"
        label.fontSize = 32
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
        let transition = SKTransition.push(with: .left, duration: 0.3)
        view?.presentScene(songListScene, transition: transition)
    }
}
