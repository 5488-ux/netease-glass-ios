import SwiftUI

/// 全屏播放器（Apple Music 风格）：大封面、滚动歌词、进度与控制
struct FullPlayerView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var lyrics: [LyricLine] = []
    @State private var lyricsLoading = false

    private var player: AudioPlayerManager { app.audioPlayer }

    var body: some View {
        ZStack {
            backgroundLayer

            if let song = player.currentSong {
                VStack(spacing: 0) {
                    topBar

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            artwork(song)
                            songInfo(song)
                            lyricSection
                            progressSection
                            controlsSection
                                .padding(.top, 14)
                                .padding(.bottom, 36)
                        }
                    }
                }
                .foregroundStyle(.white)
                .task(id: player.currentSong?.id) { await loadLyrics() }
            }
        }
    }

    // MARK: - 背景（暗色渐变 + 光斑，Apple Music 风格）

    private var backgroundLayer: some View {
        ZStack {
            Color(red: 0.09, green: 0.10, blue: 0.17)
            Circle()
                .fill(AppPalette.violet.opacity(0.45))
                .frame(width: 340, height: 340)
                .blur(radius: 60)
                .offset(x: 170, y: -320)
            Circle()
                .fill(AppPalette.blue.opacity(0.35))
                .frame(width: 300, height: 300)
                .blur(radius: 55)
                .offset(x: -180, y: 340)
        }
        .ignoresSafeArea()
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button {
                app.isFullPlayerPresented = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起播放器")

            Spacer()

            Text("正在播放")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: - 封面

    private func artwork(_ song: Song) -> some View {
        RemoteImage(url: song.coverURL, size: 262)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .padding(.top, 26)
            .padding(.horizontal, 24)
    }

    // MARK: - 歌曲信息

    private func songInfo(_ song: Song) -> some View {
        VStack(spacing: 6) {
            Text(song.name)
                .font(.title2.bold())
                .lineLimit(1)
            Text(song.artist)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
    }

    // MARK: - 歌词

    private var lyricSection: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 13) {
                    if lyricsLoading {
                        ProgressView().tint(.white)
                            .padding(.top, 46)
                    } else if lyrics.isEmpty {
                        Text("暂无歌词")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, 46)
                    } else {
                        ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                            Text(line.text)
                                .font(index == currentLyricIndex ? .subheadline.weight(.semibold) : .subheadline)
                                .foregroundStyle(index == currentLyricIndex ? .white : .white.opacity(0.45))
                                .multilineTextAlignment(.center)
                                .id(index)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 22)
            }
            .frame(height: 268)
            .onChange(of: currentLyricIndex) { _, index in
                guard let index else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .padding(.top, 14)
    }

    private var currentLyricIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        let time = player.currentTime
        let index = lyrics.lastIndex { $0.time <= time } ?? 0
        return index
    }

    // MARK: - 进度

    private var progressSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            .tint(.white)

            HStack {
                Text(timeText(player.currentTime))
                Spacer()
                Text(timeText(player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 26)
        .padding(.top, 6)
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
