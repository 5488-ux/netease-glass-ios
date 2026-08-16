import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var playingSongID: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    var errorHandler: ((String) -> Void)?

    private let api: NeteaseAPI
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    init(api: NeteaseAPI) {
        self.api = api
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? AVAudioSession.sharedInstance().setActive(true)
        installObservers()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    var remainingTime: TimeInterval {
        max(0, duration - currentTime)
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func toggle(song: Song) {
        if playingSongID == song.id, player.currentItem != nil, !isLoading {
            toggleCurrent()
            return
        }
        Task { await play(song: song) }
    }

    func toggleCurrent() {
        guard player.currentItem != nil, !isLoading else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if duration > 0, currentTime >= duration - 0.5 { seek(to: 0) }
            player.play()
            isPlaying = true
        }
    }

    func play(song: Song) async {
        player.pause()
        itemStatusObservation = nil
        currentSong = song
        playingSongID = song.id
        currentTime = 0
        duration = max(song.duration, 0)
        isPlaying = false
        isLoading = true

        do {
            let permission = try await api.resolveDownload(for: song)
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "Referer": "https://music.163.com/",
                    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15"
                ]
            ]
            let asset = AVURLAsset(url: permission.url, options: options)
            guard try await asset.load(.isPlayable) else {
                throw NeteaseAPIError.message("网易云返回的音频地址无法播放")
            }
            if let loadedDuration = try? await asset.load(.duration) {
                let seconds = loadedDuration.seconds
                if seconds.isFinite, seconds > 0 { duration = seconds }
            }

            let item = AVPlayerItem(asset: asset)
            observe(item)
            player.replaceCurrentItem(with: item)
            isLoading = false
            isPlaying = true
            player.play()
        } catch {
            player.replaceCurrentItem(with: nil)
            currentSong = nil
            playingSongID = nil
            currentTime = 0
            duration = 0
            isLoading = false
            isPlaying = false
            errorHandler?(NeteaseAPIError.userMessage(for: error))
        }
    }

    func seek(to seconds: TimeInterval) {
        guard player.currentItem != nil else { return }
        let target = min(max(seconds, 0), max(duration, 0))
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemStatusObservation = nil
        currentSong = nil
        playingSongID = nil
        currentTime = 0
        duration = 0
        isLoading = false
        isPlaying = false
    }

    private func installObservers() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite { self.currentTime = max(0, seconds) }
                if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                guard let self, let endedItem = notification.object as? AVPlayerItem, endedItem === self.player.currentItem else { return }
                self.isPlaying = false
                self.currentTime = self.duration
            }
        }
    }

    private func observe(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, let item else { return }
                if item.status == .failed {
                    self.isPlaying = false
                    self.isLoading = false
                    self.errorHandler?("音频播放失败，请重新选择歌曲")
                }
            }
        }
    }
}
