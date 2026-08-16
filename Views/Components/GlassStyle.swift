import SwiftUI
import UIKit

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
            Color(red: 0.88, green: 0.92, blue: 1.00)

            Circle()
                .fill(AppPalette.blue.opacity(0.26))
                .frame(width: 300, height: 300)
                .blur(radius: 42)
                .offset(x: 180, y: -350)

            Circle()
                .fill(AppPalette.violet.opacity(0.20))
                .frame(width: 360, height: 360)
                .blur(radius: 50)
                .offset(x: -190, y: 360)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                AppPalette.blue.opacity(0.15)
                Image(systemName: "music.note")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppPalette.blue)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) { await loadImage() }
    }

    private func loadImage() async {
        image = nil
        guard let url else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let loaded = UIImage(data: data) else { return }
        image = loaded
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
