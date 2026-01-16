//
//  TileNode.swift
//  TilesRemake
//

import SpriteKit

class TileNode: SKSpriteNode {
    let column: Int
    let tileLength: Int  // 1 for normal tile, 2+ for long tile
    let unitHeight: CGFloat  // Height of one tile unit
    var midiNotes: [UInt8] = [60]  // MIDI notes to play (multiple = chord)
    var noteDurations: [TimeInterval] = [0.5]  // Individual durations per note (parallel array with midiNotes)
    var velocities: [UInt8] = [100]  // MIDI velocities 0-127 (parallel array with midiNotes)
    var instruments: [UInt8] = [0]  // General MIDI instruments (parallel array with midiNotes)
    var gapToNextNote: TimeInterval = 0.5  // MIDI gap to next note (used for duration adjustment)

    // Double tile pairing - tiles share a note queue, first tap plays first note regardless of which tile
    weak var siblingTile: TileNode?
    var pairNotes: [[UInt8]]?             // [firstNotes, secondNotes] in musical order
    var pairDurations: [[TimeInterval]]?  // [firstDurations, secondDurations] individual durations per note
    var pairVelocities: [[UInt8]]?        // [firstVelocities, secondVelocities] per-note velocities
    var pairInstruments: [[UInt8]]?       // [firstInstruments, secondInstruments] for multi-instrument chords
    var isDoubleTilePair: Bool { return siblingTile != nil }

    // For long tiles: track which notes are currently being played (set when held)
    var currentlyPlayingNotes: [UInt8]?
    var currentlyPlayingDurations: [TimeInterval]?
    var currentlyPlayingVelocities: [UInt8]?
    var currentlyPlayingInstruments: [UInt8]?

    // Track the touch that is holding this tile (for multi-touch support)
    weak var holdingTouch: UITouch?

    /// Convenience for single note (backwards compatibility)
    var midiNote: UInt8 {
        return midiNotes.first ?? 60
    }

    /// Convenience for single instrument (backwards compatibility)
    var instrument: UInt8 {
        return instruments.first ?? 0
    }

    /// Convenience for single velocity (backwards compatibility)
    var velocity: UInt8 {
        return velocities.first ?? 100
    }

    /// Convenience for max duration (backwards compatibility)
    var noteDuration: TimeInterval {
        return noteDurations.max() ?? 0.5
    }

    /// Whether this tile plays a chord
    var isChord: Bool {
        return midiNotes.count > 1
    }

    // Extra padding around tile for easier tapping
    static let hitboxPadding: CGFloat = 8.0

    // Set to true to visualize the hitbox (for debugging)
    static let showHitboxDebug: Bool = false

    // Long tile colors
    static let longTileColor = UIColor(red: 0.3, green: 0.1, blue: 0.4, alpha: 1.0)  // Dark purple
    static let longTileFillColor = UIColor(red: 0.6, green: 0.5, blue: 0.9, alpha: 1.0)  // Light purple
    static let completedSegmentColor = UIColor.lightGray.withAlphaComponent(0.3)

    // Long tile state
    var isLongTile: Bool { return tileLength > 1 }
    var isBeingHeld: Bool = false
    var fingerY: CGFloat = 0  // Track where the user's finger is (in scene coordinates)
    var completedSegments: Int = 0  // How many segments have been completed
    var fillHeight: CGFloat = 0  // Current height of the fill (in points)

    // Segment sprites for long tiles (bottom to top) - kept for compatibility
    private var segments: [SKSpriteNode] = []

    // Fill node for long tile hold animation
    private var fillNode: SKShapeNode?
    private var fillCropNode: SKCropNode?

    // Expanded frame for hit detection
    var hitboxFrame: CGRect {
        return frame.insetBy(dx: -TileNode.hitboxPadding, dy: -TileNode.hitboxPadding)
    }

