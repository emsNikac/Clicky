import SwiftUI

@main
struct ClickyApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(controller: controller)
        } label: {
            Image("ClickyMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .opacity(controller.isEnabled ? 1 : 0.45)
                .help(controller.isEnabled ? "Clicky is on" : "Clicky is paused")
                .accessibilityLabel(controller.isEnabled ? "Clicky is on" : "Clicky is paused")
        }
        .menuBarExtraStyle(.window)
    }
}
