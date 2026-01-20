import Foundation

// MARK: - Song Progress Model

/// Represents a user's progress for a single song
struct SongProgress: Codable {
    var highScore: Int = 0
    var stars: Int = 0      // 0-3
    var crowns: Int = 0     // 0-3
    var isFavorite: Bool = false
    var fileHash: String?   // File fingerprint (size + modification date) to detect when file is replaced
}

// MARK: - Progress Manager

/// Manages persistent storage of song progress using UserDefaults
class ProgressManager {

    static let shared = ProgressManager()

    private let storageKey = "songProgress"
    private let defaults = UserDefaults.standard

    /// In-memory cache of progress data
    private var progressCache: [String: SongProgress] = [:]

    /// In-memory cache of file hashes (computed once per session)
    private var fileHashCache: [String: String] = [:]

    private init() {
        loadProgress()
    }

    // MARK: - Public API

    /// Get progress for a specific song, validating against file hash if URL provided
    func getProgress(for songId: String, fileURL: URL? = nil) -> SongProgress {
        guard let progress = progressCache[songId] else {
            return SongProgress()
        }

        // Only validate hash if there's actual progress and a stored hash to compare
        if let url = fileURL, let storedHash = progress.fileHash,
           progress.highScore > 0 || progress.stars > 0 || progress.crowns > 0 {
            let currentHash = getFileHash(for: songId, url: url)
            if currentHash != storedHash {
                // File has changed - return empty progress (don't modify cache yet)
                return SongProgress()
            }
        }

        return progress
    }

    /// Update high score for a song (only saves if higher than existing)
    func updateHighScore(for songId: String, score: Int, fileURL: URL) {
        var progress = getProgress(for: songId, fileURL: fileURL)
        if score > progress.highScore {
            progress.highScore = score
            progress.fileHash = getFileHash(for: songId, url: fileURL)
            progressCache[songId] = progress
            saveProgress()
        }
    }

    /// Update stars for a song (only saves if higher than existing)
    func updateStars(for songId: String, stars: Int, fileURL: URL) {
        var progress = getProgress(for: songId, fileURL: fileURL)
        if stars > progress.stars {
            progress.stars = stars
            progress.fileHash = getFileHash(for: songId, url: fileURL)
            progressCache[songId] = progress
            saveProgress()
        }
    }

    /// Update crowns for a song (only saves if higher than existing)
    func updateCrowns(for songId: String, crowns: Int, fileURL: URL) {
        var progress = getProgress(for: songId, fileURL: fileURL)
        if crowns > progress.crowns {
            progress.crowns = crowns
            progress.fileHash = getFileHash(for: songId, url: fileURL)
            progressCache[songId] = progress
            saveProgress()
        }
    }

    /// Toggle favorite status for a song
    func toggleFavorite(for songId: String, fileURL: URL) -> Bool {
        var progress = getProgress(for: songId, fileURL: fileURL)
        progress.isFavorite = !progress.isFavorite
        progress.fileHash = getFileHash(for: songId, url: fileURL)
        progressCache[songId] = progress
        saveProgress()
        return progress.isFavorite
    }

    /// Check if a song is favorited
    func isFavorite(for songId: String, fileURL: URL? = nil) -> Bool {
        return getProgress(for: songId, fileURL: fileURL).isFavorite
    }

    /// Update all progress for a song at once
    func updateProgress(for songId: String, score: Int, stars: Int, crowns: Int, fileURL: URL) {
        var progress = getProgress(for: songId, fileURL: fileURL)
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
            progress.fileHash = getFileHash(for: songId, url: fileURL)
            progressCache[songId] = progress
            saveProgress()
        }
    }

    // MARK: - Private Methods

    /// Get file hash from cache, or compute and cache it
    private func getFileHash(for songId: String, url: URL) -> String? {
        // Return cached hash if available
        if let cachedHash = fileHashCache[songId] {
            return cachedHash
        }

        // Compute hash and cache it
        guard let hash = computeFileHash(url: url) else {
            return nil
        }
        fileHashCache[songId] = hash
        return hash
    }

    /// Compute a fingerprint from file metadata (size + modification date) to detect changes
    private func computeFileHash(url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date,
              let fileSize = attrs[.size] as? Int else {
            return nil
        }
        return "\(fileSize)-\(Int(modDate.timeIntervalSince1970))"
    }

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
