import SwiftUI
import UIKit

/// 参考 Apple Music 信息层级设计的全屏播放器。
/// 封面与播放控制是主界面，歌词作为独立模式切换，所有悬浮控制使用 iOS 26 Liquid Glass。
struct FullPlayerView: View {
    @EnvironmentObject private var app: AppModel
    @State private var lyrics: [LyricLine] = []
    @State private var lyricsLoading = false
    @State private var artworkImage: UIImage?
    @State private var draggingProgress: Double?
    @State private var showsLyrics = false

    private var player: AudioPlayerManager { app.audioPlayer }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, max(proxy.safeAreaInsets.top, 8))

                if showsLyrics {
                    lyricSection
                        .transition(.opacity)
                } else {
                    nowPlayingContent(availableSize: proxy.size)
                        .transition(.opacity)
                }

                playbackPanel
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)

                bottomTools
                    .padding(.horizontal, 18)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 8))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background { backgroundLayer(size: proxy.size) }
            .clipped()
        }
        .foregroundStyle(.white)
        .task(id: player.currentSong?.id) {
            await loadArtwork()
            await loadLyrics()
        }
    }

    private func backgroundLayer(size: CGSize) -> some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.12)

            if let artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .blur(radius: 72)
                    .scaleEffect(1.55)
                    .opacity(0.62)
            }

            Color.black.opacity(0.32)
            LinearGradient(
                colors: [.black.opacity(0.08), .black.opacity(0.46)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(showsLyrics ? "歌词" : "正在播放")
                    .font(.subheadline.weight(.semibold))
                Text(player.preferredLevelTitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
            }

            HStack {
                Button {
                    app.isFullPlayerPresented = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityLabel("收起播放器")

                Spacer()
                qualityMenu
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
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
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .accessibilityLabel("选择音质")
    }

    private func nowPlayingContent(availableSize: CGSize) -> some View {
        let artworkSize = min(availableSize.width - 64, availableSize.height < 760 ? 218 : 252)

        return VStack(spacing: 14) {
            Spacer(minLength: 4)

            if let song = player.currentSong {
                RemoteImage(url: song.coverURL, size: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
                    }
                    .shadow(color: .black.opacity(0.24), radius: 14, y: 8)
                    .accessibilityLabel("歌曲封面")
            }

            songInformation
                .padding(.horizontal, 24)

            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var songInformation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(player.currentSong?.name ?? "未在播放")
                .font(.title3.weight(.bold))
                .lineLimit(1)
            Text(player.currentSong?.artist ?? "")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lyricSection: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if lyricsLoading {
                        ProgressView("正在加载歌词")
                            .tint(.white)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if lyrics.isEmpty {
                        ContentUnavailableView(
                            "暂无歌词",
                            systemImage: "quote.bubble",
                            description: Text("这首歌曲没有返回可用歌词")
                        )
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 64)
                    } else {
                        ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                            Button {
                                player.seek(to: line.time)
                            } label: {
                                Text(line.text)
                                    .font(.system(size: index == currentLyricIndex ? 25 : 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(index == currentLyricIndex ? .white : .white.opacity(0.34))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: currentLyricIndex) { _, index in
                guard let index else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    private var currentLyricIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        return lyrics.lastIndex { $0.time <= player.currentTime } ?? 0
    }

    private var playbackPanel: some View {
        VStack(spacing: 8) {
            VStack(spacing: 3) {
                progressBar

                HStack {
                    Text(timeText(player.currentTime))
                    Spacer()
                    Text("−\(timeText(player.remainingTime))")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.58))
            }

            HStack(spacing: 30) {
                playerControlButton("gobackward.15", size: 22, label: "后退十五秒") {
                    player.seek(to: player.currentTime - 15)
                }

                Button {
                    player.toggleCurrent()
                } label: {
                    ZStack {
                        if player.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 23, weight: .bold))
                                .offset(x: player.isPlaying ? 0 : 2)
                        }
                    }
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .tint(.white)
                .foregroundStyle(.black)
                .accessibilityLabel(player.isPlaying ? "暂停" : "继续播放")

                playerControlButton("goforward.15", size: 22, label: "前进十五秒") {
                    player.seek(to: player.currentTime + 15)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let ratio = draggingProgress ?? player.progress
            let filled = max(0, min(1, ratio))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: draggingProgress == nil ? 4 : 7)
                Capsule()
                    .fill(.white.opacity(0.92))
                    .frame(width: max(0, width * filled), height: draggingProgress == nil ? 4 : 7)
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
            .animation(.easeOut(duration: 0.16), value: draggingProgress != nil)
        }
        .frame(height: 24)
    }

    private func playerControlButton(_ icon: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var bottomTools: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showsLyrics.toggle()
                }
            } label: {
                Image(systemName: showsLyrics ? "rectangle.portrait" : "quote.bubble")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityLabel(showsLyrics ? "返回封面" : "显示歌词")
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 42)
    }

    private func loadArtwork() async {
        guard let url = player.currentSong?.coverURL else {
            artworkImage = nil
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode),
           let image = UIImage(data: data) {
            artworkImage = image
        } else {
            artworkImage = nil
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
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
