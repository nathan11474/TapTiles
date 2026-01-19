//
//  MidiParser.swift
//  TilesRemake
//

import AudioToolbox

// Represents a note event from the MIDI file (can be a single note or chord)
struct NoteEvent {
    let time: TimeInterval           // Seconds from song start when note should play
    let gapToNextNote: TimeInterval  // Time until NEXT note (used for tile length calculation)
    let noteDurations: [TimeInterval] // Individual note durations from MIDI (parallel array with midiNotes)
    let midiNotes: [UInt8]           // MIDI note numbers 0-127 (multiple = chord)
    let sustainPedalOn: Bool         // Whether sustain pedal should be active when this note plays

    // For double-tile rows (fast sections): second tile's notes
    let secondTileMidiNotes: [UInt8]?
    let secondTileNoteDurations: [TimeInterval]?
    let secondTileSustainPedalOn: Bool?

    /// Convenience for single note
    var midiNote: UInt8 {
        return midiNotes.first ?? 60
    }

    /// Convenience for single duration (max of all durations for backwards compatibility)
    var noteDuration: TimeInterval {
        return noteDurations.max() ?? 0.5
    }

    /// Convenience for second tile's duration (max)
    var secondTileNoteDuration: TimeInterval? {
        return secondTileNoteDurations?.max()
    }

    /// Whether this is a chord (multiple simultaneous notes)
    var isChord: Bool {
        return midiNotes.count > 1
    }

    /// Whether this event spawns two tiles (for fast sections)
    var isDoubleTile: Bool {
        return secondTileMidiNotes != nil
    }
}

// Holds all song data extracted from MIDI file
struct Beatmap {
    let title: String               // Song name (from filename)
    let tempo: Double               // BPM
    let notes: [NoteEvent]          // All notes sorted by time
    let totalDuration: TimeInterval // Total song length
    let averageGap: TimeInterval    // Average time between notes (for relative thresholds)
}

class MidiParser {

    // Main entry point - parses MIDI file and returns Beatmap
    func parse(url: URL) -> Beatmap? {
        var sequence: MusicSequence?
        var status = NewMusicSequence(&sequence)

        guard status == noErr, let seq = sequence else {
            print("MidiParser: Failed to create MusicSequence: \(status)")
            return nil
        }

        // Load MIDI file
        status = MusicSequenceFileLoad(seq, url as CFURL, .midiType, .smf_ChannelsToTracks)
        guard status == noErr else {
            print("MidiParser: Failed to load MIDI file: \(status)")
            DisposeMusicSequence(seq)
            return nil
        }

        // Extract tempo
        let tempo = extractTempo(from: seq)
        print("MidiParser: Extracted tempo: \(tempo) BPM")

        // Get track count
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(seq, &trackCount)
        print("MidiParser: Found \(trackCount) tracks")

        // Collect all notes and sustain events from all tracks
        var allNotes: [(time: TimeInterval, noteDuration: TimeInterval, midiNote: UInt8)] = []
        var allSustainEvents: [(time: TimeInterval, value: UInt8)] = []

        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(seq, i, &track)

            if let track = track {
                let trackNotes = parseTrack(track, tempo: tempo, sustainEvents: &allSustainEvents)
                allNotes.append(contentsOf: trackNotes)
                print("MidiParser: Track \(i) has \(trackNotes.count) notes")
            }
        }

        // Sort sustain events by time
        allSustainEvents.sort { $0.time < $1.time }
        print("MidiParser: Found \(allSustainEvents.count) sustain pedal events")

        // Sort by time
        allNotes.sort { $0.time < $1.time }

        guard !allNotes.isEmpty else {
            print("MidiParser: No notes found in MIDI file")
            DisposeMusicSequence(seq)
            return nil
        }

        // Calculate song end time (last note time + some buffer)
        let songEnd = allNotes.last!.time + 2.0

        // Calculate durations (gap to next note) and assign sustain state
        let noteEvents = calculateDurations(notes: allNotes, songEnd: songEnd, sustainEvents: allSustainEvents)

        // Calculate trimmed mean gap (remove top 10% outliers, then average)
        // This captures the typical gap while ignoring unusually long pauses
        let averageGap: TimeInterval
        if noteEvents.count > 1 {
            let gaps = noteEvents.dropLast().map { $0.gapToNextNote }.sorted()
            let trimCount = max(1, gaps.count / 10)  // Remove top 10%
            let trimmedGaps = gaps.dropLast(trimCount)
            if trimmedGaps.isEmpty {
                averageGap = gaps.first ?? 0.5
            } else {
                averageGap = trimmedGaps.reduce(0.0, +) / Double(trimmedGaps.count)
            }
        } else {
            averageGap = 0.5  // Default fallback
        }

