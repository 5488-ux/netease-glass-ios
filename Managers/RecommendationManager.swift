import Combine
import BackgroundTasks
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
    private let continuedTaskIdentifier = "com.example.NeteaseGlass.ai-playlist"
    private var isContinuedTaskRegistered = false
    private var activeContinuedTask: BGContinuedProcessingTask?
    private var playlistCreationTask: Task<Void, Never>?
    private var pendingPlaylistRequest: (preferences: AIPlaylistPreferences, likedSongIDs: Set<Int>)?
    private var pendingPlaylistThinking = ""
    private var pendingPlaylistOutput = ""
    private var streamPublishTask: Task<Void, Never>?

    init(api: NeteaseAPI) {
        self.api = api
        loadLocalAIPlaylists()
        registerContinuedProcessingTask()
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

    func startLocalAIPlaylistCreation(preferences: AIPlaylistPreferences, likedSongIDs: Set<Int>) {
        guard validatePlaylistCreation(likedSongIDs: likedSongIDs), !isCreatingPlaylist else { return }

        playlistThinking = ""
        playlistOutput = ""
        playlistGenerationError = nil
        lastCreatedPlaylist = nil
        playlistGenerationStatus = "正在申请 iOS 后台持续生成…"
        isCreatingPlaylist = true
        pendingPlaylistRequest = (preferences, likedSongIDs)

        guard isContinuedTaskRegistered else {
            startPlaylistCreation(preferences: preferences, likedSongIDs: likedSongIDs, continuedTask: nil)
            return
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: continuedTaskIdentifier,
            title: "正在创建 AI 歌单",
            subtitle: "DeepSeek 正在结合喜欢的歌曲深度策展"
        )
        request.strategy = .fail

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            playlistGenerationStatus = "后台持续处理暂不可用，正在前台生成…"
            startPlaylistCreation(preferences: preferences, likedSongIDs: likedSongIDs, continuedTask: nil)
        }
    }

    private func validatePlaylistCreation(likedSongIDs: Set<Int>) -> Bool {
        guard hasDeepSeekAPIKey else {
            lastErrorMessage = "请先在设置中保存并检测 DeepSeek API Key"
            return false
        }
        guard api.hasCookie else {
            lastErrorMessage = "请先登录网易云音乐，AI 才能把歌单中的歌曲匹配为可播放条目"
            return false
        }
        guard !likedSongIDs.isEmpty else {
            lastErrorMessage = "没有读取到你喜欢的歌曲，请先在网易云收藏歌曲并刷新喜欢列表"
            return false
        }
        return true
    }

    private func registerContinuedProcessingTask() {
        guard !isContinuedTaskRegistered else { return }
        isContinuedTaskRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: continuedTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in
                self?.handleContinuedProcessingTask(continuedTask)
            }
        }
    }

    private func handleContinuedProcessingTask(_ task: BGContinuedProcessingTask) {
        guard let pendingPlaylistRequest else {
            task.setTaskCompleted(success: false)
            return
        }
        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = 2
        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.playlistCreationTask?.cancel()
                self?.playlistGenerationStatus = "后台生成已被系统或用户取消"
                self?.playlistGenerationError = "iOS 已结束后台持续处理任务，请回到 App 后重新创建。"
            }
        }
        startPlaylistCreation(
            preferences: pendingPlaylistRequest.preferences,
            likedSongIDs: pendingPlaylistRequest.likedSongIDs,
            continuedTask: task
        )
    }

    private func startPlaylistCreation(
        preferences: AIPlaylistPreferences,
        likedSongIDs: Set<Int>,
        continuedTask: BGContinuedProcessingTask?
    ) {
        guard playlistCreationTask == nil else { return }
        pendingPlaylistRequest = nil
        activeContinuedTask = continuedTask
        playlistCreationTask = Task { [weak self] in
            guard let self else { return }
            let playlist = await self.createLocalAIPlaylist(
                preferences: preferences,
                likedSongIDs: likedSongIDs
            )
            self.finishContinuedProcessing(success: playlist != nil)
        }
    }

    private func finishContinuedProcessing(success: Bool) {
        if success {
            activeContinuedTask?.progress.completedUnitCount = 100
            activeContinuedTask?.updateTitle("AI 歌单已创建", subtitle: "已保存在 NeteaseGlass 本机")
        }
        activeContinuedTask?.setTaskCompleted(success: success)
        activeContinuedTask = nil
        streamPublishTask?.cancel()
        streamPublishTask = nil
        flushPlaylistStreamBuffer()
        playlistCreationTask = nil
        pendingPlaylistRequest = nil
    }

    private func updateContinuedProgress(_ completed: Int64, subtitle: String) {
        guard let task = activeContinuedTask else { return }
        let value = min(max(completed, task.progress.completedUnitCount), 99)
        task.progress.completedUnitCount = value
        task.updateTitle("正在创建 AI 歌单", subtitle: subtitle)
    }

    private func createLocalAIPlaylist(preferences: AIPlaylistPreferences, likedSongIDs: Set<Int>) async -> LocalAIPlaylist? {
        playlistGenerationStatus = "V4 Pro 正在深度思考…"
        defer { isCreatingPlaylist = false }
        do {
            try Task.checkCancellation()
            updateContinuedProgress(5, subtitle: "正在读取我喜欢的音乐")
            playlistGenerationStatus = "正在读取我喜欢的音乐…"
            let likedSongs = try await api.songs(ids: Array(likedSongIDs.prefix(40)))
            guard !likedSongs.isEmpty else {
                throw RecommendationServiceError.message("已同步喜欢歌曲 ID，但未能读取歌曲详情，请刷新登录状态后重试")
            }
            updateContinuedProgress(15, subtitle: "DeepSeek 正在深度思考")
            playlistGenerationStatus = "V4 Pro 正在结合喜欢歌曲深度思考…"
            let plan = try await deepSeek.streamPlaylistPlan(
                preferences: preferences,
                likedSongs: likedSongs,
                apiKey: KeychainStore.loadDeepSeekAPIKey() ?? ""
            ) { [weak self] reasoning, content in
                guard let self else { return }
                if let reasoning {
                    await self.updatePlaylistGenerationStatus("AI 正在逐字展示思考过程…")
                    await self.enqueuePlaylistStream(reasoning, toThinking: true)
                }
                if let content {
                    await self.updatePlaylistGenerationStatus("AI 正在逐字整理歌单方案…")
                    await self.enqueuePlaylistStream(content, toThinking: false)
                }
            }
            try Task.checkCancellation()
            flushPlaylistStreamBuffer()
            playlistGenerationStatus = "正在匹配网易云歌曲…"
            updateContinuedProgress(65, subtitle: "正在匹配网易云歌曲")
            var songs: [Song] = []
            let targetCount = min(max(preferences.trackCount, 1), 30)
            let candidateQueries = uniqueStrings(plan.queries + (plan.candidates ?? [])).prefix(50)
            for (index, query) in candidateQueries.enumerated() where songs.count < targetCount {
                try Task.checkCancellation()
                playlistGenerationStatus = "正在匹配网易云歌曲 \(songs.count)/\(targetCount)（候选 \(index + 1)/\(candidateQueries.count)）"
                let matchingProgress = 65 + Int64((Double(index + 1) / Double(max(candidateQueries.count, 1))) * 30)
                updateContinuedProgress(matchingProgress, subtitle: "已匹配 \(songs.count)/\(targetCount) 首")
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
        } catch is CancellationError {
            playlistGenerationStatus = "生成已取消"
            playlistGenerationError = "后台任务已被系统或用户取消，请重新创建。"
            return nil
        } catch {
            playlistGenerationStatus = "创建失败"
            playlistGenerationError = NeteaseAPIError.userMessage(for: error)
            return nil
        }
    }

    private func updatePlaylistGenerationStatus(_ value: String) {
        playlistGenerationStatus = value
    }

    private func enqueuePlaylistStream(_ value: String, toThinking: Bool) {
        guard !value.isEmpty, !Task.isCancelled else { return }
        if toThinking {
            pendingPlaylistThinking.append(value)
        } else {
            pendingPlaylistOutput.append(value)
        }
        guard streamPublishTask == nil else { return }
        streamPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let self else { return }
            self.flushPlaylistStreamBuffer()
        }
    }

    private func flushPlaylistStreamBuffer() {
        streamPublishTask = nil
        if !pendingPlaylistThinking.isEmpty {
            playlistThinking.append(pendingPlaylistThinking)
            pendingPlaylistThinking = ""
        }
        if !pendingPlaylistOutput.isEmpty {
            playlistOutput.append(pendingPlaylistOutput)
            pendingPlaylistOutput = ""
        }
        let streamProgress = min(60, 18 + Int64((playlistThinking.count + playlistOutput.count) / 250))
        let subtitle = playlistOutput.isEmpty ? "DeepSeek 正在思考" : "正在整理歌单方案"
        updateContinuedProgress(streamProgress, subtitle: subtitle)
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
