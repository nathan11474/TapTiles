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
    private var noteGenerations: [UInt8: Int] = [:]

    // Sustain pedal state (CC64)
    private var sustainPedalOn: Bool = false

    // Async setup state
    private var isSetup: Bool = false
    private var isSettingUp: Bool = false
    private var setupCompletionHandlers: [() -> Void] = []
    private let stateQueue = DispatchQueue(label: "com.tilesremake.audiomanager.state")

    /// Whether audio is ready to use
    var isReady: Bool {
        return stateQueue.sync { isSetup }
    }

    private init() {
        engine = AVAudioEngine()
        sampler = AVAudioUnitSampler()
    }

    /// Synchronous setup - blocks until complete (waits if async setup is in progress)
    func setup() {
        // If already set up, return immediately
        if stateQueue.sync(execute: { isSetup }) {
            return
        }

        // Use a semaphore to wait for completion
        let semaphore = DispatchSemaphore(value: 0)
        setupInternal(dispatchToMain: false) { semaphore.signal() }
        semaphore.wait()
    }

    /// Async setup - returns immediately, calls completion on main thread when done
    func setupAsync(completion: (() -> Void)? = nil) {
        // Check if already set up
        let alreadySetup = stateQueue.sync { isSetup }
        if alreadySetup {
            if let completion = completion {
                DispatchQueue.main.async { completion() }
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            self.setupInternal(dispatchToMain: true, completion: completion)
        }
    }

    /// Internal setup that handles both sync and async cases
    /// - Parameters:
    ///   - dispatchToMain: If true, completion handlers are called on main thread
    ///   - completion: Optional completion handler
    private func setupInternal(dispatchToMain: Bool, completion: (() -> Void)?) {
        // Thread-safe state check and update
        let shouldPerformSetup = stateQueue.sync { () -> Bool in
            if isSetup {
                // Already set up - just call completion
                if let completion = completion {
                    if dispatchToMain {
                        DispatchQueue.main.async { completion() }
                    } else {
                        completion()
                    }
                }
                return false
            }

            if isSettingUp {
                // Setup in progress - queue completion handler with dispatch preference
                if let completion = completion {
                    let wrappedCompletion: () -> Void = dispatchToMain
                        ? { DispatchQueue.main.async { completion() } }
                        : completion
                    setupCompletionHandlers.append(wrappedCompletion)
                }
                return false
            }

            // Start setup
            isSettingUp = true
            if let completion = completion {
                let wrappedCompletion: () -> Void = dispatchToMain
                    ? { DispatchQueue.main.async { completion() } }
                    : completion
                setupCompletionHandlers.append(wrappedCompletion)
            }
            return true
        }

        guard shouldPerformSetup else { return }

        // Perform actual setup (outside the lock)
        configureAudioSession()
        setupAudioEngine()
        loadSoundFont()
        startEngine()

        // Mark complete and notify all waiting handlers
        let handlers = stateQueue.sync { () -> [() -> Void] in
            isSetup = true
            isSettingUp = false
            let handlers = setupCompletionHandlers
            setupCompletionHandlers.removeAll()
            return handlers
        }

        // Call all completion handlers (dispatch is already baked into each handler)
        for handler in handlers {
            handler()
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
            #if DEBUG
            print("AudioManager: Failed to configure audio session: \(error)")
            #endif
        }
    }

    private func setupAudioEngine() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }

    private func loadSoundFont() {
        guard let url = Bundle.main.url(forResource: "FluidR3_GM", withExtension: "sf2") else {
            #if DEBUG
            print("AudioManager: Could not find FluidR3_GM.sf2 in bundle")
            #endif
            return
        }

        #if DEBUG
        print("AudioManager: Loading soundfont from \(url.lastPathComponent)")
        #endif

        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0,  // Piano
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
            #if DEBUG
            print("AudioManager: Soundfont loaded successfully (Piano only)")
            #endif
        } catch {
            #if DEBUG
            print("AudioManager: Failed to load soundfont: \(error)")
            #endif
        }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }

        do {
            try engine.start()
        } catch {
            #if DEBUG
            print("AudioManager: Failed to start audio engine: \(error)")
            #endif
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
