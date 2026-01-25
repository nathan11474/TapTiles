//
//  AdManager.swift
//  TilesRemake
//

import GoogleMobileAds
import UIKit

/// Manages interstitial ads throughout the app
class AdManager: NSObject {

    static let shared = AdManager()

    // MARK: - Configuration

    /// Ad Unit ID for interstitial ads
    /// TODO: Replace with production ID before release: ca-app-pub-7117418330459420/7107708406
    #if DEBUG
    private let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"  // Google test ad
    #else
    private let interstitialAdUnitID = "ca-app-pub-7117418330459420/7107708406"  // Production ad
    #endif

    /// Show an ad every N game sessions (restart or exit)
    private let showAdEveryNSessions = 3

    // MARK: - State

    private var interstitialAd: InterstitialAd?
    private var sessionsSinceLastAd = 0
    private var isLoadingAd = false

    // Ready state tracking
    private var isConfigured = false
    private var readyCallbacks: [() -> Void] = []
    private let stateQueue = DispatchQueue(label: "com.tilesremake.admanager.state")

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    /// Call this once in AppDelegate after Google Mobile Ads SDK is started
    func configure() {
        // Mark as ready immediately - SDK is initialized, ad loading can happen in background
        markAsReady()

        // Load ads on a background queue to avoid blocking main thread
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.loadInterstitialAd()
        }
    }

    /// Register a callback to be notified when AdManager is ready
    /// If already ready, callback is invoked immediately on main thread
    func notifyWhenReady(completion: @escaping () -> Void) {
        stateQueue.async { [weak self] in
            guard let self = self else { return }

            if self.isConfigured {
                DispatchQueue.main.async { completion() }
            } else {
                self.readyCallbacks.append(completion)
            }
        }
    }

    /// Mark as configured and notify all waiting callbacks
    private func markAsReady() {
        stateQueue.async { [weak self] in
            guard let self = self, !self.isConfigured else { return }

            self.isConfigured = true
            let callbacks = self.readyCallbacks
            self.readyCallbacks.removeAll()

            DispatchQueue.main.async {
                for callback in callbacks {
                    callback()
                }
            }
        }
    }

    // MARK: - Ad Loading

    private func loadInterstitialAd() {
        guard !isLoadingAd else { return }

        isLoadingAd = true

        // Ad loading must happen on main thread (Google SDK requirement)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            InterstitialAd.load(
                with: self.interstitialAdUnitID,
                request: Request()
            ) { [weak self] ad, error in
                self?.isLoadingAd = false

                if let error = error {
                    #if DEBUG
                    print("AdManager: Failed to load interstitial ad: \(error.localizedDescription)")
                    #endif
                    return
                }

                self?.interstitialAd = ad
                self?.interstitialAd?.fullScreenContentDelegate = self

                #if DEBUG
                print("AdManager: Interstitial ad loaded successfully")
                #endif
            }
        }
    }

    // MARK: - Ad Showing

    /// Call this when a game session ends (restart or exit)
    /// Shows an ad if it's time and one is available
    func onGameSessionEnd(from viewController: UIViewController) {
        sessionsSinceLastAd += 1

        #if DEBUG
        print("AdManager: Session ended. Sessions since last ad: \(sessionsSinceLastAd)/\(showAdEveryNSessions)")
        #endif

        // Check if it's time to show an ad
        guard sessionsSinceLastAd >= showAdEveryNSessions else { return }

        // Try to show the ad
        if let ad = interstitialAd {
            ad.present(from: viewController)
            sessionsSinceLastAd = 0
        } else {
            #if DEBUG
            print("AdManager: Ad not ready, skipping this time")
            #endif
            // Reset counter and preload for next time
            sessionsSinceLastAd = 0
            loadInterstitialAd()
        }
    }

    /// Force show an ad if available (use sparingly)
    func showAdIfAvailable(from viewController: UIViewController) -> Bool {
        guard let ad = interstitialAd else {
            loadInterstitialAd()
            return false
        }

        ad.present(from: viewController)
        return true
    }
}

// MARK: - FullScreenContentDelegate

extension AdManager: FullScreenContentDelegate {

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("AdManager: Ad dismissed")
        #endif
        // Preload the next ad
        interstitialAd = nil
        loadInterstitialAd()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        #if DEBUG
        print("AdManager: Failed to present ad: \(error.localizedDescription)")
        #endif
        // Preload another ad
        interstitialAd = nil
        loadInterstitialAd()
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("AdManager: Ad will present")
        #endif
    }
}
