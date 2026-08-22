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
    @Published private(set) var playlistGenerationError: String?
    @Published private(set) var lastCreatedPlaylist: LocalAIPlaylist?
    @Published private(set) var isCreatingPlaylist = false
    @Published private(set) var playlistChoiceQuestion: AIPlaylistChoiceRequest?
    @Published private(set) var playlistChoiceAnswers: [AIPlaylistChoiceAnswer] = []
    @Published private(set) var isLoadingPlaylistChoice = false
    @Published private(set) var isPlaylistInterviewReady = false
    @Published private(set) var playlistChoiceError: String?

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

    func beginPlaylistChoiceInterview() async {
        guard playlistChoiceQuestion == nil, !isPlaylistInterviewReady else { return }
        await requestNextPlaylistChoice()
    }

    func resetPlaylistChoiceInterview() async {
        playlistChoiceQuestion = nil
        playlistChoiceAnswers = []
        playlistChoiceError = nil
        isPlaylistInterviewReady = false
        await requestNextPlaylistChoice()
    }

    func submitPlaylistChoice(_ answer: String) async {
        guard let question = playlistChoiceQuestion, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        playlistChoiceAnswers.append(AIPlaylistChoiceAnswer(question: question.question, answer: answer))
        playlistChoiceQuestion = nil
        await requestNextPlaylistChoice()
    }

    func playlistPreferences(trackCount: Int) -> AIPlaylistPreferences {
        let values = playlistChoiceAnswers.map(\.answer)
        return AIPlaylistPreferences(
            mood: values.first ?? "由 AI 选择器决定",
            scene: values.dropFirst().first ?? "由 AI 选择器决定",
            energy: values.dropFirst(2).first ?? "由 AI 选择器决定",
            language: values.dropFirst(3).first ?? "不限语言",
            trackCount: trackCount,
            customDirection: playlistChoiceAnswers.map { "\($0.question)：\($0.answer)" }.joined(separator: "；")
        )
    }

    private func requestNextPlaylistChoice() async {
        guard hasDeepSeekAPIKey else {
            playlistChoiceError = "请先在设置中保存 DeepSeek API Key"
            return
        }
        guard !isLoadingPlaylistChoice else { return }
        isLoadingPlaylistChoice = true
        playlistChoiceError = nil
        defer { isLoadingPlaylistChoice = false }
        do {
            let step = try await deepSeek.nextPlaylistChoice(
                answers: playlistChoiceAnswers,
                apiKey: KeychainStore.loadDeepSeekAPIKey() ?? ""
            )
            switch step {
            case let .question(question):
                playlistChoiceQuestion = question
            case .ready:
                isPlaylistInterviewReady = true
            }
        } catch {
            playlistChoiceError = NeteaseAPIError.userMessage(for: error)
        }
    }

    func createLocalAIPlaylist(preferences: AIPlaylistPreferences, likedSongIDs: Set<Int>) async -> LocalAIPlaylist? {
        guard hasDeepSeekAPIKey else {
            lastErrorMessage = "请先在设置中保存并检测 DeepSeek API Key"
            return nil
        }
        guard api.hasCookie else {
            lastErrorMessage = "请先登录网易云音乐，AI 才能把歌单中的歌曲匹配为可播放条目"
            return nil
        }
        guard !likedSongIDs.isEmpty else {
            lastErrorMessage = "没有读取到你喜欢的歌曲，请先在网易云收藏歌曲并刷新喜欢列表"
            return nil
        }
        guard !isCreatingPlaylist else { return nil }
        isCreatingPlaylist = true
        playlistThinking = ""
        playlistOutput = ""
        playlistGenerationError = nil
        lastCreatedPlaylist = nil
        playlistGenerationStatus = "V4 Pro 正在深度思考…"
        defer { isCreatingPlaylist = false }
        do {
            playlistGenerationStatus = "正在读取我喜欢的音乐…"
            let likedSongs = try await api.songs(ids: Array(likedSongIDs.prefix(40)))
            guard !likedSongs.isEmpty else {
                throw RecommendationServiceError.message("已同步喜欢歌曲 ID，但未能读取歌曲详情，请刷新登录状态后重试")
            }
            playlistGenerationStatus = "V4 Pro 正在结合喜欢歌曲深度思考…"
            let plan = try await deepSeek.streamPlaylistPlan(
                preferences: preferences,
                likedSongs: likedSongs,
                apiKey: KeychainStore.loadDeepSeekAPIKey() ?? ""
            ) { [weak self] reasoning, content in
                guard let self else { return }
                if let reasoning {
                    await self.updatePlaylistGenerationStatus("AI 正在逐字展示思考过程…")
                    await self.appendPlaylistCharacters(reasoning, toThinking: true)
                }
                if let content {
                    await self.updatePlaylistGenerationStatus("AI 正在逐字整理歌单方案…")
                    await self.appendPlaylistCharacters(content, toThinking: false)
                }
            }
            playlistGenerationStatus = "正在匹配网易云歌曲…"
            var songs: [Song] = []
            let targetCount = min(max(preferences.trackCount, 1), 30)
            let candidateQueries = uniqueStrings(plan.queries + (plan.candidates ?? [])).prefix(50)
            for (index, query) in candidateQueries.enumerated() where songs.count < targetCount {
                playlistGenerationStatus = "正在匹配网易云歌曲 \(songs.count)/\(targetCount)（候选 \(index + 1)/\(candidateQueries.count)）"
                if let results = try? await api.searchSongs(query),
                   let song = results.first(where: { result in
                       !songs.contains(where: { $0.id == result.id })
                   }) {
                    songs.append(song)
                }
            }
            for song in likedSongs where songs.count < targetCount && !songs.contains(where: { $0.id == song.id }) {
                songs.append(song)
            }
            for song in personalizedSongs + trendingSongs where songs.count < targetCount && !songs.contains(where: { $0.id == song.id }) {
                songs.append(song)
            }
            guard songs.count == targetCount else {
                throw RecommendationServiceError.message("要求创建 \(targetCount) 首，但 50 首 AI 候选和喜欢歌曲中只匹配到 \(songs.count) 首可用歌曲")
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
            lastCreatedPlaylist = playlist
            playlistGenerationStatus = "已创建，仅保存在本机"
            return playlist
        } catch {
            playlistGenerationStatus = "创建失败"
            playlistGenerationError = NeteaseAPIError.userMessage(for: error)
            return nil
        }
    }

    private func updatePlaylistGenerationStatus(_ value: String) {
        playlistGenerationStatus = value
    }

    private func appendPlaylistCharacters(_ value: String, toThinking: Bool) async {
        for character in value {
            if toThinking { playlistThinking.append(character) } else { playlistOutput.append(character) }
            await Task.yield()
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

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !key.isEmpty && seen.insert(key).inserted
        }
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
