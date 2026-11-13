import Testing
@testable import Asyq

struct SmokeTests {
    @Test func appModuleLoads() {
        _ = RootView()
    }
}
