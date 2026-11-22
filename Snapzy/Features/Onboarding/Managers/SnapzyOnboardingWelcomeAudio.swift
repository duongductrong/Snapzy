//
//  SnapzyOnboardingWelcomeAudio.swift
//  Snapzy
//
//  Original procedural stereo soundscape & micro-foley for the Welcome screen.
//  Synthesizes a warm analog-synth aurora pad with algorithmic stereo reverb (synced to the
//  orb → flood → mark → headline choreography) plus tactile glass hover/confirm cues.
//  Gated by `PreferencesKeys.playSounds` and rendered off the main actor.
//

import AVFoundation
import Foundation

@MainActor
final class SnapzyOnboardingWelcomeAudio {
  static let shared = SnapzyOnboardingWelcomeAudio()

  private enum CueKey: Hashable, Sendable {
    case hoverTick
    case confirmChime
    case completionChime
    case stepForward
    case stepBackward
    case stepComplete
    case buttonTap
    case challengeTick
    case shutterSnap
  }

  private var ambientPlayer: AVAudioPlayer?
  private var fadingPlayers: [ObjectIdentifier: (player: AVAudioPlayer, task: Task<Void, Never>)] = [:]
  /// One-shot cues start off the main thread: creating and starting an `AVAudioPlayer` costs
  /// several milliseconds, and cues fire on the same frame a step transition begins.
  private let effectVoices = OnboardingEffectVoicePool()
  private var synthesisTask: Task<Void, Never>?
  private var prewarmTask: Task<Void, Never>?

  private var cachedFullScoreWAV: Data?
  private var cachedReducedScoreWAV: Data?
  private var cachedCueWAVs: [CueKey: Data] = [:]

  private init() {}

  nonisolated deinit {}

