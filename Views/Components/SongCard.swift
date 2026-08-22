import SwiftUI

struct SongCard: View {
    @EnvironmentObject private var app: AppModel
    let song: Song

    private var isPlaying: Bool { app.audioPlayer.playingSongID == song.id && app.audioPlayer.isPlaying }
    private var isLoadingAudio: Bool { app.audioPlayer.playingSongID == song.id && app.audioPlayer.isLoading }
    private var downloadTask: DownloadTask? { app.downloadManager.task(for: song.id) }

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
                Group {
                    if isLoadingAudio {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.blue)
            .accessibilityLabel(isPlaying ? "暂停试听" : "播放试听")
            SongLikeButton(songID: song.id, width: 40)
            Button {
                switch app.downloadManager.enqueue(song: song) {
                case .queued, .restarted:
                    break
                case .alreadyActive:
                    app.alertMessage = "这首歌曲已经在下载列表中"
                case .alreadyCompleted:
                    app.alertMessage = "这首歌曲已经下载完成"
                }
            } label: {
                Group {
                    if downloadTask?.state == .waiting || downloadTask?.state == .downloading {
                        ProgressView().controlSize(.small)
                    } else if downloadTask?.state == .completed {
                        Image(systemName: "checkmark.circle.fill")
                    } else if downloadTask?.state == .failed {
                        Image(systemName: "arrow.clockwise.circle")
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.orange)
            .accessibilityLabel("下载")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .appGlass(cornerRadius: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

}

struct SongLikeButton: View {
    @EnvironmentObject private var app: AppModel
    let songID: Int
    var width: CGFloat = 44

    private var isLiked: Bool { app.likeManager.isLiked(songID) }
    private var isPending: Bool { app.likeManager.isPending(songID) }

    var body: some View {
        Button {
            toggleLike()
        } label: {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .opacity(isPending ? 0.55 : 1)
            .frame(width: width, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .disabled(isPending)
        .accessibilityLabel(isLiked ? "取消喜欢" : "添加到我喜欢的音乐")
    }

    private func toggleLike() {
        Task {
            if app.loginManager.account == nil, app.loginManager.isLoggedIn {
                await app.loginManager.refreshAccount()
            }
            guard let userID = app.loginManager.account?.user.id else {
                app.alertMessage = "请先登录网易云音乐，再同步我喜欢的音乐"
                return
            }

            do {
                let liked = try await app.likeManager.toggle(songID: songID, userID: userID)
                app.alertMessage = liked
                    ? "恭喜你添加了这首歌"
                    : "已取消喜欢，并已同步到网易云音乐"
            } catch {
                app.alertMessage = NeteaseAPIError.userMessage(for: error)
            }
        }
    }
}
