import SpriteKit

// MARK: - Song List Scene

/// Song selection screen showing available songs
class SongListScene: SKScene {

    // MARK: - Properties

    private var songs: [SongInfo] = []
    private var songRows: [(container: SKNode, song: SongInfo)] = []
    private let rowHeight: CGFloat = 80

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .white
        songs = SongManager.shared.availableSongs
        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        setupHeader()
        setupSongList()
    }

    private func setupHeader() {
        // Back button
        let backButton = SKLabelNode(text: "< Back")
        backButton.fontName = "Helvetica"
        backButton.fontSize = 20
        backButton.fontColor = .darkGray
        backButton.name = "backButton"
        backButton.horizontalAlignmentMode = .left
        backButton.position = CGPoint(x: 20, y: size.height - 60)
        addChild(backButton)

        // "Select Song" header
        let headerLabel = SKLabelNode(text: "Select Song")
        headerLabel.fontName = "Helvetica-Bold"
        headerLabel.fontSize = 32
        headerLabel.fontColor = .black
        headerLabel.position = CGPoint(x: size.width / 2, y: size.height - 60)
        addChild(headerLabel)
    }

    private func setupSongList() {
        let startY = size.height - 120

        for (index, song) in songs.enumerated() {
            let yPos = startY - CGFloat(index) * rowHeight
            let songRow = createSongRow(song: song, at: yPos)
            addChild(songRow)
            songRows.append((container: songRow, song: song))
        }

        // Show message if no songs found
        if songs.isEmpty {
            let noSongsLabel = SKLabelNode(text: "No songs found")
            noSongsLabel.fontName = "Helvetica"
            noSongsLabel.fontSize = 24
            noSongsLabel.fontColor = .gray
            noSongsLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(noSongsLabel)
        }
    }

    private func createSongRow(song: SongInfo, at yPos: CGFloat) -> SKNode {
        let container = SKNode()
        container.position = CGPoint(x: 0, y: yPos)
        container.name = "songRow_\(song.id)"

        // Row background (for tap area)
        let background = SKShapeNode(rectOf: CGSize(width: size.width - 40, height: rowHeight - 10))
        background.fillColor = UIColor(white: 0.95, alpha: 1.0)
        background.strokeColor = .clear
        background.position = CGPoint(x: size.width / 2, y: 0)
        container.addChild(background)

        // Song title
        let titleLabel = SKLabelNode(text: song.title)
        titleLabel.fontName = "Helvetica"
        titleLabel.fontSize = 22
        titleLabel.fontColor = .black
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 30, y: 0)
        container.addChild(titleLabel)

        // Play button
        let playButton = SKLabelNode(text: "▶")
        playButton.fontName = "Helvetica"
        playButton.fontSize = 28
        playButton.fontColor = .black
        playButton.verticalAlignmentMode = .center
        playButton.position = CGPoint(x: size.width - 40, y: 0)
        container.addChild(playButton)

        return container
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check back button
        if let backButton = childNode(withName: "backButton"),
           backButton.contains(location) {
            transitionToHome()
            return
        }

        // Check song rows
        for (container, song) in songRows {
            if container.contains(location) {
                startGame(with: song)
                return
            }
        }
    }

    // MARK: - Navigation

    private func transitionToHome() {
        let homeScene = HomeScene(size: size)
        homeScene.scaleMode = scaleMode
        let transition = SKTransition.push(with: .right, duration: 0.3)
        view?.presentScene(homeScene, transition: transition)
    }

    private func startGame(with song: SongInfo) {
        let gameScene = GameScene(size: size, songURL: song.url, customSpeed: song.customSpeed, startFromNote: song.startFromNote)
        gameScene.scaleMode = scaleMode
        let transition = SKTransition.push(with: .left, duration: 0.3)
        view?.presentScene(gameScene, transition: transition)
    }
}
