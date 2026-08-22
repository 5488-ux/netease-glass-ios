import SwiftUI

struct SongCommentsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let song: Song

    @State private var hotComments: [SongComment] = []
    @State private var comments: [SongComment] = []
    @State private var total = 0
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let pageSize = 20

    var body: some View {
        NavigationStack {
            ZStack {
                AppPageBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        songHeader

                        if isLoading && comments.isEmpty {
                            ProgressView("正在读取网易云评论…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 46)
                        } else if let errorMessage, comments.isEmpty && hotComments.isEmpty {
                            ContentUnavailableView {
                                Label("评论加载失败", systemImage: "exclamationmark.bubble.fill")
                            } description: {
                                Text(errorMessage)
                            } actions: {
                                Button("重新加载") { Task { await loadComments(reset: true) } }
                                    .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            if !hotComments.isEmpty {
                                sectionTitle("热门评论", count: hotComments.count)
                                ForEach(hotComments) { comment in
                                    commentRow(comment, isHot: true)
                                }
                            }

                            sectionTitle("全部评论", count: total)
                            if comments.isEmpty {
                                ContentUnavailableView("暂无评论", systemImage: "bubble.left")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else {
                                ForEach(comments) { comment in
                                    commentRow(comment, isHot: false)
                                }
                            }

                            if hasMore {
                                Button {
                                    Task { await loadComments(reset: false) }
                                } label: {
                                    if isLoading {
                                        ProgressView().frame(maxWidth: .infinity)
                                    } else {
                                        Label("加载更多评论", systemImage: "arrow.down.circle")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isLoading)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .scrollIndicators(.hidden)
                .refreshable { await loadComments(reset: true) }
            }
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: song.id) { await loadComments(reset: true) }
        }
    }

    private var songHeader: some View {
        HStack(spacing: 12) {
            RemoteImage(url: song.coverURL, size: 58)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(song.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if total > 0 {
                    Text("网易云音乐 · \(total) 条评论")
                        .font(.caption)
                        .foregroundStyle(AppPalette.blue)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appGlass(cornerRadius: 20)
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func commentRow(_ comment: SongComment, isHot: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            RemoteImage(url: comment.avatarURL, size: 42)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(comment.nickname)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if isHot {
                        Text("热")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red, in: Capsule())
                    }
                    Spacer(minLength: 4)
                    if comment.likedCount > 0 {
                        Label("\(comment.likedCount)", systemImage: "hand.thumbsup")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(comment.content)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if let repliedContent = comment.repliedContent {
                    Text("回复 @\(comment.repliedNickname ?? "用户")：\(repliedContent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack(spacing: 6) {
                    Text(comment.timeText)
                    if let location = comment.location, !location.isEmpty {
                        Text("·")
                        Text(location)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .appGlass(cornerRadius: 18)
    }

    @MainActor
    private func loadComments(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let offset = reset ? 0 : comments.count
            let page = try await app.api.songComments(songID: song.id, offset: offset, limit: pageSize)
            if reset {
                hotComments = page.hotComments
                comments = page.comments
            } else {
                let existing = Set(comments.map(\.id))
                comments.append(contentsOf: page.comments.filter { !existing.contains($0.id) })
            }
            total = page.total
            hasMore = page.hasMore && comments.count < page.total
        } catch {
            errorMessage = NeteaseAPIError.userMessage(for: error)
        }
    }
}
