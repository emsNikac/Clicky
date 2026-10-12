import SwiftUI

@main
struct ClickyApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(controller: controller)
        } label: {
            Image(systemName: controller.isEnabled ? "keyboard" : "keyboard.badge.ellipsis")
                .accessibilityLabel(controller.isEnabled ? "Clicky is on" : "Clicky is paused")
        }
        .menuBarExtraStyle(.window)
    }
}
