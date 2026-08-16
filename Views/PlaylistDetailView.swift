import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var detail: Playlist
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(playlist: Playlist) {
        self.playlist = playlist
        _detail = State(initialValue: playlist)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        RemoteImage(url: detail.coverURL, size: 104)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(detail.name).font(.title3.bold()).lineLimit(3)
                            Text(detail.creatorName).font(.subheadline).foregroundStyle(.secondary)
                            Text("\(detail.songs.count > 0 ? detail.songs.count : detail.trackCount) 首歌曲")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .appGlass(cornerRadius: 22)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !detail.description.isEmpty {
                        Text(detail.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if isLoading {
                        ProgressView("正在加载歌曲…")
                            .tint(AppPalette.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else if detail.songs.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "music.note.list")
                                .font(.title2)
                                .foregroundStyle(AppPalette.blue)
                            Text("暂时没有可显示的歌曲")
                                .font(.subheadline.weight(.semibold))
                            Text("点击右上角完成后重新进入，或检查网易云登录状态。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(detail.songs) { SongCard(song: $0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
            .navigationTitle("歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task {
                guard detail.songs.isEmpty else { return }
                isLoading = true
                do {
                    detail = try await app.api.playlist(id: detail.id)
                } catch {
                    errorMessage = NeteaseAPIError.userMessage(for: error)
                }
                isLoading = false
            }
            .alert("加载歌单失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}
