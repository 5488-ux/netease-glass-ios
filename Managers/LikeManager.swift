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

    /// 立即更新红心，再向网易云发送一次真实同步请求；失败时回滚。
    /// 不在每次点击后立刻重拉整份喜欢列表，避免连续两次请求触发风控。
    func toggle(songID: Int, userID: Int) async throws -> Bool {
        guard !pendingSongIDs.contains(songID) else {
            return likedSongIDs.contains(songID)
        }

        guard loadedUserID == nil || loadedUserID == userID else {
            throw NeteaseAPIError.message("登录账号已发生变化，请重新操作")
        }

        let targetState = !likedSongIDs.contains(songID)
        let previousState = !targetState
        loadedUserID = userID
        pendingSongIDs.insert(songID)
        setLocalState(songID: songID, liked: targetState)

        do {
            try await api.setSongLiked(songID: songID, liked: targetState)
            pendingSongIDs.remove(songID)
            return targetState
        } catch {
            if loadedUserID == userID {
                setLocalState(songID: songID, liked: previousState)
            }
            pendingSongIDs.remove(songID)
            throw error
        }
    }

    private func setLocalState(songID: Int, liked: Bool) {
        if liked {
            likedSongIDs.insert(songID)
        } else {
            likedSongIDs.remove(songID)
        }
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
