import Foundation

struct Song: Codable, Hashable, Identifiable {
    let id: Int
    var name: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var coverURL: URL?
    var fee: Int
    var isVIP: Bool
    var size: Int64?
    var bitrate: Int?

    var durationText: String {
        let total = Int(duration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

