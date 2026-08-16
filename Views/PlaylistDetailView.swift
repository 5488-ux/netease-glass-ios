import SwiftUI

struct PlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        RemoteImage(url: playlist.coverURL, size: 104)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(playlist.name).font(.title3.bold()).lineLimit(3)
                            Text(playlist.creatorName).font(.subheadline).foregroundStyle(.secondary)
                            Text("\(playlist.songs.count > 0 ? playlist.songs.count : playlist.trackCount) 首歌曲")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .appGlass(cornerRadius: 22)
                    if !playlist.description.isEmpty {
                        Text(playlist.description).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(playlist.songs) { SongCard(song: $0) }
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .navigationTitle("歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

