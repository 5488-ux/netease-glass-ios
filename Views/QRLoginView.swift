import SwiftUI

struct QRLoginView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var session: QRLoginSession?
    @State private var status: QRLoginStatus = .waiting
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let session, let image = QRCodeRenderer.image(for: session.loginURL.absoluteString) {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 220, height: 220).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    Text(status.rawValue).font(.headline)
                    Text(statusHint).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if status == .expired || status == .failed {
                        Button("刷新二维码") { createSession() }.buttonStyle(.borderedProminent)
                    } else if status == .success {
                        Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                } else if isLoading {
                    ProgressView("正在生成二维码…")
                } else {
                    Text(errorMessage ?? "二维码生成失败").foregroundStyle(.secondary)
                    Button("重试") { createSession() }.buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("登录网易云音乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
            .task { createSession() }
            .onDisappear { pollTask?.cancel() }
        }
    }

    private var statusHint: String {
        switch status { case .waiting: return "请使用网易云音乐 App 扫描二维码"; case .scanned: return "已扫码，请在手机上确认登录"; case .success: return "登录成功，账号信息已保存"; case .expired: return "二维码已过期，请刷新后重试"; case .failed: return errorMessage ?? "登录失败，请刷新二维码" }
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
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                do {
                    let newStatus = try await app.api.checkQRLogin(loginSession)
                    status = newStatus
                    if newStatus == .success {
                        await app.loginManager.finishLogin(with: app.api.currentCookie)
                        return
                    }
                    if newStatus == .expired || newStatus == .failed { return }
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }
}
