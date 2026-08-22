import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

@main
struct NeteaseGlassWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingLiveActivity()
    }
}

struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingActivityAttributes.self) { context in
            HStack(spacing: 12) {
                cover(context.state.coverThumbnail, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .padding(14)
            .activityBackgroundTint(Color(red: 0.93, green: 0.96, blue: 1.0))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    cover(context.state.coverThumbnail, size: 50)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: progress(context.state))
                        .tint(.blue)
                }
            } compactLeading: {
                cover(context.state.coverThumbnail, size: 24)
            } compactTrailing: {
                Text(context.state.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 62)
            } minimal: {
                cover(context.state.coverThumbnail, size: 22)
            }
            .keylineTint(.blue)
        }
    }

    @ViewBuilder
    private func cover(_ data: Data?, size: CGFloat) -> some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(Color.blue.opacity(0.2))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: size, height: size)
        }
    }

    private func progress(_ state: NowPlayingActivityAttributes.ContentState) -> Double {
        guard state.duration > 0 else { return 0 }
        return min(max(state.elapsedTime / state.duration, 0), 1)
    }
}
