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

    var isLoggedIn: Bool { account != nil && api.hasCookie }

    func refreshAccount() async {
        guard api.hasCookie else { account = nil; return }
        isLoading = true
        defer { isLoading = false }
        do {
            account = try await api.account()
        } catch {
            account = nil
            errorMessage = error.localizedDescription
        }
    }

    func finishLogin(with cookie: String) async {
        guard !cookie.isEmpty else { errorMessage = "登录成功但没有拿到 Cookie"; return }
        do {
            try KeychainStore.saveCookie(cookie)
            api.updateCookie(cookie)
            await refreshAccount()
        } catch { errorMessage = error.localizedDescription }
    }

    func logout() {
        KeychainStore.deleteCookie()
        api.updateCookie("")
        account = nil
    }
}
