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
    private var noteGenerations: [NoteKey: Int] = [:]

    // Key for tracking note generations (note + instrument combination)
    private struct NoteKey: Hashable {
        let note: UInt8
        let instrument: UInt8
    }

    // Multi-instrument support
    private var extraSamplers: [UInt8: AVAudioUnitSampler] = [:]
    private var soundFontURL: URL?

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

    func preloadInstruments(_ instruments: Set<UInt8>) {
        guard let url = soundFontURL else {
            print("AudioManager: ERROR - No soundfont URL, cannot preload instruments")
            return
        }

        let requestedInstruments = instruments.sorted()
        print("AudioManager: Preloading instruments: \(requestedInstruments)")

        // Stop engine to add new samplers
        engine.stop()

        // Load NEW extra instruments
        for instrument in instruments where instrument != 0 {
            if extraSamplers[instrument] == nil {
                let newSampler = AVAudioUnitSampler()
                engine.attach(newSampler)
                engine.connect(newSampler, to: engine.mainMixerNode, format: nil)
                extraSamplers[instrument] = newSampler
            }
        }

        // CRITICAL: Reload ALL soundfonts after engine stop (engine stop corrupts sampler state)
        var loadedInstruments: [UInt8] = []
        var failedInstruments: [UInt8] = []

        // Reload piano
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
            loadedInstruments.append(0)
        } catch {
            print("AudioManager: FAILED to load piano (instrument 0): \(error)")
            failedInstruments.append(0)
        }

        // Reload all extra instruments
        for (instrument, extraSampler) in extraSamplers {
            do {
                try extraSampler.loadSoundBankInstrument(
                    at: url,
                    program: instrument,
                    bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                    bankLSB: 0
                )
                loadedInstruments.append(instrument)
            } catch {
                print("AudioManager: FAILED to load instrument \(instrument): \(error)")
                failedInstruments.append(instrument)
            }
        }

        // Restart engine
        do { try engine.start() } catch {
            print("AudioManager: FAILED to restart engine: \(error)")
        }

        // Summary
        print("AudioManager: Loaded \(loadedInstruments.count) instruments: \(loadedInstruments.sorted())")
        if !failedInstruments.isEmpty {
            print("AudioManager: WARNING - \(failedInstruments.count) instruments failed: \(failedInstruments.sorted())")
        }
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

        soundFontURL = url  // Save for later use
        print("AudioManager: Loading soundfont from \(url.lastPathComponent)")

        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0,
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

    private func incrementGeneration(for note: UInt8, instrument: UInt8) -> Int {
        let key = NoteKey(note: note, instrument: instrument)
        let newGeneration = (noteGenerations[key] ?? 0) + 1
        noteGenerations[key] = newGeneration
        return newGeneration
    }

    private func getGeneration(for note: UInt8, instrument: UInt8) -> Int {
        let key = NoteKey(note: note, instrument: instrument)
        return noteGenerations[key] ?? 0
    }

    /// Get the sampler for an instrument (falls back to piano)
    private func getSampler(for instrument: UInt8) -> AVAudioUnitSampler {
        if instrument == 0 {
            return sampler
        }
        if let extraSampler = extraSamplers[instrument] {
            return extraSampler
        }
        print("AudioManager: WARNING - Instrument \(instrument) not loaded, falling back to piano")
        return sampler
    }

    func playSustainedNote(_ note: UInt8, velocity: UInt8 = 127, instrument: UInt8 = 0) {
        _ = incrementGeneration(for: note, instrument: instrument)
        getSampler(for: instrument).startNote(note, withVelocity: velocity, onChannel: 0)
    }

    func playShortNote(_ note: UInt8, velocity: UInt8 = 100, duration: TimeInterval = 0.5, instrument: UInt8 = 0) {
        let generation = incrementGeneration(for: note, instrument: instrument)
        let targetSampler = getSampler(for: instrument)
        targetSampler.startNote(note, withVelocity: velocity, onChannel: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self.getGeneration(for: note, instrument: instrument) == generation else { return }
            targetSampler.stopNote(note, onChannel: 0)
        }
    }

    func stopNote(_ note: UInt8) {
        // Invalidate generations for this note on all instruments
        _ = incrementGeneration(for: note, instrument: 0)
        for instrument in extraSamplers.keys {
            _ = incrementGeneration(for: note, instrument: instrument)
        }
        // Stop on all samplers
        sampler.stopNote(note, onChannel: 0)
        for (_, extraSampler) in extraSamplers {
            extraSampler.stopNote(note, onChannel: 0)
        }
    }

    func stopNoteAfterDelay(_ note: UInt8, delay: TimeInterval) {
        // Capture current generations for all instruments
        let pianoGen = getGeneration(for: note, instrument: 0)
        var extraGens: [UInt8: Int] = [:]
        for instrument in extraSamplers.keys {
            extraGens[instrument] = getGeneration(for: note, instrument: instrument)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            // Only stop if generations haven't changed (note wasn't replayed)
            if self.getGeneration(for: note, instrument: 0) == pianoGen {
                self.sampler.stopNote(note, onChannel: 0)
            }
            for (instrument, extraSampler) in self.extraSamplers {
                if self.getGeneration(for: note, instrument: instrument) == extraGens[instrument] {
                    extraSampler.stopNote(note, onChannel: 0)
                }
            }
        }
    }

    func playSustainedNotes(_ notes: [UInt8], velocity: UInt8 = 127, instruments: [UInt8] = [0]) {
        for (index, note) in notes.enumerated() {
            let instrument = index < instruments.count ? instruments[index] : (instruments.last ?? 0)
            playSustainedNote(note, velocity: velocity, instrument: instrument)
        }
    }

    func playShortNotes(_ notes: [UInt8], velocity: UInt8 = 100, durations: [TimeInterval] = [0.5], instruments: [UInt8] = [0]) {
        for (index, note) in notes.enumerated() {
            let instrument = index < instruments.count ? instruments[index] : (instruments.last ?? 0)
            let duration = index < durations.count ? durations[index] : (durations.last ?? 0.5)
            playShortNote(note, velocity: velocity, duration: duration, instrument: instrument)
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
        noteGenerations.removeAll()
        for note: UInt8 in 0...127 {
            sampler.stopNote(note, onChannel: 0)
            for (_, extraSampler) in extraSamplers {
                extraSampler.stopNote(note, onChannel: 0)
            }
        }
    }
}
