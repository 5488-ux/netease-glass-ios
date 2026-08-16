import SwiftUI

enum HomeSearchMode: String, CaseIterable, Identifiable {
    case song = "单曲"
    case playlist = "歌单"
    case user = "用户"
    var id: String { rawValue }
}

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @State private var mode: HomeSearchMode = .song
    @State private var keyword = ""
    @State private var songs: [Song] = []
    @State private var users: [NeteaseUser] = []
    @State private var selectedPlaylist: Playlist?
    @State private var selectedUser: NeteaseUser?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("发现音乐").font(.largeTitle.bold())
                        Text("搜索、试听，保存你有权限下载的歌曲")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Picker("搜索类型", selection: $mode) {
                        ForEach(HomeSearchMode.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, _ in resetResults() }
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(mode == .playlist ? "粘贴网易云歌单链接" : "搜索网易云音乐", text: $keyword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { search() }
                        if !keyword.isEmpty {
                            Button { keyword = ""; resetResults() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        }
                        Button { search() } label: {
                            if isLoading { ProgressView().controlSize(.small) }
                            else { Text("搜索").font(.subheadline.weight(.semibold)) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .appGlass(cornerRadius: 18)
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedPlaylist) { PlaylistDetailView(playlist: $0) }
            .sheet(item: $selectedUser) { UserDetailView(user: $0) }
            .alert("请求失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    @ViewBuilder private var content: some View {
        if isLoading && songs.isEmpty && users.isEmpty {
            ProgressView("正在搜索…").frame(maxWidth: .infinity).padding(.top, 30)
        } else if mode == .song {
            if songs.isEmpty { emptyState("输入关键词开始搜索", icon: "music.note.list") }
            else { LazyVStack(spacing: 10) { ForEach(songs) { SongCard(song: $0) } } }
        } else if mode == .user {
            if users.isEmpty { emptyState("输入用户名搜索用户", icon: "person.2") }
            else { LazyVStack(spacing: 10) { ForEach(users) { user in Button { selectedUser = user } label: { UserCard(user: user) }.buttonStyle(.plain) } } }
        } else {
            emptyState("粘贴链接后进入歌单详情", icon: "rectangle.stack")
        }
    }

    private func emptyState(_ title: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 55)
    }

    private func search() {
        let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                switch mode {
                case .song: songs = try await app.api.searchSongs(value)
                case .user: users = try await app.api.searchUsers(value)
                case .playlist:
                    guard let id = Self.playlistID(from: value) else { throw NeteaseAPIError.message("没有识别到有效的网易云歌单链接") }
                    selectedPlaylist = try await app.api.playlist(id: id)
                }
            } catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }

    private func resetResults() { songs = []; users = []; selectedPlaylist = nil }

    private static func playlistID(from value: String) -> Int? {
        guard let components = URLComponents(string: value), let id = components.queryItems?.first(where: { $0.name == "id" })?.value else {
            let pattern = #"playlist[=/](\d+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), let range = Range(match.range(at: 1), in: value) else { return nil }
            return Int(value[range])
        }
        return Int(id)
    }
}

