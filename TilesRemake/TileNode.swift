//
//  TileNode.swift
//  TilesRemake
//

import SpriteKit

class TileNode: SKSpriteNode {
    let column: Int

    init(column: Int, size: CGSize) {
        self.column = column
        super.init(texture: nil, color: .black, size: size)

        // Add subtle border for visual clarity
        let border = SKShapeNode(rectOf: size)
        border.strokeColor = .darkGray
        border.lineWidth = 1
        border.fillColor = .clear
        addChild(border)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
