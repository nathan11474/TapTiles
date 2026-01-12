import SpriteKit

// MARK: - Song List Scene

/// Song selection screen showing available songs
class SongListScene: SKScene {

    // MARK: - Properties

    private var songs: [SongInfo] = []
    private var songRows: [(container: SKNode, song: SongInfo)] = []
    private let rowHeight: CGFloat = 80

    // Difficulty thresholds (based on initial speed in pts/sec)
    private static let difficultyThresholds: [(maxSpeed: CGFloat, level: Int)] = [
        (400, 1),
        (700, 2),
        (1000, 3),
        (1300, 4)
    ]

    // Difficulty colors (green to red gradient)
    private static let difficultyColors: [Int: UIColor] = [
        1: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0),  // Green
        2: UIColor(red: 0.5, green: 0.7, blue: 0.2, alpha: 1.0),  // Yellow-green
        3: UIColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1.0),  // Yellow
        4: UIColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1.0),  // Orange
        5: UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0)   // Red
    ]

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

        // Difficulty box
        let difficulty = calculateDifficulty(for: song)
        let boxSize: CGFloat = 36
        let difficultyBox = SKShapeNode(rectOf: CGSize(width: boxSize, height: boxSize), cornerRadius: 4)
        difficultyBox.fillColor = SongListScene.difficultyColors[difficulty] ?? .gray
        difficultyBox.strokeColor = .clear
        difficultyBox.position = CGPoint(x: 38, y: 0)
        container.addChild(difficultyBox)

        let difficultyLabel = SKLabelNode(text: "\(difficulty)")
        difficultyLabel.fontName = "Helvetica-Bold"
        difficultyLabel.fontSize = 20
        difficultyLabel.fontColor = .white
        difficultyLabel.verticalAlignmentMode = .center
        difficultyLabel.horizontalAlignmentMode = .center
        difficultyLabel.position = CGPoint(x: 38, y: 0)
        container.addChild(difficultyLabel)

        // Song title (shifted right to make room for difficulty box)
        let titleLabel = SKLabelNode(text: song.title)
        titleLabel.fontName = "Helvetica"
        titleLabel.fontSize = 18  // Change this value to adjust song name font size
        titleLabel.fontColor = .black
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 65, y: 0)
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

    // MARK: - Difficulty Calculation

    /// Calculate difficulty level (1-5) for a song based on its initial speed
    private func calculateDifficulty(for song: SongInfo) -> Int {
        let speed = calculateSpeed(for: song)

        for (maxSpeed, level) in SongListScene.difficultyThresholds {
            if speed <= maxSpeed {
                return level
            }
        }
        return 5  // Highest difficulty for speeds > 1300
    }

    /// Calculate initial speed for a song (same formula as GameScene)
    private func calculateSpeed(for song: SongInfo) -> CGFloat {
        // Use custom speed if provided
        if let customSpeed = song.customSpeed {
            return customSpeed
        }

        // Parse MIDI to calculate speed from note density
        let parser = MidiParser()
        guard let beatmap = parser.parse(url: song.url) else {
            return 500  // Default fallback
        }

        let notesPerSecond = CGFloat(beatmap.notes.count) / CGFloat(beatmap.totalDuration)
        let estimatedTileHeight = size.height / GameConfig.visibleTileCount
        return estimatedTileHeight * notesPerSecond
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
