import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published private(set) var playingSongID: Int?
    @Published private(set) var isPlaying = false
    private let api: NeteaseAPI
    private let player = AVPlayer()

    init(api: NeteaseAPI) {
        self.api = api
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func toggle(song: Song) {
        if playingSongID == song.id {
            if isPlaying { player.pause(); isPlaying = false }
            else { player.play(); isPlaying = true }
            return
        }
        Task { await play(song: song) }
    }

    func play(song: Song) async {
        do {
            let permission = try await api.resolveDownload(for: song)
            player.replaceCurrentItem(with: AVPlayerItem(url: permission.url))
            playingSongID = song.id
            isPlaying = true
            player.play()
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        playingSongID = nil
        isPlaying = false
    }
}
