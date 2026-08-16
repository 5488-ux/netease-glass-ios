import SwiftUI

struct UserDetailView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let user: NeteaseUser
    @State private var detail: NeteaseUser
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedPlaylist: Playlist?

    init(user: NeteaseUser) { self.user = user; _detail = State(initialValue: user) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        AsyncImage(url: detail.avatarURL) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.12) }
                        }
                        .frame(width: 82, height: 82).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(detail.nickname).font(.title3.bold())
                            Text(detail.signature.isEmpty ? "暂无简介" : detail.signature).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    .padding(14)
                    .appGlass(cornerRadius: 22)
                    Text("公开歌单").font(.headline)
                    if isLoading { ProgressView().frame(maxWidth: .infinity).padding(30) }
                    else { LazyVStack(spacing: 10) { ForEach(detail.playlists) { playlist in Button { selectedPlaylist = playlist } label: { PlaylistCard(playlist: playlist) }.buttonStyle(.plain) } } }
                }
                .padding(16)
            }
            .navigationTitle("用户详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task {
                do { detail = try await app.api.loadUser(user) }
                catch { errorMessage = error.localizedDescription }
                isLoading = false
            }
            .sheet(item: $selectedPlaylist) { PlaylistDetailView(playlist: $0) }
            .alert("加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }
}