        // Merge fast consecutive notes into double-tile events
        let mergedNotes = mergeDoubleTiles(notes: noteEvents, averageGap: averageGap)
        let doubleTileCount = mergedNotes.filter { $0.isDoubleTile }.count

        // Extract title from filename
        let title = url.deletingPathExtension().lastPathComponent

        print("MidiParser: Parsed '\(title)' - \(mergedNotes.count) events (\(doubleTileCount) double tiles), \(String(format: "%.1f", songEnd))s, trimmed mean gap: \(String(format: "%.3f", averageGap))s")

        DisposeMusicSequence(seq)

        return Beatmap(
            title: title,
            tempo: tempo,
            notes: mergedNotes,
            totalDuration: songEnd,
            averageGap: averageGap
        )
    }

    // Extract tempo from tempo track (defaults to 120 BPM)
    private func extractTempo(from sequence: MusicSequence) -> Double {
        var tempoTrack: MusicTrack?
        MusicSequenceGetTempoTrack(sequence, &tempoTrack)

        guard let track = tempoTrack else {
            return 120.0
        }

        var iterator: MusicEventIterator?
        NewMusicEventIterator(track, &iterator)

        guard let iter = iterator else {
            return 120.0
        }

        var hasCurrentEvent: DarwinBoolean = false
        MusicEventIteratorHasCurrentEvent(iter, &hasCurrentEvent)

        while hasCurrentEvent.boolValue {
            var timestamp: MusicTimeStamp = 0
            var eventType: MusicEventType = 0
            var eventData: UnsafeRawPointer?
            var eventDataSize: UInt32 = 0

            MusicEventIteratorGetEventInfo(iter, &timestamp, &eventType, &eventData, &eventDataSize)

            if eventType == kMusicEventType_ExtendedTempo {
                if let data = eventData {
                    let tempoEvent = data.assumingMemoryBound(to: ExtendedTempoEvent.self)
                    DisposeMusicEventIterator(iter)
                    return tempoEvent.pointee.bpm
                }
            }

            MusicEventIteratorNextEvent(iter)
            MusicEventIteratorHasCurrentEvent(iter, &hasCurrentEvent)
        }

        DisposeMusicEventIterator(iter)
        return 120.0  // Default tempo if none found
    }

    // Parse a single track, extracting note events with their durations and sustain state
    private func parseTrack(_ track: MusicTrack, tempo: Double, sustainEvents: inout [(time: TimeInterval, value: UInt8)]) -> [(time: TimeInterval, noteDuration: TimeInterval, midiNote: UInt8)] {
        var notes: [(time: TimeInterval, noteDuration: TimeInterval, midiNote: UInt8)] = []

        var iterator: MusicEventIterator?
        NewMusicEventIterator(track, &iterator)

        guard let iter = iterator else {
            return notes
        }

        var hasCurrentEvent: DarwinBoolean = false
        MusicEventIteratorHasCurrentEvent(iter, &hasCurrentEvent)

        while hasCurrentEvent.boolValue {
            var timestamp: MusicTimeStamp = 0
            var eventType: MusicEventType = 0
            var eventData: UnsafeRawPointer?
            var eventDataSize: UInt32 = 0

            MusicEventIteratorGetEventInfo(iter, &timestamp, &eventType, &eventData, &eventDataSize)

            if eventType == kMusicEventType_MIDINoteMessage {
                if let data = eventData {
                    let noteMessage = data.assumingMemoryBound(to: MIDINoteMessage.self)
                    let channel = noteMessage.pointee.channel

                    // Skip drum channel (channel 10 = index 9 in 0-indexed MIDI)
                    if channel == 9 {
                        MusicEventIteratorNextEvent(iter)
                        MusicEventIteratorHasCurrentEvent(iter, &hasCurrentEvent)
                        continue
                    }

                    let midiNote = noteMessage.pointee.note
                    let durationInBeats = Double(noteMessage.pointee.duration)

                    // Convert beats to seconds: (beats / bpm) * 60
                    let timeInSeconds = (timestamp / tempo) * 60.0
                    let durationInSeconds = (durationInBeats / tempo) * 60.0

                    notes.append((time: timeInSeconds, noteDuration: durationInSeconds, midiNote: midiNote))
                }
            } else if eventType == kMusicEventType_MIDIChannelMessage {
                if let data = eventData {
                    let channelMessage = data.assumingMemoryBound(to: MIDIChannelMessage.self)
                    let status = channelMessage.pointee.status
                    let statusType = status & 0xF0

                    // Control Change message (0xB0-0xBF)
                    if statusType == 0xB0 {
                        let controller = channelMessage.pointee.data1
                        let value = channelMessage.pointee.data2

                        // CC64 = Sustain Pedal (Damper)
                        if controller == 64 {
                            let timeInSeconds = (timestamp / tempo) * 60.0
                            sustainEvents.append((time: timeInSeconds, value: value))
                        }
                    }
                }
            }

            MusicEventIteratorNextEvent(iter)
            MusicEventIteratorHasCurrentEvent(iter, &hasCurrentEvent)
        }

        DisposeMusicEventIterator(iter)
        return notes
    }

    // Group notes into chords and calculate gaps
    // Notes within chordTolerance seconds of each other are considered simultaneous (a chord)
    private func calculateDurations(notes: [(time: TimeInterval, noteDuration: TimeInterval, midiNote: UInt8)], songEnd: TimeInterval, sustainEvents: [(time: TimeInterval, value: UInt8)]) -> [NoteEvent] {
        guard !notes.isEmpty else { return [] }

        // Tolerance for considering notes as simultaneous (in seconds)
        let chordTolerance: TimeInterval = 0.02

        // Helper: determine if sustain pedal is on at a given time
        // Sustain is ON when value >= 64, OFF when < 64
        func isSustainOn(at time: TimeInterval) -> Bool {
            var sustainOn = false
            for event in sustainEvents {
                if event.time > time { break }
                sustainOn = event.value >= 64
            }
            return sustainOn
        }

        // Group notes into chords based on timing
        // Stores individual durations per note (parallel arrays)
        var chordGroups: [(time: TimeInterval, durations: [TimeInterval], midiNotes: [UInt8])] = []

        var currentGroup: (time: TimeInterval, durations: [TimeInterval], midiNotes: [UInt8]) = (
            time: notes[0].time,
            durations: [notes[0].noteDuration],
            midiNotes: [notes[0].midiNote]
        )

        for i in 1..<notes.count {
            let note = notes[i]

            // Check if this note is within tolerance of the current group's time
            if abs(note.time - currentGroup.time) <= chordTolerance {
                // Same chord - add note with its individual duration
                currentGroup.midiNotes.append(note.midiNote)
                currentGroup.durations.append(note.noteDuration)
            } else {
                // New chord - save current group and start new one
                chordGroups.append(currentGroup)
                currentGroup = (
                    time: note.time,
                    durations: [note.noteDuration],
                    midiNotes: [note.midiNote]
                )
            }
        }
        // Don't forget the last group
        chordGroups.append(currentGroup)

        // Now create NoteEvents with gaps calculated between chord groups
        var noteEvents: [NoteEvent] = []

        for i in 0..<chordGroups.count {
            let group = chordGroups[i]
            let gapToNext: TimeInterval

            if i < chordGroups.count - 1 {
                // Gap = time until next chord starts
                gapToNext = chordGroups[i + 1].time - group.time
            } else {
                // Last chord - gap until song end (or default)
                gapToNext = max(songEnd - group.time, 1.0)
            }

            // Determine sustain pedal state at this note's time
            let sustainOn = isSustainOn(at: group.time)

            noteEvents.append(NoteEvent(
                time: group.time,
                gapToNextNote: gapToNext,
                noteDurations: group.durations,
                midiNotes: group.midiNotes,
                sustainPedalOn: sustainOn,
                secondTileMidiNotes: nil,
                secondTileNoteDurations: nil,
                secondTileSustainPedalOn: nil
            ))
        }

        return noteEvents
    }

    // Merge consecutive fast notes into double-tile events
    // Notes with very short gaps (fast sections) get combined into a single row with 2 tiles
    private func mergeDoubleTiles(notes: [NoteEvent], averageGap: TimeInterval) -> [NoteEvent] {
        guard notes.count > 1 else { return notes }

        // Threshold for "fast" notes - gaps below this trigger double tiles
        let doubleTileThreshold = averageGap * GameConfig.doubleTileGapMultiplier

        var result: [NoteEvent] = []
        var i = 0

        while i < notes.count {
            let current = notes[i]

            // Check if this note has a short gap to the next note
            // AND the next note exists AND it's not already a double tile scenario
            if current.gapToNextNote < doubleTileThreshold && i + 1 < notes.count {
                let next = notes[i + 1]

                // Merge: current note becomes a double tile with next note's data
                // Gap to the note after next (or original if next was last)
                let newGapToNext: TimeInterval
                if i + 2 < notes.count {
                    newGapToNext = notes[i + 2].time - current.time
                } else {
                    newGapToNext = current.gapToNextNote + next.gapToNextNote
                }

                let merged = NoteEvent(
                    time: current.time,
                    gapToNextNote: newGapToNext,
                    noteDurations: current.noteDurations,
                    midiNotes: current.midiNotes,
                    sustainPedalOn: current.sustainPedalOn,
                    secondTileMidiNotes: next.midiNotes,
                    secondTileNoteDurations: next.noteDurations,
                    secondTileSustainPedalOn: next.sustainPedalOn
                )
                result.append(merged)

                // Skip the next note since it was merged
                i += 2
            } else {
                // Normal note - keep as is
                result.append(current)
                i += 1
            }
        }

        return result
    }
}
