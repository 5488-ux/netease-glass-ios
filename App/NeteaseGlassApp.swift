import SwiftUI

@main
struct NeteaseGlassApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
