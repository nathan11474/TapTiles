//
//  MidiParser.swift
//  TilesRemake
//

import AudioToolbox

// Represents a single note event from the MIDI file
struct NoteEvent {
    let time: TimeInterval           // Seconds from song start when note should play
    let gapToNextNote: TimeInterval  // Time until NEXT note (used for tile length calculation)
    let noteDuration: TimeInterval   // Actual note duration from MIDI (for audio decay)
    let midiNote: UInt8              // MIDI note number 0-127 for audio playback
}

// Holds all song data extracted from MIDI file
struct Beatmap {
    let title: String               // Song name (from filename)
    let tempo: Double               // BPM
    let notes: [NoteEvent]          // All notes sorted by time
    let totalDuration: TimeInterval // Total song length
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

        // Collect all notes from all tracks
        var allNotes: [(time: TimeInterval, noteDuration: TimeInterval, midiNote: UInt8)] = []

        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(seq, i, &track)

            if let track = track {
                let trackNotes = parseTrack(track, tempo: tempo)
                allNotes.append(contentsOf: trackNotes)
                print("MidiParser: Track \(i) has \(trackNotes.count) notes")
            }
        }

        // Sort by time
        allNotes.sort { $0.time < $1.time }

        guard !allNotes.isEmpty else {
            print("MidiParser: No notes found in MIDI file")
            DisposeMusicSequence(seq)
            return nil
        }

        // Calculate song end time (last note time + some buffer)
        let songEnd = allNotes.last!.time + 2.0

        // Calculate durations (gap to next note)
        let noteEvents = calculateDurations(notes: allNotes, songEnd: songEnd)

        // Extract title from filename
        let title = url.deletingPathExtension().lastPathComponent

        print("MidiParser: Parsed '\(title)' - \(noteEvents.count) notes, \(songEnd) seconds")

        DisposeMusicSequence(seq)

        return Beatmap(
            title: title,
            tempo: tempo,
            notes: noteEvents,
            totalDuration: songEnd
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

    // Parse a single track, extracting note events with their durations
    private func parseTrack(_ track: MusicTrack, tempo: Double) -> [(time: TimeInterval, noteDuration: TimeInterval, midiNote: UInt8)] {
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
                    let midiNote = noteMessage.pointee.note
                    let durationInBeats = Double(noteMessage.pointee.duration)

                    // Convert beats to seconds: (beats / bpm) * 60
                    let timeInSeconds = (timestamp / tempo) * 60.0
                    let durationInSeconds = (durationInBeats / tempo) * 60.0

                    notes.append((time: timeInSeconds, noteDuration: durationInSeconds, midiNote: midiNote))
                }
            }

            MusicEventIteratorNextEvent(iter)
            MusicEventIteratorHasCurrentEvent(iter, &hasCurrentEvent)
        }

        DisposeMusicEventIterator(iter)
        return notes
    }

    // Calculate gap to next note for each note (for tile length), preserving note duration (for audio)
    private func calculateDurations(notes: [(time: TimeInterval, noteDuration: TimeInterval, midiNote: UInt8)], songEnd: TimeInterval) -> [NoteEvent] {
        var noteEvents: [NoteEvent] = []

        for i in 0..<notes.count {
            let note = notes[i]
            let gapToNext: TimeInterval

            if i < notes.count - 1 {
                // Gap = time until next note starts
                gapToNext = notes[i + 1].time - note.time
            } else {
                // Last note - gap until song end (or default)
                gapToNext = max(songEnd - note.time, 1.0)
            }

            noteEvents.append(NoteEvent(
                time: note.time,
                gapToNextNote: gapToNext,
                noteDuration: note.noteDuration,
                midiNote: note.midiNote
            ))
        }

        return noteEvents
    }
}
