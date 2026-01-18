import Foundation

// MARK: - Song Progress Model

/// Represents a user's progress for a single song
struct SongProgress: Codable {
    var highScore: Int = 0
    var stars: Int = 0      // 0-3
    var crowns: Int = 0     // 0-3
}

// MARK: - Progress Manager

/// Manages persistent storage of song progress using UserDefaults
class ProgressManager {

    static let shared = ProgressManager()

    private let storageKey = "songProgress"
    private let defaults = UserDefaults.standard

    /// In-memory cache of progress data
    private var progressCache: [String: SongProgress] = [:]

    private init() {
        loadProgress()
    }

    // MARK: - Public API

    /// Get progress for a specific song
    func getProgress(for songId: String) -> SongProgress {
        return progressCache[songId] ?? SongProgress()
    }

    /// Update high score for a song (only saves if higher than existing)
    func updateHighScore(for songId: String, score: Int) {
        var progress = getProgress(for: songId)
        if score > progress.highScore {
            progress.highScore = score
            progressCache[songId] = progress
            saveProgress()
        }
    }

    /// Update stars for a song (only saves if higher than existing)
    func updateStars(for songId: String, stars: Int) {
        var progress = getProgress(for: songId)
        if stars > progress.stars {
            progress.stars = stars
            progressCache[songId] = progress
            saveProgress()
        }
    }

    /// Update crowns for a song (only saves if higher than existing)
    func updateCrowns(for songId: String, crowns: Int) {
        var progress = getProgress(for: songId)
        if crowns > progress.crowns {
            progress.crowns = crowns
            progressCache[songId] = progress
            saveProgress()
        }
    }

    /// Update all progress for a song at once
    func updateProgress(for songId: String, score: Int, stars: Int, crowns: Int) {
        var progress = getProgress(for: songId)
        var changed = false

        if score > progress.highScore {
            progress.highScore = score
            changed = true
        }
        if stars > progress.stars {
            progress.stars = stars
            changed = true
        }
        if crowns > progress.crowns {
            progress.crowns = crowns
            changed = true
        }

        if changed {
            progressCache[songId] = progress
            saveProgress()
        }
    }

    // MARK: - Private Methods

    private func loadProgress() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: SongProgress].self, from: data) {
            progressCache = decoded
        } else {
            progressCache = [:]
        }
    }

    private func saveProgress() {
        if let data = try? JSONEncoder().encode(progressCache) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