  private var soundsEnabled: Bool {
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
      return false
    }
    return UserDefaults.standard.object(forKey: PreferencesKeys.playSounds) as? Bool ?? true
  }

  // MARK: - Public API

  /// Starts the welcome soundscape synced to the visual timeline.
  func playWelcomeScore(reducedMotion: Bool) {
    guard soundsEnabled else { return }
    stopAmbient(fadeDuration: 0.35)
    synthesisTask?.cancel()

    if reducedMotion, let data = cachedReducedScoreWAV {
      startAmbientPlayer(with: data, volume: 0.62)
      return
    }
    if !reducedMotion, let data = cachedFullScoreWAV {
      startAmbientPlayer(with: data, volume: 0.68)
      return
    }

    synthesisTask = Task { [weak self] in
      let wavData = await Task.detached(priority: .userInitiated) {
        reducedMotion
          ? WelcomeAudioSynthesizer.renderReducedWelcomeScoreWAV()
          : WelcomeAudioSynthesizer.renderFullWelcomeScoreWAV()
      }.value

      guard !Task.isCancelled, let self, self.soundsEnabled else { return }
      if reducedMotion {
        self.cachedReducedScoreWAV = wavData
        self.startAmbientPlayer(with: wavData, volume: 0.62)
      } else {
        self.cachedFullScoreWAV = wavData
        self.startAmbientPlayer(with: wavData, volume: 0.68)
      }
      self.prewarmInteractionEffects()
    }
  }

  /// Pre-renders all tiny interactive onboarding WAV buffers off-main (pure Swift DSP only).
  /// Playback of these cues happens on `OnboardingEffectVoicePool`'s queue, which releases its
  /// players after a quiet period so no idle AudioQueues remain open after onboarding closes.
  func prewarmInteractionEffects() {
    guard soundsEnabled else { return }
    guard prewarmTask == nil, cachedCueWAVs.count < 9 else { return }

    prewarmTask = Task { [weak self] in
      let built = await Task.detached(priority: .utility) { () -> [(CueKey, Data)] in
        [
          (.hoverTick, WelcomeAudioSynthesizer.renderHoverTickWAV()),
          (.confirmChime, WelcomeAudioSynthesizer.renderConfirmChimeWAV()),
          (.completionChime, WelcomeAudioSynthesizer.renderCompletionChimeWAV()),
          (.stepForward, WelcomeAudioSynthesizer.renderStepForwardWAV()),
          (.stepBackward, WelcomeAudioSynthesizer.renderStepBackwardWAV()),
          (.stepComplete, WelcomeAudioSynthesizer.renderStepCompleteWAV()),
          (.buttonTap, WelcomeAudioSynthesizer.renderButtonTapWAV()),
          (.challengeTick, WelcomeAudioSynthesizer.renderChallengeTickWAV()),
          (.shutterSnap, WelcomeAudioSynthesizer.renderShutterSnapWAV()),
        ]
      }.value

      guard let self else { return }
      for (key, wav) in built {
        if self.cachedCueWAVs[key] == nil {
          self.cachedCueWAVs[key] = wav
        }
      }
      self.prewarmTask = nil
    }
  }

  /// Soft optical-glass micro-tick when hovering the hero arrow button.
  func playHoverTick() {
    playCue(.hoverTick, volume: 0.22) {
      WelcomeAudioSynthesizer.renderHoverTickWAV()
    }
  }

  /// Warm ascending crystalline confirmation bloom when clicking the arrow button to begin,
  /// accompanied by a long, velvety curved fade-out of the ambient welcome music.
  func playConfirmChime() {
    guard soundsEnabled else { return }
    stopAmbient(fadeDuration: 2.0)
    playCue(.confirmChime, volume: 0.56) {
      WelcomeAudioSynthesizer.renderConfirmChimeWAV()
    }
  }

  /// Warm two-beat resolving chord synced to the completion finale:
  /// Beat 1 (0.0s) lifts the icon from the window; Beat 2 (0.88s) chimes crisply on menu bar dock.
  func playCompletionChime() {
    guard soundsEnabled else { return }
    stopAmbient(fadeDuration: 0.6)
    playCue(.completionChime, volume: 0.58) {
      WelcomeAudioSynthesizer.renderCompletionChimeWAV()
    }
  }

  /// Buoyant ascending two-note glass interval when advancing to the next step (Continue / Skip / Step Rail).
  func playStepForward() {
    playCue(.stepForward, volume: 0.36) {
      WelcomeAudioSynthesizer.renderStepForwardWAV()
    }
  }

  /// Soft descending two-note glass interval when stepping backward (Esc / Step Rail / Review).
  func playStepBackward() {
    playCue(.stepBackward, volume: 0.30) {
      WelcomeAudioSynthesizer.renderStepBackwardWAV()
    }
  }

  /// Sunlit three-note major arrival chord when finishing Step 4 into the "You're All Set!" card.
  func playStepComplete() {
    playCue(.stepComplete, volume: 0.40) {
      WelcomeAudioSynthesizer.renderStepCompleteWAV()
    }
  }

  /// Crisp optical-glass micro-detent for secondary onboarding buttons, menus, and tools.
  func playButtonTap() {
    playCue(.buttonTap, volume: 0.24) {
      WelcomeAudioSynthesizer.renderButtonTapWAV()
    }
  }

  /// Warm marimba-glass confirmation pip when an interactive checklist challenge completes.
  func playChallengeComplete() {
    playCue(.challengeTick, volume: 0.30) {
      WelcomeAudioSynthesizer.renderChallengeTickWAV()
    }
  }

  /// Damped tactile camera shutter micro-click for interactive capture/record simulations.
  func playShutterSnap() {
    playCue(.shutterSnap, volume: 0.30) {
      WelcomeAudioSynthesizer.renderShutterSnapWAV()
    }
  }

  private func playCue(
    _ key: CueKey,
    volume: Float,
    render: @escaping @Sendable () -> Data
  ) {
    guard soundsEnabled else { return }

    if let data = cachedCueWAVs[key] {
      effectVoices.play(key: key, data: data, volume: volume)
      return
    }

    Task { [weak self] in
      let wav = await Task.detached(priority: .userInitiated) {
        render()
      }.value
      guard let self, self.soundsEnabled else { return }
      self.cachedCueWAVs[key] = wav
      self.effectVoices.play(key: key, data: wav, volume: volume)
    }
  }

  /// Smoothly fades out any active welcome score using a perceptual exponential curve (never hard-cuts).
  /// Safe to call again from `onDisappear` — an already-detached player continues its smooth fade untouched.
  func stopAmbient(fadeDuration: TimeInterval = 1.25) {
    synthesisTask?.cancel()
    synthesisTask = nil

    guard let player = ambientPlayer else { return }
    ambientPlayer = nil

    if fadeDuration <= 0.02 || !player.isPlaying {
      player.stop()
      return
    }

    let id = ObjectIdentifier(player)
    let startVolume = player.volume
    let steps = max(24, Int(fadeDuration * 60.0))
    let stepDurationNs = UInt64((fadeDuration / Double(steps)) * 1_000_000_000)

    let fadeTask = Task { @MainActor [weak self] in
      for step in 1...steps {
        try? await Task.sleep(nanoseconds: stepDurationNs)
        guard !Task.isCancelled, player.isPlaying else { break }
        let progress = Double(step) / Double(steps)
        // Perceptual equal-power / exponential decay feels silky and natural to human hearing
        let remaining = pow(max(0.0, 1.0 - progress), 2.3)
        player.volume = startVolume * Float(remaining)
      }
      player.volume = 0
      player.stop()
      self?.fadingPlayers.removeValue(forKey: id)
    }

    fadingPlayers[id] = (player: player, task: fadeTask)
  }

  // MARK: - Playback Helpers

  private func startAmbientPlayer(with data: Data, volume: Float) {
    do {
      let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
      player.volume = volume
      player.prepareToPlay()
      player.play()
      ambientPlayer = player
    } catch {
      DiagnosticLogger.shared.log(
        .debug,
        .ui,
        "Welcome ambient audio failed to initialize: \(error.localizedDescription)"
      )
    }
  }
}

// MARK: - Effect Voice Pool

