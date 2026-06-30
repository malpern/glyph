import Foundation
import MediaPlayer

/// Bridges read-aloud to the system: the lock screen, Control Center, and AirPods
/// gestures (single-press play/pause, double/triple-press skip) drive playback via
/// `MPRemoteCommandCenter`, and `MPNowPlayingInfoCenter` shows the book + current
/// sentence. The handlers call back through closures into the one `SpeechController`
/// — the same surface as the on-screen and (future) X4 buttons.
@MainActor
final class NowPlayingController {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    private let bookTitle: String

    init(bookTitle: String) {
        self.bookTitle = bookTitle
        let center = MPRemoteCommandCenter.shared()
        // MPRemoteCommandCenter doesn't guarantee its handlers run on the main thread, so
        // hop to the main actor explicitly (assuming isolation would trap if delivered
        // off-main). Return .success synchronously; the playback mutation happens on hop.
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlay?() }; return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPause?() }; return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onTogglePlayPause?() }; return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNext?() }; return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPrevious?() }; return .success
        }
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = false
    }

    /// Reflect current playback in the system Now Playing panel.
    func update(isPlaying: Bool, sentence: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: sentence.isEmpty ? bookTitle : sentence,
            MPMediaItemPropertyArtist: bookTitle,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                        center.nextTrackCommand, center.previousTrackCommand] {
            command.removeTarget(nil)
        }
    }
}
