import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("下载").font(.largeTitle.bold())
                        Spacer()
                        Text("\(app.downloadManager.tasks.count) 个任务").font(.caption).foregroundStyle(.secondary)
                    }
                    if app.downloadManager.tasks.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "arrow.down.circle").font(.largeTitle).foregroundStyle(.secondary)
                            Text("还没有下载任务").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 120)
                    } else {
                        LazyVStack(spacing: 10) { ForEach(app.downloadManager.tasks) { task in DownloadTaskCard(task: task) } }
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct DownloadTaskCard: View {
    @EnvironmentObject private var app: AppModel
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                RemoteImage(url: task.song.coverURL, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.song.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(task.song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(task.state.rawValue).font(.caption.weight(.medium)).foregroundStyle(color(for: task.state))
            }
            ProgressView(value: task.progress)
                .tint(task.state == .failed ? .red : .accentColor)
            HStack(spacing: 10) {
                Text("\(task.progressText) · \(task.downloadedSizeText)/\(task.totalSizeText)")
                Spacer()
                Text(task.speedText)
                Text(task.remainingText)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            HStack {
                if let error = task.errorMessage { Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2) }
                Spacer()
                if task.state == .downloading {
                    Button { app.downloadManager.pause(task) } label: { Label("暂停", systemImage: "pause.fill") }
                } else if task.state == .paused || task.state == .failed {
                    Button { app.downloadManager.resume(task) } label: { Label(task.state == .failed ? "重试" : "继续", systemImage: task.state == .failed ? "arrow.clockwise" : "play.fill") }
                }
                Button(role: .destructive) { app.downloadManager.delete(task) } label: { Image(systemName: "trash") }
                    .accessibilityLabel("删除任务")
            }
            .font(.caption.weight(.medium))
        }
        .padding(13)
        .appGlass(cornerRadius: 18)
    }

    private func color(for state: DownloadState) -> Color {
        switch state { case .completed: return .green; case .failed: return .red; case .paused: return .orange; default: return .primary }
    }
}

