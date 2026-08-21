import Foundation
import SwiftUI
import Combine

enum AppTab: Hashable {
    case home
    case recommendations
    case downloads
    case settings
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var alertMessage: String?
    @Published var isFullPlayerPresented = false

    let api: NeteaseAPI
    let loginManager: LoginManager
    let audioPlayer: AudioPlayerManager
    let downloadManager: DownloadManager
    let likeManager: LikeManager
    let recommendationManager: RecommendationManager
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let api = NeteaseAPI(cookie: KeychainStore.loadCookie() ?? "")
        self.api = api
        loginManager = LoginManager(api: api)
        audioPlayer = AudioPlayerManager(api: api)
        downloadManager = DownloadManager(api: api)
        likeManager = LikeManager(api: api)
        recommendationManager = RecommendationManager(api: api)
        audioPlayer.errorHandler = { [weak self] message in self?.alertMessage = message }
        downloadManager.errorHandler = { [weak self] message in self?.alertMessage = message }

        loginManager.objectWillChange
            .merge(with: audioPlayer.objectWillChange, downloadManager.objectWillChange)
            .merge(with: likeManager.objectWillChange)
            .merge(with: recommendationManager.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        loginManager.$account
            .map { $0?.user.id }
            .removeDuplicates()
            .sink { [weak self] userID in
                Task {
                    await self?.likeManager.refresh(userID: userID)
                    await self?.recommendationManager.refreshForAccount(
                        userID: userID,
                        likedSongIDs: self?.likeManager.likedSongIDs ?? []
                    )
                }
            }
            .store(in: &cancellables)
    }
}
