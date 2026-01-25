//
//  LoadingScene.swift
//  TilesRemake
//

import SpriteKit

/// Loading screen that preloads all resources before showing the home screen
class LoadingScene: SKScene {

    // MARK: - Properties

    private var loadingLabel: SKLabelNode!
    private var dotTimer: Timer?
    private var dotCount = 0

    // Track completion of each loading task
    private var adMobReady = false
    private var audioReady = false
    private var songsReady = false
    private var storeReady = false

    private var hasTransitioned = false
    private let minimumDisplayTime: TimeInterval = 1.5  // Minimum time to show loading screen
    private var sceneStartTime: TimeInterval = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .white
        sceneStartTime = CACurrentMediaTime()

        setupUI()
        startLoadingAnimation()
        startLoadingResources()
    }

    override func willMove(from view: SKView) {
        dotTimer?.invalidate()
        dotTimer = nil
    }

    // MARK: - UI Setup

    private func setupUI() {
        let tileWidth = size.width / 2
        let tileHeight = size.height / 2

        // Top-left: Black tile
        let topLeftTile = SKShapeNode(rectOf: CGSize(width: tileWidth, height: tileHeight))
        topLeftTile.fillColor = .black
        topLeftTile.strokeColor = .clear
        topLeftTile.position = CGPoint(x: tileWidth / 2, y: size.height - tileHeight / 2)
        addChild(topLeftTile)

        // Top-right: White tile
        let topRightTile = SKShapeNode(rectOf: CGSize(width: tileWidth, height: tileHeight))
        topRightTile.fillColor = .white
        topRightTile.strokeColor = .clear
        topRightTile.position = CGPoint(x: size.width - tileWidth / 2, y: size.height - tileHeight / 2)
        addChild(topRightTile)

        // Bottom-left: White tile
        let bottomLeftTile = SKShapeNode(rectOf: CGSize(width: tileWidth, height: tileHeight))
        bottomLeftTile.fillColor = .white
        bottomLeftTile.strokeColor = .clear
        bottomLeftTile.position = CGPoint(x: tileWidth / 2, y: tileHeight / 2)
        addChild(bottomLeftTile)

        // Bottom-right: Black tile
        let bottomRightTile = SKShapeNode(rectOf: CGSize(width: tileWidth, height: tileHeight))
        bottomRightTile.fillColor = .black
        bottomRightTile.strokeColor = .clear
        bottomRightTile.position = CGPoint(x: size.width - tileWidth / 2, y: tileHeight / 2)
        addChild(bottomRightTile)

        // "Tap" label centered in top-left tile
        let tapLabel = SKLabelNode(text: "Tap")
        tapLabel.fontName = "Helvetica-Bold"
        tapLabel.fontSize = 64
        tapLabel.fontColor = .white
        tapLabel.verticalAlignmentMode = .baseline
        tapLabel.horizontalAlignmentMode = .center
        tapLabel.position = CGPoint(x: tileWidth / 2, y: size.height - tileHeight / 2)
        tapLabel.zPosition = 10
        addChild(tapLabel)

        // "Tiles" label centered in top-right tile
        let tilesLabel = SKLabelNode(text: "Tiles")
        tilesLabel.fontName = "Helvetica-Bold"
        tilesLabel.fontSize = 64
        tilesLabel.fontColor = .black
        tilesLabel.verticalAlignmentMode = .baseline
        tilesLabel.horizontalAlignmentMode = .center
        tilesLabel.position = CGPoint(x: size.width - tileWidth / 2, y: size.height - tileHeight / 2)
        tilesLabel.zPosition = 10
        addChild(tilesLabel)

        // Loading button (grey rounded rectangle like Play button)
        let loadingButton = createLoadingButton()
        loadingButton.position = CGPoint(x: size.width / 2, y: size.height * 0.35)
        loadingButton.zPosition = 10
        addChild(loadingButton)
    }

    private func createLoadingButton() -> SKNode {
        let container = SKNode()

        let buttonWidth: CGFloat = 200
        let buttonHeight: CGFloat = 44
        let cornerRadius: CGFloat = 22
        let greyColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)

        // Grey rounded button background
        let background = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: cornerRadius)
        background.fillColor = greyColor
        background.strokeColor = .clear
        container.addChild(background)

        // Button label
        loadingLabel = SKLabelNode(text: "Loading")
        loadingLabel.fontName = "Helvetica-Bold"
        loadingLabel.fontSize = 20
        loadingLabel.fontColor = .white
        loadingLabel.verticalAlignmentMode = .center
        container.addChild(loadingLabel)

        return container
    }

    // MARK: - Loading Animation

    private func startLoadingAnimation() {
        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.dotCount = (self.dotCount + 1) % 4
            let dots = String(repeating: ".", count: self.dotCount)
            self.loadingLabel.text = "Loading\(dots)"
        }
    }

    // MARK: - Resource Loading

    private func startLoadingResources() {
        // 1. Initialize AdMob (already started in AppDelegate, just wait for SDK init)
        AdManager.shared.notifyWhenReady { [weak self] in
            self?.adMobReady = true
            self?.checkAllLoaded()
        }

        // 2. Start audio loading in background (don't block on it)
        // Audio will be ready by the time user navigates to a song
        AudioManager.shared.setupAsync()
        audioReady = true  // Mark ready immediately, loading continues in background
        checkAllLoaded()

        // 3. Force SongManager initialization (loads songs and cached difficulties)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Access the singleton to trigger initialization
            _ = SongManager.shared.availableSongs

            DispatchQueue.main.async {
                self?.songsReady = true
                self?.checkAllLoaded()
            }
        }

        // 4. StoreManager uses cached state (already marked ready in init)
        StoreManager.shared.notifyWhenReady { [weak self] in
            self?.storeReady = true
            self?.checkAllLoaded()
        }
    }

    private func checkAllLoaded() {
        guard !hasTransitioned else { return }

        #if DEBUG
        print("LoadingScene: Status - AdMob: \(adMobReady), Audio: \(audioReady), Songs: \(songsReady), Store: \(storeReady)")
        #endif

        // Check if all resources are loaded
        guard adMobReady && audioReady && songsReady && storeReady else { return }

        // Ensure minimum display time has passed
        let elapsed = CACurrentMediaTime() - sceneStartTime
        let remainingTime = max(0, minimumDisplayTime - elapsed)

        if remainingTime > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) { [weak self] in
                self?.transitionToHome()
            }
        } else {
            transitionToHome()
        }
    }

    private func transitionToHome() {
        guard !hasTransitioned else { return }
        hasTransitioned = true

        dotTimer?.invalidate()
        dotTimer = nil

        #if DEBUG
        let totalTime = CACurrentMediaTime() - sceneStartTime
        print("LoadingScene: All resources loaded in \(String(format: "%.2f", totalTime))s, transitioning to HomeScene")
        #endif

        let homeScene = HomeScene(size: size)
        homeScene.scaleMode = scaleMode

        // Smooth fade transition
        let transition = SKTransition.fade(withDuration: 0.3)
        view?.presentScene(homeScene, transition: transition)
    }
}
