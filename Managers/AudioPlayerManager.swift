import AVFoundation
import Combine
import Foundation

/// 音质档位（对应网易云 level 参数）
enum AudioQuality: String, CaseIterable, Identifiable {
    case standard = "standard"
    case exhigh = "exhigh"
    case lossless = "lossless"
    case hires = "hires"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "标准音质"
        case .exhigh: return "高品音质"
        case .lossless: return "无损音质"
        case .hires: return "Hi-Res"
        }
    }

    /// 该音质下依次尝试的（编码, 音质档）组合，前面的失败自动降级到后面的
    static func attempts(for level: String) -> [(encodeType: String, level: String)] {
        switch level {
        case AudioQuality.hires.rawValue:
            return [("flac", "hires"), ("flac", "lossless"), ("mp3", "exhigh"), ("mp3", "standard")]
        case AudioQuality.lossless.rawValue:
            return [("flac", "lossless"), ("mp3", "exhigh"), ("mp3", "standard")]
        case AudioQuality.exhigh.rawValue:
            return [("mp3", "exhigh"), ("mp3", "standard"), ("aac", "standard")]
        default:
            return [("mp3", "standard"), ("aac", "standard"), ("mp3", "exhigh")]
        }
    }
}

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var playingSongID: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var preferredLevel: String
    @Published private(set) var volume: Float

    var errorHandler: ((String) -> Void)?

    private let api: NeteaseAPI
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var playbackRequestID = UUID()

    init(api: NeteaseAPI) {
        self.api = api
        self.preferredLevel = UserDefaults.standard.string(forKey: "player.quality") ?? AudioQuality.standard.rawValue
        self.volume = UserDefaults.standard.object(forKey: "player.volume") == nil
            ? 1
            : UserDefaults.standard.float(forKey: "player.volume")
        super.init()
        player.volume = volume
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? AVAudioSession.sharedInstance().setActive(true)
        installObservers()
    }

    var preferredLevelTitle: String {
        AudioQuality(rawValue: preferredLevel)?.title ?? AudioQuality.standard.title
    }

    /// 切换音质：保存偏好，并立即用新音质重新加载当前歌曲
    func setPreferredLevel(_ level: String) {
        guard AudioQuality(rawValue: level) != nil, level != preferredLevel else { return }
        let resumeTime = currentTime
        let shouldResumePlaying = isPlaying
        preferredLevel = level
        UserDefaults.standard.set(level, forKey: "player.quality")
        if let song = currentSong {
            Task {
                await play(song: song)
                guard preferredLevel == level, playingSongID == song.id, player.currentItem != nil else { return }
                seek(to: resumeTime)
                if !shouldResumePlaying {
                    player.pause()
                    isPlaying = false
                }
            }
        }
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
        let requestID = UUID()
        playbackRequestID = requestID
        player.pause()
        itemStatusObservation = nil
        currentSong = song
        playingSongID = song.id
        currentTime = 0
        duration = max(song.duration, 0)
        isPlaying = false
        isLoading = true

        // 按用户选择的音质依次尝试：不同格式会分配到不同 CDN 节点，
        // 前一种地址被 CDN 拒绝时自动降级
        let attempts = AudioQuality.attempts(for: preferredLevel)
        var lastError: Error?
        for attempt in attempts {
            guard playbackRequestID == requestID else { return }
            do {
                let permission = try await api.resolveDownload(for: song, encodeType: attempt.encodeType, level: attempt.level)
                guard playbackRequestID == requestID else { return }
                let asset = try await loadPlayableAsset(from: permission)
                guard playbackRequestID == requestID else { return }
                await startPlayback(with: asset, requestID: requestID)
                return
            } catch {
                lastError = error
            }
        }
        guard playbackRequestID == requestID else { return }
        finishPlaybackFailure(lastError ?? NeteaseAPIError.message("播放失败：无法获取可播放的音频"))
    }

    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        volume = clamped
        player.volume = clamped
        UserDefaults.standard.set(clamped, forKey: "player.volume")
    }

    private func startPlayback(with asset: AVURLAsset, requestID: UUID) async {
        guard playbackRequestID == requestID else { return }
        if let loadedDuration = try? await asset.load(.duration), loadedDuration.seconds.isFinite, loadedDuration.seconds > 0 {
            duration = loadedDuration.seconds
        }
        guard playbackRequestID == requestID else { return }
        let item = AVPlayerItem(asset: asset)
        observe(item)
        player.replaceCurrentItem(with: item)
        isLoading = false
        isPlaying = true
        player.play()
    }

    private func finishPlaybackFailure(_ error: Error) {
        player.replaceCurrentItem(with: nil)
        currentSong = nil
        playingSongID = nil
        currentTime = 0
        duration = 0
        isLoading = false
        isPlaying = false
        errorHandler?(NeteaseAPIError.userMessage(for: error))
    }

    /// 依次尝试多种组合加载音频资源（原始协议/备用协议、iPhone/桌面 UA、携带 Cookie），
    /// 全部失败时抛出带详细信息的错误，便于定位真实原因。
    private func loadPlayableAsset(from permission: DownloadPermission) async throws -> AVURLAsset {
        let iphoneUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15"
        let desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36 NeteaseMusicDesktop/3.0.18.203152"
        var fullCookie = api.hasCookie ? api.currentCookie : ""
        if !fullCookie.isEmpty { fullCookie += "; " }
        fullCookie += api.deviceCookie
        func makeOptions(_ ua: String, includeCookie: Bool) -> [String: Any] {
            var headers: [String: String] = ["Referer": "https://music.163.com/", "User-Agent": ua]
            if includeCookie, !fullCookie.isEmpty { headers["Cookie"] = fullCookie }
            return ["AVURLAssetHTTPHeaderFieldsKey": headers]
        }
        var candidates: [(URL, [String: Any])] = []
        func addCandidate(_ url: URL, _ ua: String) {
            candidates.append((url, makeOptions(ua, includeCookie: true)))
            candidates.append((url, makeOptions(ua, includeCookie: false)))
        }
        addCandidate(permission.url, iphoneUA)
        addCandidate(permission.url, desktopUA)
        if var components = URLComponents(url: permission.url, resolvingAgainstBaseURL: false) {
            let originalScheme = components.scheme
            components.scheme = originalScheme == "https" ? "http" : "https"
            if let alternate = components.url { addCandidate(alternate, iphoneUA) }
        }

        var lastError: Error?
        for (url, options) in candidates {
            let asset = AVURLAsset(url: url, options: options)
            do {
                if try await asset.load(.isPlayable) { return asset }
                lastError = NeteaseAPIError.message("音频地址无法播放：\(url.absoluteString)")
            } catch {
                lastError = error
            }
        }
        if let lastError {
            let detail = (lastError as? URLError).map { "网络错误码 \($0.code.rawValue)：\($0.localizedDescription)" } ?? lastError.localizedDescription
            throw NeteaseAPIError.message("音频加载失败（\(detail)）。音频地址：\(permission.url.absoluteString)")
        }
        throw NeteaseAPIError.message("音频加载失败：无法获取可播放的音频地址")
    }

    func seek(to seconds: TimeInterval) {
        guard player.currentItem != nil else { return }
        let target = min(max(seconds, 0), max(duration, 0))
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        playbackRequestID = UUID()
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

#if DEBUG
    /// 仅供 CI 模拟器做播放器真实截图检查，不会进入 Release 构建行为。
    func prepareLayoutPreview() {
        let isCommentCheck = ProcessInfo.processInfo.arguments.contains("--ui-check-comments")
        let previewSong = Song(
            id: isCommentCheck ? 347230 : -1,
            name: isCommentCheck ? "海阔天空" : "播放器布局检查",
            artist: isCommentCheck ? "BEYOND" : "NeteaseGlass",
            album: "UI Check",
            duration: 180,
            coverURL: nil,
            fee: 0,
            isVIP: false,
            size: nil,
            bitrate: nil
        )
        currentSong = previewSong
        playingSongID = previewSong.id
        currentTime = 21
        duration = previewSong.duration
        isPlaying = false
        isLoading = false
    }
#endif

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
                    let detail = item.error?.localizedDescription ?? ""
                    self.errorHandler?(detail.isEmpty ? "音频播放失败，请重新选择歌曲" : "音频播放失败：\(detail)")
                }
            }
        }
    }
}
