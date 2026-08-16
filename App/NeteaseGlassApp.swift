import SwiftUI
import UIKit

@main
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let appModel = AppModel()
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = .systemGroupedBackground
        window.rootViewController = UIHostingController(
            rootView: ContentView()
                .environmentObject(appModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppPageBackground())
        )
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
