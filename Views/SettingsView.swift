import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showingLogin = false
    @State private var selectedPlaylist: Playlist?

    var body: some View {
        NavigationStack {
            ZStack {
                AppPageBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 13) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .fill(AppPalette.violet.opacity(0.13))
                                    .frame(width: 58, height: 58)
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 25, weight: .bold))
                                    .foregroundStyle(AppPalette.violet)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("设置")
                                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                                Text("账号、歌单和本地保存位置")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)

                        if let account = app.loginManager.account {
                            accountHeader(account.user)
                            AppSectionHeader(title: "我的歌单", subtitle: "创建和收藏的网易云歌单", count: "\(account.user.playlists.count)")
                            LazyVStack(spacing: 10) {
                                ForEach(account.user.playlists) { playlist in
                                    Button { selectedPlaylist = playlist } label: { PlaylistCard(playlist: playlist) }.buttonStyle(.plain)
                                }
                            }
                            Button("退出登录", role: .destructive) { app.loginManager.logout() }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)
                        } else if app.loginManager.isLoggedIn {
                            savedLoginCard
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("登录网易云音乐")
                                    .font(.title3.bold())
                                Text("扫码后可读取个人歌单，并由网易云接口判断每首歌曲的实际下载权限。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button { showingLogin = true } label: {
                                    Label("二维码登录", systemImage: "qrcode")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppPalette.violet)
                            }
                            .padding(18)
                            .appGlass(cornerRadius: 22)
                        }

                        AppSectionHeader(title: "关于", subtitle: "应用信息与文件保存说明")
                        VStack(alignment: .leading, spacing: 8) {
                            Label("NeteaseGlass", systemImage: "waveform")
                            Text("iOS 26 · SwiftUI · Liquid Glass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("下载文件保存在 App 沙盒 Documents/Music/，不会上传到第三方服务器。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .appGlass(cornerRadius: 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingLogin) { QRLoginView() }
            .sheet(item: $selectedPlaylist) { PlaylistDetailView(playlist: $0) }
            .alert("刷新登录状态失败", isPresented: Binding(get: {
                app.loginManager.isLoggedIn && app.loginManager.errorMessage != nil
            }, set: { if !$0 { app.loginManager.errorMessage = nil } })) {
                Button("知道了", role: .cancel) { app.loginManager.errorMessage = nil }
            } message: {
                Text(app.loginManager.errorMessage ?? "")
            }
        }
    }

    private var savedLoginCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(AppPalette.violet)
            Text("网易云登录凭证已保存")
                .font(.title3.bold())
            Text("账号资料和歌单会在网络可用时自动加载；也可以手动刷新当前登录状态。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await app.loginManager.refreshAccount() }
            } label: {
                Label(app.loginManager.isLoading ? "正在刷新…" : "刷新登录状态", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.violet)
            .disabled(app.loginManager.isLoading)
            Button("重新扫码登录") { showingLogin = true }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appGlass(cornerRadius: 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountHeader(_ user: NeteaseUser) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: user.avatarURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.12) }
            }
            .frame(width: 78, height: 78).clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) { Text(user.nickname).font(.title3.bold()); if user.isVIP { VIPBadge() } }
                Text(user.signature.isEmpty ? "暂无简介" : user.signature).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if let level = user.level { Text("等级 \(level)").font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer()
        }
        .padding(15)
        .appGlass(cornerRadius: 22)
    }
}
