import Foundation
import CoreGraphics

// MARK: - Imported Song Data Model

/// Represents metadata for an imported song (persisted to JSON)
struct ImportedSongData: Codable {
    let fileName: String           // Original filename (with extension)
    let displayName: String        // User-facing name (derived from filename for Phase 1)
    let importDate: Date           // When the song was imported
    let customSpeed: Double?       // Optional custom speed override (nil = use calculated)
}

// MARK: - Imported Song Manager

/// Singleton that manages imported MIDI songs stored in the app's Documents directory
class ImportedSongManager {

    static let shared = ImportedSongManager()

    /// Prefix added to imported song IDs to distinguish them from bundled songs
    /// This prevents ID collisions when an imported song has the same filename as a bundled song
    static let importedIdPrefix = "imported_"

    /// Currently available imported songs (rebuilt on init and after import/delete)
    private(set) var availableImportedSongs: [SongInfo] = []

    /// Imported songs metadata (persisted to JSON)
    private var importedSongsData: [ImportedSongData] = []

    /// Name of the directory where imported songs are stored
    private let importedSongsDirectoryName = "ImportedSongs"

    /// Name of the JSON file storing import metadata
    private let metadataFileName = "imported-songs.json"

    private init() {
        ensureImportedSongsDirectoryExists()
        loadImportedSongsData()
        rebuildAvailableSongs()
    }

    // MARK: - Directory Management

