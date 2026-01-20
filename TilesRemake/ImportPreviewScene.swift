import SpriteKit
import UIKit

// MARK: - Import Preview Scene

/// Scene for previewing and customizing a song before importing
/// Shows display name, speed adjustment, and preview/import/cancel buttons
class ImportPreviewScene: SKScene {

    // MARK: - Properties

    /// The source URL of the MIDI file (from document picker, not yet copied to Documents)
    private let sourceURL: URL

    /// Parsed beatmap data for speed calculation
    private var beatmap: Beatmap?

    /// Calculated base speed for this song
    private var calculatedSpeed: CGFloat = 1000

    /// User-adjusted custom speed (nil = use calculated)
    private var customSpeed: CGFloat?

    /// Display name (editable by user)
    private var displayName: String

    /// UI Elements
    private var nameTextField: UITextField?
    private var speedLabel: SKLabelNode?
    private var speedValueLabel: SKLabelNode?
    private var previewButton: SKNode?
    private var importButton: SKNode?
    private var cancelButton: SKLabelNode?
    private var statusLabel: SKLabelNode?

    /// Speed slider range - fixed constants
    private let speedMin: CGFloat = 0
    private let speedMax: CGFloat = 2200

    /// Track if we're transitioning to preview (to keep security-scoped access)
    private var isTransitioningToPreview = false

    /// Reset button
    private var resetButton: SKNode?

    /// Custom SpriteKit slider components
    private var sliderTrack: SKShapeNode?
    private var sliderFill: SKShapeNode?
    private var sliderThumb: SKShapeNode?
    private var sliderTrackWidth: CGFloat = 0
    private var sliderMinX: CGFloat = 0
    private var isDraggingSlider = false

    // MARK: - Initialization

    init(size: CGSize, sourceURL: URL, restoredState: PreviewState? = nil) {
        self.sourceURL = sourceURL

        // Use restored state if available, otherwise derive from filename
        if let state = restoredState {
            self.displayName = state.displayName
            self.customSpeed = state.sliderValue
        } else {
            let filename = sourceURL.deletingPathExtension().lastPathComponent
            let baseName = ImportPreviewScene.formatDisplayName(from: filename)
            // Generate unique name if duplicate exists
            self.displayName = ImportedSongManager.shared.uniqueDisplayName(for: baseName)
        }

        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .white

        // Start accessing security-scoped resource (for files from document picker)
        _ = sourceURL.startAccessingSecurityScopedResource()

        // Parse the MIDI file to get beatmap data
        parseMidiFile()

        setupUI(in: view)
    }

