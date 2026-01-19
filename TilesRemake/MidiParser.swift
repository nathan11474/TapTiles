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
    let instruments: [UInt8]         // MIDI program numbers 0-127 (parallel array with midiNotes)
    let sustainPedalOn: Bool         // Whether sustain pedal should be active when this note plays

    // For double-tile rows (fast sections): second tile's notes
    let secondTileMidiNotes: [UInt8]?
    let secondTileNoteDurations: [TimeInterval]?
    let secondTileInstruments: [UInt8]?
    let secondTileSustainPedalOn: Bool?

    /// Convenience for single note
    var midiNote: UInt8 {
        return midiNotes.first ?? 60
    }

    /// Convenience for single instrument
    var instrument: UInt8 {
        return instruments.first ?? 0
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

    /// Convenience for second tile's instrument (single)
    var secondTileInstrument: UInt8? {
        return secondTileInstruments?.first
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
        var allNotes: [(time: TimeInterval, noteDuration: TimeInterval, midiNote: UInt8, instrument: UInt8)] = []
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

        // Debug: Print instrument distribution summary
        var instrumentCounts: [UInt8: Int] = [:]
        for note in mergedNotes {
            for inst in note.instruments {
                instrumentCounts[inst, default: 0] += 1
            }
        }
        print("MidiParser: Instrument distribution:")
        for (inst, count) in instrumentCounts.sorted(by: { $0.key < $1.key }) {
            print("  - \(gmInstrumentName(inst)): \(count) notes")
        }

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

    // Parse a single track, extracting note events with their durations, instruments, and sustain state
    private func parseTrack(_ track: MusicTrack, tempo: Double, sustainEvents: inout [(time: TimeInterval, value: UInt8)]) -> [(time: TimeInterval, noteDuration: TimeInterval, midiNote: UInt8, instrument: UInt8)] {
        var notes: [(time: TimeInterval, noteDuration: TimeInterval, midiNote: UInt8, instrument: UInt8)] = []

        // First pass: collect program changes (instrument assignments) by channel
        // Key: (channel, timeInBeats), Value: program number
        var programChanges: [(time: MusicTimeStamp, channel: UInt8, program: UInt8)] = []

        // Current program for each channel (default to 0 = Acoustic Grand Piano)
        var channelPrograms: [UInt8: UInt8] = [:]

        var iterator: MusicEventIterator?
        NewMusicEventIterator(track, &iterator)

        guard let iter = iterator else {
            return notes
        }

        var hasCurrentEvent: DarwinBoolean = false
        MusicEventIteratorHasCurrentEvent(iter, &hasCurrentEvent)

        // First pass: collect all program changes
        while hasCurrentEvent.boolValue {
            var timestamp: MusicTimeStamp = 0
            var eventType: MusicEventType = 0
            var eventData: UnsafeRawPointer?
            var eventDataSize: UInt32 = 0

            MusicEventIteratorGetEventInfo(iter, &timestamp, &eventType, &eventData, &eventDataSize)

            if eventType == kMusicEventType_MIDIChannelMessage {
                if let data = eventData {
                    let channelMessage = data.assumingMemoryBound(to: MIDIChannelMessage.self)
                    let status = channelMessage.pointee.status
                    let statusType = status & 0xF0
                    let channel = status & 0x0F

                    // Program Change message (0xC0-0xCF)
                    if statusType == 0xC0 {
                        let program = channelMessage.pointee.data1
                        programChanges.append((time: timestamp, channel: channel, program: program))
                    }

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

        // Sort program changes by time
        programChanges.sort { $0.time < $1.time }


        // Reset iterator for second pass
        DisposeMusicEventIterator(iter)
        NewMusicEventIterator(track, &iterator)

        guard let iter2 = iterator else {
            return notes
        }

        MusicEventIteratorHasCurrentEvent(iter2, &hasCurrentEvent)

        // Second pass: collect notes with their instruments
        while hasCurrentEvent.boolValue {
            var timestamp: MusicTimeStamp = 0
            var eventType: MusicEventType = 0
            var eventData: UnsafeRawPointer?
            var eventDataSize: UInt32 = 0

            MusicEventIteratorGetEventInfo(iter2, &timestamp, &eventType, &eventData, &eventDataSize)

            if eventType == kMusicEventType_MIDINoteMessage {
                if let data = eventData {
                    let noteMessage = data.assumingMemoryBound(to: MIDINoteMessage.self)
                    let midiNote = noteMessage.pointee.note
                    let channel = noteMessage.pointee.channel
                    let durationInBeats = Double(noteMessage.pointee.duration)

                    // Find the most recent program change for this channel before this note
                    for change in programChanges where change.channel == channel && change.time <= timestamp {
                        channelPrograms[channel] = change.program
                    }

                    // Get current program for this channel (default to 0 = piano)
                    let instrument = channelPrograms[channel] ?? 0

                    // Convert beats to seconds: (beats / bpm) * 60
                    let timeInSeconds = (timestamp / tempo) * 60.0
                    let durationInSeconds = (durationInBeats / tempo) * 60.0

                    notes.append((time: timeInSeconds, noteDuration: durationInSeconds, midiNote: midiNote, instrument: instrument))
                }
            }

            MusicEventIteratorNextEvent(iter2)
            MusicEventIteratorHasCurrentEvent(iter2, &hasCurrentEvent)
        }

        DisposeMusicEventIterator(iter2)
        return notes
    }

    // Group notes into chords and calculate gaps
    // Notes within chordTolerance seconds of each other are considered simultaneous (a chord)
    private func calculateDurations(notes: [(time: TimeInterval, noteDuration: TimeInterval, midiNote: UInt8, instrument: UInt8)], songEnd: TimeInterval, sustainEvents: [(time: TimeInterval, value: UInt8)]) -> [NoteEvent] {
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
        var chordGroups: [(time: TimeInterval, durations: [TimeInterval], midiNotes: [UInt8], instruments: [UInt8])] = []

        var currentGroup: (time: TimeInterval, durations: [TimeInterval], midiNotes: [UInt8], instruments: [UInt8]) = (
            time: notes[0].time,
            durations: [notes[0].noteDuration],
            midiNotes: [notes[0].midiNote],
            instruments: [notes[0].instrument]
        )

        for i in 1..<notes.count {
            let note = notes[i]

            // Check if this note is within tolerance of the current group's time
            if abs(note.time - currentGroup.time) <= chordTolerance {
                // Same chord - add note with its individual duration and instrument
                currentGroup.midiNotes.append(note.midiNote)
                currentGroup.durations.append(note.noteDuration)
                currentGroup.instruments.append(note.instrument)
            } else {
                // New chord - save current group and start new one
                chordGroups.append(currentGroup)
                currentGroup = (
                    time: note.time,
                    durations: [note.noteDuration],
                    midiNotes: [note.midiNote],
                    instruments: [note.instrument]
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
                instruments: group.instruments,
                sustainPedalOn: sustainOn,
                secondTileMidiNotes: nil,
                secondTileNoteDurations: nil,
                secondTileInstruments: nil,
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
                    instruments: current.instruments,
                    sustainPedalOn: current.sustainPedalOn,
                    secondTileMidiNotes: next.midiNotes,
                    secondTileNoteDurations: next.noteDurations,
                    secondTileInstruments: next.instruments,
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

    // Helper: Convert GM program number to instrument name for debugging
    private func gmInstrumentName(_ program: UInt8) -> String {
        let names = [
            "Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano", "Honky-tonk Piano",
            "Electric Piano 1", "Electric Piano 2", "Harpsichord", "Clavinet",
            "Celesta", "Glockenspiel", "Music Box", "Vibraphone",
            "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",
            "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ",
            "Reed Organ", "Accordion", "Harmonica", "Tango Accordion",
            "Acoustic Guitar (nylon)", "Acoustic Guitar (steel)", "Electric Guitar (jazz)", "Electric Guitar (clean)",
            "Electric Guitar (muted)", "Overdriven Guitar", "Distortion Guitar", "Guitar Harmonics",
            "Acoustic Bass", "Electric Bass (finger)", "Electric Bass (pick)", "Fretless Bass",
            "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2",
            "Violin", "Viola", "Cello", "Contrabass",
            "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani",
            "String Ensemble 1", "String Ensemble 2", "Synth Strings 1", "Synth Strings 2",
            "Choir Aahs", "Voice Oohs", "Synth Voice", "Orchestra Hit",
            "Trumpet", "Trombone", "Tuba", "Muted Trumpet",
            "French Horn", "Brass Section", "Synth Brass 1", "Synth Brass 2",
            "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax",
            "Oboe", "English Horn", "Bassoon", "Clarinet",
            "Piccolo", "Flute", "Recorder", "Pan Flute",
            "Blown Bottle", "Shakuhachi", "Whistle", "Ocarina",
            "Lead 1 (square)", "Lead 2 (sawtooth)", "Lead 3 (calliope)", "Lead 4 (chiff)",
            "Lead 5 (charang)", "Lead 6 (voice)", "Lead 7 (fifths)", "Lead 8 (bass + lead)",
            "Pad 1 (new age)", "Pad 2 (warm)", "Pad 3 (polysynth)", "Pad 4 (choir)",
            "Pad 5 (bowed)", "Pad 6 (metallic)", "Pad 7 (halo)", "Pad 8 (sweep)",
            "FX 1 (rain)", "FX 2 (soundtrack)", "FX 3 (crystal)", "FX 4 (atmosphere)",
            "FX 5 (brightness)", "FX 6 (goblins)", "FX 7 (echoes)", "FX 8 (sci-fi)",
            "Sitar", "Banjo", "Shamisen", "Koto",
            "Kalimba", "Bagpipe", "Fiddle", "Shanai",
            "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock",
            "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
            "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet",
            "Telephone Ring", "Helicopter", "Applause", "Gunshot"
        ]
        return program < names.count ? names[Int(program)] : "Unknown (\(program))"
    }
}
