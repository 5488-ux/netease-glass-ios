import Combine
import Foundation

@MainActor
final class RecommendationManager: ObservableObject {
    enum APIStatus: Equatable {
        case notChecked
        case checking
        case active
        case failed(String)
    }

    @Published private(set) var personalizedSongs: [Song] = []
    @Published private(set) var trendingSongs: [Song] = []
    @Published private(set) var platformTracks: [PlatformTrack] = []
    @Published private(set) var insight: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var apiStatus: APIStatus = .notChecked
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var localAIPlaylists: [LocalAIPlaylist] = []
    @Published private(set) var playlistThinking = ""
    @Published private(set) var playlistOutput = ""
    @Published private(set) var playlistGenerationStatus: String?
    @Published private(set) var isCreatingPlaylist = false

    private let api: NeteaseAPI
    private let deepSeek = DeepSeekRecommendationService()
    private let appleMusic = AppleMusicChartService()
    private var analyzedUserID: Int?
    private var recentTrendingIDs: Set<Int> = []
    private var recentPersonalizedIDs: Set<Int> = []
    private let localPlaylistStorageKey = "neteaseglass.local-ai-playlists.v1"

    init(api: NeteaseAPI) {
        self.api = api
        loadLocalAIPlaylists()
    }

    var hasDeepSeekAPIKey: Bool {
        !(KeychainStore.loadDeepSeekAPIKey() ?? "").isEmpty
    }

