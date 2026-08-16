import Foundation

enum DownloadState: String, Codable, CaseIterable {
    case waiting = "等待下载"
    case downloading = "下载中"
    case paused = "已暂停"
    case completed = "下载完成"
    case failed = "下载失败"
}

struct DownloadTask: Codable, Identifiable, Hashable {
    let id: UUID
    let song: Song
    var state: DownloadState
    var progress: Double
    var downloadedBytes: Int64
    var totalBytes: Int64
    var speedBytesPerSecond: Int64
    var estimatedRemaining: TimeInterval?
    var errorMessage: String?
    var fileURL: URL?
    var resumeData: Data?

    var progressText: String { "\(Int(progress * 100))%" }
    var downloadedSizeText: String { ByteFormatter.string(from: downloadedBytes) }
    var totalSizeText: String { totalBytes > 0 ? ByteFormatter.string(from: totalBytes) : "未知大小" }
    var speedText: String { speedBytesPerSecond > 0 ? "\(ByteFormatter.string(from: speedBytesPerSecond))/秒" : "--" }
    var remainingText: String {
        guard let remaining = estimatedRemaining, remaining.isFinite else { return "--" }
        return remaining < 60 ? "约 \(Int(remaining)) 秒" : "约 \(Int(remaining / 60)) 分钟"
    }
}

enum ByteFormatter {
    static func string(from bytes: Int64) -> String {
        let value = Double(max(bytes, 0))
        if value < 1024 { return "\(Int(value)) B" }
        if value < 1024 * 1024 { return String(format: "%.1f KB", value / 1024) }
        if value < 1024 * 1024 * 1024 { return String(format: "%.1f MB", value / 1024 / 1024) }
        return String(format: "%.2f GB", value / 1024 / 1024 / 1024)
    }
}

