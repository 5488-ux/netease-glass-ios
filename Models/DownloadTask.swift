import Foundation

enum DownloadState: String, Codable, CaseIterable {
    case waiting = "等待下载"
    case downloading = "下载中"
    case paused = "已暂停"
    case completed = "下载完成"
    case failed = "下载失败"
}

struct DownloadAttemptDetail: Codable, Identifiable, Hashable {
    let id: UUID
    let encodeType: String
    let level: String
    let result: String

    init(encodeType: String, level: String, result: String) {
        id = UUID()
        self.encodeType = encodeType
        self.level = level
        self.result = result
    }
}

struct DownloadFailureDetail: Codable, Identifiable, Hashable {
    let id: UUID
    let occurredAt: Date
    let stage: String
    let summary: String
    let songID: Int
    let selectedQuality: String
    let loginState: String
    let errorDomain: String
    let errorCode: Int
    let httpStatus: Int?
    let requestAddress: String?
    let attempts: [DownloadAttemptDetail]

    init(
        stage: String,
        summary: String,
        songID: Int,
        selectedQuality: String,
        loginState: String,
        errorDomain: String,
        errorCode: Int,
        httpStatus: Int? = nil,
        requestAddress: String? = nil,
        attempts: [DownloadAttemptDetail] = []
    ) {
        id = UUID()
        occurredAt = Date()
        self.stage = stage
        self.summary = summary
        self.songID = songID
        self.selectedQuality = selectedQuality
        self.loginState = loginState
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.httpStatus = httpStatus
        self.requestAddress = requestAddress
        self.attempts = attempts
    }

    var reportText: String {
        var lines = [
            "下载失败诊断",
            "时间：\(occurredAt.formatted(date: .numeric, time: .standard))",
            "阶段：\(stage)",
            "歌曲 ID：\(songID)",
            "选择音质：\(selectedQuality)",
            "登录状态：\(loginState)",
            "错误域：\(errorDomain)",
            "错误码：\(errorCode)",
            "原因：\(summary)"
        ]
        if let httpStatus { lines.append("HTTP 状态：\(httpStatus)") }
        if let requestAddress { lines.append("请求地址：\(requestAddress)") }
        if !attempts.isEmpty {
            lines.append("音质尝试：")
            lines.append(contentsOf: attempts.map { "- \($0.encodeType)/\($0.level)：\($0.result)" })
        }
        return lines.joined(separator: "\n")
    }
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
    var failureDetail: DownloadFailureDetail? = nil
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
