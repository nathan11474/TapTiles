import Foundation
import CoreGraphics

// MARK: - Song Info

/// Represents metadata for an available song
struct SongInfo {
    let id: String              // Filename without extension (unique identifier)
    let title: String           // Display name (formatted from filename)
    let url: URL                // Bundle URL to the MIDI file
    let customSpeed: CGFloat?   // Optional custom initial speed (nil = use calculated speed)
    let startFromNote: Int?     // Optional note index to start from (nil = start from beginning)

    /// Creates a SongInfo from a MIDI file URL
    init(url: URL, customSpeed: CGFloat? = nil, startFromNote: Int? = nil) {
        self.url = url
        self.id = url.deletingPathExtension().lastPathComponent
        self.title = SongInfo.formatTitle(from: id)
        self.customSpeed = customSpeed
        self.startFromNote = startFromNote
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
    let initialSpeed: Double?
    let startFromNote: Int?      // Skip to this note index (0-based) when starting
}

/// Root structure for song-settings.json
/// Maps song ID (filename without extension) to its settings
typealias SongSettingsFile = [String: SongSettings]
