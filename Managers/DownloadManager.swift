import Foundation
import Combine
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
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private var activeTasks: [Int: UUID] = [:]
    private var lastProgress: [UUID: (date: Date, bytes: Int64)] = [:]

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
        tasks.insert(DownloadTask(id: id, song: song, state: .waiting, progress: 0, downloadedBytes: 0, totalBytes: 0, speedBytesPerSecond: 0, estimatedRemaining: nil, errorMessage: nil, fileURL: nil, resumeData: nil), at: 0)
        Task { await begin(id: id, song: song) }
        return .queued
    }

    func task(for songID: Int) -> DownloadTask? {
        tasks.first(where: { $0.song.id == songID })
    }

    func pause(_ task: DownloadTask) {
        guard let taskIdentifier = activeTasks.first(where: { $0.value == task.id })?.key else {
            update(id: task.id) { $0.state = .paused }
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
                    }
                    self.persistCompletedTasks()
                }
            })
        }
    }

    func resume(_ task: DownloadTask) {
        guard task.state == .paused || task.state == .failed else { return }
        update(id: task.id) { $0.state = .waiting; $0.errorMessage = nil }
        Task { await begin(id: task.id, song: task.song, resumeData: task.resumeData) }
    }

    func retry(_ task: DownloadTask) {
        update(id: task.id) { $0.state = .waiting; $0.progress = 0; $0.downloadedBytes = 0; $0.totalBytes = 0; $0.errorMessage = nil; $0.resumeData = nil }
        Task { await begin(id: task.id, song: task.song) }
    }

    func delete(_ task: DownloadTask) {
        if let pair = activeTasks.first(where: { $0.value == task.id }) {
            session.getAllTasks { all in all.first(where: { $0.taskIdentifier == pair.key })?.cancel() }
            activeTasks[pair.key] = nil
        }
        if let fileURL = task.fileURL { try? FileManager.default.removeItem(at: fileURL) }
        tasks.removeAll { $0.id == task.id }
        persistCompletedTasks()
    }

    private func begin(id: UUID, song: Song, resumeData: Data? = nil) async {
        do {
            let permission = try await api.resolveDownload(for: song)
            var task: URLSessionDownloadTask
            if let resumeData, !resumeData.isEmpty { task = session.downloadTask(withResumeData: resumeData) }
            else {
                var request = URLRequest(url: permission.url)
                request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                task = session.downloadTask(with: request)
            }
            activeTasks[task.taskIdentifier] = id
            update(id: id) { item in item.state = .downloading; item.totalBytes = max(item.totalBytes, permission.totalBytes); item.resumeData = nil }
            task.resume()
        } catch {
            let message = NeteaseAPIError.userMessage(for: error)
            update(id: id) { item in item.state = .failed; item.errorMessage = message }
            errorMessage = message
            errorHandler?(message)
        }
    }

    private func update(id: UUID, _ body: (inout DownloadTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        body(&tasks[index])
    }

    private func createMusicDirectory() {
        try? FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
    }

    private var musicDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Music", directoryHint: .isDirectory)
    }

    private func loadCompletedTasks() {
        guard let data = UserDefaults.standard.data(forKey: "download.tasks"), let decoded = try? JSONDecoder().decode([DownloadTask].self, from: data) else { return }
        tasks = decoded
    }

    private func persistCompletedTasks() {
        let saved = tasks.filter { $0.state == .completed || $0.state == .failed || $0.state == .paused }
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "download.tasks") }
    }

    private func finish(id: UUID, location: URL) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let destination = musicDirectory.appending(path: FilenameSanitizer.makeSongFilename(task.song))
        let finalURL = uniqueURL(destination)
        do {
            let bytes = try Data(contentsOf: location)
            let coverData = await api.imageData(url: task.song.coverURL)
            let tagged = MP3MetadataWriter.addTags(to: bytes, song: task.song, coverData: coverData)
            try tagged.write(to: finalURL, options: .atomic)
            try? FileManager.default.removeItem(at: location)
            update(id: id) { item in item.state = .completed; item.progress = 1; item.fileURL = finalURL; item.downloadedBytes = Int64(tagged.count); item.totalBytes = Int64(tagged.count); item.estimatedRemaining = 0; item.errorMessage = nil }
            persistCompletedTasks()
        } catch {
            let message = NeteaseAPIError.userMessage(for: error)
            update(id: id) { item in item.state = .failed; item.errorMessage = message }
            errorHandler?(message)
        }
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
            if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                let message = "音频服务器返回错误（HTTP \(response.statusCode)）"
                self.update(id: id) { item in item.state = .failed; item.errorMessage = message }
                self.errorHandler?(message)
                self.persistCompletedTasks()
                return
            }
            await self.finish(id: id, location: location)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
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
                if speed > 0 && totalBytesExpectedToWrite > 0 { item.estimatedRemaining = Double(totalBytesExpectedToWrite - totalBytesWritten) / Double(speed) }
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
                self.update(id: id) { item in item.state = .paused; item.resumeData = resumeData; item.errorMessage = nil }
            } else {
                let message = NeteaseAPIError.userMessage(for: error)
                self.update(id: id) { item in item.state = .failed; item.errorMessage = message }
                self.errorHandler?(message)
            }
            self.persistCompletedTasks()
        }
    }
}
