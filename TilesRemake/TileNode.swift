//
//  TileNode.swift
//  TilesRemake
//

import SpriteKit

class TileNode: SKSpriteNode {
    let column: Int

    // Extra padding around tile for easier tapping
    static let hitboxPadding: CGFloat = 8.0

    // Set to true to visualize the hitbox (for debugging)
    static let showHitboxDebug: Bool = false

    // Expanded frame for hit detection
    var hitboxFrame: CGRect {
        return frame.insetBy(dx: -TileNode.hitboxPadding, dy: -TileNode.hitboxPadding)
    }

    init(column: Int, size: CGSize) {
        self.column = column
        super.init(texture: nil, color: .black, size: size)

        // Add subtle border for visual clarity
        let border = SKShapeNode(rectOf: size)
        border.strokeColor = .darkGray
        border.lineWidth = 1
        border.fillColor = .clear
        addChild(border)

        // Debug visualization of hitbox
        if TileNode.showHitboxDebug {
            let padding = TileNode.hitboxPadding
            let hitboxSize = CGSize(width: size.width + padding * 2, height: size.height + padding * 2)
            let hitboxDebug = SKShapeNode(rectOf: hitboxSize)
            hitboxDebug.strokeColor = .red
            hitboxDebug.lineWidth = 1
            hitboxDebug.fillColor = .clear
            addChild(hitboxDebug)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
