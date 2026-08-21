import Foundation

enum RecommendationServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case message(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "请先在设置中保存 DeepSeek API Key"
        case .invalidResponse: return "DeepSeek 没有返回可用的推荐结果"
        case let .message(value): return value
        }
    }
}

final class DeepSeekRecommendationService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func verify(apiKey: String) async throws {
        _ = try await requestCompletion(
            messages: [["role": "user", "content": "只返回 {\\\"ok\\\":true}" ]],
            apiKey: apiKey,
            temperature: 0,
            maxTokens: 16
        )
    }

    func analyze(likedSongs: [Song], lyricSnippets: [String], apiKey: String, variationSeed: String?) async throws -> AIRecommendationProfile {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecommendationServiceError.missingAPIKey
        }
        let songsText = likedSongs.map { "\($0.name) - \($0.artist)" }.joined(separator: "；")
        let lyricsText = lyricSnippets.prefix(2).joined(separator: "\n---\n")
        let prompt = """
        根据用户喜欢的歌曲，分析音乐偏好并生成网易云搜索词。只返回 JSON，不要 Markdown：
        {"summary":"不超过45字的中文偏好总结","keywords":["歌曲名 歌手", "..."]}
        keywords 必须是 6 到 8 个真实、可搜索的歌曲或歌手+歌曲名组合，不要编造解释。
        喜欢的歌曲：\(songsText)
        歌词摘要（仅作风格判断）：\(lyricsText.isEmpty ? "无" : lyricsText)
        本次推荐标识：\(variationSeed ?? "首次推荐")。如本次推荐标识不同，请不要重复上一次的歌曲组合。
        """
        let content = try await requestCompletion(
            messages: [
                ["role": "system", "content": "你是严谨的中文音乐推荐助手，必须输出有效 JSON。"],
                ["role": "user", "content": prompt]
            ],
            apiKey: apiKey,
            temperature: variationSeed == nil ? 0.55 : 0.9,
            maxTokens: 500
        )
        guard let profileData = content.data(using: .utf8),
              let profile = try? JSONDecoder().decode(AIRecommendationProfile.self, from: profileData),
              !profile.keywords.isEmpty else {
            throw RecommendationServiceError.invalidResponse
        }
        return profile
    }

    /// 使用 V4 Pro 深度思考并通过 SSE 逐步回传思考和最终歌单 JSON。
    func streamPlaylistPlan(
        preferences: AIPlaylistPreferences,
        apiKey: String,
        onDelta: @escaping @Sendable (_ reasoning: String?, _ content: String?) async -> Void
    ) async throws -> AIPlaylistPlan {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecommendationServiceError.missingAPIKey
        }
        let prompt = """
        你正在为用户制作一个仅保存在本地的音乐歌单。请认真深度思考用户选择，避免泛泛而谈，选择可在网易云搜索到的真实歌曲。
        用户选择：\(preferences.promptDescription)
        最终只能输出 JSON，不要 Markdown：
        {"title":"不超过16字的歌单名","summary":"不超过48字的歌单简介","thoughts":["至少3条具体创作想法"],"queries":["歌曲名 歌手", "..."]}
        queries 必须给出恰好 \(preferences.trackCount) 条真实歌曲名加歌手，覆盖不同节奏但保持同一主题。
        """
        let body: [String: Any] = [
            "model": "deepseek-v4-pro",
            "messages": [
                ["role": "system", "content": "你是专业音乐策展人。先深度思考，再给出准确的本地歌单方案。"],
                ["role": "user", "content": prompt]
            ],
            "thinking": ["type": "enabled"],
            "reasoning_effort": "high",
            "stream": true,
            "temperature": 0.75,
            "max_tokens": 1_400,
            "response_format": ["type": "json_object"]
        ]
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw RecommendationServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            var errorText = ""
            for try await line in bytes.lines {
                errorText += line
                if errorText.count > 400 { break }
            }
            throw RecommendationServiceError.message("DeepSeek 歌单生成失败（HTTP \(http.statusCode)）\(errorText.isEmpty ? "" : "：\(errorText.prefix(220))")")
        }

        var finalContent = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { continue }
            let reasoning = delta["reasoning_content"] as? String
            let content = delta["content"] as? String
            if let content { finalContent += content }
            if reasoning != nil || content != nil { await onDelta(reasoning, content) }
        }
        guard let planData = finalContent.data(using: .utf8),
              let plan = try? JSONDecoder().decode(AIPlaylistPlan.self, from: planData),
              !plan.title.isEmpty,
              !plan.queries.isEmpty else {
            throw RecommendationServiceError.invalidResponse
        }
        return plan
    }

    private func requestCompletion(messages: [[String: String]], apiKey: String, temperature: Double, maxTokens: Int) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecommendationServiceError.missingAPIKey
        }
        let body: [String: Any] = [
            "model": "deepseek-v4-flash",
            "messages": messages,
            "thinking": ["type": "disabled"],
            "temperature": temperature,
            "max_tokens": maxTokens,
            "response_format": ["type": "json_object"]
        ]
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RecommendationServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let server = String(data: data, encoding: .utf8) ?? ""
            throw RecommendationServiceError.message("DeepSeek 请求失败（HTTP \(http.statusCode)）\(server.isEmpty ? "" : "：\(server.prefix(160))")")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let content = (choices.first?["message"] as? [String: Any])?["content"] as? String,
              !content.isEmpty else {
            throw RecommendationServiceError.invalidResponse
        }
        return content
    }
}

final class AppleMusicChartService {
    func fetchChinaTopSongs(limit: Int = 12) async throws -> [PlatformTrack] {
        let url = URL(string: "https://rss.marketingtools.apple.com/api/v2/cn/music/most-played/\(limit)/songs.json")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = json["feed"] as? [String: Any],
              let results = feed["results"] as? [[String: Any]] else {
            throw RecommendationServiceError.invalidResponse
        }
        return results.compactMap { item in
            guard let name = item["name"] as? String,
                  let artist = item["artistName"] as? String else { return nil }
            let artwork = URL(string: item["artworkUrl100"] as? String ?? "")
            return PlatformTrack(source: "Apple Music 热歌", name: name, artist: artist, artworkURL: artwork)
        }
    }
}
