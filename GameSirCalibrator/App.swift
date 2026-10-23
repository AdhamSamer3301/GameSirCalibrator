import SwiftUI

@main
struct GameSirCalibratorApp: App {
    @State private var gamepads = Gamepads()

    var body: some Scene {
        Window("GameSir Calibrator", id: "main") {
            ContentView(gamepads: gamepads)
        }
        .windowResizability(.contentSize)
    }
}
