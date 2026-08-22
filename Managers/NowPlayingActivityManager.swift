import ActivityKit
import Foundation
import UIKit

@MainActor
final class NowPlayingActivityManager {
    private var activity: Activity<NowPlayingActivityAttributes>?
    private var currentSongID: Int?
    private var coverThumbnail: Data?
    private var lastPublishedAt = Date.distantPast
    private var lastPublishedPlayingState: Bool?
    private var latestElapsedTime: TimeInterval = 0
    private var latestDuration: TimeInterval = 0
    private var artworkTask: Task<Void, Never>?

    init() {
        activity = Activity<NowPlayingActivityAttributes>.activities.first
        currentSongID = activity?.attributes.songID
    }

    func start(song: Song, isPlaying: Bool, elapsedTime: TimeInterval, duration: TimeInterval) {
        artworkTask?.cancel()
        artworkTask = nil
        coverThumbnail = nil
        latestElapsedTime = elapsedTime
        latestDuration = duration

        Task { [weak self] in
            guard let self else { return }
            if let existing = self.activity, existing.attributes.songID != song.id {
                await existing.end(nil, dismissalPolicy: .immediate)
                self.activity = nil
            }

            self.currentSongID = song.id
            let state = self.makeState(
                song: song,
                isPlaying: isPlaying,
                elapsedTime: elapsedTime,
                duration: duration
            )

            if let activity = self.activity {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                do {
                    self.activity = try Activity.request(
                        attributes: NowPlayingActivityAttributes(songID: song.id),
                        content: ActivityContent(state: state, staleDate: nil),
                        pushType: nil
                    )
                } catch {
                    self.activity = nil
                }
            }
            self.lastPublishedAt = Date()
            self.lastPublishedPlayingState = isPlaying
            self.loadArtwork(for: song)
        }
    }

    func update(song: Song, isPlaying: Bool, elapsedTime: TimeInterval, duration: TimeInterval, force: Bool = false) {
        guard currentSongID == song.id, let activity else { return }
        latestElapsedTime = elapsedTime
        latestDuration = duration
        let playingStateChanged = lastPublishedPlayingState != isPlaying
        guard force || playingStateChanged || Date().timeIntervalSince(lastPublishedAt) >= 5 else { return }
        lastPublishedAt = Date()
        lastPublishedPlayingState = isPlaying
        let state = makeState(song: song, isPlaying: isPlaying, elapsedTime: elapsedTime, duration: duration)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        artworkTask?.cancel()
        artworkTask = nil
        currentSongID = nil
        coverThumbnail = nil
        lastPublishedPlayingState = nil
        latestElapsedTime = 0
        latestDuration = 0
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func makeState(
        song: Song,
        isPlaying: Bool,
        elapsedTime: TimeInterval,
        duration: TimeInterval
    ) -> NowPlayingActivityAttributes.ContentState {
        NowPlayingActivityAttributes.ContentState(
            title: String(song.name.prefix(80)),
            artist: String(song.artist.prefix(80)),
            album: String(song.album.prefix(80)),
            isPlaying: isPlaying,
            elapsedTime: max(0, elapsedTime),
            duration: max(0, duration),
            coverThumbnail: coverThumbnail
        )
    }

    private func loadArtwork(for song: Song) {
        guard let url = song.coverURL else { return }
        artworkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                guard self.currentSongID == song.id,
                      let image = UIImage(data: data),
                      let thumbnail = self.compactJPEG(from: image) else { return }
                self.coverThumbnail = thumbnail
                self.update(
                    song: song,
                    isPlaying: self.lastPublishedPlayingState ?? false,
                    elapsedTime: self.latestElapsedTime,
                    duration: self.latestDuration,
                    force: true
                )
            } catch {
                return
            }
        }
    }

    private func compactJPEG(from image: UIImage) -> Data? {
        let size = CGSize(width: 44, height: 44)
        let renderer = UIGraphicsImageRenderer(size: size)
        let square = renderer.image { context in
            context.cgContext.addRect(CGRect(origin: .zero, size: size))
            context.cgContext.clip()
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        for quality in [0.72, 0.55, 0.38, 0.24, 0.12] {
            if let data = square.jpegData(compressionQuality: quality), data.count <= 2_000 {
                return data
            }
        }
        return nil
    }
}