    override func willMove(from view: SKView) {
        // Clean up UIKit elements
        nameTextField?.removeFromSuperview()
        nameTextField = nil

        // Only stop security-scoped access if NOT transitioning to preview
        // (GameScene needs continued access to the file for preview mode)
        if !isTransitioningToPreview {
            sourceURL.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - MIDI Parsing

    private func parseMidiFile() {
        let parser = MidiParser()
        if let loadedBeatmap = parser.parse(url: sourceURL) {
            beatmap = loadedBeatmap

            // Calculate initial speed based on note density (same formula as GameScene)
            let notesPerSecond = CGFloat(loadedBeatmap.notes.count) / CGFloat(loadedBeatmap.totalDuration)
            let estimatedTileHeight = size.height / GameConfig.visibleTileCount
            calculatedSpeed = estimatedTileHeight * notesPerSecond

            #if DEBUG
            print("ImportPreviewScene: Parsed '\(loadedBeatmap.title)' - \(loadedBeatmap.notes.count) notes, calculated speed: \(Int(calculatedSpeed))")
            #endif
        } else {
            #if DEBUG
            print("ImportPreviewScene: Failed to parse MIDI file")
            #endif
            // Use default speed if parsing fails
            calculatedSpeed = 1000
        }
    }

    // MARK: - UI Setup

    private func setupUI(in view: SKView) {
        // Cancel button (top left)
        let cancel = SKLabelNode(text: "Cancel")
        cancel.fontName = "Helvetica"
        cancel.fontSize = 20
        cancel.fontColor = .systemRed
        cancel.name = "cancelButton"
        cancel.horizontalAlignmentMode = .left
        cancel.position = CGPoint(x: 20, y: size.height - 60)
        cancel.zPosition = 101
        addChild(cancel)
        cancelButton = cancel

        // Title
        let titleLabel = SKLabelNode(text: "Import Song")
        titleLabel.fontName = "Helvetica-Bold"
        titleLabel.fontSize = 28
        titleLabel.fontColor = .black
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height - 100)
        addChild(titleLabel)

        // Display name section
        setupNameSection(in: view)

        // Speed section
        setupSpeedSection(in: view)

        // Buttons section
        setupButtons()

        // Status label (for showing import success/failure)
        let status = SKLabelNode(text: "")
        status.fontName = "Helvetica"
        status.fontSize = 16
        status.fontColor = .gray
        status.position = CGPoint(x: size.width / 2, y: 80)
        status.name = "statusLabel"
        addChild(status)
        statusLabel = status
    }

    private func setupNameSection(in view: SKView) {
        // Label
        let nameLabel = SKLabelNode(text: "Song Name")
        nameLabel.fontName = "Helvetica-Bold"
        nameLabel.fontSize = 18
        nameLabel.fontColor = .black
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.position = CGPoint(x: 30, y: size.height - 160)
        addChild(nameLabel)

        // Text field for editing display name
        let textFieldY: CGFloat = 175  // UIKit Y (from top)
        let textField = UITextField()
        textField.text = displayName
        textField.borderStyle = .roundedRect
        textField.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        textField.textColor = .black
        textField.font = UIFont.systemFont(ofSize: 18)
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        textField.returnKeyType = .done
        textField.delegate = self
        textField.frame = CGRect(
            x: 30,
            y: textFieldY,
            width: view.bounds.width - 60,
            height: 44
        )
        view.addSubview(textField)
        nameTextField = textField
    }

    private func setupSpeedSection(in view: SKView) {
        let sectionY = size.height - 280

        // Speed label
        let label = SKLabelNode(text: "Scroll Speed")
        label.fontName = "Helvetica-Bold"
        label.fontSize = 18
        label.fontColor = .black
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: 30, y: sectionY)
        addChild(label)
        speedLabel = label

        // Determine initial speed (use customSpeed if restored, else calculated)
        let initialSpeed = customSpeed ?? calculatedSpeed

        // Current speed value label
        let valueLabel = SKLabelNode(text: "\(Int(initialSpeed))")
        valueLabel.fontName = "Helvetica-Bold"
        valueLabel.fontSize = 24
        valueLabel.fontColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        valueLabel.horizontalAlignmentMode = .center
        valueLabel.position = CGPoint(x: size.width / 2, y: sectionY - 50)
        addChild(valueLabel)
        speedValueLabel = valueLabel

        // Custom SpriteKit slider
        let sliderY = sectionY - 95
        let padding: CGFloat = 30
        sliderTrackWidth = size.width - (padding * 2)
        sliderMinX = padding

        // Track background (gray)
        let track = SKShapeNode(rectOf: CGSize(width: sliderTrackWidth, height: 6), cornerRadius: 3)
        track.fillColor = UIColor.lightGray
        track.strokeColor = .clear
        track.position = CGPoint(x: size.width / 2, y: sliderY)
        track.name = "sliderTrack"
        addChild(track)
        sliderTrack = track

        // Fill (blue, shows progress)
        let initialProgress = (initialSpeed - speedMin) / (speedMax - speedMin)
        let fillWidth = sliderTrackWidth * initialProgress
        let fill = SKShapeNode(rectOf: CGSize(width: max(fillWidth, 1), height: 6), cornerRadius: 3)
        fill.fillColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        fill.strokeColor = .clear
        fill.position = CGPoint(x: sliderMinX + fillWidth / 2, y: sliderY)
        fill.name = "sliderFill"
        addChild(fill)
        sliderFill = fill

        // Thumb (draggable circle)
        let thumbX = sliderMinX + (sliderTrackWidth * initialProgress)
        let thumb = SKShapeNode(circleOfRadius: 14)
        thumb.fillColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        thumb.strokeColor = .white
        thumb.lineWidth = 2
        thumb.position = CGPoint(x: thumbX, y: sliderY)
        thumb.name = "sliderThumb"
        thumb.zPosition = 10
        addChild(thumb)
        sliderThumb = thumb

        // Min/max/calculated labels - positioned BELOW the slider
        let labelsY = sectionY - 130

        let minLabel = SKLabelNode(text: "\(Int(speedMin))")
        minLabel.fontName = "Helvetica"
        minLabel.fontSize = 14
        minLabel.fontColor = .gray
        minLabel.horizontalAlignmentMode = .left
        minLabel.position = CGPoint(x: 30, y: labelsY)
        addChild(minLabel)

        let maxLabel = SKLabelNode(text: "\(Int(speedMax))")
        maxLabel.fontName = "Helvetica"
        maxLabel.fontSize = 14
        maxLabel.fontColor = .gray
        maxLabel.horizontalAlignmentMode = .right
        maxLabel.position = CGPoint(x: size.width - 30, y: labelsY)
        addChild(maxLabel)

        // Calculated speed indicator
        let calcLabel = SKLabelNode(text: "(Calculated: \(Int(calculatedSpeed)))")
        calcLabel.fontName = "Helvetica"
        calcLabel.fontSize = 14
        calcLabel.fontColor = .gray
        calcLabel.horizontalAlignmentMode = .center
        calcLabel.position = CGPoint(x: size.width / 2, y: labelsY)
        addChild(calcLabel)

        // Reset button (below the labels)
        setupResetButton(at: labelsY - 40)
    }

