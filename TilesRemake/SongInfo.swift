import Foundation
import CoreGraphics

// MARK: - Song Info

/// Represents metadata for an available song
struct SongInfo {
    let id: String              // Unique identifier (filename without extension, optionally prefixed)
    let title: String           // Display name (custom or formatted from filename)
    let url: URL                // URL to the MIDI file (bundle or Documents)
    let customSpeed: CGFloat?   // Optional custom initial speed (nil = use calculated speed)
    let startFromNote: Int?     // Optional note index to start from (nil = start from beginning)
    let category: String        // Category/source (e.g., "Chopin", "Beethoven", "Anime")

    /// Creates a SongInfo from a MIDI file URL
    /// - Parameters:
    ///   - url: The URL to the MIDI file
    ///   - displayName: Custom display name (nil = auto-format from filename)
    ///   - customSpeed: Optional custom scroll speed
    ///   - startFromNote: Optional note index to start from
    ///   - category: Category label for the song
    ///   - idPrefix: Optional prefix for the ID to namespace songs (e.g., "imported_")
    init(url: URL, displayName: String? = nil, customSpeed: CGFloat? = nil, startFromNote: Int? = nil, category: String = "Uncategorized", idPrefix: String? = nil) {
        self.url = url
        let baseId = url.deletingPathExtension().lastPathComponent
        self.id = (idPrefix ?? "") + baseId
        self.title = displayName ?? SongInfo.formatTitle(from: baseId)
        self.customSpeed = customSpeed
        self.startFromNote = startFromNote
        self.category = category
    }

    /// Converts a kebab-case filename to a display title
    /// "twinkle-twinkle-little-star" → "Twinkle Twinkle Little Star"
    static func formatTitle(from filename: String) -> String {
        return filename
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Song Settings (for JSON config)

/// Settings loaded from song-settings.json
struct SongSettings: Codable {
    let displayName: String?     // Custom display name (nil = auto-format from filename)
    let initialSpeed: Double?
    let startFromNote: Int?      // Skip to this note index (0-based) when starting
    let category: String?        // Category/source (e.g., "Chopin", "Beethoven", "Anime")
}

/// Root structure for song-settings.json
/// Maps song ID (filename without extension) to its settings
typealias SongSettingsFile = [String: SongSettings]
