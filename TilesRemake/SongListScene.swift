import SpriteKit
import UIKit

// MARK: - Song List Scene

/// Song selection screen showing available songs
class SongListScene: SKScene {

    // MARK: - Properties

    private var songs: [SongInfo] = []
    private var filteredSongs: [(song: SongInfo, difficulty: Int)] = []
    private var playButtons: [(button: SKNode, song: SongInfo)] = []
    private let rowHeight: CGFloat = 80

    // Scrolling
    private var scrollContainer: SKNode!
    private var scrollOffset: CGFloat = 0
    private var lastTouchY: CGFloat = 0
    private var lastTouchTime: TimeInterval = 0
    private var isDragging = false
    private var scrollVelocity: CGFloat = 0
    private let decelerationRate: CGFloat = 0.92  // Friction multiplier per frame
    private let minVelocity: CGFloat = 0.5  // Stop scrolling below this
    private var contentHeight: CGFloat = 0
    private var visibleAreaTop: CGFloat = 0
    private var visibleAreaBottom: CGFloat = 0

    // Search
    private var searchTextField: UITextField?
    private var searchQuery: String = ""
    private var searchDebounceTimer: Timer?

    // Async difficulty loading
    private var loadingLabel: SKLabelNode?
    private var pendingDifficultyCalculations: Set<String> = []

    // Difficulty thresholds (based on notes per second - screen independent)
    private static let difficultyThresholds: [(maxNotesPerSec: CGFloat, level: Int)] = [
        (2.0, 1),   // Easy: up to 2 notes/sec
        (3.5, 2),   // Medium: up to 3.5 notes/sec
        (5.0, 3),   // Hard: up to 5 notes/sec
        (7.0, 4)    // Very Hard: up to 7 notes/sec
        // Expert: > 7 notes/sec = level 5
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

        // Start loading audio in background (will be ready by the time user picks a song)
        AudioManager.shared.setupAsync()

        songs = SongManager.shared.availableSongs

        // Check which songs need difficulty calculation (validates fingerprint for changed files)
        var songsNeedingCalculation: [SongInfo] = []
        for song in songs {
            if SongManager.shared.getCachedDifficulty(for: song.id, fileURL: song.url) == nil {
                songsNeedingCalculation.append(song)
            }
        }

        setupHeader()
        setupScrollContainer()
        setupSearchBar(in: view)

        if songsNeedingCalculation.isEmpty {
            // All difficulties cached - show list immediately
            buildSortedSongList()
        } else {
            // Show loading message and calculate in background
            showLoadingMessage()
            calculateDifficultiesAsync(for: songsNeedingCalculation)
        }
    }

    override func willMove(from view: SKView) {
        searchTextField?.removeFromSuperview()
        searchTextField = nil
    }

    // MARK: - UI Setup

    private func setupHeader() {
        // Header background (covers scrolling content)
        let headerHeight: CGFloat = 180
        let headerBackground = SKSpriteNode(color: .white, size: CGSize(width: size.width, height: headerHeight))
        headerBackground.anchorPoint = CGPoint(x: 0, y: 1)
        headerBackground.position = CGPoint(x: 0, y: size.height)
        headerBackground.zPosition = 100  // Above scroll content
        addChild(headerBackground)

        // Back button
        let backButton = SKLabelNode(text: "< Back")
        backButton.fontName = "Helvetica"
        backButton.fontSize = 20
        backButton.fontColor = .darkGray
        backButton.name = "backButton"
        backButton.horizontalAlignmentMode = .left
        backButton.position = CGPoint(x: 20, y: size.height - 60)
        backButton.zPosition = 101
        addChild(backButton)

        // "Select Song" header (positioned lower)
        let headerLabel = SKLabelNode(text: "Select Song")
        headerLabel.fontName = "Helvetica-Bold"
        headerLabel.fontSize = 32
        headerLabel.fontColor = .black
        headerLabel.position = CGPoint(x: size.width / 2, y: size.height - 110)
        headerLabel.zPosition = 101
        addChild(headerLabel)
    }

