import SwiftUI

struct PlaylistCard: View {
    let playlist: Playlist
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: playlist.coverURL, size: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text(playlist.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(playlist.trackCount) 首 · \(playlist.creatorName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .appGlass(cornerRadius: 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
