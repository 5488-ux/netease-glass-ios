import Foundation
import Combine

@MainActor
final class LoginManager: ObservableObject {
    @Published private(set) var account: NeteaseAccount?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let api: NeteaseAPI

    init(api: NeteaseAPI) {
        self.api = api
        if let cookie = KeychainStore.loadCookie() {
            api.updateCookie(cookie)
            Task { await refreshAccount() }
        }
    }

    var isLoggedIn: Bool { api.hasCookie }

    func refreshAccount() async {
        guard api.hasCookie else { account = nil; return }
        isLoading = true
        defer { isLoading = false }
        do {
            account = try await api.account()
            errorMessage = nil
        } catch {
            if let apiError = error as? NeteaseAPIError, apiError.isSessionExpired {
                // 会话已失效：清除过期凭证，提示用户重新扫码登录
                logout()
                errorMessage = "登录状态已失效，请重新扫码登录"
            } else {
                errorMessage = NeteaseAPIError.userMessage(for: error)
            }
        }
    }

    @discardableResult
    func finishLogin(with cookie: String) -> Bool {
        guard !cookie.isEmpty else {
            errorMessage = "登录成功但没有拿到 Cookie"
            return false
        }

        do {
            try KeychainStore.saveCookie(cookie)
            api.updateCookie(cookie)
        } catch {
            errorMessage = NeteaseAPIError.userMessage(for: error)
            return false
        }

        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            await self.refreshAccount()
        }
        return true
    }

    func logout() {
        KeychainStore.deleteCookie()
        api.updateCookie("")
        account = nil
        errorMessage = nil
    }
}