    private func setupSearchBar(in view: SKView) {
        let searchBarHeight: CGFloat = 40
        let searchBarY: CGFloat = 125  // Below header
        let padding: CGFloat = 20

        let textField = UITextField()
        textField.placeholder = "Search songs..."
        textField.borderStyle = .roundedRect
        textField.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        textField.textColor = .black
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        textField.returnKeyType = .search
        textField.frame = CGRect(
            x: padding,
            y: searchBarY,
            width: view.bounds.width - padding * 2,
            height: searchBarHeight
        )
        textField.addTarget(self, action: #selector(searchTextChanged(_:)), for: .editingChanged)
        textField.delegate = self

        view.addSubview(textField)
        searchTextField = textField
    }

    @objc private func searchTextChanged(_ textField: UITextField) {
        searchQuery = textField.text ?? ""

        // Debounce: wait for typing to stop before rebuilding
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.filterAndRebuildSongList()
        }
    }

    private func filterAndRebuildSongList() {
        // Use cached difficulties
        let songsWithDifficulty = songs.map { song -> (song: SongInfo, difficulty: Int) in
            let difficulty = SongManager.shared.getCachedDifficulty(for: song.id) ?? 3
            return (song: song, difficulty: difficulty)
        }

        // Filter by search query
        let filtered: [(song: SongInfo, difficulty: Int)]
        if searchQuery.isEmpty {
            filtered = songsWithDifficulty
        } else {
            filtered = songsWithDifficulty.filter {
                $0.song.title.localizedCaseInsensitiveContains(searchQuery) ||
                $0.song.category.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        // Sort by difficulty, then by name
        filteredSongs = filtered.sorted { lhs, rhs in
            if lhs.difficulty != rhs.difficulty {
                return lhs.difficulty < rhs.difficulty
            }
            return lhs.song.title < rhs.song.title
        }

        // Reset scroll and rebuild
        scrollOffset = 0
        rebuildSongList()
    }

    private func setupScrollContainer() {
        scrollContainer = SKNode()
        scrollContainer.name = "scrollContainer"
        addChild(scrollContainer)

        // Define visible area (below search bar)
        visibleAreaTop = size.height - 180  // Below header and search bar
        visibleAreaBottom = 20  // Above bottom of screen
    }

    private func showLoadingMessage() {
        let label = SKLabelNode(text: "Loading songs...")
        label.fontName = "Helvetica"
        label.fontSize = 24
        label.fontColor = .gray
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.name = "loadingLabel"
        addChild(label)
        loadingLabel = label
    }

    private func hideLoadingMessage() {
        loadingLabel?.removeFromParent()
        loadingLabel = nil
    }

    private func buildSortedSongList() {
        // Build sorted list from cached difficulties
        filteredSongs = songs.map { song -> (song: SongInfo, difficulty: Int) in
            let difficulty = SongManager.shared.getCachedDifficulty(for: song.id) ?? 3  // Fallback to medium
            return (song: song, difficulty: difficulty)
        }.sorted { lhs, rhs in
            if lhs.difficulty != rhs.difficulty {
                return lhs.difficulty < rhs.difficulty
            }
            return lhs.song.title < rhs.song.title
        }

        rebuildSongList()
    }

    private func rebuildSongList() {
        // Clear existing song rows
        scrollContainer.removeAllChildren()
        playButtons.removeAll()

        // Calculate content height
        contentHeight = CGFloat(filteredSongs.count) * rowHeight

        // Create rows in scroll container (positioned from top)
        for (index, item) in filteredSongs.enumerated() {
            let yPos = visibleAreaTop - CGFloat(index) * rowHeight - rowHeight / 2
            let (songRow, playButton) = createSongRow(song: item.song, difficulty: item.difficulty, at: yPos)
            scrollContainer.addChild(songRow)
            playButtons.append((button: playButton, song: item.song))
        }

        // Show message if no songs found
        childNode(withName: "noSongsLabel")?.removeFromParent()
        if filteredSongs.isEmpty {
            let noSongsLabel = SKLabelNode(text: searchQuery.isEmpty ? "No songs found" : "No matching songs")
            noSongsLabel.fontName = "Helvetica"
            noSongsLabel.fontSize = 24
            noSongsLabel.fontColor = .gray
            noSongsLabel.name = "noSongsLabel"
            noSongsLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(noSongsLabel)
        }

        // Apply current scroll offset
        updateScrollPosition()
    }

    private func updateScrollPosition() {
        scrollContainer.position.y = scrollOffset
    }

    private func createSongRow(song: SongInfo, difficulty: Int, at yPos: CGFloat) -> (container: SKNode, playButton: SKNode) {
        let container = SKNode()
        container.position = CGPoint(x: 0, y: yPos)
        container.name = "songRow_\(song.id)"

        let boxHeight = rowHeight - 10
        let difficultyBoxWidth = boxHeight  // Square difficulty box
        let cornerRadius: CGFloat = 10
        let padding: CGFloat = 20
        let songBoxWidth = size.width - padding * 2 - difficultyBoxWidth - 5  // 5pt gap between boxes
        let songBoxLeftEdge = padding + difficultyBoxWidth + 15

        // Difficulty box (left side, same height as song box)
        let difficultyBox = SKShapeNode(rectOf: CGSize(width: difficultyBoxWidth, height: boxHeight), cornerRadius: cornerRadius)
        difficultyBox.fillColor = SongListScene.difficultyColors[difficulty] ?? .gray
        difficultyBox.strokeColor = .clear
        difficultyBox.position = CGPoint(x: padding + difficultyBoxWidth / 2, y: 0)
        container.addChild(difficultyBox)

        let difficultyLabel = SKLabelNode(text: "\(difficulty)")
        difficultyLabel.fontName = "Helvetica-Bold"
        difficultyLabel.fontSize = 28
        difficultyLabel.fontColor = .white
        difficultyLabel.verticalAlignmentMode = .center
        difficultyLabel.horizontalAlignmentMode = .center
        difficultyLabel.position = CGPoint(x: padding + difficultyBoxWidth / 2, y: 0)
        container.addChild(difficultyLabel)

        // Song box (right of difficulty box, with curved edges)
        let songBoxX = padding + difficultyBoxWidth + 5 + songBoxWidth / 2
        let songBox = SKShapeNode(rectOf: CGSize(width: songBoxWidth, height: boxHeight), cornerRadius: cornerRadius)
        songBox.fillColor = UIColor(white: 0.95, alpha: 1.0)
        songBox.strokeColor = .clear
        songBox.position = CGPoint(x: songBoxX, y: 0)
        container.addChild(songBox)

        // Get progress for this song (validates file hash to detect replaced files)
        let progress = ProgressManager.shared.getProgress(for: song.id, fileURL: song.url)
        let hasProgress = progress.stars > 0 || progress.crowns > 0

        // Song title (top line)
        let titleLabel = SKLabelNode(text: song.title)
        titleLabel.fontName = "Helvetica"
        titleLabel.fontSize = 14
        titleLabel.fontColor = .black
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: songBoxLeftEdge, y: hasProgress ? 16 : 8)
        container.addChild(titleLabel)

        // Category (middle line)
        let categoryLabel = SKLabelNode(text: song.category)
        categoryLabel.fontName = "Helvetica"
        categoryLabel.fontSize = 11
        categoryLabel.fontColor = .darkGray
        categoryLabel.horizontalAlignmentMode = .left
        categoryLabel.verticalAlignmentMode = .center
        categoryLabel.position = CGPoint(x: songBoxLeftEdge, y: hasProgress ? 0 : -8)
        container.addChild(categoryLabel)

        // Stars/crowns (bottom line, only if has progress)
        if hasProgress {
            let earnedCount = progress.crowns > 0 ? progress.crowns : progress.stars
            let filledSymbol = progress.crowns > 0 ? "crown.fill" : "star.fill"
            let outlineSymbol = progress.crowns > 0 ? "crown" : "star"

            let iconSpacing: CGFloat = 14
            let goldenColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
            let iconSize = CGSize(width: 12, height: 12)

            // Show all 3 icons (filled for earned, outlined for remaining)
            // Add half icon width to align left edge with text (sprites are center-anchored)
            let iconStartX = songBoxLeftEdge + iconSize.width / 2
            for i in 0..<3 {
                let isFilled = i < earnedCount
                let symbolName = isFilled ? filledSymbol : outlineSymbol
                let color = isFilled ? goldenColor : .lightGray

                if let iconTexture = getProgressIcon(symbolName: symbolName, color: color, size: iconSize) {
                    let iconNode = SKSpriteNode(texture: iconTexture)
                    iconNode.position = CGPoint(x: iconStartX + CGFloat(i) * iconSpacing, y: -16)
                    container.addChild(iconNode)
                }
            }
        }

        // Play button container (larger hit area) - positioned relative to container
        let playButtonContainer = SKNode()
        playButtonContainer.position = CGPoint(x: size.width - padding - 25, y: 0)
        playButtonContainer.zPosition = 10  // Ensure it's above other elements

        // Invisible hit area (larger than the triangle for easier tapping)
        let hitAreaSize: CGFloat = 44
        let hitArea = SKShapeNode(rectOf: CGSize(width: hitAreaSize, height: hitAreaSize))
        hitArea.fillColor = .clear
        hitArea.strokeColor = .clear
        playButtonContainer.addChild(hitArea)

        // Visible triangle
        let triangleSize: CGFloat = 16
        let trianglePath = CGMutablePath()
        trianglePath.move(to: CGPoint(x: -triangleSize / 2, y: -triangleSize / 2))
        trianglePath.addLine(to: CGPoint(x: -triangleSize / 2, y: triangleSize / 2))
        trianglePath.addLine(to: CGPoint(x: triangleSize / 2, y: 0))
        trianglePath.closeSubpath()

        let triangle = SKShapeNode(path: trianglePath)
        triangle.fillColor = .black
        triangle.strokeColor = .clear
        playButtonContainer.addChild(triangle)

        container.addChild(playButtonContainer)

        return (container, playButtonContainer)
    }

    // MARK: - Difficulty Calculation

    /// Calculate difficulty level (1-5) for a song based on notes per second (screen independent)
    private func calculateDifficulty(for song: SongInfo) -> Int {
        let notesPerSecond = calculateNotesPerSecond(for: song)

        for (maxNotesPerSec, level) in SongListScene.difficultyThresholds {
            if notesPerSecond <= maxNotesPerSec {
                return level
            }
        }
        return 5  // Highest difficulty for > 7 notes/sec
    }

    /// Calculate notes per second for a song (screen independent difficulty metric)
    private func calculateNotesPerSecond(for song: SongInfo) -> CGFloat {
        // If custom speed is provided, estimate notes/sec from it
        // Using a reference tile height of 200 pts (typical screen)
        if let customSpeed = song.customSpeed {
            let referenceTileHeight: CGFloat = 200
            return customSpeed / referenceTileHeight
        }

        // Parse MIDI to calculate actual note density
        let parser = MidiParser()
        guard let beatmap = parser.parse(url: song.url) else {
            return 2.5  // Default fallback (medium difficulty)
        }

        return CGFloat(beatmap.notes.count) / CGFloat(beatmap.totalDuration)
    }

    // MARK: - Async Difficulty Loading

    /// Calculate difficulties asynchronously for songs without cached values
    private func calculateDifficultiesAsync(for songs: [SongInfo]) {
        pendingDifficultyCalculations = Set(songs.map { $0.id })

        for song in songs {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                // Calculate difficulty (this is the expensive MIDI parsing)
                let difficulty = self.calculateDifficulty(for: song)

                // Cache the result with file fingerprint
                SongManager.shared.cacheDifficulty(difficulty, for: song.id, fileURL: song.url)

                // Update UI on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.pendingDifficultyCalculations.remove(song.id)

                    // When all calculations are complete, show the sorted list
                    if self.pendingDifficultyCalculations.isEmpty {
                        self.hideLoadingMessage()
                        self.buildSortedSongList()
                    }
                }
            }
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Dismiss keyboard when tapping outside search bar
        searchTextField?.resignFirstResponder()

        // Check back button
        if let backButton = childNode(withName: "backButton"),
           backButton.contains(location) {
            transitionToHome()
            return
        }

        // Check play buttons only (not the entire song row)
        for (button, song) in playButtons {
            // Convert scene location to the button's parent coordinate space
            if let parent = button.parent {
                let locationInParent = parent.convert(location, from: self)
                if button.contains(locationInParent) {
                    startGame(with: song)
                    return
                }
            }
        }

        // Start scroll tracking
        lastTouchY = location.y
        lastTouchTime = CACurrentMediaTime()
        scrollVelocity = 0  // Stop any existing momentum
        isDragging = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDragging, let touch = touches.first else { return }
        let location = touch.location(in: self)
        let currentTime = CACurrentMediaTime()

        let deltaY = location.y - lastTouchY
        let deltaTime = currentTime - lastTouchTime

        // Calculate velocity (points per second)
        if deltaTime > 0 {
            scrollVelocity = deltaY / CGFloat(deltaTime)
        }

        lastTouchY = location.y
        lastTouchTime = currentTime

        // Update scroll offset
        scrollOffset += deltaY
        clampScrollOffset()
        updateScrollPosition()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDragging = false
        // Velocity is preserved for momentum scrolling
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDragging = false
        scrollVelocity = 0
    }

