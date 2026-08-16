import SwiftUI

struct UserCard: View {
    let user: NeteaseUser
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.avatarURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Color.secondary.opacity(0.12) }
            }
            .frame(width: 54, height: 54)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(user.nickname).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(user.signature.isEmpty ? "暂无简介" : user.signature)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(11)
        .appGlass(cornerRadius: 16)
    }
}