/// Plays short cues on a private serial queue, reusing an idle prepared player per cue so a repeat
/// play only rewinds it. Every player is touched only on `queue`, which is why the type opts out
/// of the target's default main-actor isolation. Players are dropped after a short quiet period,
/// so no idle AudioQueue outlives the onboarding session.
private nonisolated final class OnboardingEffectVoicePool: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.snapzy.onboarding.effect-audio", qos: .userInteractive)
  private var voices: [AnyHashable: [AVAudioPlayer]] = [:]
  private var releaseWork: DispatchWorkItem?
  /// Caps how many players one cue may hold, so rapid repeats overlap a little but never pile up.
  private let maxVoicesPerCue = 3
  private let idleRelease: TimeInterval = 10

  func play(key: AnyHashable, data: Data, volume: Float) {
    queue.async { [self] in
      var pool = voices[key] ?? []
      let player: AVAudioPlayer
      if let idle = pool.first(where: { !$0.isPlaying }) {
        player = idle
      } else if pool.count >= maxVoicesPerCue {
        // Every voice is busy: restart the one that began longest ago rather than adding more.
        player = pool.removeFirst()
        pool.append(player)
        voices[key] = pool
      } else {
        do {
          let created = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
          created.prepareToPlay()
          player = created
          pool.append(created)
          voices[key] = pool
        } catch {
          let message = error.localizedDescription
          DispatchQueue.main.async {
            DiagnosticLogger.shared.log(.debug, .ui, "Welcome effect audio failed to initialize: \(message)")
          }
          return
        }
      }
      player.currentTime = 0
      player.volume = volume
      player.play()
      scheduleRelease()
    }
  }

  private func scheduleRelease() {
    releaseWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.voices = self.voices.compactMapValues { pool in
        let playing = pool.filter(\.isPlaying)
        return playing.isEmpty ? nil : playing
      }
      if !self.voices.isEmpty { self.scheduleRelease() }
    }
    releaseWork = work
    queue.asyncAfter(deadline: .now() + idleRelease, execute: work)
  }
}

// MARK: - Pure-Swift Procedural Synthesizer (44.1 kHz Stereo PCM)

