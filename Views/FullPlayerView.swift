import SwiftUI
import UIKit

/// 全屏播放器（Apple Music 风格）：
/// 页面整体固定不滚动；封面模糊背景；歌词区域独立滚动并高亮跟随；支持音质选择
struct FullPlayerView: View {
    @EnvironmentObject private var app: AppModel
    @State private var lyrics: [LyricLine] = []
    @State private var lyricsLoading = false
    @State private var artworkImage: UIImage?
    @State private var draggingProgress: Double?

    private var player: AudioPlayerManager { app.audioPlayer }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                // 顶部留白，给覆盖层顶栏让位
                Color.clear.frame(height: 54)

                artwork
                songInfo
                lyricSection
                progressSection
                controlsSection
                    .padding(.top, 6)
                    .padding(.bottom, 26)
            }
            .foregroundStyle(.white)
        }
        // 顶栏独立覆盖在最上层，永不丢失
        .overlay(alignment: .top) {
            topBar
                .padding(.horizontal, 14)
                .padding(.top, 8)
        }
        .task(id: player.currentSong?.id) {
            await loadArtwork()
            await loadLyrics()
        }
    }

    // MARK: - 背景（封面模糊 + 暗色，iOS 26 Apple Music 风格）

    private var backgroundLayer: some View {
        ZStack {
            if let artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 62)
                    .scaleEffect(1.9)
                    .opacity(0.6)
            } else {
                LinearGradient(
                    colors: [Color(red: 0.13, green: 0.14, blue: 0.21), Color(red: 0.05, green: 0.06, blue: 0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // 保证浅色封面时白色控件依然清晰可见
            Color.black.opacity(0.45)
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .center)
                .frame(height: 140)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }

    // MARK: - 顶栏（覆盖层：收起按钮 + 标题 + 音质选择）

    private var topBar: some View {
        HStack {
            Button {
                app.isFullPlayerPresented = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起播放器")

            Spacer()

            Text("正在播放")
                .font(.subheadline.weight(.semibold))

            Spacer()

            qualityMenu
        }
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(AudioQuality.allCases) { quality in
                Button {
                    player.setPreferredLevel(quality.rawValue)
                } label: {
                    if player.preferredLevel == quality.rawValue {
                        Label(quality.title, systemImage: "checkmark")
                    } else {
                        Text(quality.title)
                    }
                }
            }
        } label: {
            Text(player.preferredLevelTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
        }
        .accessibilityLabel("选择音质")
    }

    // MARK: - 封面

    private var artwork: some View {
        Group {
            if let song = player.currentSong {
                RemoteImage(url: song.coverURL, size: 216)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - 歌曲信息

    private var songInfo: some View {
        VStack(spacing: 5) {
            if let song = player.currentSong {
                Text(song.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 24)
    }

    // MARK: - 歌词（独立滚动、高亮、自动跟随播放进度）

    private var lyricSection: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 15) {
                    if lyricsLoading {
                        ProgressView().tint(.white)
                            .padding(.top, 42)
                    } else if lyrics.isEmpty {
                        Text("暂无歌词")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, 42)
                    } else {
                        ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                            Text(line.text)
                                .font(index == currentLyricIndex ? .subheadline.weight(.semibold) : .subheadline)
                                .foregroundStyle(index == currentLyricIndex ? .white : .white.opacity(0.42))
                                .multilineTextAlignment(.center)
                                .id(index)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 26)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: currentLyricIndex) { _, index in
                guard let index else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .padding(.top, 4)
    }

    private var currentLyricIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        let time = player.currentTime
        return lyrics.lastIndex { $0.time <= time } ?? 0
    }

    // MARK: - 进度（Apple Music 风格细胶囊条）

    private var progressSection: some View {
        VStack(spacing: 4) {
            progressBar
            HStack {
                Text(timeText(player.currentTime))
                Spacer()
                Text(timeText(player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 26)
        .padding(.top, 2)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let ratio = draggingProgress ?? (player.duration > 0 ? player.currentTime / player.duration : 0)
            let filled = max(0, min(1, ratio))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: 5)
                Capsule()
                    .fill(.white)
                    .frame(width: max(0, width * filled), height: 5)
                if draggingProgress != nil {
                    Circle()
                        .fill(.white)
                        .frame(width: 13, height: 13)
                        .offset(x: max(0, width * filled) - 6.5)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        draggingProgress = min(max(value.location.x / max(width, 1), 0), 1)
                    }
                    .onEnded { _ in
                        if let ratio = draggingProgress {
                            player.seek(to: ratio * max(player.duration, 0))
                        }
                        draggingProgress = nil
                    }
            )
        }
        .frame(height: 22)
    }

    // MARK: - 控制

    private var controlsSection: some View {
        HStack(spacing: 34) {
            controlButton("gobackward.15", size: 30) {
                player.seek(to: player.currentTime - 15)
            }
            .accessibilityLabel("后退十五秒")

            Button {
                player.toggleCurrent()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 62))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "暂停" : "继续播放")

            controlButton("goforward.15", size: 30) {
                player.seek(to: player.currentTime + 15)
            }
            .accessibilityLabel("前进十五秒")
        }
    }

    private func controlButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 数据

    private func loadArtwork() async {
        guard let url = player.currentSong?.coverURL else {
            artworkImage = nil
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        if let (data, _) = try? await URLSession.shared.data(for: request), let image = UIImage(data: data) {
            artworkImage = image
        }
    }

    private func loadLyrics() async {
        guard let song = player.currentSong else {
            lyrics = []
            return
        }
        lyrics = []
        lyricsLoading = true
        defer { lyricsLoading = false }
        do {
            lyrics = try await app.api.lyrics(for: song.id)
        } catch {
            lyrics = []
        }
    }

    private func timeText(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
