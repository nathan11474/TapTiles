import SpriteKit
import UIKit
import UniformTypeIdentifiers

// MARK: - Import Scene

/// Scene that handles importing MIDI files from the user's device
class ImportScene: SKScene {

    // MARK: - Properties

    private var importButton: SKNode?
    private var backButton: SKLabelNode?
    private var statusLabel: SKLabelNode?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .white
        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Back button
        let back = SKLabelNode(text: "< Back")
        back.fontName = "Helvetica"
        back.fontSize = 20
        back.fontColor = .darkGray
        back.name = "backButton"
        back.horizontalAlignmentMode = .left
        back.position = CGPoint(x: 20, y: size.height - 60)
        back.zPosition = 101
        addChild(back)
        backButton = back

        // Title
        let titleLabel = SKLabelNode(text: "Import Song")
        titleLabel.fontName = "Helvetica-Bold"
        titleLabel.fontSize = 32
        titleLabel.fontColor = .black
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height - 140)
        addChild(titleLabel)

        // Instructions
        let instructionsLabel = SKLabelNode(text: "Select a MIDI file to import")
        instructionsLabel.fontName = "Helvetica"
        instructionsLabel.fontSize = 18
        instructionsLabel.fontColor = .darkGray
        instructionsLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 80)
        addChild(instructionsLabel)

        // Import button
        createImportButton()

        // Status label (for showing import success/failure)
        let status = SKLabelNode(text: "")
        status.fontName = "Helvetica"
        status.fontSize = 16
        status.fontColor = .gray
        status.position = CGPoint(x: size.width / 2, y: size.height / 2 - 100)
        status.name = "statusLabel"
        addChild(status)
        statusLabel = status
    }

    private func createImportButton() {
        let buttonContainer = SKNode()
        buttonContainer.position = CGPoint(x: size.width / 2, y: size.height / 2)
        buttonContainer.name = "importButton"

        // Button background
        let buttonWidth: CGFloat = 200
        let buttonHeight: CGFloat = 50
        let buttonBackground = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 10)
        buttonBackground.fillColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        buttonBackground.strokeColor = .clear
        buttonContainer.addChild(buttonBackground)

        // Plus icon (using SF Symbol rendered as texture)
        let iconSize = CGSize(width: 24, height: 24)
        if let iconTexture = renderIcon(symbolName: "plus.circle.fill", color: .white, size: iconSize) {
            let iconNode = SKSpriteNode(texture: iconTexture)
            iconNode.position = CGPoint(x: -60, y: 0)
            buttonContainer.addChild(iconNode)
        }

        // Button text
        let buttonLabel = SKLabelNode(text: "Select MIDI File")
        buttonLabel.fontName = "Helvetica-Bold"
        buttonLabel.fontSize = 18
        buttonLabel.fontColor = .white
        buttonLabel.verticalAlignmentMode = .center
        buttonLabel.horizontalAlignmentMode = .center
        buttonLabel.position = CGPoint(x: 10, y: 0)
        buttonContainer.addChild(buttonLabel)

        addChild(buttonContainer)
        importButton = buttonContainer
    }

    /// Renders an SF Symbol as a texture
    private func renderIcon(symbolName: String, color: UIColor, size: CGSize) -> SKTexture? {
        let config = UIImage.SymbolConfiguration(pointSize: size.height, weight: .regular)
        guard let symbolImage = UIImage(systemName: symbolName, withConfiguration: config) else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            let drawRect = CGRect(origin: .zero, size: size)
            symbolImage.draw(in: drawRect, blendMode: .normal, alpha: 1.0)
            context.fill(drawRect, blendMode: .sourceIn)
        }

        return SKTexture(image: image)
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check back button
        if let back = backButton, back.contains(location) {
            transitionToSongList()
            return
        }

        // Check import button
        if let importBtn = importButton {
            // Create a larger hit area for the button
            let hitRect = CGRect(
                x: importBtn.position.x - 100,
                y: importBtn.position.y - 25,
                width: 200,
                height: 50
            )
            if hitRect.contains(location) {
                presentDocumentPicker()
                return
            }
        }
    }

    // MARK: - Document Picker

    private func presentDocumentPicker() {
        guard let view = self.view,
              let window = view.window,
              let rootViewController = window.rootViewController else {
            showStatus("Unable to open file picker", isError: true)
            return
        }

        // Create document picker for MIDI files
        let midiTypes: [UTType] = [UTType.midi, UTType(filenameExtension: "mid")!, UTType(filenameExtension: "midi")!]
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: midiTypes)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false

        // Find the topmost presented view controller
        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }

        topController.present(documentPicker, animated: true)
    }

    // MARK: - Status Display

    private func showStatus(_ message: String, isError: Bool = false) {
        statusLabel?.text = message
        statusLabel?.fontColor = isError ? .red : .gray

        // Auto-clear after delay
        let wait = SKAction.wait(forDuration: 3.0)
        let clear = SKAction.run { [weak self] in
            self?.statusLabel?.text = ""
        }
        statusLabel?.run(SKAction.sequence([wait, clear]))
    }

    // MARK: - Navigation

    private func transitionToSongList() {
        let songListScene = SongListScene(size: size)
        songListScene.scaleMode = scaleMode
        view?.presentScene(songListScene)
    }
}

// MARK: - UIDocumentPickerDelegate

extension ImportScene: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let selectedURL = urls.first else {
            showStatus("No file selected", isError: true)
            return
        }

        // Import the selected file
        if let importedSong = ImportedSongManager.shared.importSong(from: selectedURL) {
            #if DEBUG
            print("ImportScene: Successfully imported '\(importedSong.title)'")
            #endif
            // Return to song list with imports tab selected
            transitionToSongList()
        } else {
            showStatus("Failed to import file", isError: true)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // User cancelled - stay on import scene
        #if DEBUG
        print("ImportScene: Document picker cancelled")
        #endif
    }
}
