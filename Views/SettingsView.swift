import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showingLogin = false
    @State private var selectedPlaylist: Playlist?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("设置").font(.largeTitle.bold())
                    if let account = app.loginManager.account {
                        accountHeader(account.user)
                        Text("我的歌单").font(.headline)
                        LazyVStack(spacing: 10) {
                            ForEach(account.user.playlists) { playlist in
                                Button { selectedPlaylist = playlist } label: { PlaylistCard(playlist: playlist) }.buttonStyle(.plain)
                            }
                        }
                        Button("退出登录", role: .destructive) { app.loginManager.logout() }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "person.crop.circle.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                            Text("登录网易云音乐").font(.title3.bold())
                            Text("扫码后可读取个人歌单，并由网易云接口判断每首歌曲的实际下载权限。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button { showingLogin = true } label: { Label("二维码登录", systemImage: "qrcode") }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(18)
                        .appGlass(cornerRadius: 22)
                    }
                    Text("关于")
                        .font(.headline)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("NeteaseGlass", systemImage: "waveform")
                        Text("iOS 26 · SwiftUI · Liquid Glass")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("下载文件保存在 App 沙盒 Documents/Music/，不会上传到第三方服务器。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(15)
                    .appGlass(cornerRadius: 18)
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingLogin) { QRLoginView() }
            .sheet(item: $selectedPlaylist) { PlaylistDetailView(playlist: $0) }
        }
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
