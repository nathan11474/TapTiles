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
    static let initialScrollSpeed: CGFloat = 1300.0
    static let maxScrollSpeed: CGFloat = 2500.0
    static let speedIncreaseRate: CGFloat = 5.0

    // Target number of tiles visible on screen
    static let visibleTileCount: CGFloat = 4.3

    // Long tile settings
    static let longTileSpawnChance: CGFloat = 0.2  // 20% chance to spawn a long tile
    static let longTileMinLength: Int = 2          // Minimum length in tile units
    static let longTileMaxLength: Int = 3          // Maximum length in tile units

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
}
