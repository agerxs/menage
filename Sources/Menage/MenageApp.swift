import MenageCore
import SwiftUI

@main
struct MenageApp: App {
    @State private var monitor = MonitorModel()
    @State private var cleaner: CleanerModel
    @State private var map: DiskMapModel

    init() {
        #if DEBUG
        PanelSnapshot.renderIfRequested()
        ScanDump.runIfRequested()
        MapDump.runIfRequested()
        MapDump.renderTreemapIfRequested()
        #endif
        let cleaner = CleanerModel()
        _cleaner = State(initialValue: cleaner)
        _map = State(initialValue: DiskMapModel(
            protectedPaths: {
                .standard(home: FileManager.default.homeDirectoryForCurrentUser, projectRoots: cleaner.projectRoots)
            },
            onTrash: { cleaner.reloadJournal() }
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Window("Ménage", id: MainWindowView.windowID) {
            MainWindowView(cleaner: cleaner, map: map)
        }
        .defaultSize(width: 980, height: 680)

        Settings {
            SettingsView(monitor: monitor, cleaner: cleaner)
        }
    }
}
