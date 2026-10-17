import SwiftUI
import TodayCore

@main
struct TodayApp: App {
    var body: some Scene {
        WindowGroup {
            DebugPlanView(content: .forLaunch())
                .preferredColorScheme(.dark)
        }
    }
}
