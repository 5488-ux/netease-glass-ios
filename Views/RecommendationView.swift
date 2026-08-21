import SwiftUI

/// 推荐页：网易云账号推荐、DeepSeek 偏好推荐与公开平台热歌在同一个可播放入口中展示。
struct RecommendationView: View {
    @EnvironmentObject private var app: AppModel
    @State private var resolvingTrackID: String?

    private var manager: RecommendationManager { app.recommendationManager }

    var body: some View {
        NavigationStack {
            ZStack {
                AppPageBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header
                        personalizedSection
                        platformSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await manager.loadPublicRecommendations()
                await manager.refreshForAccount(
                    userID: app.loginManager.account?.user.id,
                    likedSongIDs: app.likeManager.likedSongIDs
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(AppPalette.orange.opacity(0.15))
                    .frame(width: 58, height: 58)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppPalette.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("推荐")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                Text("喜欢的音乐、网易云日推与公开热歌榜")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if manager.isLoading || manager.isAnalyzing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var personalizedSection: some View {
        AppSectionHeader(
            title: "根据你喜爱的歌曲推荐",
            subtitle: manager.hasDeepSeekAPIKey ? "打开 App 后自动由 DeepSeek 分析" : "登录后可使用网易云每日推荐"
        )

        if let insight = manager.insight {
            Label(insight, systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appGlass(cornerRadius: 18)
        }

        if manager.personalizedSongs.isEmpty {
            ContentUnavailableView(
                app.loginManager.isLoggedIn ? "正在准备推荐" : "登录后解锁个性推荐",
                systemImage: "heart.text.square",
                description: Text(app.loginManager.isLoggedIn ? "会自动读取喜欢歌曲并生成推荐" : "在设置中扫码登录网易云音乐")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(manager.personalizedSongs.prefix(8)) { SongCard(song: $0) }
            }
        }
    }

    @ViewBuilder
    private var platformSection: some View {
        AppSectionHeader(title: "各大主流平台热歌", subtitle: "网易云新歌速递与 Apple Music 中国区公开榜单")

        if !manager.trendingSongs.isEmpty {
            platformTitle("网易云音乐 · 新歌速递", icon: "flame.fill", color: .red)
            LazyVStack(spacing: 10) {
                ForEach(manager.trendingSongs.prefix(5)) { SongCard(song: $0) }
            }
        }

        if !manager.platformTracks.isEmpty {
            platformTitle("Apple Music · 中国区热歌", icon: "chart.bar.fill", color: AppPalette.orange)
            LazyVStack(spacing: 8) {
                ForEach(manager.platformTracks.prefix(8)) { track in
                    PlatformTrackRow(track: track, isLoading: resolvingTrackID == track.id) {
                        await playPlatformTrack(track)
                    }
                }
            }
        }
    }

    private func platformTitle(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.top, 2)
    }

    @MainActor
    private func playPlatformTrack(_ track: PlatformTrack) async {
        guard app.loginManager.isLoggedIn else {
            app.alertMessage = "请先登录网易云音乐，才能播放平台热歌"
            return
        }
        resolvingTrackID = track.id
        defer { resolvingTrackID = nil }
        do {
            let song = try await manager.resolvePlatformTrack(track)
            app.audioPlayer.toggle(song: song)
        } catch {
            app.alertMessage = NeteaseAPIError.userMessage(for: error)
        }
    }
}

private struct PlatformTrackRow: View {
    let track: PlatformTrack
    let isLoading: Bool
    let play: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: track.artworkURL, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(track.source)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppPalette.orange)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button {
                Task { await play() }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                        .font(.body.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.blue)
            .frame(width: 44, height: 44)
            .disabled(isLoading)
            .accessibilityLabel("在网易云中播放")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlass(cornerRadius: 18)
    }
}