    // Bottom segment frame for initial tap detection on long tiles
    var bottomSegmentFrame: CGRect {
        let segmentHeight = unitHeight
        let bottomY = position.y - size.height / 2
        return CGRect(
            x: position.x - size.width / 2 - TileNode.hitboxPadding,
            y: bottomY - TileNode.hitboxPadding,
            width: size.width + TileNode.hitboxPadding * 2,
            height: segmentHeight + TileNode.hitboxPadding * 2
        )
    }

    // Top of the first (bottom) segment - used for game over detection
    var firstSegmentTop: CGFloat {
        let tileBottom = position.y - size.height / 2
        return tileBottom + unitHeight
    }

    init(column: Int, size: CGSize, tileLength: Int = 1, midiNotes: [UInt8] = [60], noteDurations: [TimeInterval] = [0.5], velocities: [UInt8] = [100], instruments: [UInt8] = [0], gapToNextNote: TimeInterval = 0.5) {
        self.column = column
        self.tileLength = tileLength
        self.unitHeight = size.height
        self.midiNotes = midiNotes
        self.noteDurations = noteDurations
        self.velocities = velocities
        self.instruments = instruments
        self.gapToNextNote = gapToNextNote

        // Calculate actual size based on tile length
        let actualHeight = size.height * CGFloat(tileLength)
        let actualSize = CGSize(width: size.width, height: actualHeight)

        // Use purple for long tiles, black for normal
        let tileColor: UIColor = tileLength > 1 ? TileNode.longTileColor : .black

        super.init(texture: nil, color: tileColor, size: actualSize)

        if tileLength > 1 {
            // For long tiles, create individual segment sprites
            setupLongTileSegments(size: size, tileLength: tileLength)
        } else {
            // For normal tiles, just add a border
            let border = SKShapeNode(rectOf: actualSize)
            border.strokeColor = .darkGray
            border.lineWidth = 1
            border.fillColor = .clear
            addChild(border)
        }

        // Debug visualization of hitbox
        if TileNode.showHitboxDebug {
            let padding = TileNode.hitboxPadding
            let hitboxSize = CGSize(width: actualSize.width + padding * 2, height: actualSize.height + padding * 2)
            let hitboxDebug = SKShapeNode(rectOf: hitboxSize)
            hitboxDebug.strokeColor = .red
            hitboxDebug.lineWidth = 1
            hitboxDebug.fillColor = .clear
            addChild(hitboxDebug)
        }
    }

    // Long tile decoration colors (matching the fill color)
    static let decorationColor = UIColor(red: 0.5, green: 0.4, blue: 0.8, alpha: 0.25)  // Slightly muted purple for decoration
    static let decorationCircleRadius: CGFloat = 10
    static let decorationLineWidth: CGFloat = 2

    private func setupLongTileSegments(size: CGSize, tileLength: Int) {
        // Use the base sprite as the dark purple background
        self.color = TileNode.longTileColor

        // Add a border around the entire tile (will be covered by fill when held)
        let border = SKShapeNode(rectOf: self.size)
        border.strokeColor = .darkGray
        border.lineWidth = 2
        border.fillColor = .clear
        border.zPosition = 2
        addChild(border)

        // Add circle and line decoration
        addLongTileDecoration()

        // Create the fill shape (starts empty, will grow from bottom)
        // Use a crop node to clip the fill to the tile bounds
        let cropNode = SKCropNode()
        cropNode.zPosition = 5  // Above border so fill covers it

        // Mask is slightly larger than tile so fill covers the border
        let maskSize = CGSize(width: self.size.width + 4, height: self.size.height + 4)
        let maskNode = SKSpriteNode(color: .white, size: maskSize)
        cropNode.maskNode = maskNode

        // Create the fill shape - starts with zero height
        updateFillShape(height: 0, in: cropNode)

        addChild(cropNode)
        fillCropNode = cropNode

        // Create placeholder segments for compatibility with existing logic
        let segmentSize = CGSize(width: size.width, height: size.height)
        for i in 0..<tileLength {
            let segment = SKSpriteNode(color: .clear, size: segmentSize)
            let yOffset = -self.size.height / 2 + segmentSize.height / 2 + CGFloat(i) * segmentSize.height
            segment.position = CGPoint(x: 0, y: yOffset)
            segment.zPosition = 0
            segments.append(segment)
            // Don't add to scene - these are just for tracking
        }
    }

