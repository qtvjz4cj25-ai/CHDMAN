import AppKit
import SwiftUI

@main
struct CHDMANApp: App {
    @StateObject private var viewModel = AppViewModel()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        Window("CHDMAN", id: "main") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}
