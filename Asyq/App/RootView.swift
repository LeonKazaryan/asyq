import SwiftUI

/// Placeholder until M2 (design system) and M1 (throw prototype) land.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Asyq")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("Асық ату")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView()
}
