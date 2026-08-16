import Foundation

struct Playlist: Codable, Hashable, Identifiable {
    let id: Int
    var name: String
    var creatorName: String
    var description: String
    var trackCount: Int
    var coverURL: URL?
    var songs: [Song] = []
}

