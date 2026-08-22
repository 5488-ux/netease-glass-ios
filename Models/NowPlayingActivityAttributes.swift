import ActivityKit
import Foundation

struct NowPlayingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var elapsedTime: Double
        var duration: Double
        var coverThumbnail: Data?
    }

    let songID: Int
}