    func loadPublicRecommendations() async {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-check-recommendations") {
            prepareLayoutPreview()
            return
        }
#endif
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let songs = try? await api.trendingSongs() {
            trendingSongs = freshSongs(from: songs, excluding: &recentTrendingIDs, limit: 12)
        }
        if let tracks = try? await appleMusic.fetchChinaTopSongs() { platformTracks = tracks }
    }

    func refreshForAccount(userID: Int?, likedSongIDs: Set<Int>, forceAI: Bool = false) async {
        guard let userID else {
            personalizedSongs = []
            insight = nil
            analyzedUserID = nil
            return
        }
        if let songs = try? await api.dailyRecommendedSongs() {
            personalizedSongs = freshSongs(from: songs, excluding: &recentPersonalizedIDs, limit: 12)
        }
        guard (analyzedUserID != userID || forceAI), !likedSongIDs.isEmpty, hasDeepSeekAPIKey else { return }
        analyzedUserID = userID
        await analyzeLikes(likedSongIDs: likedSongIDs, force: forceAI)
    }

    func saveDeepSeekAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.deleteDeepSeekAPIKey()
        } else {
            try KeychainStore.saveDeepSeekAPIKey(trimmed)
        }
        analyzedUserID = nil
        apiStatus = .notChecked
    }

    func checkDeepSeekAPI() async {
        guard hasDeepSeekAPIKey else {
            apiStatus = .failed("请先保存 DeepSeek API Key")
            return
        }
        if case .checking = apiStatus { return }
        apiStatus = .checking
        do {
            try await deepSeek.verify(apiKey: KeychainStore.loadDeepSeekAPIKey() ?? "")
            apiStatus = .active
        } catch {
            apiStatus = .failed(NeteaseAPIError.userMessage(for: error))
        }
    }

    func manuallyRefreshRecommendations(userID: Int?, likedSongIDs: Set<Int>) async {
        lastErrorMessage = nil
        await loadPublicRecommendations()
        guard let userID else {
            lastErrorMessage = "请先登录网易云音乐，才能生成个性歌曲推荐"
            return
        }
        await refreshForAccount(userID: userID, likedSongIDs: likedSongIDs, forceAI: true)
        if personalizedSongs.isEmpty {
            lastErrorMessage = "暂无可用推荐。请确认喜欢列表已同步，或稍后再试。"
        }
    }

    func dismissError() {
        lastErrorMessage = nil
    }

    func createLocalAIPlaylist(preferences: AIPlaylistPreferences) async -> LocalAIPlaylist? {
        guard hasDeepSeekAPIKey else {
            lastErrorMessage = "请先在设置中保存并检测 DeepSeek API Key"
            return nil
        }
        guard api.hasCookie else {
            lastErrorMessage = "请先登录网易云音乐，AI 才能把歌单中的歌曲匹配为可播放条目"
            return nil
        }
        guard !isCreatingPlaylist else { return nil }
        isCreatingPlaylist = true
        playlistThinking = ""
        playlistOutput = ""
        playlistGenerationStatus = "V4 Pro 正在深度思考…"
        defer { isCreatingPlaylist = false }
        do {
            let plan = try await deepSeek.streamPlaylistPlan(
                preferences: preferences,
                apiKey: KeychainStore.loadDeepSeekAPIKey() ?? ""
            ) { [weak self] reasoning, content in
                guard let self else { return }
                if let reasoning {
                    await self.appendPlaylistCharacters(reasoning, toThinking: true)
                }
                if let content {
                    await self.appendPlaylistCharacters(content, toThinking: false)
                }
            }
            playlistGenerationStatus = "正在匹配网易云歌曲…"
            var songs: [Song] = []
            for query in plan.queries.prefix(preferences.trackCount) {
                if let song = try? await api.searchSongs(query).first,
                   !songs.contains(where: { $0.id == song.id }) {
                    songs.append(song)
                }
            }
            guard !songs.isEmpty else {
                throw RecommendationServiceError.message("AI 已给出歌单方案，但未能在网易云匹配到可播放歌曲")
            }
            let playlist = LocalAIPlaylist(
                id: UUID(),
                createdAt: Date(),
                preferences: preferences,
                title: plan.title,
                summary: plan.summary,
                thoughts: plan.thoughts,
                songs: songs
            )
            localAIPlaylists.insert(playlist, at: 0)
            persistLocalAIPlaylists()
            playlistGenerationStatus = "已创建，仅保存在本机"
            return playlist
        } catch {
            playlistGenerationStatus = "创建失败"
            lastErrorMessage = NeteaseAPIError.userMessage(for: error)
            return nil
        }
    }

    private func appendPlaylistCharacters(_ value: String, toThinking: Bool) async {
        for character in value {
            if toThinking { playlistThinking.append(character) } else { playlistOutput.append(character) }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func loadLocalAIPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: localPlaylistStorageKey),
              let playlists = try? JSONDecoder().decode([LocalAIPlaylist].self, from: data) else { return }
        localAIPlaylists = playlists.sorted { $0.createdAt > $1.createdAt }
    }

    private func persistLocalAIPlaylists() {
        guard let data = try? JSONEncoder().encode(localAIPlaylists) else { return }
        UserDefaults.standard.set(data, forKey: localPlaylistStorageKey)
    }

    func analyzeLikes(likedSongIDs: Set<Int>, force: Bool = false) async {
        guard hasDeepSeekAPIKey, !likedSongIDs.isEmpty, !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let sourceSongs = try await api.songs(ids: Array(likedSongIDs.prefix(8)))
            var snippets: [String] = []
            for song in sourceSongs.prefix(2) {
                if let lyricLines = try? await api.lyrics(for: song.id),
                   let firstLine = lyricLines.first?.text,
                   !firstLine.isEmpty {
                    snippets.append(firstLine.prefix(160).description)
                }
            }
            let profile = try await deepSeek.analyze(
                likedSongs: sourceSongs,
                lyricSnippets: snippets,
                apiKey: KeychainStore.loadDeepSeekAPIKey() ?? "",
                variationSeed: force ? UUID().uuidString : nil
            )
            insight = profile.summary
            var resolved: [Song] = []
            for keyword in profile.keywords.prefix(8) {
                if let song = try? await api.searchSongs(keyword).first,
                   !resolved.contains(where: { $0.id == song.id }) {
                    resolved.append(song)
                }
            }
            if !resolved.isEmpty {
                personalizedSongs = freshSongs(from: resolved, excluding: &recentPersonalizedIDs, limit: 8)
            }
        } catch {
            insight = "AI 偏好分析暂时不可用，已显示网易云每日推荐。"
            lastErrorMessage = NeteaseAPIError.userMessage(for: error)
        }
    }

    private func freshSongs(from candidates: [Song], excluding recentIDs: inout Set<Int>, limit: Int) -> [Song] {
        let unique = Dictionary(grouping: candidates, by: \.id).compactMap { $0.value.first }
        var fresh = unique.filter { !recentIDs.contains($0.id) }.shuffled()
        if fresh.count < min(limit, unique.count) {
            recentIDs.removeAll()
            fresh = unique.shuffled()
        }
        let selected = Array(fresh.prefix(limit))
        recentIDs.formUnion(selected.map(\.id))
        return selected
    }

    func resolvePlatformTrack(_ track: PlatformTrack) async throws -> Song {
        guard let song = try await api.searchSongs("\(track.name) \(track.artist)").first else {
            throw RecommendationServiceError.message("没有在网易云找到「\(track.name)」")
        }
        return song
    }

#if DEBUG
    private func prepareLayoutPreview() {
        let sample = Song(
            id: -3,
            name: "根据喜欢歌曲推荐",
            artist: "NeteaseGlass",
            album: "自动推荐",
            duration: 201,
            coverURL: nil,
            fee: 0,
            isVIP: false,
            size: nil,
            bitrate: nil
        )
        personalizedSongs = [sample]
        trendingSongs = [
            Song(id: -4, name: "网易云热歌示例", artist: "热门歌手", album: "新歌速递", duration: 196, coverURL: nil, fee: 0, isVIP: false, size: nil, bitrate: nil)
        ]
        platformTracks = [
            PlatformTrack(source: "Apple Music 热歌", name: "公开榜单示例", artist: "Apple Music 中国区", artworkURL: nil)
        ]
        insight = "已根据喜欢歌曲生成推荐方向"
    }
#endif
}
