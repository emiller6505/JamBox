import AppKit
import Combine
import MediaPlayer

/// Bridges PlayerEngine state to the macOS system playback APIs:
/// - `MPRemoteCommandCenter` receives media key presses, Control Center buttons,
///   lock screen controls, and Touch Bar buttons. We register handlers that
///   forward to the player.
/// - `MPNowPlayingInfoCenter` publishes the currently playing track so the
///   system shows it in the Now Playing widget. Without keeping this current,
///   the OS may consider the app inactive and stop routing media keys to it.
@MainActor
final class MediaKeyController {
    private let player: PlayerEngine
    private var cancellables = Set<AnyCancellable>()

    init(player: PlayerEngine) {
        self.player = player
        registerCommands()
        observePlayer()
    }

    // MARK: - Command registration

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()

        // Standalone play / pause / toggle. macOS sends `togglePlayPause`
        // for the F8 key but we register all three for completeness (Control
        // Center has separate play and pause buttons).
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !self.player.isPlaying { self.player.togglePlayPause() }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.player.isPlaying { self.player.togglePlayPause() }
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.player.togglePlayPause()
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.player.skipForward()
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.player.skipBackward()
            return .success
        }

        // Drag-to-seek from the Now Playing widget.
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }

            let target = positionEvent.positionTime
            guard self.player.playbackDuration > 0 else { return .commandFailed }
            self.player.seek(to: target / self.player.playbackDuration)
            return .success
        }

        // Explicitly disable features we don't support so they don't appear
        // in Control Center.
        center.changeShuffleModeCommand.isEnabled = false
        center.changeRepeatModeCommand.isEnabled = false
    }

    // MARK: - Now Playing info

    private func observePlayer() {
        // Update on any change to the four properties that affect the widget.
        // CombineLatest emits whenever any input changes.
        Publishers.CombineLatest4(
            player.$currentTrack,
            player.$isPlaying,
            player.$playbackDuration,
            player.$currentArtwork
        )
        .sink { [weak self] _, _, _, _ in
            self?.updateNowPlayingInfo()
        }
        .store(in: &cancellables)

        // Position is updated 4× per second by the periodic time observer.
        // Update the widget when it changes too — but the system can also
        // interpolate from MPNowPlayingInfoPropertyElapsedPlaybackTime + the
        // current rate, so we don't strictly need every tick.
        player.$playbackPosition
            .sink { [weak self] _ in self?.updateNowPlayingInfo() }
            .store(in: &cancellables)
    }

    private func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()

        guard let track = player.currentTrack else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayName,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: player.playbackDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.playbackPosition,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0
        ]

        if let artwork = player.currentArtwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
                artwork
            }
        }

        center.nowPlayingInfo = info
        center.playbackState = player.isPlaying ? .playing : .paused
    }
}
