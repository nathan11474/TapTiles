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
    var instruments: [UInt8] = [0]  // General MIDI instruments (parallel array with midiNotes)

    // Double tile pairing - tiles share a note queue, first tap plays first note regardless of which tile
    weak var siblingTile: TileNode?
    var pairNotes: [[UInt8]]?             // [firstNotes, secondNotes] in musical order
    var pairDurations: [[TimeInterval]]?  // [firstDurations, secondDurations] individual durations per note
    var pairInstruments: [[UInt8]]?       // [firstInstruments, secondInstruments] for multi-instrument chords
    var isDoubleTilePair: Bool { return siblingTile != nil }

    // For long tiles: track which notes are currently being played (set when held)
    var currentlyPlayingNotes: [UInt8]?
    var currentlyPlayingDurations: [TimeInterval]?
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
    static let completedSegmentColor = UIColor.lightGray.withAlphaComponent(0.3)

    // Long tile state
    var isLongTile: Bool { return tileLength > 1 }
    var isBeingHeld: Bool = false
    var fingerY: CGFloat = 0  // Track where the user's finger is (in scene coordinates)
    var completedSegments: Int = 0  // How many segments have been completed

    // Segment sprites for long tiles (bottom to top)
    private var segments: [SKSpriteNode] = []

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

    init(column: Int, size: CGSize, tileLength: Int = 1, midiNotes: [UInt8] = [60], noteDurations: [TimeInterval] = [0.5], instruments: [UInt8] = [0]) {
        self.column = column
        self.tileLength = tileLength
        self.unitHeight = size.height
        self.midiNotes = midiNotes
        self.noteDurations = noteDurations
        self.instruments = instruments

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

    private func setupLongTileSegments(size: CGSize, tileLength: Int) {
        // Hide the base sprite color - we'll use segment sprites instead
        self.color = .clear

        let segmentSize = CGSize(width: size.width, height: size.height)

        for i in 0..<tileLength {
            // Create segment sprite
            let segment = SKSpriteNode(color: TileNode.longTileColor, size: segmentSize)

            // Position from bottom to top
            // Bottom segment is at -height/2 + segmentHeight/2
            let yOffset = -self.size.height / 2 + segmentSize.height / 2 + CGFloat(i) * segmentSize.height
            segment.position = CGPoint(x: 0, y: yOffset)
            segment.zPosition = 1

            // Add border to each segment
            let border = SKShapeNode(rectOf: segmentSize)
            border.strokeColor = .darkGray
            border.lineWidth = 1
            border.fillColor = .clear
            segment.addChild(border)

            addChild(segment)
            segments.append(segment)
        }
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
        guard isLongTile, completedSegments == 0, !segments.isEmpty else { return }

        let segment = segments[0]
        segment.color = TileNode.completedSegmentColor
        segment.children.forEach { $0.removeFromParent() }
        completedSegments = 1
    }

    // Update segments based on finger position as tile scrolls
    // Returns the number of newly completed segments
    func updateSegmentsForHold(fingerY: CGFloat) -> Int {
        guard isLongTile, isBeingHeld else { return 0 }

        self.fingerY = fingerY
        var newlyCompleted = 0

        // Check each uncompleted segment
        for i in completedSegments..<tileLength {
            let segment = segments[i]

            // Get the segment's position in scene coordinates
            let segmentSceneY = position.y + segment.position.y
            let segmentBottom = segmentSceneY - unitHeight / 2

            // If the segment's bottom has scrolled past (below) the finger, it's completed
            if segmentBottom < fingerY {
                // Complete this segment
                segment.color = TileNode.completedSegmentColor
                segment.children.forEach { $0.removeFromParent() }  // Remove border
                completedSegments += 1
                newlyCompleted += 1
            }
        }

        return newlyCompleted
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
            for segment in segments {
                segment.color = TileNode.completedSegmentColor
                segment.children.forEach { $0.removeFromParent() }
            }
        } else {
            self.color = TileNode.completedSegmentColor
            self.children.forEach { $0.removeFromParent() }
        }
    }
}
