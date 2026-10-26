import MenageCore
import SwiftUI

@main
struct MenageApp: App {
    @State private var monitor = MonitorModel()

    init() {
        #if DEBUG
        PanelSnapshot.renderIfRequested()
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(monitor: monitor)
        }
    }
}
