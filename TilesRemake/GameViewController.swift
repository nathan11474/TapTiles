//
//  GameViewController.swift
//  TilesRemake
//

import UIKit
import SpriteKit

class GameViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let view = self.view as? SKView else { return }

        // Create scene programmatically with view bounds
        let scene = GameScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill

        view.presentScene(scene)
        view.ignoresSiblingOrder = true

        // Debug info (remove for release)
        view.showsFPS = true
        view.showsNodeCount = true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
