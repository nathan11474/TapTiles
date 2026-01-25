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

        // Start with loading screen to preload all resources
        let scene = LoadingScene(size: view.bounds.size)
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

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        return .all
    }
}
