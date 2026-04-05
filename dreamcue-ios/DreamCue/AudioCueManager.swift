import AVFoundation
import AudioToolbox
import Foundation

/// Plays a reality-check sound cue on the iPhone for a configurable duration.
///
/// Usage:
///   - Drop a file named `cue_sound.mp3` (or .wav / .m4a) into the DreamCue Xcode group.
///   - If no file is found, a system sound plays as a fallback.
///   - Call `AudioCueManager.shared.playCue(duration:)` from any thread; it dispatches internally.
///
/// Background audio note:
///   UIBackgroundModes must include "audio" in Info.plist (already done).
///   The AVAudioSession is configured with `.playback` so the cue fires even when
///   the phone is locked and the screen is off.
@MainActor
final class AudioCueManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AudioCueManager()

    // MARK: - Published state

    /// `true` while a cue is actively playing.
    @Published var isPlaying: Bool = false

    // MARK: - Private

    private var audioPlayer: AVAudioPlayer?
    private var stopTimer: Timer?

    /// Supported sound file names searched in order (first match wins).
    private let candidateNames: [(name: String, ext: String)] = [
        ("cue_sound", "mp3"),
        ("cue_sound", "wav"),
        ("cue_sound", "m4a"),
        ("cue_sound", "aiff"),
    ]

    private init() {
        configureAudioSession()
    }

    // MARK: - Public API

    /// Play the cue sound for `duration` seconds, then stop automatically.
    ///
    /// - Parameter duration: How many seconds to play. The sound loops if it is shorter
    ///   than the duration. Defaults to 30 seconds.
    func playCue(duration: TimeInterval = 30) {
        // Cancel any currently playing cue before starting a new one.
        stopCue()

        if let url = bundledSoundURL() {
            playFile(at: url, duration: duration)
        } else {
            // No bundled file — fall back to a system sound repeated for ~duration.
            playSystemSoundLoop(duration: duration)
        }
    }

    /// Stop a currently playing cue immediately.
    func stopCue() {
        stopTimer?.invalidate()
        stopTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback keeps audio running when the phone is locked.
            // .mixWithOthers allows other apps (e.g. sleep sounds) to keep playing at lower volume.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[AudioCueManager] Audio session setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - File playback

    private func bundledSoundURL() -> URL? {
        for candidate in candidateNames {
            if let url = Bundle.main.url(forResource: candidate.name, withExtension: candidate.ext) {
                return url
            }
        }
        return nil
    }

    private func playFile(at url: URL, duration: TimeInterval) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1   // loop indefinitely until stopped
            audioPlayer?.volume = 0.6
            audioPlayer?.prepareToPlay()
            let didStart = audioPlayer?.play() ?? false

            if didStart {
                isPlaying = true
                scheduleStop(after: duration)
            } else {
                print("[AudioCueManager] AVAudioPlayer.play() returned false — using fallback")
                playSystemSoundLoop(duration: duration)
            }
        } catch {
            print("[AudioCueManager] Could not create player for \(url.lastPathComponent): \(error.localizedDescription)")
            playSystemSoundLoop(duration: duration)
        }
    }

    // MARK: - System sound fallback

    private func playSystemSoundLoop(duration: TimeInterval) {
        // System sound 1005 is the SMS-received chime — audible and gentle.
        // We repeat it every 3 seconds for the requested duration.
        isPlaying = true
        let repeatInterval: TimeInterval = 3.0
        let repetitions = max(1, Int(duration / repeatInterval))
        var fired = 0

        func fireNext() {
            guard fired < repetitions else {
                Task { @MainActor in self.isPlaying = false }
                return
            }
            AudioServicesPlaySystemSound(1005)
            fired += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + repeatInterval) {
                fireNext()
            }
        }

        fireNext()

        // Also schedule the isPlaying=false via the normal stop timer for accuracy.
        scheduleStop(after: duration)
    }

    // MARK: - Stop scheduling

    private func scheduleStop(after duration: TimeInterval) {
        stopTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopCue()
            }
        }
    }
}
