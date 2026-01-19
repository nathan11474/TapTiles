import Foundation
import CoreGraphics

// MARK: - Song Manager

/// Singleton that discovers and manages available songs
class SongManager {
    static let shared = SongManager()

    private(set) var availableSongs: [SongInfo] = []
    private var songSettings: SongSettingsFile = [:]

    // Cache for calculated difficulties (persists for app lifetime)
    private var cachedDifficulties: [String: Int] = [:]
    private let cacheQueue = DispatchQueue(label: "com.tilesremake.difficultycache")

    private init() {
        loadSongSettings()
        loadAvailableSongs()
    }

    // MARK: - Difficulty Cache

    /// Get cached difficulty for a song, or nil if not yet calculated
    func getCachedDifficulty(for songId: String) -> Int? {
        return cacheQueue.sync {
            cachedDifficulties[songId]
        }
    }

    /// Cache a calculated difficulty for a song
    func cacheDifficulty(_ difficulty: Int, for songId: String) {
        cacheQueue.sync {
            cachedDifficulties[songId] = difficulty
        }
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
                print("SongManager: Loaded settings for \(songSettings.count) song(s) from \(url.lastPathComponent)")
                return
            } catch {
                print("SongManager: Failed to load song-settings.json: \(error)")
            }
        }

        print("SongManager: No song-settings.json found, using default speeds")
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
    }
}
