import Foundation

struct PlatformTrack: Identifiable, Hashable {
    let source: String
    let name: String
    let artist: String
    let artworkURL: URL?

    var id: String { "\(source)-\(name)-\(artist)" }
}

struct AIRecommendationProfile: Codable, Equatable {
    let summary: String
    let keywords: [String]
}

/// 仅保存在本机的 AI 歌单偏好，不会写入网易云音乐。
struct AIPlaylistPreferences: Codable, Hashable {
    var mood: String
    var scene: String
    var energy: String
    var language: String
    var trackCount: Int
    var customDirection: String?

    var promptDescription: String {
        "情绪：\(mood)；场景：\(scene)；能量：\(energy)；语言偏好：\(language)；目标曲数：\(trackCount)；自定义：\(customDirection?.isEmpty == false ? customDirection! : "无")"
    }
}

struct AIPlaylistPlan: Codable, Equatable {
    let title: String
    let summary: String
    let thoughts: [String]
    let queries: [String]
}

struct AIPlaylistChoiceAnswer: Codable, Hashable, Identifiable {
    let id: UUID
    let question: String
    let answer: String

    init(question: String, answer: String) {
        id = UUID()
        self.question = question
        self.answer = answer
    }
}

struct AIPlaylistChoiceRequest: Equatable, Identifiable {
    let id = UUID()
    let question: String
    let options: [String]
}

enum AIPlaylistChoiceStep: Equatable {
    case question(AIPlaylistChoiceRequest)
    case ready
}

struct LocalAIPlaylist: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let preferences: AIPlaylistPreferences
    let title: String
    let summary: String
    let thoughts: [String]
    let songs: [Song]
}
