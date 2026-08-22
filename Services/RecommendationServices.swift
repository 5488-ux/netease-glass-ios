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

    /// 让 V4 Pro 主动调用 App 内置的 present_choice 工具，决定下一道选择题。
    func nextPlaylistChoice(
        answers: [AIPlaylistChoiceAnswer],
        apiKey: String
    ) async throws -> AIPlaylistChoiceStep {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecommendationServiceError.missingAPIKey
        }
        if answers.count >= 5 { return .ready }
        let history = answers.isEmpty
            ? "尚未提问"
            : answers.map { "问题：\($0.question)\n选择：\($0.answer)" }.joined(separator: "\n---\n")
        let prompt = """
        你正在通过选择器了解用户想创建的音乐歌单。
        已有回答：
        \(history)

        规则：
        1. 至少询问 2 题，最多询问 5 题；问题数量由你根据已有信息决定。
        2. 信息不足时必须调用 present_choice，一次只问一个最有价值的问题。
        3. 给出 2 到 5 个简短、互斥的选项，最后一个选项必须严格写为“自定义”。
        4. 不要重复已经问过的问题。
        5. 信息足够且已经至少回答 2 题时，不调用工具，只回复 READY。
        """
        let tools: [[String: Any]] = [[
            "type": "function",
            "function": [
                "name": "present_choice",
                "description": "在 App 中向用户显示一个可点击的单选选择器",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "question": ["type": "string", "description": "要向用户提出的简短中文问题"],
                        "options": [
                            "type": "array",
                            "items": ["type": "string"],
                            "minItems": 2,
                            "maxItems": 5,
                            "description": "可点击选项，最后一项必须为自定义"
                        ]
                    ],
                    "required": ["question", "options"]
                ]
            ]
        ]]
        let body: [String: Any] = [
            "model": "deepseek-v4-pro",
            "messages": [
                ["role": "system", "content": "你是音乐策展访谈助手。需要用户选择时调用工具，不要输出伪选项文本。"],
                ["role": "user", "content": prompt]
            ],
            "tools": tools,
            "thinking": ["type": "enabled"],
            "reasoning_effort": "high",
            "max_tokens": 700
        ]
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RecommendationServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let server = String(data: data, encoding: .utf8) ?? ""
            throw RecommendationServiceError.message("AI 选择器请求失败（HTTP \(http.statusCode)）\(server.isEmpty ? "" : "：\(server.prefix(220))")")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw RecommendationServiceError.invalidResponse
        }
        if let toolCalls = message["tool_calls"] as? [[String: Any]],
           let function = toolCalls.first?["function"] as? [String: Any],
           function["name"] as? String == "present_choice",
           let arguments = function["arguments"] as? String,
           let argumentsData = arguments.data(using: .utf8),
           let payload = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any],
           let question = payload["question"] as? String,
           var options = payload["options"] as? [String],
           !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            options = options
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != "自定义" }
            options = Array(options.prefix(4)) + ["自定义"]
            return .question(AIPlaylistChoiceRequest(question: question, options: options))
        }
        let content = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if answers.count >= 2, content.uppercased().contains("READY") { return .ready }
        throw RecommendationServiceError.message("AI 没有正确调用选择器，请点击重试")
    }

    /// 使用 V4 Pro 深度思考并通过 SSE 逐步回传思考和最终歌单 JSON。
    func streamPlaylistPlan(
        preferences: AIPlaylistPreferences,
        likedSongs: [Song],
        apiKey: String,
        onDelta: @escaping @Sendable (_ reasoning: String?, _ content: String?) async -> Void
    ) async throws -> AIPlaylistPlan {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecommendationServiceError.missingAPIKey
        }
        let requestedCount = min(max(preferences.trackCount, 1), 30)
        let candidateCount = min(50, requestedCount + 20)
        let likedSongsText = likedSongs.prefix(40).enumerated().map { index, song in
            "\(index + 1). \(song.name) - \(song.artist)"
        }.joined(separator: "\n")
        let prompt = """
        你正在为用户制作一个仅保存在本地的音乐歌单。请认真深度思考用户选择，并且必须把用户真实喜欢的歌曲作为主要审美依据，避免只按情绪标签泛泛推荐。选择可在网易云搜索到的真实歌曲，不要编造歌曲或歌手。
        用户选择：\(preferences.promptDescription)
        用户真实喜欢的歌曲（用于分析审美、歌手、年代、语言、编曲和歌词倾向）：
        \(likedSongsText.isEmpty ? "未读取到" : likedSongsText)

        策展流程：
        1. 先结合喜欢歌曲和用户选择建立候选池，候选池必须恰好 \(candidateCount) 首，绝对不能超过 50 首。
        2. 再从候选池中筛选恰好 \(requestedCount) 首作为最终歌单。
        3. 最终歌曲必须包含与喜欢歌曲相近的风格，同时保留适量新鲜探索，避免清一色同一歌手。
        4. 深度思考中不要编号列举超过 50 首，完整候选只放进最终 JSON 的 candidates。

        最终只能输出 JSON，不要 Markdown：
        {"title":"不超过16字的歌单名","summary":"不超过48字的歌单简介","thoughts":["至少3条具体创作想法"],"candidates":["歌曲名 - 歌手", "..."],"queries":["歌曲名 - 歌手", "..."]}
        candidates 必须恰好 \(candidateCount) 条且不重复；queries 必须恰好 \(requestedCount) 条、只能从 candidates 中选择且不重复。
        """
        let body: [String: Any] = [
            "model": "deepseek-v4-pro",
            "messages": [
                ["role": "system", "content": "你是专业音乐策展人。先深度思考，再给出准确的本地歌单方案。"],
                ["role": "user", "content": prompt]
            ],
            "thinking": ["type": "enabled"],
            "reasoning_effort": "max",
            "stream": true,
            "max_tokens": 12_000,
            "response_format": ["type": "json_object"]
        ]
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
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
        var finishReason: String?
        var reasoningLimiter = NumberedListLimiter(maximumNumber: 50)
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let choice = choices.first else { continue }
            if let value = choice["finish_reason"] as? String { finishReason = value }
            guard let delta = choice["delta"] as? [String: Any] else { continue }
            let reasoning = delta["reasoning_content"] as? String
            let content = delta["content"] as? String
            if let content { finalContent += content }
            let visibleReasoning = reasoning.map { reasoningLimiter.consume($0) }
            if visibleReasoning?.isEmpty == false || content != nil {
                await onDelta(visibleReasoning, content)
            }
        }
        let reasoningTail = reasoningLimiter.flush()
        if !reasoningTail.isEmpty { await onDelta(reasoningTail, nil) }
        if finishReason == "length" {
            throw RecommendationServiceError.message("DeepSeek 输出达到长度限制，最终歌单 JSON 被截断，请重试")
        }
        guard let planData = jsonData(from: finalContent),
              let plan = try? JSONDecoder().decode(AIPlaylistPlan.self, from: planData),
              !plan.title.isEmpty,
              !plan.queries.isEmpty else {
            throw RecommendationServiceError.message(finalContent.isEmpty
                ? "DeepSeek 深度思考完成，但没有返回最终歌单 JSON，请重试"
                : "DeepSeek 返回的最终歌单格式不完整，请重试")
        }
        let candidates = uniqueQueries((plan.candidates ?? []) + plan.queries, limit: 50)
        var selected = uniqueQueries(plan.queries, limit: requestedCount)
        for query in candidates where selected.count < requestedCount && !selected.contains(query) {
            selected.append(query)
        }
        guard selected.count == requestedCount else {
            throw RecommendationServiceError.message("AI 只给出 \(selected.count) 首有效歌曲，少于要求的 \(requestedCount) 首，请重试")
        }
        return AIPlaylistPlan(
            title: plan.title,
            summary: plan.summary,
            thoughts: plan.thoughts,
            candidates: candidates,
            queries: selected
        )
    }

    private func jsonData(from content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else { return nil }
        return String(trimmed[start...end]).data(using: .utf8)
    }

    private func uniqueQueries(_ values: [String], limit: Int) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, seen.insert(key).inserted else { continue }
            result.append(trimmed)
            if result.count == limit { break }
        }
        return result
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

/// DeepSeek 的思考文本仍会逐字显示，但模型若失控列出第 51 首及以后的编号候选，App 会直接丢弃这些行。
private struct NumberedListLimiter {
    let maximumNumber: Int
    private var pending = ""

    init(maximumNumber: Int) {
        self.maximumNumber = maximumNumber
    }

    mutating func consume(_ value: String) -> String {
        pending += value
        var output = ""
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newline])
            pending.removeSubrange(...newline)
            if shouldKeep(line) { output += line + "\n" }
        }
        return output
    }

    mutating func flush() -> String {
        defer { pending = "" }
        return shouldKeep(pending) ? pending : ""
    }

    private func shouldKeep(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty,
              let number = Int(digits),
              number > maximumNumber else { return true }
        let suffix = trimmed.dropFirst(digits.count)
        return !(suffix.hasPrefix(".") || suffix.hasPrefix("、") || suffix.hasPrefix(")") || suffix.hasPrefix("）"))
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
