//
//  GameConfig.swift
//  TilesRemake
//

import Foundation
import CoreGraphics

struct GameConfig {
    // Grid layout
    static let columnCount: Int = 4

    // Scrolling speed
    // Initial speed is now calculated from song tempo in GameScene
    // (1700 pts/sec at 120 BPM, scaled linearly with tempo)
    // No max speed - speed increases indefinitely
    static let speedIncreaseRate: CGFloat = 5.0  // Points per second increase rate

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

    // Long tile threshold as a multiplier of the song's average gap
    // Gaps longer than (averageGap × this multiplier) become long tiles
    // e.g., 1.5 means gaps 50% longer than average trigger long tiles
    static let longTileGapMultiplier: Double = 1.5

    // Double tile threshold - gaps shorter than (averageGap × this multiplier)
    // spawn two tiles in a row (for fast "key spam" sections)
    // e.g., 0.5 means gaps half the average trigger double tiles
    static let doubleTileGapMultiplier: Double = 0.5

    // Each segment of a long tile represents this multiple of the average gap
    // e.g., 1.0 means each segment = one average gap duration
    static let tileSegmentMultiplier: Double = 1.0

    // How far ahead (in seconds) to spawn tiles before they need to be tapped
    // This gives the tile time to scroll from top to bottom of screen
    static let spawnLeadTime: TimeInterval = 2.0
}