    /// Returns the URL to the ImportedSongs directory in Documents
    func getImportedSongsDirectory() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent(importedSongsDirectoryName)
    }

    /// Creates the ImportedSongs directory if it doesn't exist
    private func ensureImportedSongsDirectoryExists() {
        let directoryURL = getImportedSongsDirectory()
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                #if DEBUG
                print("ImportedSongManager: Created ImportedSongs directory")
                #endif
            } catch {
                #if DEBUG
                print("ImportedSongManager: Failed to create ImportedSongs directory: \(error)")
                #endif
            }
        }
    }

    /// Returns the URL to the metadata JSON file
    private func getMetadataFileURL() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent(metadataFileName)
    }

    // MARK: - Persistence

    /// Loads imported songs metadata from JSON file
    private func loadImportedSongsData() {
        let metadataURL = getMetadataFileURL()

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            importedSongsData = []
            return
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            importedSongsData = try JSONDecoder().decode([ImportedSongData].self, from: data)
            #if DEBUG
            print("ImportedSongManager: Loaded \(importedSongsData.count) imported song(s) from metadata")
            #endif
        } catch {
            #if DEBUG
            print("ImportedSongManager: Failed to load imported songs metadata: \(error)")
            #endif
            importedSongsData = []
        }
    }

    /// Saves imported songs metadata to JSON file
    private func saveImportedSongsData() {
        let metadataURL = getMetadataFileURL()

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(importedSongsData)
            try data.write(to: metadataURL)
            #if DEBUG
            print("ImportedSongManager: Saved \(importedSongsData.count) imported song(s) to metadata")
            #endif
        } catch {
            #if DEBUG
            print("ImportedSongManager: Failed to save imported songs metadata: \(error)")
            #endif
        }
    }

    // MARK: - Song List Building

    /// Rebuilds the availableImportedSongs array from stored metadata
    /// Also cleans up orphaned entries (metadata for files that no longer exist)
    private func rebuildAvailableSongs() {
        let directoryURL = getImportedSongsDirectory()
        var validSongs: [SongInfo] = []
        var validData: [ImportedSongData] = []

        for songData in importedSongsData {
            let fileURL = directoryURL.appendingPathComponent(songData.fileName)

            // Check if the file still exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // Create SongInfo for this imported song with prefix to avoid ID collisions
                let customSpeed = songData.customSpeed.map { CGFloat($0) }
                let songInfo = SongInfo(
                    url: fileURL,
                    displayName: songData.displayName,
                    customSpeed: customSpeed,
                    startFromNote: nil,
                    category: "Imported",
                    idPrefix: ImportedSongManager.importedIdPrefix
                )
                validSongs.append(songInfo)
                validData.append(songData)
            } else {
                #if DEBUG
                print("ImportedSongManager: Removing orphaned entry for missing file: \(songData.fileName)")
                #endif
            }
        }

        // Update data if any orphaned entries were removed
        if validData.count != importedSongsData.count {
            importedSongsData = validData
            saveImportedSongsData()
        }

        availableImportedSongs = validSongs

        #if DEBUG
        print("ImportedSongManager: \(availableImportedSongs.count) imported song(s) available")
        #endif
    }

    // MARK: - Import Operations

    /// Imports a MIDI file from a source URL
    /// - Parameters:
    ///   - sourceURL: The URL to the MIDI file (typically from document picker)
    ///   - displayName: Custom display name for the song (nil = auto-format from filename)
    ///   - customSpeed: Custom scroll speed override (nil = use calculated speed)
    /// - Returns: The imported SongInfo if successful, nil otherwise
    @discardableResult
    func importSong(from sourceURL: URL, displayName: String? = nil, customSpeed: CGFloat? = nil) -> SongInfo? {
        let directoryURL = getImportedSongsDirectory()

        // Get the original filename
        let originalFileName = sourceURL.lastPathComponent

        // Generate a unique filename if one already exists
        let destinationFileName = generateUniqueFileName(originalFileName, in: directoryURL)
        let destinationURL = directoryURL.appendingPathComponent(destinationFileName)

        // Start accessing security-scoped resource (for files from document picker)
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        // Copy the file to our directory
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            #if DEBUG
            print("ImportedSongManager: Copied \(originalFileName) to \(destinationFileName)")
            #endif
        } catch {
            #if DEBUG
            print("ImportedSongManager: Failed to copy file: \(error)")
            #endif
            return nil
        }

        // Create metadata entry with custom display name if provided
        let finalDisplayName = displayName ?? formatDisplayName(from: destinationFileName)
        let songData = ImportedSongData(
            fileName: destinationFileName,
            displayName: finalDisplayName,
            importDate: Date(),
            customSpeed: customSpeed.map { Double($0) }  // Convert CGFloat to Double for storage
        )

        // Add to our data and save
        importedSongsData.append(songData)
        saveImportedSongsData()

        // Create SongInfo with prefix to avoid ID collisions with bundled songs
        let songInfo = SongInfo(
            url: destinationURL,
            displayName: finalDisplayName,
            customSpeed: customSpeed,
            startFromNote: nil,
            category: "Imported",
            idPrefix: ImportedSongManager.importedIdPrefix
        )

        availableImportedSongs.append(songInfo)

        #if DEBUG
        print("ImportedSongManager: Successfully imported '\(finalDisplayName)' with custom speed: \(String(describing: customSpeed))")
        #endif

        return songInfo
    }

    /// Generates a unique filename by appending a number if the file already exists
    private func generateUniqueFileName(_ originalName: String, in directory: URL) -> String {
        var fileName = originalName
        var counter = 1

        let nameWithoutExtension = (originalName as NSString).deletingPathExtension
        let fileExtension = (originalName as NSString).pathExtension

        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
            fileName = "\(nameWithoutExtension)-\(counter).\(fileExtension)"
            counter += 1
        }

        return fileName
    }

    /// Formats a display name from a filename
    /// Removes extension and converts kebab-case/underscores to spaces with title case
    private func formatDisplayName(from fileName: String) -> String {
        // Remove extension
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension

        // Replace hyphens and underscores with spaces
        let withSpaces = nameWithoutExtension
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        // Title case each word
        return withSpaces
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    // MARK: - Delete Operations (for Phase 3, but structure is here)

    /// Deletes an imported song by its ID
    /// - Parameter songId: The song ID (with "imported_" prefix)
    /// - Returns: true if deletion was successful
    @discardableResult
    func deleteImportedSong(id songId: String) -> Bool {
        // Strip the prefix from the songId to get the base filename
        let baseId: String
        if songId.hasPrefix(ImportedSongManager.importedIdPrefix) {
            baseId = String(songId.dropFirst(ImportedSongManager.importedIdPrefix.count))
        } else {
            baseId = songId
        }

        // Find the song data by matching the base ID (filename without extension)
        guard let index = importedSongsData.firstIndex(where: {
            ($0.fileName as NSString).deletingPathExtension == baseId
        }) else {
            #if DEBUG
            print("ImportedSongManager: Song not found for deletion: \(songId)")
            #endif
            return false
        }

        let songData = importedSongsData[index]
        let fileURL = getImportedSongsDirectory().appendingPathComponent(songData.fileName)

        // Delete the file
        do {
            try FileManager.default.removeItem(at: fileURL)
            #if DEBUG
            print("ImportedSongManager: Deleted file: \(songData.fileName)")
            #endif
        } catch {
            #if DEBUG
            print("ImportedSongManager: Failed to delete file: \(error)")
            #endif
            return false
        }

        // Remove from metadata
        importedSongsData.remove(at: index)
        saveImportedSongsData()

        // Remove from available songs
        availableImportedSongs.removeAll { $0.id == songId }

        return true
    }

    /// Updates an imported song's settings (display name and/or custom speed)
    /// - Parameters:
    ///   - songId: The song ID (with "imported_" prefix)
    ///   - displayName: New display name (nil = keep current)
    ///   - customSpeed: New custom speed (nil = use calculated)
    /// - Returns: true if update was successful
    @discardableResult
    func updateImportedSong(id songId: String, displayName: String? = nil, customSpeed: CGFloat?) -> Bool {
        // Strip the prefix from the songId to get the base filename
        let baseId: String
        if songId.hasPrefix(ImportedSongManager.importedIdPrefix) {
            baseId = String(songId.dropFirst(ImportedSongManager.importedIdPrefix.count))
        } else {
            baseId = songId
        }

        // Find the song data by matching the base ID (filename without extension)
        guard let index = importedSongsData.firstIndex(where: {
            ($0.fileName as NSString).deletingPathExtension == baseId
        }) else {
            #if DEBUG
            print("ImportedSongManager: Song not found for update: \(songId)")
            #endif
            return false
        }

        let existingData = importedSongsData[index]

        // Create updated data entry
        let updatedData = ImportedSongData(
            fileName: existingData.fileName,
            displayName: displayName ?? existingData.displayName,
            importDate: existingData.importDate,
            customSpeed: customSpeed.map { Double($0) }
        )

        // Update in array
        importedSongsData[index] = updatedData
        saveImportedSongsData()

        // Rebuild the available songs list to reflect changes
        rebuildAvailableSongs()

        #if DEBUG
        print("ImportedSongManager: Updated '\(updatedData.displayName)' with custom speed: \(String(describing: customSpeed))")
        #endif

        return true
    }

    /// Gets the stored data for an imported song by its ID
    /// - Parameter songId: The song ID (with "imported_" prefix)
    /// - Returns: The song data if found
    func getImportedSongData(id songId: String) -> ImportedSongData? {
        // Strip the prefix from the songId to get the base filename
        let baseId: String
        if songId.hasPrefix(ImportedSongManager.importedIdPrefix) {
            baseId = String(songId.dropFirst(ImportedSongManager.importedIdPrefix.count))
        } else {
            baseId = songId
        }

        return importedSongsData.first {
            ($0.fileName as NSString).deletingPathExtension == baseId
        }
    }

    /// Reloads all imported songs (useful after external changes)
    func reload() {
        loadImportedSongsData()
        rebuildAvailableSongs()
    }

    // MARK: - Name Validation

    /// Checks if a display name is already used by an imported song
    /// - Parameter name: The display name to check
    /// - Returns: True if the name is already in use
    func isDisplayNameTaken(_ name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return importedSongsData.contains { $0.displayName.lowercased() == normalizedName }
    }

    /// Generates a unique display name by appending (1), (2), etc. if needed
    /// - Parameter baseName: The desired base name
    /// - Returns: A unique name, either the original or with a numeric suffix
    func uniqueDisplayName(for baseName: String) -> String {
        let trimmedName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the name isn't taken, use it as-is
        if !isDisplayNameTaken(trimmedName) {
            return trimmedName
        }

        // Find the next available number
        var counter = 1
        var candidateName = "\(trimmedName) (\(counter))"
        while isDisplayNameTaken(candidateName) {
            counter += 1
            candidateName = "\(trimmedName) (\(counter))"
        }

        return candidateName
    }
}
