import SwiftUI

struct QRLoginView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: QRLoginSession?
    @State private var status: QRLoginStatus = .waiting
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let session, let image = QRCodeRenderer.image(for: session.loginURL.absoluteString) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                        .overlay { RoundedRectangle(cornerRadius: 20).stroke(AppPalette.blue.opacity(0.16), lineWidth: 1) }
                    Text(status.rawValue).font(.headline)
                    Text(statusHint).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if status == .expired || status == .failed {
                        Button("刷新二维码") { createSession() }.buttonStyle(.borderedProminent).tint(AppPalette.blue)
                    } else if status == .success {
                        Button("完成") { dismiss() }.buttonStyle(.borderedProminent).tint(AppPalette.blue)
                    } else {
                        HStack(spacing: 12) {
                            ProgressView().tint(AppPalette.blue).controlSize(.small)
                            Button("刷新登录状态") { refreshStatus() }
                                .buttonStyle(.bordered)
                                .tint(AppPalette.blue)
                        }
                    }
                } else if isLoading {
                    ProgressView("正在生成二维码…").tint(AppPalette.blue)
                } else {
                    Text(errorMessage ?? "二维码生成失败").foregroundStyle(.secondary)
                    Button("重试") { createSession() }.buttonStyle(.borderedProminent).tint(AppPalette.blue)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("登录网易云音乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
            .task { createSession() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let session, status != .success, status != .expired else { return }
                startPolling(session)
            }
            .onDisappear {
                pollTask?.cancel()
                pollTask = nil
            }
        }
    }

    private var statusHint: String {
        switch status {
        case .waiting: return errorMessage ?? "请使用网易云音乐 App 扫描二维码"
        case .scanned: return errorMessage ?? "已扫码，请在手机上确认登录"
        case .success: return errorMessage ?? "登录成功，账号信息已保存"
        case .expired: return "二维码已过期，请刷新后重试"
        case .failed: return errorMessage ?? "登录失败，请刷新二维码"
        }
    }

    private func createSession() {
        pollTask?.cancel()
        isLoading = true; errorMessage = nil; status = .waiting
        Task {
            do {
                let newSession = try await app.api.createQRLogin()
                session = newSession; isLoading = false; startPolling(newSession)
            } catch { isLoading = false; errorMessage = error.localizedDescription }
        }
    }

    private func startPolling(_ loginSession: QRLoginSession) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                do {
                    let newStatus = try await app.api.checkQRLogin(loginSession)
                    status = newStatus
                    errorMessage = nil
                    if newStatus == .success {
                        if completeLogin() {
                            status = .success
                            return
                        }
                        status = .failed
                        return
                    }
                    if newStatus == .expired || newStatus == .failed { return }
                } catch is CancellationError {
                    return
                } catch {
                    errorMessage = "网络暂时中断，回到本应用后会继续检查登录状态"
                }
            }
        }
    }

    private func refreshStatus() {
        guard let session else {
            createSession()
            return
        }
        pollTask?.cancel()
        errorMessage = nil

        Task {
            do {
                let newStatus = try await app.api.checkQRLogin(session)
                status = newStatus
                if newStatus == .success {
                    if completeLogin() {
                        status = .success
                        return
                    }
                    status = .failed
                    return
                }
                if newStatus != .expired && newStatus != .failed {
                    startPolling(session)
                }
            } catch {
                errorMessage = "刷新状态失败，请确认网络后重试"
                startPolling(session)
            }
        }
    }

    private func completeLogin() -> Bool {
        let saved = app.loginManager.finishLogin(with: app.api.currentCookie)
        if !saved {
            errorMessage = app.loginManager.errorMessage ?? "登录成功但凭证保存失败"
        }
        return saved
    }
}
