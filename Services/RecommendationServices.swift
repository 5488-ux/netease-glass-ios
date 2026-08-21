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

    func analyze(likedSongs: [Song], lyricSnippets: [String], apiKey: String) async throws -> AIRecommendationProfile {
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
        """
        let body: [String: Any] = [
            "model": "deepseek-v4-flash",
            "messages": [
                ["role": "system", "content": "你是严谨的中文音乐推荐助手，必须输出有效 JSON。"],
                ["role": "user", "content": prompt]
            ],
            "thinking": ["type": "disabled"],
            "temperature": 0.55,
            "max_tokens": 500,
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
              let profileData = content.data(using: .utf8),
              let profile = try? JSONDecoder().decode(AIRecommendationProfile.self, from: profileData),
              !profile.keywords.isEmpty else {
            throw RecommendationServiceError.invalidResponse
        }
        return profile
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
