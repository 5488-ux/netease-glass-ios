import Foundation
import SwiftUI

enum AppTab: Hashable {
    case home
    case downloads
    case settings
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var alertMessage: String?

    let api: NeteaseAPI
    let loginManager: LoginManager
    let audioPlayer: AudioPlayerManager
    let downloadManager: DownloadManager

    init() {
        let api = NeteaseAPI(cookie: KeychainStore.loadCookie() ?? "")
        self.api = api
        loginManager = LoginManager(api: api)
        audioPlayer = AudioPlayerManager(api: api)
        downloadManager = DownloadManager(api: api)
        downloadManager.errorHandler = { [weak self] message in self?.alertMessage = message }
    }
}