    override func update(_ currentTime: TimeInterval) {
        // Apply momentum scrolling when not dragging
        guard !isDragging, abs(scrollVelocity) > minVelocity else { return }

        // Apply velocity (scaled for 60fps frame time)
        let frameTime: CGFloat = 1.0 / 60.0
        scrollOffset += scrollVelocity * frameTime
        clampScrollOffset()
        updateScrollPosition()

        // Apply deceleration
        scrollVelocity *= decelerationRate
    }

    private func clampScrollOffset() {
        let visibleHeight = visibleAreaTop - visibleAreaBottom
        let maxScroll = max(0, contentHeight - visibleHeight)
        scrollOffset = max(0, min(scrollOffset, maxScroll))

        // Stop velocity at bounds
        if scrollOffset <= 0 || scrollOffset >= maxScroll {
            scrollVelocity = 0
        }
    }

    // MARK: - Navigation

    private func transitionToHome() {
        searchTextField?.removeFromSuperview()
        searchTextField = nil

        let homeScene = HomeScene(size: size)
        homeScene.scaleMode = scaleMode
        view?.presentScene(homeScene)
    }

    private func startGame(with song: SongInfo) {
        searchTextField?.removeFromSuperview()
        searchTextField = nil

        let gameScene = GameScene(size: size, songURL: song.url, customSpeed: song.customSpeed, startFromNote: song.startFromNote)
        gameScene.scaleMode = scaleMode
        view?.presentScene(gameScene)
    }

