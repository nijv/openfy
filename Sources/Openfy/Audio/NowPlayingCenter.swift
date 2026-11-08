import AppKit
import MediaPlayer
import OpenfyCore

/// Media keys (F7–F9), Control Center and the lock screen "Now Playing" widget.
final class NowPlayingCenter {
    private weak var player: PlayerController?
    private var artworkKey: String?
    private var artwork: MPMediaItemArtwork?
    var artworkProvider: ((String) -> NSImage?)?

    init(player: PlayerController) {
        self.player = player
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.player?.resume(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.player?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.player?.togglePlayPause(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.player?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.player?.previous(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.player?.seek(to: e.positionTime)
            return .success
        }
    }

    func update() {
        guard let player, let track = player.current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.position,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if track.artworkKey != artworkKey {
            artworkKey = track.artworkKey
            artwork = track.artworkKey.flatMap { key in
                artworkProvider?(key).map { image in
                    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                }
            }
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = player.isPlaying ? .playing : .paused
    }
}
