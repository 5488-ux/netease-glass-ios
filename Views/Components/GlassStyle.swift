import SwiftUI

enum AppPalette {
    static let blue = Color(red: 0.12, green: 0.48, blue: 0.96)
    static let cyan = Color(red: 0.05, green: 0.70, blue: 0.82)
    static let violet = Color(red: 0.47, green: 0.32, blue: 0.90)
    static let orange = Color(red: 0.96, green: 0.47, blue: 0.20)
}

extension View {
    @ViewBuilder
    func appGlass(cornerRadius: CGFloat = 20) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

struct AppPageBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.96, blue: 1.00)

            Circle()
                .fill(AppPalette.blue.opacity(0.10))
                .frame(width: 300, height: 300)
                .blur(radius: 42)
                .offset(x: 180, y: -350)

            Circle()
                .fill(AppPalette.violet.opacity(0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 50)
                .offset(x: -190, y: 360)
        }
        .ignoresSafeArea()
    }
}

struct AppSectionHeader: View {
    let title: String
    let subtitle: String
    var count: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let count {
                Text(count)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
        }
    }
}

struct RemoteImage: View {
    let url: URL?
    var size: CGFloat
    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "music.note").font(.title3).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct VIPBadge: View {
    var body: some View {
        Text("VIP")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.red, in: Capsule())
    }
}
