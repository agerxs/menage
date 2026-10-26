import Testing
@testable import MenageCore

@Suite struct ProcessGroupingTests {
    @Test func helperProcessesBelongToTheirOutermostApp() {
        let path = "/Applications/Firefox.app/Contents/MacOS/plugin-container.app/Contents/MacOS/plugin-container"
        #expect(ProcessGrouping.appBundlePath(forExecutable: path) == "/Applications/Firefox.app")
    }

    @Test func processOutsideAnAppHasNoBundle() {
        #expect(ProcessGrouping.appBundlePath(forExecutable: "/usr/local/bin/node") == nil)
    }

    @Test func groupsAddUpAndSortByWeight() {
        let processes = [
            ProcessFootprint(pid: 1, executablePath: "/Applications/Firefox.app/Contents/MacOS/firefox", bytes: 400),
            ProcessFootprint(
                pid: 2,
                executablePath: "/Applications/Firefox.app/Contents/MacOS/plugin-container.app/Contents/MacOS/plugin-container",
                bytes: 1300
            ),
            ProcessFootprint(pid: 3, executablePath: "/Applications/Claude.app/Contents/MacOS/Claude", bytes: 800),
            ProcessFootprint(pid: 4, executablePath: "/usr/local/bin/node", bytes: 300),
            ProcessFootprint(pid: 5, executablePath: "/opt/homebrew/bin/node", bytes: 200),
            ProcessFootprint(pid: 6, executablePath: "/usr/bin/idle", bytes: 0),
        ]

        let groups = ProcessGrouping.group(processes)

        #expect(groups.map(\.name) == ["Firefox", "Claude", "node"])
        #expect(groups[0].bytes == 1700)
        #expect(groups[0].processCount == 2)
        #expect(groups[0].bundlePath == "/Applications/Firefox.app")
        #expect(groups[2].bytes == 500)
        #expect(groups[2].bundlePath == nil)
    }

    @Test func appNameKeepsDotsThatAreNotTheExtension() {
        let groups = ProcessGrouping.group([
            ProcessFootprint(pid: 1, executablePath: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron", bytes: 10),
            ProcessFootprint(pid: 2, executablePath: "/Applications/app.store.app/Contents/MacOS/x", bytes: 5),
        ])
        #expect(groups.map(\.name) == ["Visual Studio Code", "app.store"])
    }
}
