import Foundation
import CoreGraphics

// MARK: - Difficulty Cache Entry

/// Cached difficulty with file fingerprint for invalidation
private struct DifficultyCacheEntry: Codable {
    let difficulty: Int
    let fingerprint: String  // file size + modification date
}

// MARK: - Song Manager

/// Singleton that discovers and manages available songs
class SongManager {
    static let shared = SongManager()

    private(set) var availableSongs: [SongInfo] = []
    private var songSettings: SongSettingsFile = [:]

    // Cache for calculated difficulties (persisted to UserDefaults)
    private var difficultyCache: [String: DifficultyCacheEntry] = [:]
    private let cacheQueue = DispatchQueue(label: "com.tilesremake.difficultycache")
    private let difficultyCacheKey = "difficultyCacheV1"

    // Debounced save (coalesces rapid updates into single write)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveDebounceDelay: TimeInterval = 0.5

    private init() {
        loadDifficultyCache()
        loadSongSettings()
        loadAvailableSongs()
        cleanupOrphanedCacheEntries()
    }

    // MARK: - Difficulty Cache

    /// Get cached difficulty for a song if fingerprint matches, or nil if needs recalculation
    func getCachedDifficulty(for songId: String, fileURL: URL? = nil) -> Int? {
        return cacheQueue.sync {
            guard let entry = difficultyCache[songId] else { return nil }

            // If URL provided, validate fingerprint
            if let url = fileURL {
                let currentFingerprint = computeFileFingerprint(url: url)
                if currentFingerprint != entry.fingerprint {
                    return nil  // File changed, needs recalculation
                }
            }

            return entry.difficulty
        }
    }

    /// Cache a calculated difficulty for a song with its file fingerprint
    func cacheDifficulty(_ difficulty: Int, for songId: String, fileURL: URL) {
        cacheQueue.sync {
            let fingerprint = computeFileFingerprint(url: fileURL) ?? ""
            difficultyCache[songId] = DifficultyCacheEntry(difficulty: difficulty, fingerprint: fingerprint)
            saveDifficultyCache()
        }
    }

    /// Clear cached difficulty for a specific song (used when deleting imported songs)
    func clearCachedDifficulty(for songId: String) {
        cacheQueue.sync {
            if difficultyCache.removeValue(forKey: songId) != nil {
                saveDifficultyCache()
                #if DEBUG
                print("SongManager: Cleared cached difficulty for \(songId)")
                #endif
            }
        }
    }

    // MARK: - Cache Persistence

    private func loadDifficultyCache() {
        guard let data = UserDefaults.standard.data(forKey: difficultyCacheKey),
              let decoded = try? JSONDecoder().decode([String: DifficultyCacheEntry].self, from: data) else {
            difficultyCache = [:]
            return
        }
        difficultyCache = decoded
        #if DEBUG
        print("SongManager: Loaded \(difficultyCache.count) cached difficulties from disk")
        #endif
    }

    /// Schedule a debounced save - coalesces rapid updates into a single write
    private func saveDifficultyCache() {
        // Cancel any pending save
        pendingSaveWorkItem?.cancel()

        // Schedule new save after delay
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveDifficultyCacheNow()
        }
        pendingSaveWorkItem = workItem
        cacheQueue.asyncAfter(deadline: .now() + saveDebounceDelay, execute: workItem)
    }

    /// Save immediately without debouncing
    private func saveDifficultyCacheNow() {
        // Cancel any pending debounced save
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil

        if let data = try? JSONEncoder().encode(difficultyCache) {
            UserDefaults.standard.set(data, forKey: difficultyCacheKey)
        }
    }

    /// Remove cache entries for songs that no longer exist in the bundle
    private func cleanupOrphanedCacheEntries() {
        let validSongIds = Set(availableSongs.map { $0.id })
        var orphanedCount = 0

        for cachedId in difficultyCache.keys {
            if !validSongIds.contains(cachedId) {
                difficultyCache.removeValue(forKey: cachedId)
                orphanedCount += 1
            }
        }

        if orphanedCount > 0 {
            saveDifficultyCacheNow()  // Immediate save for cleanup
            #if DEBUG
            print("SongManager: Cleaned up \(orphanedCount) orphaned cache entries")
            #endif
        }
    }

    /// Compute file fingerprint from metadata (size + modification date)
    private func computeFileFingerprint(url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date,
              let fileSize = attrs[.size] as? Int else {
            return nil
        }
        return "\(fileSize)-\(Int(modDate.timeIntervalSince1970))"
    }

    /// Reload songs from bundle (useful if songs are added dynamically)
    func reload() {
        loadSongSettings()
        loadAvailableSongs()
    }

    /// Load custom song settings from song-settings.json
    private func loadSongSettings() {
        songSettings = [:]

        // Try Songs subdirectory first, then bundle root
        let possibleURLs = [
            Bundle.main.url(forResource: "song-settings", withExtension: "json", subdirectory: "Songs"),
            Bundle.main.url(forResource: "song-settings", withExtension: "json")
        ]

        for possibleURL in possibleURLs {
            guard let url = possibleURL else { continue }

            do {
                let data = try Data(contentsOf: url)
                songSettings = try JSONDecoder().decode(SongSettingsFile.self, from: data)
                #if DEBUG
                print("SongManager: Loaded settings for \(songSettings.count) song(s) from \(url.lastPathComponent)")
                #endif
                return
            } catch {
                #if DEBUG
                print("SongManager: Failed to load song-settings.json: \(error)")
                #endif
            }
        }

        #if DEBUG
        print("SongManager: No song-settings.json found, using default speeds")
        #endif
    }

    private func loadAvailableSongs() {
        availableSongs = []

        let midiExtensions = ["mid", "midi"]

        // Try to load from Songs subdirectory first
        for ext in midiExtensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Songs") {
                for url in urls {
                    let songId = url.deletingPathExtension().lastPathComponent
                    let settings = songSettings[songId]
                    let displayName = settings?.displayName
                    let customSpeed = settings?.initialSpeed.map { CGFloat($0) }
                    let startFromNote = settings?.startFromNote
                    let category = settings?.category ?? "Uncategorized"
                    availableSongs.append(SongInfo(url: url, displayName: displayName, customSpeed: customSpeed, startFromNote: startFromNote, category: category))
                }
            }
        }

        // Fallback: search bundle root for MIDI files
        if availableSongs.isEmpty {
            for ext in midiExtensions {
                if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                    for url in urls {
                        let songId = url.deletingPathExtension().lastPathComponent
                        let settings = songSettings[songId]
                        let displayName = settings?.displayName
                        let customSpeed = settings?.initialSpeed.map { CGFloat($0) }
                        let startFromNote = settings?.startFromNote
                        let category = settings?.category ?? "Uncategorized"
                        availableSongs.append(SongInfo(url: url, displayName: displayName, customSpeed: customSpeed, startFromNote: startFromNote, category: category))
                    }
                }
            }
        }

        // Sort alphabetically by title
        availableSongs.sort { $0.title < $1.title }

        #if DEBUG
        print("SongManager: Found \(availableSongs.count) song(s)")
        for song in availableSongs {
            var extras: [String] = []
            extras.append("category: \(song.category)")
            if let speed = song.customSpeed {
                extras.append("speed: \(Int(speed))")
            }
            if let startNote = song.startFromNote {
                extras.append("startFromNote: \(startNote)")
            }
            print("  - \(song.title) (\(song.id)) [\(extras.joined(separator: ", "))]")
        }
        #endif
    }
}