    private func setupResetButton(at y: CGFloat) {
        let container = SKNode()
        container.position = CGPoint(x: size.width / 2, y: y)
        container.name = "resetButton"

        let bg = SKShapeNode(rectOf: CGSize(width: 160, height: 32), cornerRadius: 6)
        bg.fillColor = UIColor(white: 0.9, alpha: 1.0)
        bg.strokeColor = .clear
        container.addChild(bg)

        let label = SKLabelNode(text: "Reset to Calculated")
        label.fontName = "Helvetica"
        label.fontSize = 14
        label.fontColor = .darkGray
        label.verticalAlignmentMode = .center
        container.addChild(label)

        addChild(container)
        resetButton = container
    }

    private func setupButtons() {
        let buttonY: CGFloat = size.height / 2 - 100
        let buttonSpacing: CGFloat = 140
        let buttonWidth: CGFloat = 120
        let buttonHeight: CGFloat = 50

        // Preview button
        let previewContainer = SKNode()
        previewContainer.position = CGPoint(x: size.width / 2 - buttonSpacing / 2, y: buttonY)
        previewContainer.name = "previewButton"

        let previewBg = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 10)
        previewBg.fillColor = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        previewBg.strokeColor = .clear
        previewContainer.addChild(previewBg)

        let previewLabel = SKLabelNode(text: "Preview")
        previewLabel.fontName = "Helvetica-Bold"
        previewLabel.fontSize = 18
        previewLabel.fontColor = .white
        previewLabel.verticalAlignmentMode = .center
        previewContainer.addChild(previewLabel)

        addChild(previewContainer)
        previewButton = previewContainer

        // Import button
        let importContainer = SKNode()
        importContainer.position = CGPoint(x: size.width / 2 + buttonSpacing / 2, y: buttonY)
        importContainer.name = "importButton"