    // MARK: - Progress Icon Rendering

    // Cache for progress icon textures (only 4 unique icons needed)
    private static var cachedProgressIcons: [String: SKTexture] = [:]

    /// Gets a cached progress icon texture, creating it if needed
    private func getProgressIcon(symbolName: String, color: UIColor, size: CGSize) -> SKTexture? {
        let key = "\(symbolName)-\(color.cgColor.hashValue)"

        if let cached = SongListScene.cachedProgressIcons[key] {
            return cached
        }

        if let texture = renderProgressIcon(symbolName: symbolName, color: color, size: size) {
            SongListScene.cachedProgressIcons[key] = texture
            return texture
        }
        return nil
    }

    /// Renders a colored SF Symbol as a texture for progress display
    private func renderProgressIcon(symbolName: String, color: UIColor, size: CGSize) -> SKTexture? {
        let config = UIImage.SymbolConfiguration(pointSize: size.height, weight: .regular)
        guard let symbolImage = UIImage(systemName: symbolName, withConfiguration: config) else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()

            // Scale symbol to fit within bounds while maintaining aspect ratio
            let symbolSize = symbolImage.size
            let scale = min(size.width / symbolSize.width, size.height / symbolSize.height)
            let scaledWidth = symbolSize.width * scale
            let scaledHeight = symbolSize.height * scale

            // Center the symbol
            let x = (size.width - scaledWidth) / 2
            let y = (size.height - scaledHeight) / 2
            let drawRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)

            symbolImage.draw(in: drawRect, blendMode: .normal, alpha: 1.0)
            context.fill(CGRect(origin: .zero, size: size), blendMode: .sourceIn)
        }

        return SKTexture(image: image)
    }
}

// MARK: - UITextFieldDelegate

extension SongListScene: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
