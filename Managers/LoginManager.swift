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

    @discardableResult
    func finishLogin(with cookie: String) async -> Bool {
        guard !cookie.isEmpty else {
            errorMessage = "登录成功但没有拿到 Cookie"
            return false
        }

        do {
            try KeychainStore.saveCookie(cookie)
            api.updateCookie(cookie)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        for attempt in 0..<4 {
            do {
                account = try await api.account()
                errorMessage = nil
                return true
            } catch {
                if attempt < 3 {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }

        errorMessage = "扫码已成功，账号资料暂时加载失败；保持网络后回到设置页会自动重试"
        return false
    }

    func logout() {
        KeychainStore.deleteCookie()
        api.updateCookie("")
        account = nil
    }
}