        let importBg = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 10)
        importBg.fillColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        importBg.strokeColor = .clear
        importContainer.addChild(importBg)

        let importLabel = SKLabelNode(text: "Import")
        importLabel.fontName = "Helvetica-Bold"
        importLabel.fontSize = 18
        importLabel.fontColor = .white
        importLabel.verticalAlignmentMode = .center
        importContainer.addChild(importLabel)

        addChild(importContainer)
        importButton = importContainer
    }

    // MARK: - Slider Handlers

    private func updateSliderPosition(to x: CGFloat) {
        // Clamp x to slider bounds
        let clampedX = max(sliderMinX, min(x, sliderMinX + sliderTrackWidth))

        // Calculate progress (0 to 1)
        let progress = (clampedX - sliderMinX) / sliderTrackWidth

        // Calculate speed value
        let newSpeed = speedMin + (speedMax - speedMin) * progress
        customSpeed = newSpeed
        speedValueLabel?.text = "\(Int(newSpeed))"

        // Update thumb position
        sliderThumb?.position.x = clampedX

        // Update fill width and position
        let fillWidth = max(sliderTrackWidth * progress, 1)
        sliderFill?.removeFromParent()
        let fill = SKShapeNode(rectOf: CGSize(width: fillWidth, height: 6), cornerRadius: 3)
        fill.fillColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        fill.strokeColor = .clear
        fill.position = CGPoint(x: sliderMinX + fillWidth / 2, y: sliderThumb?.position.y ?? 0)
        fill.name = "sliderFill"
        addChild(fill)
        sliderFill = fill
    }

    private func resetSliderToCalculated() {
        let progress = (calculatedSpeed - speedMin) / (speedMax - speedMin)
        let thumbX = sliderMinX + (sliderTrackWidth * progress)
        updateSliderPosition(to: thumbX)
    }

    private func isNearSlider(_ location: CGPoint) -> Bool {
        guard let thumb = sliderThumb else { return false }
        // Check if touch is within slider area (generous hit area)
        let sliderY = thumb.position.y
        let hitRect = CGRect(
            x: sliderMinX - 20,
            y: sliderY - 30,
            width: sliderTrackWidth + 40,
            height: 60
        )
        return hitRect.contains(location)
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Dismiss keyboard
        nameTextField?.resignFirstResponder()

        // Check slider first (for immediate response)
        if isNearSlider(location) {
            isDraggingSlider = true
            updateSliderPosition(to: location.x)
            return
        }

        // Check cancel button
        if let cancel = cancelButton, cancel.contains(location) {
            transitionToSongList()
            return
        }

        // Check preview button
        if let preview = previewButton {
            let hitRect = CGRect(
                x: preview.position.x - 60,
                y: preview.position.y - 25,
                width: 120,
                height: 50
            )
            if hitRect.contains(location) {
                startPreview()
                return
            }
        }

        // Check import button
        if let importBtn = importButton {
            let hitRect = CGRect(
                x: importBtn.position.x - 60,
                y: importBtn.position.y - 25,
                width: 120,
                height: 50
            )
            if hitRect.contains(location) {
                performImport()
                return
            }
        }

        // Check reset button
        if let reset = resetButton {
            let hitRect = CGRect(
                x: reset.position.x - 80,
                y: reset.position.y - 16,
                width: 160,
                height: 32
            )
            if hitRect.contains(location) {
                resetSliderToCalculated()
                return
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDraggingSlider, let touch = touches.first else { return }
        let location = touch.location(in: self)
        updateSliderPosition(to: location.x)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDraggingSlider = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDraggingSlider = false
    }

    // MARK: - Actions

    private func startPreview() {
        // Get current values
        let name = nameTextField?.text ?? displayName
        let speed = customSpeed ?? calculatedSpeed

        #if DEBUG
        print("ImportPreviewScene: Starting preview for '\(name)' at speed \(Int(speed))")
        #endif

        // Store current state for returning from preview (preserve exact slider position)
        let previewState = PreviewState(
            sourceURL: sourceURL,
            displayName: name,
            sliderValue: speed,  // Store the actual speed value to restore slider position
            calculatedSpeed: calculatedSpeed
        )

        // Clean up UIKit elements before transitioning
        nameTextField?.removeFromSuperview()
        nameTextField = nil

        // Mark that we're transitioning to preview (keep security-scoped access)
        isTransitioningToPreview = true

        // Transition to GameScene in preview mode
        let gameScene = GameScene(
            size: size,
            songURL: sourceURL,
            customSpeed: speed,
            startFromNote: nil,
            isPreviewMode: true,
            previewReturnState: previewState
        )
        gameScene.scaleMode = scaleMode
        view?.presentScene(gameScene)
    }

    private func performImport() {
        // Get final values
        let finalName = nameTextField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? displayName
        let finalSpeed = customSpeed  // nil means use calculated

        // Validate name is not empty
        guard !finalName.isEmpty else {
            showStatus("Please enter a song name", isError: true)
            return
        }

        // Validate name is not already taken
        if ImportedSongManager.shared.isDisplayNameTaken(finalName) {
            showStatus("A song with this name already exists", isError: true)
            return
        }

        #if DEBUG
        print("ImportPreviewScene: Importing '\(finalName)' with custom speed: \(String(describing: finalSpeed))")
        #endif

        // Import the song with customizations
        if let importedSong = ImportedSongManager.shared.importSong(
            from: sourceURL,
            displayName: finalName,
            customSpeed: finalSpeed
        ) {
            #if DEBUG
            print("ImportPreviewScene: Successfully imported '\(importedSong.title)'")
            #endif
            transitionToSongList()
        } else {
            showStatus("Failed to import song", isError: true)
        }
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
        nameTextField?.removeFromSuperview()
        nameTextField = nil

        let songListScene = SongListScene(size: size)
        songListScene.scaleMode = scaleMode
        view?.presentScene(songListScene)
    }

    // MARK: - Helpers

    /// Formats a display name from a filename
    /// Removes extension and converts kebab-case/underscores to spaces with title case
    static func formatDisplayName(from fileName: String) -> String {
        // Remove extension
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension

        // Replace hyphens and underscores with spaces
        let withSpaces = nameWithoutExtension
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        // Title case each word
        return withSpaces
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - UITextFieldDelegate

extension ImportPreviewScene: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        // Update display name when editing ends
        if let text = textField.text, !text.isEmpty {
            displayName = text
        }
    }
}

// MARK: - Preview State

/// State passed to GameScene for preview mode, allows returning with preserved settings
struct PreviewState {
    let sourceURL: URL
    let displayName: String
    let sliderValue: CGFloat  // The actual slider position to restore
    let calculatedSpeed: CGFloat
}
