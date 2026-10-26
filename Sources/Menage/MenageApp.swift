import MenageCore
import SwiftUI

@main
struct MenageApp: App {
    @State private var monitor = MonitorModel()
    @State private var cleaner: CleanerModel
    @State private var map: DiskMapModel
    @State private var history: HistoryModel

    init() {
        #if DEBUG
        PanelSnapshot.renderIfRequested()
        ScanDump.runIfRequested()
        MapDump.runIfRequested()
        MapDump.renderTreemapIfRequested()
        HistoryPreview.renderIfRequested()
        #endif
        let cleaner = CleanerModel()
        _cleaner = State(initialValue: cleaner)
        let map = DiskMapModel(
            protectedPaths: {
                .standard(home: FileManager.default.homeDirectoryForCurrentUser, projectRoots: cleaner.projectRoots)
            },
            onTrash: { cleaner.reloadJournal() }
        )
        _map = State(initialValue: map)
        _history = State(initialValue: HistoryModel(map: map))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Window("Ménage", id: MainWindowView.windowID) {
            MainWindowView(cleaner: cleaner, map: map, history: history)
        }
        .defaultSize(width: 980, height: 680)

        Settings {
            SettingsView(monitor: monitor, cleaner: cleaner)
        }
    }
}
