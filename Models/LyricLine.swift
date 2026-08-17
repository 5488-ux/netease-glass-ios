import Foundation

/// 一行带时间戳的歌词
struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

/// 解析标准 LRC 歌词文本（支持 [mm:ss.xx] 与 [hh:mm:ss] 标签）
enum LyricsParser {
    static func parse(_ lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        let tagPattern = #"\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
        for rawLine in lrc.components(separatedBy: .newlines) {
            var rest = rawLine
            var times: [TimeInterval] = []
            while let range = rest.range(of: tagPattern, options: .regularExpression) {
                let tag = String(rest[range])
                rest.removeSubrange(range)
                if let parsed = Self.time(from: tag) { times.append(parsed) }
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for time in times { result.append(LyricLine(time: time, text: text)) }
        }
        return result.sorted { $0.time < $1.time }
    }

    /// 从 [mm:ss.xx] 或 [hh:mm:ss] 标签解析为秒数
    static func time(from tag: String) -> TimeInterval? {
        let inner = tag.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let parts = inner.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }
}
