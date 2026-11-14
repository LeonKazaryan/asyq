import SwiftUI

/// The menu, a match, practice, the lesson, or the rules. A new player starts with the lesson.
struct RootView: View {
    private enum Route: Equatable {
        case menu
        case match
        case practice
        case lesson
        case rules

        static var initial: Route {
            switch DebugLaunchArguments.screen {
            case "match": .match
            case "practice": .practice
            case "lesson": .lesson
            case "rules": .rules
            case "menu": .menu
            default: LessonController.isCompleted ? .menu : .lesson
            }
        }
    }

    @State private var route = Route.initial
    @State private var category = DebugLaunchArguments.category ?? .eresek

    var body: some View {
        ZStack {
            switch route {
            case .menu:
                MenuScreen(
                    category: $category,
                    onPlay: { route = .match },
                    onPractice: { route = .practice },
                    onLesson: { route = .lesson },
                    onRules: { route = .rules }
                )
                .transition(.opacity)
            case .match:
                MatchScreen(category: category, onClose: { route = .menu })
                    .transition(.opacity)
            case .practice:
                PracticeScreen(category: category, onClose: { route = .menu })
                    .transition(.opacity)
            case .lesson:
                LessonScreen { play in route = play ? .match : .menu }
                    .transition(.opacity)
            case .rules:
                RulesScreen(category: category, onClose: { route = .menu })
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: route)
    }
}

#Preview {
    RootView()
}
