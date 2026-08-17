import Combine
import Foundation
import UIKit

enum DownloadEnqueueResult {
    case queued
    case restarted
    case alreadyActive
    case alreadyCompleted
}

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []
    @Published var errorMessage: String?
    var errorHandler: ((String) -> Void)?

    private let api: NeteaseAPI
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60 * 30
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private var activeTasks: [Int: UUID] = [:]
    private var lastProgress: [UUID: (date: Date, bytes: Int64)] = [:]
    private var attemptHistory: [UUID: [DownloadAttemptDetail]] = [:]

    init(api: NeteaseAPI) {
        self.api = api
        super.init()
        loadCompletedTasks()
        createMusicDirectory()
    }

    @discardableResult
    func enqueue(song: Song) -> DownloadEnqueueResult {
        if let existing = tasks.first(where: { $0.song.id == song.id }) {
            switch existing.state {
            case .failed:
                retry(existing)
                return .restarted
            case .completed:
                return .alreadyCompleted
            case .waiting, .downloading, .paused:
                return .alreadyActive
            }
        }

        let id = UUID()
        tasks.insert(
            DownloadTask(
                id: id,
                song: song,
                state: .waiting,
                progress: 0,
                downloadedBytes: 0,
                totalBytes: 0,
                speedBytesPerSecond: 0,
                estimatedRemaining: nil,
                errorMessage: nil,
                failureDetail: nil,
                fileURL: nil,
                resumeData: nil
            ),
            at: 0
        )
        Task { await begin(id: id, song: song) }
        return .queued
    }

    func task(for songID: Int) -> DownloadTask? {
        tasks.first(where: { $0.song.id == songID })
    }

    func pause(_ task: DownloadTask) {
        guard let taskIdentifier = activeTasks.first(where: { $0.value == task.id })?.key else {
            update(id: task.id) { $0.state = .paused }
            persistCompletedTasks()
            return
        }

        session.getAllTasks { [weak self] tasks in
            guard let download = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first(where: { $0.taskIdentifier == taskIdentifier }) else { return }
            download.cancel(byProducingResumeData: { resumeData in
                Task { @MainActor in
                    guard let self else { return }
                    self.activeTasks[taskIdentifier] = nil
                    self.update(id: task.id) { item in
                        item.state = .paused
                        item.resumeData = resumeData
                        item.errorMessage = nil
                        item.failureDetail = nil
                    }
                    self.persistCompletedTasks()
                }
            })
        }
    }

    func resume(_ task: DownloadTask) {
        guard task.state == .paused || task.state == .failed else { return }
        update(id: task.id) {
            $0.state = .waiting
            $0.errorMessage = nil
            $0.failureDetail = nil
        }
        Task { await begin(id: task.id, song: task.song, resumeData: task.resumeData) }
    }

    func retry(_ task: DownloadTask) {
        update(id: task.id) {
            $0.state = .waiting
            $0.progress = 0
            $0.downloadedBytes = 0
            $0.totalBytes = 0
            $0.speedBytesPerSecond = 0
            $0.estimatedRemaining = nil
            $0.errorMessage = nil
            $0.failureDetail = nil
            $0.resumeData = nil
        }
        Task { await begin(id: task.id, song: task.song) }
    }

    func delete(_ task: DownloadTask) {
        if let pair = activeTasks.first(where: { $0.value == task.id }) {
            session.getAllTasks { all in
                all.first(where: { $0.taskIdentifier == pair.key })?.cancel()
            }
            activeTasks[pair.key] = nil
        }
        if let fileURL = task.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        attemptHistory[task.id] = nil
        lastProgress[task.id] = nil
        tasks.removeAll { $0.id == task.id }
        persistCompletedTasks()
    }

    private func begin(id: UUID, song: Song, resumeData: Data? = nil) async {
        let preferred = UserDefaults.standard.string(forKey: "player.quality") ?? AudioQuality.standard.rawValue
        let attempts = mp3Attempts(for: preferred)
        attemptHistory[id] = []
        var lastError: Error?

        for attempt in attempts {
            do {
                let permission = try await api.resolveDownload(for: song, encodeType: attempt.encodeType, level: attempt.level)
                appendAttempt(id: id, encodeType: attempt.encodeType, level: attempt.level, result: "成功取得音频地址：\(safeAddress(permission.url))")

                let task: URLSessionDownloadTask
                if let resumeData, !resumeData.isEmpty {
                    task = session.downloadTask(withResumeData: resumeData)
                } else {
                    var request = URLRequest(url: permission.url)
                    request.timeoutInterval = 45
                    request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
                    request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                    var fullCookie = api.hasCookie ? api.currentCookie + "; " : ""
                    fullCookie += api.deviceCookie
                    request.setValue(fullCookie, forHTTPHeaderField: "Cookie")
                    task = session.downloadTask(with: request)
                }

                activeTasks[task.taskIdentifier] = id
                update(id: id) { item in
                    item.state = .downloading
                    item.totalBytes = max(item.totalBytes, permission.totalBytes)
                    item.resumeData = nil
                    item.errorMessage = nil
                    item.failureDetail = nil
                }
                task.resume()
                return
            } catch {
                lastError = error
                appendAttempt(
                    id: id,
                    encodeType: attempt.encodeType,
                    level: attempt.level,
                    result: NeteaseAPIError.diagnosticDescription(for: error)
                )
            }
        }

        let error = lastError ?? NeteaseAPIError.message("全部 MP3 音质都没有返回下载地址")
        fail(
            id: id,
            stage: "获取网易云下载地址",
            summary: NeteaseAPIError.userMessage(for: error),
            error: error
        )
    }

    /// 文件固定保存为 MP3，因此下载链路只请求 MP3，不能把 FLAC/AAC 改扩展名冒充 MP3。
    private func mp3Attempts(for preferred: String) -> [(encodeType: String, level: String)] {
        if preferred == AudioQuality.standard.rawValue {
            return [("mp3", "standard"), ("mp3", "exhigh")]
        }
        return [("mp3", "exhigh"), ("mp3", "standard")]
    }

    private func appendAttempt(id: UUID, encodeType: String, level: String, result: String) {
        attemptHistory[id, default: []].append(
            DownloadAttemptDetail(encodeType: encodeType, level: level, result: result)
        )
    }

    private func update(id: UUID, _ body: (inout DownloadTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        body(&tasks[index])
    }

    private func fail(
        id: UUID,
        stage: String,
        summary: String,
        error: Error? = nil,
        httpStatus: Int? = nil,
        requestURL: URL? = nil
    ) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let nsError = error.map { $0 as NSError }
        let preferred = UserDefaults.standard.string(forKey: "player.quality") ?? AudioQuality.standard.rawValue
        let detail = DownloadFailureDetail(
            stage: stage,
            summary: summary,
            songID: task.song.id,
            selectedQuality: AudioQuality(rawValue: preferred)?.title ?? preferred,
            loginState: api.hasCookie ? "已登录，Cookie 已保存" : "未登录或 Cookie 为空",
            errorDomain: nsError?.domain ?? (httpStatus == nil ? "NeteaseGlass.Download" : "HTTPURLResponse"),
            errorCode: nsError?.code ?? httpStatus ?? -1,
            httpStatus: httpStatus,
            requestAddress: requestURL.map(safeAddress),
            attempts: attemptHistory[id] ?? []
        )

        update(id: id) { item in
            item.state = .failed
            item.speedBytesPerSecond = 0
            item.estimatedRemaining = nil
            item.errorMessage = summary
            item.failureDetail = detail
        }
        let alert = "「\(task.song.name)」下载失败，请在下载页面查看详细错误"
        errorMessage = alert
        errorHandler?(alert)
        persistCompletedTasks()
    }

    private func createMusicDirectory() {
        try? FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
    }

    private var musicDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "Music", directoryHint: .isDirectory)
    }

    private func loadCompletedTasks() {
        guard let data = UserDefaults.standard.data(forKey: "download.tasks"),
              let decoded = try? JSONDecoder().decode([DownloadTask].self, from: data) else { return }
        tasks = decoded
    }

    private func persistCompletedTasks() {
        let saved = tasks.filter { $0.state == .completed || $0.state == .failed || $0.state == .paused }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "download.tasks")
        }
    }

    private func finish(id: UUID, location: URL) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let destination = musicDirectory.appending(path: FilenameSanitizer.makeSongFilename(task.song))
        let finalURL = uniqueURL(destination)

        do {
            let bytes = try Data(contentsOf: location)
            guard isMP3(bytes) else {
                throw NeteaseAPIError.invalidResponse("下载内容不是有效 MP3，收到 \(ByteFormatter.string(from: Int64(bytes.count))) 数据；服务器可能返回了错误页或其他音频格式")
            }
            let coverData = await api.imageData(url: task.song.coverURL)
            let tagged = MP3MetadataWriter.addTags(to: bytes, song: task.song, coverData: coverData)
            try tagged.write(to: finalURL, options: .atomic)
            try? FileManager.default.removeItem(at: location)
            update(id: id) { item in
                item.state = .completed
                item.progress = 1
                item.fileURL = finalURL
                item.downloadedBytes = Int64(tagged.count)
                item.totalBytes = Int64(tagged.count)
                item.speedBytesPerSecond = 0
                item.estimatedRemaining = 0
                item.errorMessage = nil
                item.failureDetail = nil
            }
            attemptHistory[id] = nil
            lastProgress[id] = nil
            persistCompletedTasks()
        } catch {
            fail(
                id: id,
                stage: "校验 MP3 并写入文件",
                summary: NeteaseAPIError.userMessage(for: error),
                error: error
            )
        }
    }

    private func isMP3(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        if data.starts(with: [0x49, 0x44, 0x33]) { return true }
        let bytes = [UInt8](data.prefix(16_384))
        guard bytes.count >= 2 else { return false }
        return (0..<(bytes.count - 1)).contains { index in
            bytes[index] == 0xFF && (bytes[index + 1] & 0xE0) == 0xE0
        }
    }

    private func safeAddress(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.host ?? "无法解析地址"
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? "\(url.scheme ?? "https")://\(url.host ?? "未知主机")\(url.path)"
    }

    private func uniqueURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for number in 2...999 {
            let candidate = url.deletingLastPathComponent().appending(path: "\(base) (\(number)).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url.deletingLastPathComponent().appending(path: "\(UUID().uuidString).\(ext)")
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor in
            guard let id = self.activeTasks[downloadTask.taskIdentifier] else { return }
            self.activeTasks[downloadTask.taskIdentifier] = nil

            if let response = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                let message = "音频服务器返回 HTTP \(response.statusCode)，没有取得有效文件"
                self.fail(
                    id: id,
                    stage: "从音频 CDN 下载文件",
                    summary: message,
                    httpStatus: response.statusCode,
                    requestURL: downloadTask.originalRequest?.url
                )
                return
            }
            await self.finish(id: id, location: location)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard let id = self.activeTasks[downloadTask.taskIdentifier] else { return }
            let now = Date()
            let previous = self.lastProgress[id]
            let delta = max(0, totalBytesWritten - (previous?.bytes ?? 0))
            let interval = max(0.1, now.timeIntervalSince(previous?.date ?? now))
            let speed = Int64(Double(delta) / interval)
            self.lastProgress[id] = (now, totalBytesWritten)
            self.update(id: id) { item in
                item.downloadedBytes = totalBytesWritten
                item.totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : item.totalBytes
                item.progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
                item.speedBytesPerSecond = speed
                if speed > 0 && totalBytesExpectedToWrite > 0 {
                    item.estimatedRemaining = Double(totalBytesExpectedToWrite - totalBytesWritten) / Double(speed)
                }
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            guard let id = self.activeTasks[task.taskIdentifier] else { return }
            self.activeTasks[task.taskIdentifier] = nil
            let nsError = error as NSError

            if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                self.update(id: id) { item in
                    item.state = .paused
                    item.resumeData = resumeData
                    item.errorMessage = nil
                    item.failureDetail = nil
                }
                self.persistCompletedTasks()
            } else {
                self.fail(
                    id: id,
                    stage: "传输音频文件",
                    summary: NeteaseAPIError.userMessage(for: error),
                    error: error,
                    requestURL: task.originalRequest?.url
                )
            }
        }
    }
}
