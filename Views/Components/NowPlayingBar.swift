import SwiftUI

struct NowPlayingBar: View {
    @EnvironmentObject private var app: AppModel
    @State private var isCollapsed = false

    private var player: AudioPlayerManager { app.audioPlayer }

    var body: some View {
        if let song = player.currentSong {
            VStack(spacing: isCollapsed ? 7 : 12) {
                HStack(spacing: 10) {
                    Button {
                        app.isFullPlayerPresented = true
                    } label: {
                        HStack(spacing: 10) {
                            RemoteImage(url: song.coverURL, size: isCollapsed ? 38 : 46)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(isCollapsed ? remainingText : song.artist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开全屏播放器")

                    Spacer(minLength: 4)

                    if player.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 44, height: 44)
                    } else {
                        actionButton(player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "暂停" : "继续播放") {
                            player.toggleCurrent()
                        }
                    }

                    actionButton(isCollapsed ? "chevron.up" : "chevron.down", label: isCollapsed ? "展开播放器" : "收起播放器") {
                        isCollapsed.toggle()
                    }
                }

                if isCollapsed {
                    ProgressView(value: player.progress)
                        .tint(AppPalette.blue)
                } else {
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
                        Text(remainingText)
                        Spacer()
                        Text(timeText(player.duration))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        actionButton("gobackward.15", label: "后退十五秒") {
                            player.seek(to: player.currentTime - 15)
                        }
                        actionButton(player.isPlaying ? "pause.circle.fill" : "play.circle.fill", size: 30, label: player.isPlaying ? "暂停" : "继续播放") {
                            player.toggleCurrent()
                        }
                        actionButton("goforward.15", label: "前进十五秒") {
                            player.seek(to: player.currentTime + 15)
                        }
                        actionButton("xmark", label: "关闭播放器") {
                            player.stop()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .appGlass(cornerRadius: 20)
        }
    }

    private var remainingText: String {
        "还剩 \(Int(player.remainingTime.rounded(.up))) 秒"
    }

    private func timeText(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func actionButton(_ icon: String, size: CGFloat = 18, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppPalette.blue)
        .accessibilityLabel(label)
    }
}
