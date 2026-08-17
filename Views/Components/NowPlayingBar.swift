import SwiftUI

/// Apple Music 风格迷你播放器：固定单行，不与页面内容争抢空间。
struct NowPlayingBar: View {
    @EnvironmentObject private var app: AppModel

    private var player: AudioPlayerManager { app.audioPlayer }

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: 10) {
                Button {
                    app.isFullPlayerPresented = true
                } label: {
                    HStack(spacing: 10) {
                        RemoteImage(url: song.coverURL, size: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
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
                        .frame(width: 38, height: 38)
                } else {
                    compactButton(player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "暂停" : "继续播放") {
                        player.toggleCurrent()
                    }
                }

                compactButton("goforward.15", label: "前进十五秒") {
                    player.seek(to: player.currentTime + 15)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .capsule)
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(AppPalette.blue)
                        .frame(width: geometry.size.width * player.progress, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 16)
            }
        }
    }

    private func compactButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }
}
