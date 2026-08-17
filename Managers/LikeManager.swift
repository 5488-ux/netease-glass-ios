import Combine
import Foundation

@MainActor
final class LikeManager: ObservableObject {
    @Published private(set) var likedSongIDs: Set<Int> = []
    @Published private(set) var pendingSongIDs: Set<Int> = []

    private let api: NeteaseAPI
    private var loadedUserID: Int?

    init(api: NeteaseAPI) {
        self.api = api
    }

    func isLiked(_ songID: Int) -> Bool {
        likedSongIDs.contains(songID)
    }

    func isPending(_ songID: Int) -> Bool {
        pendingSongIDs.contains(songID)
    }

    func refresh(userID: Int?) async {
        guard let userID else {
            loadedUserID = nil
            likedSongIDs = []
            pendingSongIDs = []
            return
        }

        let changedAccount = loadedUserID != userID
        loadedUserID = userID
        if changedAccount {
            likedSongIDs = []
            pendingSongIDs = []
        }
        do {
            let ids = try await api.likedSongIDs(userID: userID)
            guard loadedUserID == userID else { return }
            likedSongIDs = ids
        } catch {
            // 同一账号刷新失败时保留上次已确认状态，避免短暂网络波动让全部红心消失。
            return
        }
    }

    /// 返回服务器最终确认的喜欢状态。只有重新读取喜欢列表并验证成功后才更新 UI。
    func toggle(songID: Int, userID: Int) async throws -> Bool {
        guard !pendingSongIDs.contains(songID) else {
            return likedSongIDs.contains(songID)
        }

        let targetState = !likedSongIDs.contains(songID)
        pendingSongIDs.insert(songID)
        defer { pendingSongIDs.remove(songID) }

        try await api.setSongLiked(songID: songID, liked: targetState)
        let serverIDs = try await api.likedSongIDs(userID: userID)
        guard loadedUserID == userID else {
            throw NeteaseAPIError.message("登录账号已发生变化，请重新操作")
        }
        let confirmedState = serverIDs.contains(songID)
        guard confirmedState == targetState else {
            throw NeteaseAPIError.message(
                targetState
                    ? "网易云已接收请求，但喜欢列表中仍没有这首歌，请稍后重试"
                    : "网易云已接收请求，但喜欢列表中仍保留这首歌，请稍后重试"
            )
        }

        loadedUserID = userID
        likedSongIDs = serverIDs
        return confirmedState
    }

#if DEBUG
    func prepareLayoutPreview(songID: Int, liked: Bool) {
        if liked {
            likedSongIDs.insert(songID)
        } else {
            likedSongIDs.remove(songID)
        }
    }
#endif
}