private nonisolated enum WelcomeAudioSynthesizer {
  private static let sampleRate: Double = 44_100

  private nonisolated struct PadChord {
    let start: Double
    let duration: Double
    let attack: Double
    let release: Double
    let gain: Double
    let brightness: Double // 0...1 harmonic warmth
    let notes: [Double]    // Hz
  }

  private nonisolated struct GlassBell {
    let start: Double
    let duration: Double
    let frequency: Double
    let gain: Double
    let pan: Double // -1...1
  }

  // MARK: - Full Welcome Score (~18.0s with long silky 5.0s tail fade-out)

  /// Timeline alignment:
  /// - 0.00s – 1.45s: Dreamy open Gsus2 orb shimmer awakening in the dark void
  /// - 1.45s – 4.60s: Rich Gmaj9 warm bass + aurora bloom flooding edge-to-edge
  /// - 2.30s:         Soft glass resonance as the white Snapzy mark pulls into focus
  /// - 4.25s – 7.40s: Hopeful Cmaj9 emotional lift as "Meet Snapzy." pulls into focus
  /// - 4.72s:         Delicate high crystalline spark for the trailing "."
  /// - 6.80s – 10.6s: Lush Em9 floating calm while user reads & hovers
  /// - 9.80s – 14.8s: Warm resolving Gmaj9 horizon breathing out
  /// - 13.0s – 18.0s: Velvety 5.0-second cosine/exponential tail melting seamlessly into silence
  static func renderFullWelcomeScoreWAV() -> Data {
    let totalDuration = 18.0
    let frameCount = Int(totalDuration * sampleRate)
    var left = [Double](repeating: 0, count: frameCount)
    var right = [Double](repeating: 0, count: frameCount)

    let chords: [PadChord] = [
      // Beat 1 (0.0s): Weightless Gsus2 orb pad emerging from silence
      PadChord(
        start: 0.04, duration: 2.30, attack: 1.15, release: 1.15,
        gain: 0.24, brightness: 0.34,
        notes: [196.00, 293.66, 440.00, 587.33]
      ),
      // Beat 2 (1.42s): Aurora flood bloom — lush Gmaj9 with warm G2 foundation
      PadChord(
        start: 1.42, duration: 3.15, attack: 0.85, release: 1.45,
        gain: 0.42, brightness: 0.72,
        notes: [98.00, 196.00, 246.94, 293.66, 369.99, 440.00, 587.33]
      ),
      // Beat 4 (4.25s): Headline emotional lift — luminous Cmaj9
      PadChord(
        start: 4.25, duration: 3.20, attack: 0.65, release: 1.75,
        gain: 0.40, brightness: 0.78,
        notes: [130.81, 196.00, 246.94, 293.66, 329.63, 392.00, 587.33]
      ),
      // Beat 6 (6.80s): Calm interactive Em9 drift while resting on the welcome screen
      PadChord(
        start: 6.80, duration: 3.40, attack: 0.95, release: 2.20,
        gain: 0.31, brightness: 0.50,
        notes: [82.41, 164.81, 246.94, 293.66, 392.00, 493.88]
      ),
      // Beat 7 (9.80s): Serene resolving Gmaj9 floating gently into a long natural decay
      PadChord(
        start: 9.80, duration: 2.40, attack: 1.10, release: 3.60,
        gain: 0.25, brightness: 0.36,
        notes: [98.00, 196.00, 293.66, 369.99, 440.00, 587.33]
      ),
    ]

    for chord in chords {
      addAnalogPadChord(chord, left: &left, right: &right)
    }

    // Subtle air-breath swell cresting right as the orb blooms into the full window (1.45s)
    addAirBloomSwell(start: 0.65, peak: 1.65, end: 2.75, gain: 0.042, left: &left, right: &right)

    // Delicate crystalline glass accents locked to key visual reveals + serene ambient echo
    let bells: [GlassBell] = [
      // White Snapzy mark pulls into focus (~2.30s)
      GlassBell(start: 2.28, duration: 2.20, frequency: 587.33, gain: 0.075, pan: -0.22), // D5
      GlassBell(start: 2.38, duration: 2.10, frequency: 880.00, gain: 0.048, pan: 0.25),  // A5
      // "Meet Snapzy." trailing period spark (~4.72s)
      GlassBell(start: 4.70, duration: 1.90, frequency: 783.99, gain: 0.068, pan: 0.18),  // G5
      GlassBell(start: 4.76, duration: 1.70, frequency: 1174.66, gain: 0.036, pan: -0.20), // D6
      // Subtle airy shimmer as arrow pill arrives (~5.22s)
      GlassBell(start: 5.20, duration: 1.80, frequency: 659.25, gain: 0.045, pan: 0.0),   // E5
      // Gentle distant harmonic whisper on the final resolving horizon (~10.4s)
      GlassBell(start: 10.40, duration: 2.60, frequency: 587.33, gain: 0.032, pan: -0.15), // D5
      GlassBell(start: 10.75, duration: 2.50, frequency: 783.99, gain: 0.024, pan: 0.18),  // G5
    ]

    for bell in bells {
      addGlassBell(bell, left: &left, right: &right)
    }

    applyWarmLowPassSweep(left: &left, right: &right, isFullScore: true)
    applyStereoReverb(left: &left, right: &right, wetMix: 0.34, feedback: 0.56)
    applyMasterPolish(left: &left, right: &right, targetPeak: 0.78, tailFadeSeconds: 4.6)

    return encodeStereoWAV(left: left, right: right)
  }

  // MARK: - Reduced Motion Welcome Score (~6.8s calm arrival chord with 3.0s fade-out)

  static func renderReducedWelcomeScoreWAV() -> Data {
    let totalDuration = 6.8
    let frameCount = Int(totalDuration * sampleRate)
    var left = [Double](repeating: 0, count: frameCount)
    var right = [Double](repeating: 0, count: frameCount)

    addAnalogPadChord(
      PadChord(
        start: 0.02, duration: 2.40, attack: 0.45, release: 3.20,
        gain: 0.36, brightness: 0.60,
        notes: [130.81, 196.00, 246.94, 293.66, 392.00, 587.33]
      ),
      left: &left,
      right: &right
    )
    addGlassBell(
      GlassBell(start: 0.12, duration: 2.10, frequency: 783.99, gain: 0.058, pan: 0.0),
      left: &left,
      right: &right
    )

    applyWarmLowPassSweep(left: &left, right: &right, isFullScore: false)
    applyStereoReverb(left: &left, right: &right, wetMix: 0.30, feedback: 0.50)
    applyMasterPolish(left: &left, right: &right, targetPeak: 0.72, tailFadeSeconds: 2.8)

    return encodeStereoWAV(left: left, right: right)
  }

  // MARK: - Tactile Hover Tick (~70ms cool glass micro-tick)

  static func renderHoverTickWAV() -> Data {
    let totalDuration = 0.085
    let frameCount = Int(totalDuration * sampleRate)
    var left = [Double](repeating: 0, count: frameCount)
    var right = [Double](repeating: 0, count: frameCount)

    let twoPi = 2.0 * Double.pi
    for i in 0..<frameCount {
      let t = Double(i) / sampleRate
      let attack = min(1.0, t / 0.0025)
      let decay = exp(-t * 58.0)
      let env = attack * decay

      // Subtle warm glass harmonic pair (no harsh click)
      let s1 = sin(twoPi * 987.77 * t) * 0.62  // B5
      let s2 = sin(twoPi * 1479.98 * t) * 0.28 // F#6
      let body = sin(twoPi * 392.00 * t) * exp(-t * 85.0) * 0.22
      let sample = (s1 + s2 + body) * env

      left[i] = sample * 0.96
      right[i] = sample * 1.00
    }

    applyMasterPolish(left: &left, right: &right, targetPeak: 0.65)
    return encodeStereoWAV(left: left, right: right)
  }

  // MARK: - Confirm Click Bloom (~1.25s warm ascending glass chord)

  static func renderConfirmChimeWAV() -> Data {
    let totalDuration = 1.35
    let frameCount = Int(totalDuration * sampleRate)
    var left = [Double](repeating: 0, count: frameCount)
    var right = [Double](repeating: 0, count: frameCount)

    let notes: [GlassBell] = [
      GlassBell(start: 0.00, duration: 0.85, frequency: 392.00, gain: 0.20, pan: -0.15), // G4 warm root
      GlassBell(start: 0.00, duration: 0.90, frequency: 587.33, gain: 0.26, pan: -0.18), // D5
      GlassBell(start: 0.042, duration: 1.05, frequency: 783.99, gain: 0.28, pan: 0.18), // G5
      GlassBell(start: 0.075, duration: 1.00, frequency: 987.77, gain: 0.14, pan: 0.26), // B5 airy sparkle
    ]

    for bell in notes {
      addGlassBell(bell, left: &left, right: &right)
    }

    applyStereoReverb(left: &left, right: &right, wetMix: 0.28, feedback: 0.44)
    applyMasterPolish(left: &left, right: &right, targetPeak: 0.78)
    return encodeStereoWAV(left: left, right: right)
  }

  // MARK: - Completion Ascent & Menu Bar Dock Chime (~2.45s synced two-beat sign-off)

  static func renderCompletionChimeWAV() -> Data {
    let totalDuration = 2.45
    let frameCount = Int(totalDuration * sampleRate)
    var left = [Double](repeating: 0, count: frameCount)
    var right = [Double](repeating: 0, count: frameCount)

    // Beat 1 (0.00s): Warm analog Cmaj9 lift as the completion cards release and the icon ascends
    addAnalogPadChord(
      PadChord(
        start: 0.00, duration: 0.92, attack: 0.14, release: 1.05,
        gain: 0.26, brightness: 0.58,
        notes: [261.63, 329.63, 392.00, 493.88, 587.33] // C4 E4 G4 B4 D5
      ),
      left: &left,
      right: &right
    )

    let launchNotes: [GlassBell] = [
      GlassBell(start: 0.00, duration: 0.75, frequency: 523.25, gain: 0.16, pan: -0.14), // C5
      GlassBell(start: 0.05, duration: 0.80, frequency: 659.25, gain: 0.18, pan: 0.10),  // E5
    ]
    for bell in launchNotes {
      addGlassBell(bell, left: &left, right: &right)
    }

    // Subtle silky air breath during ascent
    addAirBloomSwell(start: 0.18, peak: 0.56, end: 0.92, gain: 0.022, left: &left, right: &right)

    // Beat 2 (0.90s): Crystalline resolving glass dock harmonic right as the icon lands in the menu bar
    let dockNotes: [GlassBell] = [
      GlassBell(start: 0.90, duration: 1.35, frequency: 783.99, gain: 0.26, pan: -0.12), // G5
      GlassBell(start: 0.94, duration: 1.35, frequency: 1174.66, gain: 0.19, pan: 0.18), // D6
      GlassBell(start: 0.98, duration: 1.25, frequency: 1567.98, gain: 0.08, pan: 0.24), // G6 airy shimmer
    ]
    for bell in dockNotes {
      addGlassBell(bell, left: &left, right: &right)
    }

    applyStereoReverb(left: &left, right: &right, wetMix: 0.32, feedback: 0.48)
    applyMasterPolish(left: &left, right: &right, targetPeak: 0.78, tailFadeSeconds: 0.55)
    return encodeStereoWAV(left: left, right: right)
  }

  // MARK: - Step Forward (~0.34s buoyant ascending D5 → G5 glass glide)

  static func renderStepForwardWAV() -> Data {
    let totalDuration = 0.36
    let frameCount = Int(totalDuration * sampleRate)
    var left = [Double](repeating: 0, count: frameCount)
    var right = [Double](repeating: 0, count: frameCount)

    addGlassBell(
      GlassBell(start: 0.00, duration: 0.24, frequency: 587.33, gain: 0.22, pan: -0.14), // D5
      left: &left, right: &right
    )
    addGlassBell(
      GlassBell(start: 0.036, duration: 0.30, frequency: 783.99, gain: 0.26, pan: 0.16), // G5
      left: &left, right: &right
    )

    applyStereoReverb(left: &left, right: &right, wetMix: 0.18, feedback: 0.34)
    applyMasterPolish(left: &left, right: &right, targetPeak: 0.72, tailFadeSeconds: 0.09)
    return encodeStereoWAV(left: left, right: right)
  }

  // MARK: - Step Backward (~0.32s gentle descending G5 → D5 glass settle)

  static func renderStepBackwardWAV() -> Data {
    let totalDuration = 0.34
    let frameCount = Int(totalDuration * sampleRate)
    var left = [Double](repeating: 0, count: frameCount)
    var right = [Double](repeating: 0, count: frameCount)

    addGlassBell(
      GlassBell(start: 0.00, duration: 0.22, frequency: 783.99, gain: 0.20, pan: 0.14),   // G5
      left: &left, right: &right
    )
    addGlassBell(
      GlassBell(start: 0.038, duration: 0.28, frequency: 587.33, gain: 0.24, pan: -0.16), // D5
      left: &left, right: &right
    )

    applyStereoReverb(left: &left, right: &right, wetMix: 0.16, feedback: 0.32)
    applyMasterPolish(left: &left, right: &right, targetPeak: 0.68, tailFadeSeconds: 0.09)
    return encodeStereoWAV(left: left, right: right)
  }

  // MARK: - Step 4 → Completion Card Arrival (~0.68s open C5-E5-G5 shimmer)

  static func renderStepCompleteWAV() -> Data {
    let totalDuration = 0.72
    let frameCount = Int(totalDuration * sampleRate)
    var left = [Double](repeating: 0, count: frameCount)
    var right = [Double](repeating: 0, count: frameCount)

    let notes: [GlassBell] = [
      GlassBell(start: 0.00, duration: 0.56, frequency: 523.25, gain: 0.20, pan: -0.18), // C5
      GlassBell(start: 0.042, duration: 0.58, frequency: 659.25, gain: 0.22, pan: 0.04),  // E5
      GlassBell(start: 0.084, duration: 0.60, frequency: 783.99, gain: 0.24, pan: 0.20),  // G5
    ]
    for bell in notes {
      addGlassBell(bell, left: &left, right: &right)
    }

    applyStereoReverb(left: &left, right: &right, wetMix: 0.24, feedback: 0.40)
    applyMasterPolish(left: &left, right: &right, targetPeak: 0.76, tailFadeSeconds: 0.18)
    return encodeStereoWAV(left: left, right: right)
  }

  // MARK: - Tactile Button Tap (~0.065s crisp damped optical-glass detent)

  static func renderButtonTapWAV() -> Data {
    let totalDuration = 0.068
    let frameCount = Int(totalDuration * sampleRate)
    var left = [Double](repeating: 0, count: frameCount)
    var right = [Double](repeating: 0, count: frameCount)

    let twoPi = 2.0 * Double.pi
    for i in 0..<frameCount {
      let t = Double(i) / sampleRate
      let attack = min(1.0, t / 0.0018)
      let decay = exp(-t * 74.0)
      let env = attack * decay

      let body = sin(twoPi * 440.0 * t) * 0.45 * exp(-t * 52.0)
      let glass = sin(twoPi * 880.0 * t) * 0.48
      let air = sin(twoPi * 1318.51 * t) * 0.16 * exp(-t * 95.0)
      let sample = (body + glass + air) * env

      left[i] = sample * 0.98
      right[i] = sample * 1.00
    }

    applyMasterPolish(left: &left, right: &right, targetPeak: 0.62, tailFadeSeconds: 0.015)
    return encodeStereoWAV(left: left, right: right)
  }

  // MARK: - Challenge Checklist Complete (~0.24s warm marimba-glass confirm pip)

  static func renderChallengeTickWAV() -> Data {
    let totalDuration = 0.26
    let frameCount = Int(totalDuration * sampleRate)
    var left = [Double](repeating: 0, count: frameCount)
    var right = [Double](repeating: 0, count: frameCount)

    addGlassBell(
      GlassBell(start: 0.00, duration: 0.18, frequency: 659.25, gain: 0.18, pan: -0.08), // E5 warm body
      left: &left, right: &right
    )
    addGlassBell(
      GlassBell(start: 0.024, duration: 0.22, frequency: 987.77, gain: 0.22, pan: 0.12), // B5 crisp tick
      left: &left, right: &right
    )

    applyStereoReverb(left: &left, right: &right, wetMix: 0.14, feedback: 0.28)
    applyMasterPolish(left: &left, right: &right, targetPeak: 0.70, tailFadeSeconds: 0.06)
    return encodeStereoWAV(left: left, right: right)
  }

  // MARK: - Simulated Capture Shutter Snap (~0.085s refined mechanical micro-shutter)

  static func renderShutterSnapWAV() -> Data {
    let totalDuration = 0.090
    let frameCount = Int(totalDuration * sampleRate)
    var left = [Double](repeating: 0, count: frameCount)
    var right = [Double](repeating: 0, count: frameCount)

    var rng: UInt64 = 0x71E9_23B5_4C0A_D81F
    var lp = 0.0
    var hp = 0.0
    let twoPi = 2.0 * Double.pi

    @inline(__always)
    func nextNoise() -> Double {
      rng &+= 0x9E37_79B9_7F4A_7C15
      var z = rng
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      z = z ^ (z >> 31)
      return (Double(z & 0xFFFF) / 32768.0) - 1.0
    }

    for i in 0..<frameCount {
      let t = Double(i) / sampleRate
      // Two crisp damped mechanical leaves separated by 22ms (like a modern mirrorless shutter)
      let blade1 = min(1.0, t / 0.0012) * exp(-t * 145.0)
      let t2 = max(0, t - 0.022)
      let blade2 = t >= 0.022 ? min(1.0, t2 / 0.0015) * exp(-t2 * 130.0) * 0.58 : 0.0
      let mechEnv = blade1 + blade2

      let raw = nextNoise()
      lp += 0.34 * (raw - lp)
      hp += 0.08 * (lp - hp)
      let crisp = (lp - hp) * mechEnv * 0.72
      let thump = sin(twoPi * 210.0 * t) * exp(-t * 110.0) * 0.26
      let sample = crisp + thump

      left[i] = sample * 0.96
      right[i] = sample * 1.00
    }

    applyMasterPolish(left: &left, right: &right, targetPeak: 0.68, tailFadeSeconds: 0.02)
    return encodeStereoWAV(left: left, right: right)
  }

  // MARK: - DSP Building Blocks

  /// Multi-voice detuned stereo warm analog pad with organic harmonic richness and gentle drift.
  private static func addAnalogPadChord(_ chord: PadChord, left: inout [Double], right: inout [Double]) {
    let startIdx = max(0, Int(chord.start * sampleRate))
    let totalSamples = Int((chord.duration + chord.release) * sampleRate)
    let endIdx = min(left.count, startIdx + totalSamples)
    guard endIdx > startIdx else { return }

    let twoPi = 2.0 * Double.pi
    let noteScale = chord.gain / max(1.0, sqrt(Double(chord.notes.count)))
    let h2Gain = 0.26 * chord.brightness
    let h3Gain = 0.11 * chord.brightness
    let h4Gain = 0.04 * chord.brightness

    // Detuned stereo triplet per note for lush analog chorus width
    let detuneFactors: [(ratio: Double, panL: Double, panR: Double)] = [
      (0.9968, 0.82, 0.28), // -5.5 cents left
      (1.0000, 0.62, 0.62), // center fundamental
      (1.0032, 0.28, 0.82), // +5.5 cents right
    ]

    for (noteIdx, freq) in chord.notes.enumerated() {
      let basePhase = Double(noteIdx) * 1.13
      let panBias = (Double(noteIdx % 3) - 1.0) * 0.14

      for (voiceIdx, voice) in detuneFactors.enumerated() {
        let f = freq * voice.ratio
        let phase0 = basePhase + Double(voiceIdx) * 2.07
        let lGain = noteScale * (voice.panL - panBias) * 0.55
        let rGain = noteScale * (voice.panR + panBias) * 0.55

        // Gentle per-voice vibrato for living analog character
        let vibRate = 0.35 + Double((noteIdx + voiceIdx) % 4) * 0.11
        let vibDepth = 0.0014

        var phase = phase0
        for i in startIdx..<endIdx {
          let localT = Double(i - startIdx) / sampleRate
          let env = smoothEnvelope(
            t: localT,
            attack: chord.attack,
            sustainEnd: chord.duration,
            release: chord.release
          )
          if env <= 0.00001 { continue }

          let instFreq = f * (1.0 + vibDepth * sin(twoPi * vibRate * localT + phase0))
          phase += twoPi * instFreq / sampleRate

          // Warm analog harmonic blend (no harsh buzz)
          var sample = sin(phase)
          if freq < 340 {
            sample += h2Gain * sin(2.0 * phase)
            sample += h3Gain * sin(3.0 * phase)
            sample += h4Gain * sin(4.0 * phase)
          } else {
            sample += (h2Gain * 0.65) * sin(2.0 * phase)
            sample += (h3Gain * 0.35) * sin(3.0 * phase)
          }

          let out = sample * env
          left[i] += out * lGain
          right[i] += out * rGain
        }
      }
    }
  }

  /// Crystalline glass bell harmonic accent with silky attack and long pure decay.
  private static func addGlassBell(_ bell: GlassBell, left: inout [Double], right: inout [Double]) {
    let startIdx = max(0, Int(bell.start * sampleRate))
    let endIdx = min(left.count, startIdx + Int(bell.duration * sampleRate))
    guard endIdx > startIdx else { return }

    let twoPi = 2.0 * Double.pi
    let panL = sqrt(0.5 * (1.0 - bell.pan))
    let panR = sqrt(0.5 * (1.0 + bell.pan))

    for i in startIdx..<endIdx {
      let t = Double(i - startIdx) / sampleRate
      let attack = min(1.0, t / 0.009)
      let env1 = exp(-t * (2.6 / max(0.3, bell.duration)))
      let env2 = exp(-t * (6.2 / max(0.3, bell.duration)))

      // Pure glass fundamental + soft octave shimmer + subtle glassy fifth overtone
      let fundamental = sin(twoPi * bell.frequency * t) * env1
      let octave = sin(twoPi * bell.frequency * 2.0 * t) * 0.24 * env2
      let sparkle = sin(twoPi * bell.frequency * 2.998 * t) * 0.07 * exp(-t * 14.0)

      let sample = (fundamental + octave + sparkle) * attack * bell.gain
      left[i] += sample * panL
      right[i] += sample * panR
    }
  }

  /// Whisper-soft filtered pink-air breath rising into the orb flood bloom.
  private static func addAirBloomSwell(
    start: Double,
    peak: Double,
    end: Double,
    gain: Double,
    left: inout [Double],
    right: inout [Double]
  ) {
    let startIdx = max(0, Int(start * sampleRate))
    let endIdx = min(left.count, Int(end * sampleRate))
    guard endIdx > startIdx else { return }

    var rng: UInt64 = 0x3C6E_F372_FE94_F82B
    var lpL = 0.0
    var lpR = 0.0
    var hpL = 0.0
    var hpR = 0.0

    @inline(__always)
    func nextNoise() -> Double {
      rng &+= 0x9E37_79B9_7F4A_7C15
      var z = rng
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      z = z ^ (z >> 31)
      return (Double(z & 0xFFFF) / 32768.0) - 1.0
    }

    for i in startIdx..<endIdx {
      let t = Double(i) / sampleRate
      let env: Double
      if t < peak {
        let u = (t - start) / max(0.01, peak - start)
        env = u * u * (3.0 - 2.0 * u)
      } else {
        let u = (t - peak) / max(0.01, end - peak)
        env = pow(max(0, 1.0 - u), 1.8)
      }

      // Sweeping silky air bandpass (300 Hz → 1600 Hz)
      let cutoff = 320.0 + 1300.0 * env
      let alpha = min(0.45, (2.0 * Double.pi * cutoff) / sampleRate)
      lpL += alpha * (nextNoise() - lpL)
      lpR += alpha * (nextNoise() - lpR)
      hpL += 0.025 * (lpL - hpL)
      hpR += 0.025 * (lpR - hpR)

      left[i] += (lpL - hpL) * env * gain
      right[i] += (lpR - hpR) * env * gain
    }
  }

  /// Dynamic warm low-pass filter sweep: muted & intimate during dark orb, opening radiantly on flood.
  private static func applyWarmLowPassSweep(left: inout [Double], right: inout [Double], isFullScore: Bool) {
    var yL = 0.0
    var yR = 0.0
    let twoPiOverSR = (2.0 * Double.pi) / sampleRate

    for i in 0..<left.count {
      let t = Double(i) / sampleRate
      let cutoff: Double
      if isFullScore {
        if t < 1.35 {
          let u = t / 1.35
          cutoff = 520.0 + 580.0 * u
        } else if t < 2.60 {
          let u = (t - 1.35) / 1.25
          let eased = u * u * (3.0 - 2.0 * u)
          cutoff = 1100.0 + 2800.0 * eased
        } else if t < 7.20 {
          cutoff = 3900.0
        } else {
          let u = min(1.0, (t - 7.20) / 9.50)
          let eased = u * u * (3.0 - 2.0 * u)
          cutoff = 3900.0 - 2950.0 * eased
        }
      } else {
        cutoff = 3200.0
      }

      let rc = 1.0 / (twoPiOverSR * cutoff)
      let alpha = 1.0 / (rc + 1.0)
      yL += alpha * (left[i] - yL)
      yR += alpha * (right[i] - yR)
      left[i] = yL
      right[i] = yR
    }
  }

  /// Lush stereo Schroeder-style reverb (4 damped comb filters per channel with stereo decorrelation).
  private static func applyStereoReverb(
    left: inout [Double],
    right: inout [Double],
    wetMix: Double,
    feedback: Double
  ) {
    let count = left.count
    let combDelaysL = [1367, 1621, 1889, 2347]
    let combDelaysR = [1423, 1669, 1949, 2411]

    var wetL = [Double](repeating: 0, count: count)
    var wetR = [Double](repeating: 0, count: count)

    for c in 0..<combDelaysL.count {
      let dL = combDelaysL[c]
      let dR = combDelaysR[c]
      var bufL = [Double](repeating: 0, count: dL)
      var bufR = [Double](repeating: 0, count: dR)
      var idxL = 0
      var idxR = 0
      var dampL = 0.0
      var dampR = 0.0
      let dampCoeff = 0.32

      for i in 0..<count {
        let outL = bufL[idxL]
        let outR = bufR[idxR]
        dampL = outL * (1.0 - dampCoeff) + dampL * dampCoeff
        dampR = outR * (1.0 - dampCoeff) + dampR * dampCoeff

        // Gentle cross-channel reflection for wide cinematic depth
        bufL[idxL] = left[i] * 0.78 + right[i] * 0.22 + dampL * feedback
        bufR[idxR] = right[i] * 0.78 + left[i] * 0.22 + dampR * feedback

        wetL[i] += outL * 0.25
        wetR[i] += outR * 0.25

        idxL += 1
        if idxL == dL { idxL = 0 }
        idxR += 1
        if idxR == dR { idxR = 0 }
      }
    }

    let dryMix = 1.0 - wetMix * 0.45
    for i in 0..<count {
      left[i] = left[i] * dryMix + wetL[i] * wetMix
      right[i] = right[i] * dryMix + wetR[i] * wetMix
    }
  }

  /// Soft analog warmth (`tanh`), click-free head fade, smooth curved tail fade-out, and peak normalization.
  private static func applyMasterPolish(
    left: inout [Double],
    right: inout [Double],
    targetPeak: Double,
    tailFadeSeconds: Double = 0.08
  ) {
    let count = left.count
    guard count > 0 else { return }

    var peak = 0.0001
    for i in 0..<count {
      let l = tanh(left[i] * 1.15)
      let r = tanh(right[i] * 1.15)
      left[i] = l
      right[i] = r
      peak = max(peak, max(abs(l), abs(r)))
    }

    let scale = targetPeak / peak
    let fadeInSamples = min(count / 4, Int(0.012 * sampleRate))
    let fadeOutSamples = min(count / 2, Int(tailFadeSeconds * sampleRate))

    for i in 0..<count {
      var env = 1.0
      if i < fadeInSamples {
        let u = Double(i) / Double(max(1, fadeInSamples))
        env *= 0.5 - 0.5 * cos(Double.pi * u)
      }
      let fromEnd = count - 1 - i
      if fromEnd < fadeOutSamples {
        let u = Double(fromEnd) / Double(max(1, fadeOutSamples))
        // Smooth cosine-squared tail melts the reverb imperceptibly into true zero silence
        let raised = 0.5 - 0.5 * cos(Double.pi * u)
        env *= raised * raised
      }
      left[i] *= scale * env
      right[i] *= scale * env
    }
  }

  private static func smoothEnvelope(t: Double, attack: Double, sustainEnd: Double, release: Double) -> Double {
    if t < 0 { return 0 }
    if t < attack {
      let u = t / max(0.001, attack)
      return 0.5 - 0.5 * cos(Double.pi * u)
    }
    if t < sustainEnd {
      return 1.0
    }
    let relT = t - sustainEnd
    if relT < release {
      let u = relT / max(0.001, release)
      return 0.5 + 0.5 * cos(Double.pi * u)
    }
    return 0
  }

  // MARK: - 16-bit Stereo PCM WAV Encoder

  private static func encodeStereoWAV(left: [Double], right: [Double]) -> Data {
    let frameCount = min(left.count, right.count)
    let channels: UInt16 = 2
    let bitsPerSample: UInt16 = 16
    let sr = UInt32(sampleRate)
    let byteRate = sr * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign = channels * (bitsPerSample / 8)
    let dataSize = UInt32(frameCount * Int(blockAlign))
    let chunkSize = 36 + dataSize

    var data = Data(capacity: 44 + Int(dataSize))

    func appendASCII(_ str: String) {
      data.append(contentsOf: str.utf8)
    }
    func appendLE(_ value: UInt32) {
      var v = value.littleEndian
      withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    func appendLE(_ value: UInt16) {
      var v = value.littleEndian
      withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    appendASCII("RIFF")
    appendLE(chunkSize)
    appendASCII("WAVE")
    appendASCII("fmt ")
    appendLE(UInt32(16))
    appendLE(UInt16(1)) // PCM
    appendLE(channels)
    appendLE(sr)
    appendLE(byteRate)
    appendLE(blockAlign)
    appendLE(bitsPerSample)
    appendASCII("data")
    appendLE(dataSize)

    data.reserveCapacity(44 + Int(dataSize))
    for i in 0..<frameCount {
      let lInt = Int16(max(-32_767, min(32_767, Int((left[i] * 32_767.0).rounded()))))
      let rInt = Int16(max(-32_767, min(32_767, Int((right[i] * 32_767.0).rounded()))))
      var lLE = lInt.littleEndian
      var rLE = rInt.littleEndian
      withUnsafeBytes(of: &lLE) { data.append(contentsOf: $0) }
      withUnsafeBytes(of: &rLE) { data.append(contentsOf: $0) }
    }

    return data
  }
}
