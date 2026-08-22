import Foundation

struct SongComment: Identifiable, Hashable {
    let id: Int
    let nickname: String
    let avatarURL: URL?
    let content: String
    let timeText: String
    let location: String?
    let likedCount: Int
    let repliedNickname: String?
    let repliedContent: String?
}

struct SongCommentPage {
    let hotComments: [SongComment]
    let comments: [SongComment]
    let total: Int
    let hasMore: Bool
}
