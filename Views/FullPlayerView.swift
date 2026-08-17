import AVKit
import MediaPlayer
import SwiftUI
import UIKit

/// 按 Apple Music 的信息层级重排：内容占主区域，播放控制固定在下方，歌词是独立模式。
struct FullPlayerView: View {
    @EnvironmentObject private var app: AppModel
    @State private var lyrics: [LyricLine] = []
    @State private var lyricsLoading = false
    @State private var artworkImage: UIImage?
    @State private var draggingProgress: Double?
    @State private var showsLyrics = false
    @State private var verticalDrag: CGFloat = 0

    private var player: AudioPlayerManager { app.audioPlayer }

    init() {
#if DEBUG
        _showsLyrics = State(initialValue: ProcessInfo.processInfo.arguments.contains("--ui-check-lyrics"))
#endif
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                grabber
                    .padding(.top, 7)
                    .contentShape(Rectangle())
                    .gesture(dismissGesture)

                topBar
                    .padding(.horizontal, 20)

                if showsLyrics {
                    lyricSection
                        .transition(.opacity)
                } else {
                    nowPlayingContent(availableSize: proxy.size)
                        .transition(.opacity)
                }

                playerControls
                    .padding(.horizontal, 28)

                if !showsLyrics {
                    volumeControl
                        .padding(.horizontal, 30)
                        .padding(.top, 16)
                }

                bottomTools
                    .padding(.top, showsLyrics ? 12 : 18)
                    .padding(.bottom, 8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background { backgroundLayer(size: proxy.size) }
            .clipped()
        }
        .foregroundStyle(.white)
        .offset(y: max(0, verticalDrag))
        .task(id: player.currentSong?.id) {
            await loadArtwork()
            await loadLyrics()
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(0.48))
            .frame(width: 48, height: 5)
            .frame(height: 20)
            .accessibilityHidden(true)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                verticalDrag = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 110 || value.predictedEndTranslation.height > 180 {
                    app.isFullPlayerPresented = false
                }
                withAnimation(.snappy(duration: 0.28)) {
                    verticalDrag = 0
                }
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
                    .blur(radius: 78)
                    .scaleEffect(1.62)
                    .opacity(0.58)
            }

            Color.black.opacity(0.34)
            LinearGradient(
                colors: [.black.opacity(0.04), .black.opacity(0.32)],
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
            if showsLyrics {
                VStack(spacing: 1) {
                    Text("歌词")
                        .font(.subheadline.weight(.semibold))
                    Text(player.preferredLevelTitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            HStack {
                glassIconButton("chevron.down", label: "收起播放器") {
                    app.isFullPlayerPresented = false
                }

                Spacer()
                qualityMenu
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
    }

    private func glassIconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .accessibilityLabel(label)
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
        let artworkSize = min(
            availableSize.width - 104,
            max(220, min(262, availableSize.height * 0.32))
        )

        return VStack(spacing: 0) {
            Spacer(minLength: 10)
            artwork(size: artworkSize)
            Spacer(minLength: 22)
            songInformation
                .padding(.horizontal, 30)
            Spacer(minLength: 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song = player.currentSong {
            RemoteImage(url: song.coverURL, size: size)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.22), radius: 16, y: 9)
                .accessibilityLabel("歌曲封面")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(.white.opacity(0.08))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.3, weight: .medium))
                    .foregroundStyle(.white.opacity(0.18))
            }
            .frame(width: size, height: size)
            .accessibilityLabel("暂无歌曲封面")
        }
    }

    private var songInformation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(player.currentSong?.name ?? "未在播放")
                .font(.title2.weight(.bold))
                .lineLimit(1)
            Text(player.currentSong?.artist ?? "")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lyricSection: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if lyricsLoading {
                        ProgressView("正在加载歌词")
                            .tint(.white)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 70)
                    } else if lyrics.isEmpty {
                        ContentUnavailableView(
                            "暂无歌词",
                            systemImage: "quote.bubble",
                            description: Text("这首歌曲没有返回可用歌词")
                        )
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 56)
                    } else {
                        ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                            Button {
                                player.seek(to: line.time)
                            } label: {
                                Text(line.text)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(index == currentLyricIndex ? .white : .white.opacity(0.32))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.05),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
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

    private var playerControls: some View {
        VStack(spacing: 12) {
            progressTimeline
            transportControls
        }
        .padding(.top, showsLyrics ? 10 : 0)
    }

    private var progressTimeline: some View {
        VStack(spacing: 2) {
            progressBar
            HStack {
                Text(timeText(player.currentTime))
                Spacer()
                Text("−\(timeText(player.remainingTime))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.54))
        }
    }

    private var transportControls: some View {
        HStack {
            transportButton("gobackward.15", size: 25, label: "后退十五秒") {
                player.seek(to: player.currentTime - 15)
            }

            Spacer()

            Button {
                player.toggleCurrent()
            } label: {
                ZStack {
                    if player.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 38, weight: .bold))
                            .offset(x: player.isPlaying ? 0 : 3)
                    }
                }
                .frame(width: 76, height: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(player.currentSong == nil || player.isLoading)
            .opacity(player.currentSong == nil ? 0.34 : 1)
            .accessibilityLabel(player.isPlaying ? "暂停" : "继续播放")

            Spacer()

            transportButton("goforward.15", size: 25, label: "前进十五秒") {
                player.seek(to: player.currentTime + 15)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func transportButton(_ icon: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 54, height: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(player.currentSong == nil)
        .opacity(player.currentSong == nil ? 0.24 : 0.78)
        .accessibilityLabel(label)
    }

    private var volumeControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))

            SystemVolumeSlider()
                .frame(maxWidth: .infinity)
                .frame(height: 28)

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("系统音量")
    }

    private var bottomTools: some View {
        HStack(spacing: 54) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showsLyrics.toggle()
                }
            } label: {
                Image(systemName: showsLyrics ? "rectangle.portrait" : "quote.bubble")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 38)
                    .background(showsLyrics ? .white.opacity(0.16) : .clear, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsLyrics ? "返回封面" : "显示歌词")

            AirPlayRouteButton()
                .frame(width: 42, height: 38)
                .accessibilityLabel("隔空播放")
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .foregroundStyle(.white.opacity(0.72))
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
                    .fill(.white.opacity(0.9))
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
        .frame(height: 20)
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
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-check-lyrics") {
            lyrics = [
                LyricLine(time: 0, text: "认真听见每一句旋律"),
                LyricLine(time: 16, text: "让音乐停在此刻"),
                LyricLine(time: 38, text: "下一句歌词会继续向前"),
                LyricLine(time: 62, text: "NeteaseGlass 歌词布局检查")
            ]
            lyricsLoading = false
            return
        }
#endif
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

/// 使用系统音量控件，调节的是设备真实输出音量，不是假滑块。
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        configure(view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: MPVolumeView) {
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.minimumTrackTintColor = UIColor.white.withAlphaComponent(0.9)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.2)
        slider.thumbTintColor = .white
    }
}

/// 原生隔空播放路由按钮，点击后由系统展示真实设备列表。
private struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.prioritizesVideoDevices = false
        view.tintColor = UIColor.white.withAlphaComponent(0.72)
        view.activeTintColor = .white
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = UIColor.white.withAlphaComponent(0.72)
        uiView.activeTintColor = .white
    }
}
