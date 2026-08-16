import SwiftUI

struct SongCard: View {
    @EnvironmentObject private var app: AppModel
    let song: Song

    private var isPlaying: Bool { app.audioPlayer.playingSongID == song.id && app.audioPlayer.isPlaying }

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: song.coverURL, size: 56)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(song.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if song.isVIP { VIPBadge() }
                }
                Text("\(song.artist) · \(song.album)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Button {
                app.audioPlayer.toggle(song: song)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppPalette.blue)
            .accessibilityLabel(isPlaying ? "暂停试听" : "播放试听")
            Button {
                app.downloadManager.enqueue(song: song)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppPalette.orange)
            .accessibilityLabel("下载")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .appGlass(cornerRadius: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
