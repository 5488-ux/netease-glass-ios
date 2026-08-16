import Foundation

struct NeteaseUser: Codable, Hashable, Identifiable {
    let id: Int
    var nickname: String
    var signature: String
    var avatarURL: URL?
    var level: Int?
    var vipType: Int?
    var playlists: [Playlist] = []

    var isVIP: Bool { (vipType ?? 0) > 0 }
}