    private func addLongTileDecoration() {
        let radius = TileNode.decorationCircleRadius
        let lineWidth = TileNode.decorationLineWidth

        // Position the circle near the bottom of the tile
        let circleY = -self.size.height / 2 + radius + 60  // 60pt from bottom
        let lineTopY = self.size.height / 2 - 40  // 40pt from top

        // Create outer ring (darker stroke)
        let outerRing = SKShapeNode(circleOfRadius: radius)
        outerRing.position = CGPoint(x: 0, y: circleY)
        outerRing.strokeColor = TileNode.decorationColor
        outerRing.lineWidth = 3
        outerRing.fillColor = .clear
        outerRing.zPosition = 1
        addChild(outerRing)

        // Create inner circle (filled)
        let innerCircle = SKShapeNode(circleOfRadius: radius - 5)
        innerCircle.position = CGPoint(x: 0, y: circleY)
        innerCircle.fillColor = TileNode.decorationColor.withAlphaComponent(0.6)
        innerCircle.strokeColor = .clear
        innerCircle.zPosition = 1
        addChild(innerCircle)

        // Create the vertical line from circle to top
        let linePath = CGMutablePath()
        linePath.move(to: CGPoint(x: 0, y: circleY + radius))
        linePath.addLine(to: CGPoint(x: 0, y: lineTopY))

        let line = SKShapeNode(path: linePath)
        line.strokeColor = TileNode.decorationColor
        line.lineWidth = lineWidth
        line.zPosition = 1
        addChild(line)
    }

    // Height of the oval curve at the top of the fill
    private static let ovalHeight: CGFloat = 25

    // How much higher the fill spawns above the finger position (also affects completion timing)
    // Increase this value to make fill spawn higher and complete earlier
    static let fillSpawnOffset: CGFloat = 100

