//
//  AudioManager.swift
//  TilesRemake
//

import AVFoundation
import AudioToolbox

class AudioManager {
    static let shared = AudioManager()

    private let engine: AVAudioEngine
    private let sampler: AVAudioUnitSampler
    private var isSetup: Bool = false

    // Generation counter for each note to prevent stale stop commands
    // When a note is started, its generation is incremented
    // Stop commands only execute if the generation matches
    private var noteGenerations: [UInt8: Int] = [:]

    private init() {
        engine = AVAudioEngine()
        sampler = AVAudioUnitSampler()
    }

    func setup() {
        guard !isSetup else { return }

        configureAudioSession()
        setupAudioEngine()
        loadSoundFont()
        startEngine()

        isSetup = true
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback)
            try session.setPreferredIOBufferDuration(0.005) // 5ms for low latency
            try session.setPreferredSampleRate(48000)
            try session.setActive(true)
        } catch {
            print("AudioManager: Failed to configure audio session: \(error)")
        }
    }

    private func setupAudioEngine() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }

    private func loadSoundFont() {
        guard let url = Bundle.main.url(forResource: "piano", withExtension: "sf2") else {
            print("AudioManager: Could not find piano.sf2 in bundle")
            return
        }

        print("AudioManager: Loading soundfont from \(url.lastPathComponent)")

        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0, // Piano (General MIDI program 0 = Acoustic Grand Piano)
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
            print("AudioManager: Soundfont loaded successfully")
        } catch {
            print("AudioManager: Failed to load soundfont: \(error)")
        }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }

        do {
            try engine.start()
        } catch {
            print("AudioManager: Failed to start audio engine: \(error)")
        }
    }

    /// Increment generation and return new value (call when starting a note)
    private func incrementGeneration(for note: UInt8) -> Int {
        let newGeneration = (noteGenerations[note] ?? 0) + 1
        noteGenerations[note] = newGeneration
        return newGeneration
    }

    // MARK: - Single Note Methods

    /// Play a sustained note (for long tiles) - must call stopNote() to end
    func playSustainedNote(_ note: UInt8, velocity: UInt8 = 127) {
        // Increment generation to invalidate any pending stop commands for this note
        _ = incrementGeneration(for: note)
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)
    }

    /// Play a short note that automatically stops after a duration (for normal tiles)
    func playShortNote(_ note: UInt8, velocity: UInt8 = 100, duration: TimeInterval = 0.5) {
        // Increment generation and capture it for the delayed stop
        let generation = incrementGeneration(for: note)
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            // Only stop if the generation hasn't changed (no new note started on this pitch)
            guard let self = self, self.noteGenerations[note] == generation else { return }
            self.sampler.stopNote(note, onChannel: 0)
        }
    }

    func stopNote(_ note: UInt8) {
        // Increment generation to mark this as an intentional stop
        _ = incrementGeneration(for: note)
        sampler.stopNote(note, onChannel: 0)
    }

    /// Stop a note after a delay (for natural decay on successful long tile completion)
    func stopNoteAfterDelay(_ note: UInt8, delay: TimeInterval) {
        // Capture current generation for the delayed stop
        let generation = noteGenerations[note] ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            // Only stop if the generation hasn't changed
            guard let self = self, self.noteGenerations[note] == generation else { return }
            self.sampler.stopNote(note, onChannel: 0)
        }
    }

    // MARK: - Chord Methods (multiple notes)

    /// Play multiple sustained notes (chord for long tiles) - must call stopNotes() to end
    func playSustainedNotes(_ notes: [UInt8], velocity: UInt8 = 127) {
        for note in notes {
            playSustainedNote(note, velocity: velocity)
        }
    }

    /// Play multiple short notes (chord for normal tiles)
    func playShortNotes(_ notes: [UInt8], velocity: UInt8 = 100, duration: TimeInterval = 0.5) {
        for note in notes {
            playShortNote(note, velocity: velocity, duration: duration)
        }
    }

    /// Stop multiple notes immediately
    func stopNotes(_ notes: [UInt8]) {
        for note in notes {
            stopNote(note)
        }
    }

    /// Stop multiple notes after a delay (for natural decay)
    func stopNotesAfterDelay(_ notes: [UInt8], delay: TimeInterval) {
        for note in notes {
            stopNoteAfterDelay(note, delay: delay)
        }
    }

    func stopAllNotes() {
        // Clear all generations to cancel any pending delayed stops
        noteGenerations.removeAll()
        for note: UInt8 in 0...127 {
            sampler.stopNote(note, onChannel: 0)
        }
    }
}
