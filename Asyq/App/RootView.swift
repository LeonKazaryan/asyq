import SwiftUI

/// The menu, a match, or practice.
struct RootView: View {
    private enum Route: Equatable {
        case menu
        case match
        case practice

        static var initial: Route {
            switch DebugLaunchArguments.screen {
            case "match": .match
            case "practice": .practice
            default: .menu
            }
        }
    }

    @State private var route = Route.initial
    @State private var category = DebugLaunchArguments.category ?? .eresek

    var body: some View {
        ZStack {
            switch route {
            case .menu:
                MenuScreen(category: $category, onPlay: { route = .match }, onPractice: { route = .practice })
                    .transition(.opacity)
            case .match:
                MatchScreen(category: category, onClose: { route = .menu })
                    .transition(.opacity)
            case .practice:
                PracticeScreen(category: category, onClose: { route = .menu })
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: route)
    }
}

#Preview {
    RootView()
}