    private func updateFillShape(height: CGFloat, in cropNode: SKCropNode) {
        // Remove old fill node
        fillNode?.removeFromParent()

        guard height > 0 else {
            fillNode = nil
            return
        }

        let tileWidth = self.size.width
        let tileHeight = self.size.height
        let ovalHeight = TileNode.ovalHeight

        let path = CGMutablePath()

        // Start at bottom-left (use slightly larger width to ensure edge coverage)
        let bottomY = -tileHeight / 2 - 1  // Extend slightly below
        let leftX = -tileWidth / 2 - 1     // Extend slightly left
        let rightX = tileWidth / 2 + 1     // Extend slightly right
        let topY = bottomY + height + 1    // +1 to match bottom extension

        // Bottom edge (straight)
        path.move(to: CGPoint(x: leftX, y: bottomY))
        path.addLine(to: CGPoint(x: rightX, y: bottomY))

        // Right edge up to where curve starts
        path.addLine(to: CGPoint(x: rightX, y: topY - ovalHeight))

        // Oval top using quadratic curve (more elliptical than arc)
        // The crop mask will clip anything outside the tile bounds
        path.addQuadCurve(to: CGPoint(x: leftX, y: topY - ovalHeight),
                         control: CGPoint(x: 0, y: topY))

        // Left edge back down
        path.addLine(to: CGPoint(x: leftX, y: bottomY))
        path.closeSubpath()

        let newFillNode = SKShapeNode(path: path)
        newFillNode.fillColor = TileNode.longTileFillColor
        newFillNode.strokeColor = .clear
        newFillNode.zPosition = 1

        cropNode.addChild(newFillNode)
        fillNode = newFillNode
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Check if a point is in the bottom segment (for initial tap)
    func isBottomSegmentTapped(at point: CGPoint) -> Bool {
        guard isLongTile else { return false }
        return bottomSegmentFrame.contains(point)
    }

    // Complete the first segment immediately when tapped
    func completeFirstSegment() {
        guard isLongTile, completedSegments == 0 else { return }

        // Calculate initial fill height based on where the finger tapped
        // Tile bottom in scene coordinates
        let tileBottom = position.y - size.height / 2

        // Fill height is from tile bottom to finger position
        // Add oval height so the rounded top appears at the finger position
        // Add spawn offset to make fill spawn higher and complete earlier
        let initialFillHeight = fingerY - tileBottom + TileNode.ovalHeight + TileNode.fillSpawnOffset

        // Clamp to a small minimum (so something is visible), no max clamp
        fillHeight = max(10, initialFillHeight)

        if let cropNode = fillCropNode {
            updateFillShape(height: fillHeight, in: cropNode)
        }
        completedSegments = 1
    }

    // Update segments based on finger position as tile scrolls
    // Returns the number of newly completed segments
    func updateSegmentsForHold(fingerY: CGFloat) -> Int {
        guard isLongTile, isBeingHeld else { return 0 }

        self.fingerY = fingerY

        // Calculate how much of the tile has scrolled past the finger
        // Tile bottom in scene coordinates
        let tileBottom = position.y - size.height / 2

        // How far the finger is from the tile bottom (this is how much should be filled)
        // Add oval height so the rounded top appears at the finger position
        // Add spawn offset to make fill spawn higher and complete earlier
        let targetFillHeight = fingerY - tileBottom + TileNode.ovalHeight + TileNode.fillSpawnOffset

        // Don't clamp - let fill height exceed tile height so curve scrolls past naturally
        // The crop mask will handle visual clipping
        let newFillHeight = max(0, targetFillHeight)

        // Update fill if it has grown
        if newFillHeight > fillHeight {
            fillHeight = newFillHeight
            if let cropNode = fillCropNode {
                updateFillShape(height: fillHeight, in: cropNode)
            }
        }

        // Calculate completed segments based on fill height
        let previousCompleted = completedSegments

        // Tile is complete when the BOTTOM of the curve (straight part) reaches the top
        // This happens when fillHeight >= size.height + ovalHeight
        if fillHeight >= size.height + TileNode.ovalHeight - 1 {
            completedSegments = tileLength
        } else {
            completedSegments = max(1, Int(floor(fillHeight / unitHeight)))  // At least 1 since we tapped
            completedSegments = min(completedSegments, tileLength)  // Cap at tile length
        }

        return completedSegments - previousCompleted
    }

    // Check if all segments are completed
    func isFullyCompleted() -> Bool {
        return completedSegments >= tileLength
    }

    // Check if at least half the segments are completed (for sustain threshold)
    func isHalfOrMoreCompleted() -> Bool {
        return completedSegments >= (tileLength + 1) / 2  // Rounds up: 3 segments = need 2, 4 segments = need 2
    }

    // Make the entire tile transparent (for when it becomes a ghost tile)
    func makeTransparent() {
        if isLongTile {
            // Make the background transparent
            self.color = TileNode.completedSegmentColor
            // Remove fill and border
            fillNode?.removeFromParent()
            fillNode = nil
            fillCropNode?.removeFromParent()
            fillCropNode = nil
            // Remove any remaining children (like border)
            self.children.forEach { $0.removeFromParent() }
        } else {
            self.color = TileNode.completedSegmentColor
            self.children.forEach { $0.removeFromParent() }
        }
    }

    // Animate the tile fading to completed color (for fully completed long tiles)
    func animateFillFadeOut(duration: TimeInterval = 0.1) {
        guard isLongTile else { return }

        // Set background to light gray (matching completed normal tiles)
        self.color = .lightGray

        // Remove the fill block and crop node
        fillNode?.removeFromParent()
        fillNode = nil
        fillCropNode?.removeFromParent()
        fillCropNode = nil

        // Hide the border and decorations
        for child in children {
            if let shapeNode = child as? SKShapeNode {
                shapeNode.alpha = 0
            }
        }

        // Fade to match completedSegmentColor (0.3 alpha)
        let fadeToSemiTransparent = SKAction.fadeAlpha(to: 0.3, duration: duration)
        self.run(fadeToSemiTransparent)
    }
}
