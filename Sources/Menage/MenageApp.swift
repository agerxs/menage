import MenageCore
import SwiftUI

@main
struct MenageApp: App {
    @State private var monitor = MonitorModel()
    @State private var cleaner = CleanerModel()

    init() {
        #if DEBUG
        PanelSnapshot.renderIfRequested()
        ScanDump.runIfRequested()
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Window("Faire le ménage", id: CleanerView.windowID) {
            CleanerView(model: cleaner)
        }
        .defaultSize(width: 780, height: 640)

        Settings {
            SettingsView(monitor: monitor, cleaner: cleaner)
        }
    }
}
