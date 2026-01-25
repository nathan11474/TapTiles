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

    // Tab system
    private enum Tab: String, CaseIterable {
        case songs = "Songs"
        case favorites = "Favorites"
        case imports = "Imports"
    }
    private var currentTab: Tab = .songs
    private var tabNodes: [Tab: SKNode] = [:]
    private var tabUnderlines: [Tab: SKShapeNode] = [:]
    private var emptyFavoritesLabel: SKLabelNode?
    private var emptyImportsLabel: SKLabelNode?

    // Favorite buttons
    private var favoriteButtons: [(button: SKNode, song: SongInfo)] = []

    // Delete buttons (for imported songs)
    private var deleteButtons: [(button: SKNode, song: SongInfo)] = []

    // Edit buttons (for imported songs)
    private var editButtons: [(button: SKNode, song: SongInfo)] = []

    // Import button (shown on Imports tab)
    private var importButton: SKNode?

    // Cache for heart icon textures
    private static var cachedHeartIcons: [String: SKTexture] = [:]

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

        // Tab bar
        setupTabBar()
    }

    private func setupTabBar() {
        // Center tabs between back button (y: size.height - 60) and search bar (y: size.height - 125)
        let tabY = size.height - 92
        let tabSpacing: CGFloat = 110
        let totalWidth = tabSpacing * CGFloat(Tab.allCases.count - 1)
        let startX = (size.width - totalWidth) / 2

        for (index, tab) in Tab.allCases.enumerated() {
            let tabX = startX + CGFloat(index) * tabSpacing

            // Tab container for hit testing
            let tabContainer = SKNode()
            tabContainer.position = CGPoint(x: tabX, y: tabY)
            tabContainer.name = "tab_\(tab.rawValue)"
            tabContainer.zPosition = 101

            // Tab label
            let tabLabel = SKLabelNode(text: tab.rawValue)
            tabLabel.fontName = tab == currentTab ? "Helvetica-Bold" : "Helvetica"
            tabLabel.fontSize = 22
            tabLabel.fontColor = tab == currentTab ? .black : .gray
            tabLabel.verticalAlignmentMode = .baseline
            tabLabel.horizontalAlignmentMode = .center
            tabLabel.name = "tabLabel"
            tabContainer.addChild(tabLabel)

            // Underline indicator (only visible for active tab)
            let underlineWidth: CGFloat = 60
            let underlineHeight: CGFloat = 3
            let underline = SKShapeNode(rectOf: CGSize(width: underlineWidth, height: underlineHeight), cornerRadius: 1.5)
            underline.fillColor = .black
            underline.strokeColor = .clear
            underline.position = CGPoint(x: 0, y: -20)
            underline.alpha = tab == currentTab ? 1.0 : 0.0
            underline.name = "tabUnderline"
            tabContainer.addChild(underline)

            addChild(tabContainer)
            tabNodes[tab] = tabContainer
            tabUnderlines[tab] = underline
        }

        // Setup import button (initially hidden, shown only on Imports tab)
        setupImportButton()
    }

    private func setupImportButton() {
        let padding: CGFloat = 20
        let buttonWidth = size.width - padding * 2
        let buttonHeight: CGFloat = 44
        let gapBetweenRows: CGFloat = 10  // Same gap as between song cards

        // Search bar: y=125 from top (UIKit), height=40, so bottom at y=165 from top
        // In SpriteKit: search bar bottom is at size.height - 165
        // Button top should be 10pt below search bar bottom
        let searchBarBottomSpriteKit = size.height - 165
        let buttonTop = searchBarBottomSpriteKit - gapBetweenRows
        let buttonY = buttonTop - buttonHeight / 2

        let buttonContainer = SKNode()
        buttonContainer.position = CGPoint(x: size.width / 2, y: buttonY)
        buttonContainer.zPosition = 101
        buttonContainer.name = "importButton"
        buttonContainer.alpha = 0  // Hidden by default

        // Button background (rounded rectangle matching search bar width)
        let buttonBackground = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 8)
        buttonBackground.fillColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        buttonBackground.strokeColor = .clear
        buttonBackground.name = "importButtonBackground"
        buttonContainer.addChild(buttonBackground)

        // Button text (will be updated based on purchase state)
        let buttonLabel = SKLabelNode(text: "Import")
        buttonLabel.fontName = "Helvetica-Bold"
        buttonLabel.fontSize = 18
        buttonLabel.fontColor = .white
        buttonLabel.verticalAlignmentMode = .center
        buttonLabel.horizontalAlignmentMode = .center
        buttonLabel.name = "importButtonLabel"
        buttonContainer.addChild(buttonLabel)

        addChild(buttonContainer)
        importButton = buttonContainer

        // Update appearance based on purchase state
        updateImportButtonAppearance()
    }

    private func updateImportButtonAppearance() {
        guard let buttonContainer = importButton,
              let buttonLabel = buttonContainer.childNode(withName: "importButtonLabel") as? SKLabelNode else {
            return
        }

        Task { @MainActor in
            let isUnlocked = StoreManager.shared.isImportUnlocked

            if isUnlocked {
                buttonLabel.text = "Import"
            } else {
                let price = StoreManager.shared.importFeaturePrice
                buttonLabel.text = "🔒 Unlock Import (\(price))"
            }
        }
    }

    private func switchToTab(_ tab: Tab) {
        guard tab != currentTab else { return }

        // Hide loading message if still visible (from async difficulty calculation)
        hideLoadingMessage()

        // Update tab appearance
        for (t, container) in tabNodes {
            if let label = container.childNode(withName: "tabLabel") as? SKLabelNode {
                label.fontName = t == tab ? "Helvetica-Bold" : "Helvetica"
                label.fontColor = t == tab ? .black : .gray
            }
            tabUnderlines[t]?.alpha = t == tab ? 1.0 : 0.0
        }

        currentTab = tab
        scrollOffset = 0
        scrollVelocity = 0

        // Show/hide import button and adjust visible area based on tab
        if tab == .imports {
            updateImportButtonAppearance()
            importButton?.alpha = 1.0
            // Adjust visible area to account for import button
            // Button bottom is at: (size.height - 175 - 22) - 22 = size.height - 219
            // First song box top should be 10pt below that: size.height - 229
            // Song box top = visibleAreaTop - 5, so visibleAreaTop = size.height - 224
            visibleAreaTop = size.height - 224
        } else {
            importButton?.alpha = 0.0
            visibleAreaTop = size.height - 180
        }

        // Update content based on tab
        switch tab {
        case .songs:
            hideEmptyFavoritesMessage()
            hideEmptyImportsMessage()
            searchTextField?.isHidden = false
            filterAndRebuildSongList()
        case .favorites:
            childNode(withName: "noSongsLabel")?.removeFromParent()
            hideEmptyImportsMessage()
            searchTextField?.isHidden = false
            filterAndRebuildFavorites()
        case .imports:
            childNode(withName: "noSongsLabel")?.removeFromParent()
            hideEmptyFavoritesMessage()
            searchTextField?.isHidden = false
            filterAndRebuildImports()
        }
    }

    private func filterAndRebuildFavorites() {
        hideEmptyFavoritesMessage()

        // Get all favorited bundled songs with their difficulties
        var favoriteSongs = songs.filter { song in
            ProgressManager.shared.isFavorite(for: song.id, fileURL: song.url)
        }.map { song -> (song: SongInfo, difficulty: Int) in
            let difficulty = SongManager.shared.getCachedDifficulty(for: song.id) ?? 3
            return (song: song, difficulty: difficulty)
        }

        // Also include favorited imported songs
        let favoriteImportedSongs = ImportedSongManager.shared.availableImportedSongs.filter { song in
            ProgressManager.shared.isFavorite(for: song.id, fileURL: song.url)
        }.map { song -> (song: SongInfo, difficulty: Int) in
            let difficulty = SongManager.shared.getCachedDifficulty(for: song.id, fileURL: song.url) ?? calculateAndCacheDifficulty(for: song)
            return (song: song, difficulty: difficulty)
        }
        favoriteSongs.append(contentsOf: favoriteImportedSongs)

        // Apply search filter if query is not empty
        if !searchQuery.isEmpty {
            favoriteSongs = favoriteSongs.filter {
                $0.song.title.localizedCaseInsensitiveContains(searchQuery) ||
                $0.song.category.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        // Sort by difficulty, then by name
        favoriteSongs.sort { lhs, rhs in
            if lhs.difficulty != rhs.difficulty {
                return lhs.difficulty < rhs.difficulty
            }
            return lhs.song.title < rhs.song.title
        }

        filteredSongs = favoriteSongs
        rebuildSongList()

        // Show empty message if no favorites
        if favoriteSongs.isEmpty {
            showEmptyFavoritesMessage()
        }
    }

    private func showEmptyFavoritesMessage() {
        guard emptyFavoritesLabel == nil else { return }

        let message = searchQuery.isEmpty ? "No favorites yet" : "No matching favorites"
        let label = SKLabelNode(text: message)
        label.fontName = "Helvetica"
        label.fontSize = 24
        label.fontColor = .gray
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.name = "emptyFavoritesLabel"
        addChild(label)
        emptyFavoritesLabel = label
    }

    private func hideEmptyFavoritesMessage() {
        emptyFavoritesLabel?.removeFromParent()
        emptyFavoritesLabel = nil
    }

    private func filterAndRebuildImports() {
        hideEmptyImportsMessage()

        // Get imported songs from ImportedSongManager
        var importedSongs = ImportedSongManager.shared.availableImportedSongs.map { song -> (song: SongInfo, difficulty: Int) in
            // Get cached difficulty or calculate it
            let difficulty = SongManager.shared.getCachedDifficulty(for: song.id, fileURL: song.url) ?? calculateAndCacheDifficulty(for: song)
            return (song: song, difficulty: difficulty)
        }

        // Apply search filter if query is not empty
        if !searchQuery.isEmpty {
            importedSongs = importedSongs.filter {
                $0.song.title.localizedCaseInsensitiveContains(searchQuery) ||
                $0.song.category.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        // Sort by difficulty, then by name
        importedSongs.sort { lhs, rhs in
            if lhs.difficulty != rhs.difficulty {
                return lhs.difficulty < rhs.difficulty
            }
            return lhs.song.title < rhs.song.title
        }

        filteredSongs = importedSongs
        rebuildSongList()

        // Show empty message if no imports
        if importedSongs.isEmpty {
            showEmptyImportsMessage()
        }
    }

    /// Calculates and caches difficulty for a song (used for imported songs)
    private func calculateAndCacheDifficulty(for song: SongInfo) -> Int {
        let difficulty = calculateDifficulty(for: song)
        SongManager.shared.cacheDifficulty(difficulty, for: song.id, fileURL: song.url)
        return difficulty
    }

    private func showEmptyImportsMessage() {
        guard emptyImportsLabel == nil else { return }

        let message = searchQuery.isEmpty ? "No imports yet" : "No matching imports"
        let label = SKLabelNode(text: message)
        label.fontName = "Helvetica"
        label.fontSize = 24
        label.fontColor = .gray
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.name = "emptyImportsLabel"
        addChild(label)
        emptyImportsLabel = label
    }

    private func hideEmptyImportsMessage() {
        emptyImportsLabel?.removeFromParent()
        emptyImportsLabel = nil
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
            guard let self = self else { return }
            switch self.currentTab {
            case .songs:
                self.filterAndRebuildSongList()
            case .favorites:
                self.filterAndRebuildFavorites()
            case .imports:
                self.filterAndRebuildImports()
            }
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
        favoriteButtons.removeAll()
        deleteButtons.removeAll()
        editButtons.removeAll()

        // Calculate content height
        contentHeight = CGFloat(filteredSongs.count) * rowHeight

        // Create rows in scroll container (positioned from top)
        for (index, item) in filteredSongs.enumerated() {
            let yPos = visibleAreaTop - CGFloat(index) * rowHeight - rowHeight / 2
            // Check if song is imported by seeing if its ID has the imported prefix
            let isImported = item.song.id.hasPrefix(ImportedSongManager.importedIdPrefix)
            let (songRow, playButton, favoriteButton, deleteButton, editButton) = createSongRow(song: item.song, difficulty: item.difficulty, at: yPos, isImported: isImported)
            scrollContainer.addChild(songRow)
            playButtons.append((button: playButton, song: item.song))
            favoriteButtons.append((button: favoriteButton, song: item.song))
            if let deleteBtn = deleteButton {
                deleteButtons.append((button: deleteBtn, song: item.song))
            }
            if let editBtn = editButton {
                editButtons.append((button: editBtn, song: item.song))
            }
        }

        // Show message if no songs found (only on Songs tab - Favorites tab handles its own empty state)
        childNode(withName: "noSongsLabel")?.removeFromParent()
        if filteredSongs.isEmpty && currentTab == .songs {
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

    private func createSongRow(song: SongInfo, difficulty: Int, at yPos: CGFloat, isImported: Bool = false) -> (container: SKNode, playButton: SKNode, favoriteButton: SKNode, deleteButton: SKNode?, editButton: SKNode?) {
        let container = SKNode()
        container.position = CGPoint(x: 0, y: yPos)
        container.name = "songRow_\(song.id)"

        let boxHeight = rowHeight - 10
        let difficultyBoxWidth: CGFloat = 50  // Narrower difficulty box
        let cornerRadius: CGFloat = 10
        let padding: CGFloat = 20
        let songBoxWidth = size.width - padding * 2 - difficultyBoxWidth - 5  // 5pt gap between boxes
        let songBoxLeftEdge = padding + difficultyBoxWidth + 15

        // Check if song is favorited
        let isFavorited = ProgressManager.shared.isFavorite(for: song.id, fileURL: song.url)

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

        // Right side buttons positioning
        // For imported songs: heart icon at top, edit in middle, delete below, play at bottom
        // For regular songs: heart icon at top, play at bottom
        let rightEdgeX = size.width - padding - 25

        // Favorite button (heart icon) - positioned at top right
        let favoriteButtonContainer = SKNode()
        favoriteButtonContainer.position = CGPoint(x: rightEdgeX, y: isImported ? 22 : 18)
        favoriteButtonContainer.zPosition = 10
        favoriteButtonContainer.name = "favoriteButton_\(song.id)"

        // Invisible hit area for easier tapping
        let favoriteHitAreaSize: CGFloat = 36
        let favoriteHitArea = SKShapeNode(rectOf: CGSize(width: favoriteHitAreaSize, height: favoriteHitAreaSize))
        favoriteHitArea.fillColor = .clear
        favoriteHitArea.strokeColor = .clear
        favoriteButtonContainer.addChild(favoriteHitArea)

        // Heart icon
        let heartIconSize = CGSize(width: 20, height: 20)
        if let heartTexture = getHeartIcon(filled: isFavorited, size: heartIconSize) {
            let heartIcon = SKSpriteNode(texture: heartTexture)
            heartIcon.name = "heartIcon"
            favoriteButtonContainer.addChild(heartIcon)
        }

        container.addChild(favoriteButtonContainer)

        // Edit and delete buttons (only for imported songs)
        var deleteButtonContainer: SKNode?
        var editButtonContainer: SKNode?

        if isImported {
            // Edit button (pencil icon) - positioned below heart
            let editContainer = SKNode()
            editContainer.position = CGPoint(x: rightEdgeX, y: 0)
            editContainer.zPosition = 10
            editContainer.name = "editButton_\(song.id)"

            let editHitArea = SKShapeNode(rectOf: CGSize(width: 36, height: 36))
            editHitArea.fillColor = .clear
            editHitArea.strokeColor = .clear
            editContainer.addChild(editHitArea)

            let editIconSize = CGSize(width: 18, height: 18)
            if let editTexture = getActionIcon(symbolName: "pencil", color: .darkGray, size: editIconSize) {
                let editIcon = SKSpriteNode(texture: editTexture)
                editContainer.addChild(editIcon)
            }

            container.addChild(editContainer)
            editButtonContainer = editContainer

            // Delete button (trash icon) - positioned below edit
            let deleteContainer = SKNode()
            deleteContainer.position = CGPoint(x: rightEdgeX, y: -22)
            deleteContainer.zPosition = 10
            deleteContainer.name = "deleteButton_\(song.id)"

            let deleteHitArea = SKShapeNode(rectOf: CGSize(width: 36, height: 36))
            deleteHitArea.fillColor = .clear
            deleteHitArea.strokeColor = .clear
            deleteContainer.addChild(deleteHitArea)

            let deleteIconSize = CGSize(width: 18, height: 18)
            if let deleteTexture = getActionIcon(symbolName: "trash", color: .systemRed, size: deleteIconSize) {
                let deleteIcon = SKSpriteNode(texture: deleteTexture)
                deleteContainer.addChild(deleteIcon)
            }

            container.addChild(deleteContainer)
            deleteButtonContainer = deleteContainer
        }

        // Play button container (larger hit area) - positioned at bottom right
        let playButtonContainer = SKNode()
        playButtonContainer.position = CGPoint(x: rightEdgeX, y: isImported ? -22 : -14)
        playButtonContainer.zPosition = 10  // Ensure it's above other elements

        // For imported songs, play button is positioned differently (to the left of delete)
        if isImported {
            playButtonContainer.position = CGPoint(x: rightEdgeX - 40, y: 0)
        }

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

        return (container, playButtonContainer, favoriteButtonContainer, deleteButtonContainer, editButtonContainer)
    }

    /// Gets an action icon texture (edit, delete) - caches similar to heart icons
    private static var cachedActionIcons: [String: SKTexture] = [:]

    private func getActionIcon(symbolName: String, color: UIColor, size: CGSize) -> SKTexture? {
        let key = "\(symbolName)-\(color.cgColor.hashValue)"

        if let cached = SongListScene.cachedActionIcons[key] {
            return cached
        }

        if let texture = renderProgressIcon(symbolName: symbolName, color: color, size: size) {
            SongListScene.cachedActionIcons[key] = texture
            return texture
        }
        return nil
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

                    // When all calculations are complete, rebuild the current tab's content
                    if self.pendingDifficultyCalculations.isEmpty {
                        self.hideLoadingMessage()
                        // Rebuild based on which tab is currently active
                        switch self.currentTab {
                        case .songs:
                            self.filterAndRebuildSongList()
                        case .favorites:
                            self.filterAndRebuildFavorites()
                        case .imports:
                            self.filterAndRebuildImports()
                        }
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

        // Check tab buttons
        for tab in Tab.allCases {
            if let tabNode = tabNodes[tab] {
                // Create a hit area around the tab (larger than just the text)
                let hitAreaWidth: CGFloat = 70
                let hitAreaHeight: CGFloat = 50
                let tabLocation = tabNode.position
                let hitRect = CGRect(
                    x: tabLocation.x - hitAreaWidth / 2,
                    y: tabLocation.y - hitAreaHeight / 2,
                    width: hitAreaWidth,
                    height: hitAreaHeight
                )
                if hitRect.contains(location) {
                    switchToTab(tab)
                    return
                }
            }
        }

        // Check import button (only visible on Imports tab)
        if currentTab == .imports, let importBtn = importButton {
            let padding: CGFloat = 20
            let buttonWidth = size.width - padding * 2
            let buttonHeight: CGFloat = 44
            let hitRect = CGRect(
                x: importBtn.position.x - buttonWidth / 2,
                y: importBtn.position.y - buttonHeight / 2,
                width: buttonWidth,
                height: buttonHeight
            )
            if hitRect.contains(location) {
                transitionToImport()
                return
            }
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

        // Check favorite buttons
        for (button, song) in favoriteButtons {
            if let parent = button.parent {
                let locationInParent = parent.convert(location, from: self)
                if button.contains(locationInParent) {
                    toggleFavorite(for: song, button: button)
                    return
                }
            }
        }

        // Check delete buttons (imported songs only)
        for (button, song) in deleteButtons {
            if let parent = button.parent {
                let locationInParent = parent.convert(location, from: self)
                if button.contains(locationInParent) {
                    showDeleteConfirmation(for: song)
                    return
                }
            }
        }

        // Check edit buttons (imported songs only)
        for (button, song) in editButtons {
            if let parent = button.parent {
                let locationInParent = parent.convert(location, from: self)
                if button.contains(locationInParent) {
                    transitionToEditSong(song)
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

    private func transitionToImport() {
        // Check if import feature is unlocked
        Task { @MainActor in
            if StoreManager.shared.isImportUnlocked {
                // Feature unlocked - go to import
                self.searchTextField?.removeFromSuperview()
                self.searchTextField = nil

                let importScene = ImportScene(size: self.size)
                importScene.scaleMode = self.scaleMode
                self.view?.presentScene(importScene)
            } else {
                // Show purchase prompt
                self.showPurchasePrompt()
            }
        }
    }

    private func showPurchasePrompt() {
        guard let windowScene = view?.window?.windowScene,
              let viewController = windowScene.windows.first?.rootViewController else {
            return
        }

        let price = StoreManager.shared.importFeaturePrice

        let alert = UIAlertController(
            title: "Unlock Import Feature",
            message: "Import your own MIDI files to play custom songs.\n\nPrice: \(price)",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        alert.addAction(UIAlertAction(title: "Buy \(price)", style: .default) { [weak self] _ in
            self?.handlePurchase()
        })

        alert.addAction(UIAlertAction(title: "Restore Purchases", style: .default) { [weak self] _ in
            self?.handleRestore()
        })

        viewController.present(alert, animated: true)
    }

    private func handlePurchase() {
        Task { @MainActor in
            let success = await StoreManager.shared.purchaseImportFeature()

            if success {
                // Purchase successful - transition to import
                self.searchTextField?.removeFromSuperview()
                self.searchTextField = nil

                let importScene = ImportScene(size: self.size)
                importScene.scaleMode = self.scaleMode
                self.view?.presentScene(importScene)
            } else if let error = StoreManager.shared.errorMessage {
                self.showErrorAlert(message: error)
            }
        }
    }

    private func handleRestore() {
        Task { @MainActor in
            await StoreManager.shared.restorePurchases()

            if StoreManager.shared.isImportUnlocked {
                // Restored successfully - show success and allow access
                self.showSuccessAlert(message: "Import feature restored!") {
                    self.transitionToImport()
                }
            } else {
                self.showErrorAlert(message: "No previous purchase found")
            }
        }
    }

    private func showErrorAlert(message: String) {
        guard let windowScene = view?.window?.windowScene,
              let viewController = windowScene.windows.first?.rootViewController else {
            return
        }

        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
    }

    private func showSuccessAlert(message: String, completion: @escaping () -> Void) {
        guard let windowScene = view?.window?.windowScene,
              let viewController = windowScene.windows.first?.rootViewController else {
            completion()
            return
        }

        let alert = UIAlertController(
            title: "Success",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion()
        })
        viewController.present(alert, animated: true)
    }

    private func transitionToEditSong(_ song: SongInfo) {
        searchTextField?.removeFromSuperview()
        searchTextField = nil

        let editScene = EditImportedSongScene(size: size, song: song)
        editScene.scaleMode = scaleMode
        view?.presentScene(editScene)
    }

    private func showDeleteConfirmation(for song: SongInfo) {
        guard let windowScene = view?.window?.windowScene,
              let viewController = windowScene.windows.first?.rootViewController else {
            return
        }

        let alert = UIAlertController(
            title: "Delete Song",
            message: "Are you sure you want to delete \"\(song.title)\"? This cannot be undone.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteImportedSong(song)
        })

        viewController.present(alert, animated: true)
    }

    private func deleteImportedSong(_ song: SongInfo) {
        // Delete from ImportedSongManager
        if ImportedSongManager.shared.deleteImportedSong(id: song.id) {
            // Clear any cached difficulty
            SongManager.shared.clearCachedDifficulty(for: song.id)

            // Clear progress data (high score, stars, crowns, favorite status)
            ProgressManager.shared.clearProgress(for: song.id)

            // Rebuild the imports list
            filterAndRebuildImports()

            #if DEBUG
            print("SongListScene: Successfully deleted imported song '\(song.title)'")
            #endif
        } else {
            #if DEBUG
            print("SongListScene: Failed to delete imported song '\(song.title)'")
            #endif
        }
    }

    private func toggleFavorite(for song: SongInfo, button: SKNode) {
        let isNowFavorite = ProgressManager.shared.toggleFavorite(for: song.id, fileURL: song.url)

        // Update the heart icon
        if let heartIcon = button.childNode(withName: "heartIcon") as? SKSpriteNode {
            let heartIconSize = CGSize(width: 22, height: 22)
            if let newTexture = getHeartIcon(filled: isNowFavorite, size: heartIconSize) {
                heartIcon.texture = newTexture
            }
        }

        // If we're on the favorites tab and unfavorited, remove from list
        if currentTab == .favorites && !isNowFavorite {
            // Rebuild to remove the unfavorited song
            filterAndRebuildFavorites()
        }
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

    // MARK: - Heart Icon Rendering

    /// Gets a cached heart icon texture, creating it if needed
    private func getHeartIcon(filled: Bool, size: CGSize) -> SKTexture? {
        let symbolName = filled ? "heart.fill" : "heart"
        let color: UIColor = filled ? .systemRed : .lightGray
        let key = "\(symbolName)-\(filled ? "red" : "gray")"

        if let cached = SongListScene.cachedHeartIcons[key] {
            return cached
        }

        if let texture = renderProgressIcon(symbolName: symbolName, color: color, size: size) {
            SongListScene.cachedHeartIcons[key] = texture
            return texture
        }
        return nil
    }
}

// MARK: - UITextFieldDelegate

extension SongListScene: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
