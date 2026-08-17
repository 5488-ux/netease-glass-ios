import SwiftUI

/// Apple Music 风格迷你播放器：默认紧凑，展开后保留进度和跳转控制。
struct NowPlayingBar: View {
    @EnvironmentObject private var app: AppModel
    @State private var isExpanded = false

    private var player: AudioPlayerManager { app.audioPlayer }

    var body: some View {
        if let song = player.currentSong {
            VStack(spacing: isExpanded ? 10 : 0) {
                HStack(spacing: 11) {
                    Button {
                        app.isFullPlayerPresented = true
                    } label: {
                        HStack(spacing: 11) {
                            RemoteImage(url: song.coverURL, size: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开全屏播放器")

                    if player.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 42, height: 42)
                    } else {
                        compactButton(player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "暂停" : "继续播放") {
                            player.toggleCurrent()
                        }
                    }

                    compactButton("goforward.15", label: "前进十五秒") {
                        player.seek(to: player.currentTime + 15)
                    }

                    compactButton(isExpanded ? "chevron.down" : "chevron.up", size: 14, label: isExpanded ? "收起控制" : "展开控制") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                }

                if isExpanded {
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { player.currentTime },
                                set: { player.seek(to: $0) }
                            ),
                            in: 0...max(player.duration, 1)
                        )
                        .tint(AppPalette.blue)

                        HStack {
                            Text(timeText(player.currentTime))
                            Spacer()
                            Text("还剩 \(timeText(player.remainingTime))")
                            Spacer()
                            Button("停止", systemImage: "stop.fill") {
                                player.stop()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 3)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: isExpanded ? 26 : 32))
            .overlay(alignment: .bottomLeading) {
                if !isExpanded {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(AppPalette.blue)
                            .frame(width: geometry.size.width * player.progress, height: 2.5)
                    }
                    .frame(height: 2.5)
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private func compactButton(_ icon: String, size: CGFloat = 18, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .frame(width: 38, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    private func timeText(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
