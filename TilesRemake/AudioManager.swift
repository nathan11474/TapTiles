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
    private var noteGenerations: [UInt8: Int] = [:]

    // Sustain pedal state (CC64)
    private var sustainPedalOn: Bool = false

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
            try session.setPreferredIOBufferDuration(0.005)
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
        guard let url = Bundle.main.url(forResource: "FluidR3_GM", withExtension: "sf2") else {
            print("AudioManager: Could not find FluidR3_GM.sf2 in bundle")
            return
        }

        print("AudioManager: Loading soundfont from \(url.lastPathComponent)")

        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0,  // Piano
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
            print("AudioManager: Soundfont loaded successfully (Piano only)")
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

    private func incrementGeneration(for note: UInt8) -> Int {
        let newGeneration = (noteGenerations[note] ?? 0) + 1
        noteGenerations[note] = newGeneration
        return newGeneration
    }

    private func getGeneration(for note: UInt8) -> Int {
        return noteGenerations[note] ?? 0
    }

    // MARK: - Sustain Pedal Control

    /// Set sustain pedal state (sends CC64 to sampler)
    /// Value >= 64 = ON, < 64 = OFF
    func setSustainPedal(on: Bool) {
        guard on != sustainPedalOn else { return }  // No change needed
        sustainPedalOn = on

        let value: UInt8 = on ? 127 : 0
        sampler.sendController(64, withValue: value, onChannel: 0)
    }

    /// Prepare sustain pedal for a note - clears sustain if the note should have pedal off
    /// This ensures held notes are released before playing notes without sustain
    func prepareSustainPedal(for sustainOn: Bool) {
        if sustainOn {
            // Turn pedal on if needed
            setSustainPedal(on: true)
        } else {
            // Always send pedal-off when note requires no sustain
            // This ensures any ringing notes are released, even if we think pedal is already off
            sustainPedalOn = false
            sampler.sendController(64, withValue: 0, onChannel: 0)
        }
    }

    /// Get current sustain pedal state
    var isSustainPedalOn: Bool {
        return sustainPedalOn
    }

    // MARK: - Note Playback

    func playSustainedNote(_ note: UInt8, velocity: UInt8 = 127) {
        _ = incrementGeneration(for: note)
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)
    }

    func playShortNote(_ note: UInt8, velocity: UInt8 = 100, duration: TimeInterval = 0.5) {
        let generation = incrementGeneration(for: note)
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self.getGeneration(for: note) == generation else { return }
            self.sampler.stopNote(note, onChannel: 0)
        }
    }

    func stopNote(_ note: UInt8) {
        _ = incrementGeneration(for: note)
        sampler.stopNote(note, onChannel: 0)
    }

    func stopNoteAfterDelay(_ note: UInt8, delay: TimeInterval) {
        let generation = getGeneration(for: note)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if self.getGeneration(for: note) == generation {
                self.sampler.stopNote(note, onChannel: 0)
            }
        }
    }

    func playSustainedNotes(_ notes: [UInt8], velocity: UInt8 = 127) {
        for note in notes {
            playSustainedNote(note, velocity: velocity)
        }
    }

    func playShortNotes(_ notes: [UInt8], velocity: UInt8 = 100, durations: [TimeInterval] = [0.5]) {
        for (index, note) in notes.enumerated() {
            let duration = index < durations.count ? durations[index] : (durations.last ?? 0.5)
            playShortNote(note, velocity: velocity, duration: duration)
        }
    }

    func stopNotes(_ notes: [UInt8]) {
        for note in notes {
            stopNote(note)
        }
    }

    func stopNotesAfterDelay(_ notes: [UInt8], delay: TimeInterval) {
        for note in notes {
            stopNoteAfterDelay(note, delay: delay)
        }
    }

    func stopAllNotes() {
        // Reset sustain pedal
        setSustainPedal(on: false)

        noteGenerations.removeAll()
        for note: UInt8 in 0...127 {
            sampler.stopNote(note, onChannel: 0)
        }
    }
}
