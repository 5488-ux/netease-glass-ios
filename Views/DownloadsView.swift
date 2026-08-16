import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                AppPageBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 13) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .fill(AppPalette.orange.opacity(0.13))
                                    .frame(width: 58, height: 58)
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 25, weight: .bold))
                                    .foregroundStyle(AppPalette.orange)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("下载")
                                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                                Text("查看进度，管理已经保存的音乐")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)
                            Text("\(app.downloadManager.tasks.count)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        }
                        .padding(.vertical, 8)

                        if app.downloadManager.tasks.isEmpty {
                            emptyState
                        } else {
                            AppSectionHeader(title: "下载任务", subtitle: "完成后仍会保留记录", count: "\(app.downloadManager.tasks.count)")
                            LazyVStack(spacing: 10) {
                                ForEach(app.downloadManager.tasks) { task in DownloadTaskCard(task: task) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 72, height: 72)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(AppPalette.orange)
            }
            Text("还没有下载任务")
                .font(.headline)
            Text("从主页搜索歌曲后，下载任务会出现在这里")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .appGlass(cornerRadius: 24)
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
