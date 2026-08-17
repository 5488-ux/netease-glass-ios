import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                AppPageBackground()
                TabView(selection: $app.selectedTab) {
                    HomeView()
                        .tabItem { Label("主页", systemImage: "house") }
                        .tag(AppTab.home)
                    DownloadsView()
                        .tabItem { Label("下载", systemImage: "arrow.down.circle") }
                        .badge(app.downloadManager.tasks.filter { $0.state == .downloading || $0.state == .waiting }.count)
                        .tag(AppTab.downloads)
                    SettingsView()
                        .tabItem { Label("设置", systemImage: "gearshape") }
                        .tag(AppTab.settings)
                }
                .tint(AppPalette.blue)

                if app.audioPlayer.currentSong != nil {
                    NowPlayingBar()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 72)
                        .zIndex(10)
                }
            }

            if app.isFullPlayerPresented {
                Color(red: 0.08, green: 0.09, blue: 0.12)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(99)

                FullPlayerView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.22), value: app.isFullPlayerPresented)
        .alert("提示", isPresented: Binding(get: { app.alertMessage != nil }, set: { if !$0 { app.alertMessage = nil } })) {
            Button("知道了", role: .cancel) { app.alertMessage = nil }
        } message: { Text(app.alertMessage ?? "") }
        .onChange(of: app.audioPlayer.currentSong?.id) { _, songID in
            if songID == nil { app.isFullPlayerPresented = false }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, app.api.hasCookie else { return }
            Task { await app.loginManager.refreshAccount() }
        }
        .onAppear { prepareLayoutCheckIfNeeded() }
    }

    private func prepareLayoutCheckIfNeeded() {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-check-player") else { return }
        app.audioPlayer.prepareLayoutPreview()
        app.isFullPlayerPresented = true
        if ProcessInfo.processInfo.arguments.contains("--ui-check-collapse") {
            Task {
                try? await Task.sleep(for: .seconds(1))
                app.isFullPlayerPresented = false
            }
        }
#endif
    }
}
