import SwiftUI
import UIKit

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
                                Text("查看进度、文件状态和失败诊断")
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
                            AppSectionHeader(title: "下载任务", subtitle: "失败任务可查看完整接口诊断", count: "\(app.downloadManager.tasks.count)")
                            LazyVStack(spacing: 10) {
                                ForEach(app.downloadManager.tasks) { task in
                                    DownloadTaskCard(task: task)
                                }
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
    @State private var selectedFailure: DownloadFailureDetail?
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                RemoteImage(url: task.song.coverURL, size: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.song.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(task.song.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
                Text(task.state.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: task.state))
            }

            ProgressView(value: task.progress)
                .tint(task.state == .failed ? .red : AppPalette.blue)

            HStack(spacing: 10) {
                Text("\(task.progressText) · \(task.downloadedSizeText)/\(task.totalSizeText)")
                Spacer()
                Text(task.speedText)
                Text(task.remainingText)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            if let error = task.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                if let detail = task.failureDetail {
                    Button {
                        selectedFailure = detail
                    } label: {
                        Label("详细错误", systemImage: "exclamationmark.magnifyingglass")
                    }
                    .buttonStyle(.glass)
                    .tint(.red)
                }

                Spacer(minLength: 4)

                if task.state == .downloading {
                    actionButton("暂停", icon: "pause.fill") {
                        app.downloadManager.pause(task)
                    }
                } else if task.state == .paused {
                    actionButton("继续", icon: "play.fill") {
                        app.downloadManager.resume(task)
                    }
                } else if task.state == .failed {
                    actionButton("重试", icon: "arrow.clockwise") {
                        app.downloadManager.retry(task)
                    }
                }

                Button(role: .destructive) {
                    app.downloadManager.delete(task)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("删除任务")
            }
            .font(.caption.weight(.semibold))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlass(cornerRadius: 20)
        .sheet(item: $selectedFailure) { detail in
            DownloadFailureDetailView(detail: detail)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(minHeight: 38)
        }
        .buttonStyle(.glass)
        .tint(AppPalette.blue)
    }

    private func color(for state: DownloadState) -> Color {
        switch state {
        case .completed: return .green
        case .failed: return .red
        case .paused: return .orange
        default: return .primary
        }
    }
}

private struct DownloadFailureDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let detail: DownloadFailureDetail

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("下载失败", systemImage: "exclamationmark.triangle.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.red)

                    detailSection("失败位置") {
                        detailRow("阶段", detail.stage)
                        detailRow("时间", detail.occurredAt.formatted(date: .numeric, time: .standard))
                        detailRow("歌曲 ID", "\(detail.songID)")
                        detailRow("选择音质", detail.selectedQuality)
                        detailRow("登录状态", detail.loginState)
                    }

                    detailSection("服务器与系统错误") {
                        Text(detail.summary)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                        Divider()
                        detailRow("错误域", detail.errorDomain)
                        detailRow("错误码", "\(detail.errorCode)")
                        if let status = detail.httpStatus {
                            detailRow("HTTP 状态", "\(status)")
                        }
                        if let address = detail.requestAddress {
                            detailRow("请求地址", address)
                        }
                    }

                    if !detail.attempts.isEmpty {
                        detailSection("音质尝试记录") {
                            ForEach(detail.attempts) { attempt in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(attempt.encodeType.uppercased()) · \(attempt.level)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AppPalette.blue)
                                    Text(attempt.result)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if attempt.id != detail.attempts.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = detail.reportText
                        } label: {
                            Label("复制诊断", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glassProminent)

                        ShareLink(item: detail.reportText) {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(16)
            }
            .background(AppPageBackground())
            .navigationTitle("详细错误")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlass(cornerRadius: 20)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
