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
            ZStack {
                AppPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("发现")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                Text("搜索、试听并保存你有权限下载的音乐")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "waveform")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, height: 42)
                                .appGlass(cornerRadius: 14)
                        }
                        modeSelector
                        searchField
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
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

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(HomeSearchMode.allCases) { item in
                Button {
                    mode = item
                    resetResults()
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(mode == item ? .semibold : .regular))
                        .foregroundStyle(mode == item ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(mode == item ? Color.primary.opacity(0.10) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .appGlass(cornerRadius: 18)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(mode == .playlist ? "粘贴网易云歌单链接" : "搜索网易云音乐", text: $keyword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { search() }
            if !keyword.isEmpty {
                Button { keyword = ""; resetResults() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Button { search() } label: {
                Group {
                    if isLoading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.right") }
                }
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("搜索")
        }
        .padding(11)
        .appGlass(cornerRadius: 20)
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
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 45)
        .appGlass(cornerRadius: 22)
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
