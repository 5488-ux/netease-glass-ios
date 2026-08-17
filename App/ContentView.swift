import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("提示", isPresented: Binding(get: { app.alertMessage != nil }, set: { if !$0 { app.alertMessage = nil } })) {
            Button("知道了", role: .cancel) { app.alertMessage = nil }
        } message: { Text(app.alertMessage ?? "") }
        .fullScreenCover(isPresented: $app.isFullPlayerPresented) {
            FullPlayerView()
        }
        .onChange(of: app.audioPlayer.currentSong?.id) { _, songID in
            if songID == nil { app.isFullPlayerPresented = false }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, app.api.hasCookie else { return }
            Task { await app.loginManager.refreshAccount() }
        }
    }
}
