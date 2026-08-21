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
