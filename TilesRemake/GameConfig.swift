//
//  GameConfig.swift
//  TilesRemake
//

import Foundation
import CoreGraphics

struct GameConfig {
    // Grid layout
    static let columnCount: Int = 4

    // Scrolling speed (points per second)
    static let initialScrollSpeed: CGFloat = 1700.0
    static let maxScrollSpeed: CGFloat = 2500.0
    static let speedIncreaseRate: CGFloat = 5.0

    // Target number of tiles visible on screen
    static let visibleTileCount: CGFloat = 4.3

    // Long tile settings (for random mode fallback)
    static let longTileSpawnChance: CGFloat = 0.2  // 20% chance to spawn a long tile
    static let longTileMinLength: Int = 2          // Minimum length in tile units (random mode)
    static let longTileMaxLength: Int = 5          // Maximum length in tile units

    // Tile dimensions (calculated relative to screen)
    static func tileSize(for screenSize: CGSize) -> CGSize {
        let tileWidth = screenSize.width / CGFloat(columnCount)
        let tileHeight = screenSize.height / visibleTileCount
        return CGSize(width: tileWidth, height: tileHeight)
    }

    // Spawn timing - spawn a new row when previous has moved down by one tile height
    static func spawnInterval(for tileHeight: CGFloat, speed: CGFloat) -> TimeInterval {
        return TimeInterval(tileHeight / speed)
    }

    // MARK: - Audio Configuration (Fallback)

    // Used only when no beatmap is loaded - normal gameplay uses MIDI notes
    // Available notes: C major pentatonic scale across 3 octaves
    static let availableNotes: [UInt8] = [
        48, 50, 52, 55, 57,  // C3 to A3
        60, 62, 64, 67, 69,  // C4 to A4
        72, 74, 76, 79, 81   // C5 to A5
    ]

    static func randomNote() -> UInt8 {
        return availableNotes.randomElement() ?? 60
    }

    // MARK: - Beatmap Configuration

    // Threshold in seconds - gaps longer than this become long tiles
    // A normal tile takes roughly one "beat" of time to pass through
    // If the gap to the next note is longer, we fill it with a long tile
    static let longTileGapThreshold: TimeInterval = 0.5

    // How far ahead (in seconds) to spawn tiles before they need to be tapped
    // This gives the tile time to scroll from top to bottom of screen
    static let spawnLeadTime: TimeInterval = 2.0

    // How much music time (in seconds) each tile segment represents
    // This is independent of scroll speed - it's purely about music timing ratios
    static let tileSegmentDuration: TimeInterval = 0.4
}
