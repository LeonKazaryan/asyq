import SwiftUI

@main
struct AsyqApp: App {
    init() {
        if DebugLaunchArguments.freshPlayer {
            TermFamiliarity.reset()
            MatchTip.reset()
            UserDefaults.standard.removeObject(forKey: LessonController.completedKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
