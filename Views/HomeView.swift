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
    @State private var showingLogin = false
    @State private var loginRequired = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppPageBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        header
                        if !app.loginManager.isLoggedIn {
                            loginCard
                        }
                        searchSection
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedPlaylist) { PlaylistDetailView(playlist: $0) }
            .sheet(item: $selectedUser) { UserDetailView(user: $0) }
            .sheet(isPresented: $showingLogin) { QRLoginView() }
            .alert("需要登录", isPresented: $loginRequired) {
                Button("去登录") { showingLogin = true }
                Button("取消", role: .cancel) { }
            } message: {
                Text("登录网易云音乐后才能搜索歌曲、歌单和用户。")
            }
            .alert("请求失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .onAppear { prepareLikeLayoutCheckIfNeeded() }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(AppPalette.blue.opacity(0.13))
                    .frame(width: 58, height: 58)
                Image(systemName: "waveform")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(AppPalette.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("发现音乐")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                Text("搜索、试听并保存有权限下载的音乐")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button { openAccount() } label: {
                accountButtonContent
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.violet)
            .accessibilityLabel(app.loginManager.isLoggedIn ? "账号" : "登录")
        }
        .padding(.vertical, 8)
    }

    private var loginCard: some View {
        Button { showingLogin = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "qrcode")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppPalette.blue)
                    .frame(width: 40, height: 40)
                    .background(AppPalette.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("登录网易云音乐")
                        .font(.subheadline.weight(.semibold))
                    Text("扫码后才能搜索和检查歌曲下载权限")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .appGlass(cornerRadius: 20)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader(
                title: "搜索",
                subtitle: app.loginManager.isLoggedIn ? "选择类型后输入关键词" : "登录后解锁网易云搜索"
            )
            modeSelector
            searchField
        }
        .padding(16)
        .appGlass(cornerRadius: 24)
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
                        .foregroundStyle(mode == item ? AppPalette.blue : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(mode == item ? AppPalette.blue.opacity(0.13) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.045), in: Capsule())
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(AppPalette.blue)
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
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.blue)
            .background(AppPalette.blue.opacity(0.13), in: Circle())
            .accessibilityLabel("搜索")
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder private var content: some View {
        if isLoading && songs.isEmpty && users.isEmpty {
            ProgressView("正在搜索…").frame(maxWidth: .infinity).padding(.top, 30)
        } else if mode == .song {
            if songs.isEmpty { emptyState("输入关键词开始搜索", detail: "登录后搜索歌曲并试听", icon: "music.note.list") }
            else { LazyVStack(spacing: 10) { ForEach(songs) { SongCard(song: $0) } } }
        } else if mode == .user {
            if users.isEmpty { emptyState("输入用户名搜索用户", detail: "查找用户公开歌单", icon: "person.2") }
            else { LazyVStack(spacing: 10) { ForEach(users) { user in Button { selectedUser = user } label: { UserCard(user: user) }.buttonStyle(.plain) } } }
        } else {
            emptyState("粘贴链接后进入歌单详情", detail: "支持网易云音乐歌单链接", icon: "rectangle.stack")
        }
    }

    private func emptyState(_ title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(AppPalette.blue.opacity(0.13))
                    .frame(width: 66, height: 66)
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(AppPalette.blue)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func search() {
        let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard app.loginManager.isLoggedIn else {
            loginRequired = true
            return
        }
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
            } catch { errorMessage = NeteaseAPIError.userMessage(for: error) }
            isLoading = false
        }
    }

    private func resetResults() { songs = []; users = []; selectedPlaylist = nil }

    private func prepareLikeLayoutCheckIfNeeded() {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-check-like") else { return }
        let previewSong = Song(
            id: -2,
            name: "喜欢按钮布局检查",
            artist: "NeteaseGlass",
            album: "同步到网易云音乐",
            duration: 180,
            coverURL: nil,
            fee: 0,
            isVIP: false,
            size: nil,
            bitrate: nil
        )
        mode = .song
        songs = [previewSong]
        Task { @MainActor in
            // 等 AppModel 的初始未登录状态刷新结束，再固定为“已喜欢”用于截图验收。
            try? await Task.sleep(for: .milliseconds(500))
            app.likeManager.prepareLayoutPreview(songID: previewSong.id, liked: true)
        }
#endif
    }

    @ViewBuilder private var accountButtonContent: some View {
        if let user = app.loginManager.account?.user, let avatarURL = user.avatarURL {
            RemoteImage(url: avatarURL, size: 44)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.72), lineWidth: 1.5)
                }
                .contentShape(Circle())
        } else {
            Image(systemName: app.loginManager.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .appGlass(cornerRadius: 15)
        }
    }

    private func openAccount() {
        if let user = app.loginManager.account?.user {
            selectedUser = user
            return
        }
        guard app.loginManager.isLoggedIn else {
            showingLogin = true
            return
        }
        Task {
            await app.loginManager.refreshAccount()
            if let user = app.loginManager.account?.user {
                selectedUser = user
            } else {
                errorMessage = app.loginManager.errorMessage ?? "账号资料暂时没有加载成功，请稍后重试"
            }
        }
    }

    private static func playlistID(from value: String) -> Int? {
        guard let components = URLComponents(string: value), let id = components.queryItems?.first(where: { $0.name == "id" })?.value else {
            let pattern = #"playlist[=/](\d+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), let range = Range(match.range(at: 1), in: value) else { return nil }
            return Int(value[range])
        }
        return Int(id)
    }
}
