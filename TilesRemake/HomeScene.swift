import SpriteKit
import UIKit

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
        tapLabel.verticalAlignmentMode = .baseline
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
        tilesLabel.verticalAlignmentMode = .baseline
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

        // Restore Purchases button below play button
        let restoreButton = createRestoreButton()
        restoreButton.position = CGPoint(x: size.width / 2, y: size.height * 0.35 - 60)
        restoreButton.zPosition = 10
        addChild(restoreButton)
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

    private func createRestoreButton() -> SKNode {
        let container = SKNode()
        container.name = "restoreButton"

        let buttonWidth: CGFloat = 200
        let buttonHeight: CGFloat = 50
        let cornerRadius: CGFloat = 25
        let blueColor = UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)

        // Blue rounded button background
        let background = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: cornerRadius)
        background.fillColor = blueColor
        background.strokeColor = .clear
        container.addChild(background)

        // Button label
        let label = SKLabelNode(text: "Restore Purchases")
        label.fontName = "Helvetica-Bold"
        label.fontSize = 18
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
            return
        }

        if let restoreButton = childNode(withName: "restoreButton"),
           restoreButton.contains(location) {
            handleRestorePurchases()
            return
        }
    }

    // MARK: - Restore Purchases

    private func handleRestorePurchases() {
        Task { @MainActor in
            await StoreManager.shared.restorePurchases()

            if StoreManager.shared.isImportUnlocked {
                showAlert(title: "Restored", message: "Import feature has been restored!")
            } else {
                showAlert(title: "No Purchases Found", message: "No previous purchases were found for this Apple ID.")
            }
        }
    }

    private func showAlert(title: String, message: String) {
        guard let windowScene = view?.window?.windowScene,
              let viewController = windowScene.windows.first?.rootViewController else {
            return
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
    }

    // MARK: - Navigation

    private func transitionToSongList() {
        let songListScene = SongListScene(size: size)
        songListScene.scaleMode = scaleMode
        view?.presentScene(songListScene)
    }
}
