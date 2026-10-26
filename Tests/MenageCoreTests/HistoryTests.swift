import Foundation
import Testing
@testable import MenageCore

private let mb: Int64 = 1_000_000
private let gb: Int64 = 1_000_000_000

private func snapshot(_ day: Int, _ sizes: [String: Int64]) -> DiskSnapshot {
    DiskSnapshot(date: Date(timeIntervalSince1970: Double(day) * 86_400), scannedBytes: 0, diskFree: 0, sizes: sizes)
}

@Suite struct DiskSnapshotTests {
    @Test func keepsDirectoriesUpToThreeLevelsAndAboveTenMegabytes() {
        func dir(_ path: String, _ bytes: Int64, _ children: [DiskNode] = []) -> DiskNode {
            DiskNode(path: "/h/" + path, name: (path as NSString).lastPathComponent, kind: .directory, bytes: bytes, children: children)
        }
        let root = DiskNode(path: "/h", name: "h", kind: .directory, bytes: 900 * mb, children: [
            dir("devapps", 800 * mb, [
                dir("devapps/vitalis", 700 * mb, [
                    dir("devapps/vitalis/app", 600 * mb, [dir("devapps/vitalis/app/deep", 500 * mb)]),
                ]),
                dir("devapps/tiny", 5 * mb),
            ]),
            DiskNode(path: "/h/film.mov", name: "film.mov", kind: .file, bytes: 90 * mb),
        ])

        let snap = DiskSnapshot(root: root, diskFree: 40 * gb)

        #expect(snap.sizes == [
            "devapps": 800 * mb,
            "devapps/vitalis": 700 * mb,
            "devapps/vitalis/app": 600 * mb,
        ])
        #expect(snap.scannedBytes == 900 * mb)
        #expect(snap.diskFree == 40 * gb)
    }
}

@Suite struct GrowthReportTests {
    @Test func listsWhatGrewAndHidesParentsExplainedByAChild() {
        let old = snapshot(0, [
            "Library": 100 * gb, "Library/Caches": 9 * gb, "Library/Caches/com.openai.codex": 3 * gb,
            "devapps": 60 * gb, "devapps/a": 10 * gb, "devapps/b": 10 * gb,
            "Downloads": 19 * gb,
        ])
        let new = snapshot(1, [
            "Library": 103 * gb, "Library/Caches": 12 * gb, "Library/Caches/com.openai.codex": 6 * gb,
            "devapps": 62 * gb, "devapps/a": 11 * gb, "devapps/b": 11 * gb,
            "Downloads": 18 * gb,
            "backups": 500 * mb,
        ])

        let report = GrowthReport.growth(from: old, to: new)

        // Library et Library/Caches : leur croissance vient de codex, ils disparaissent.
        // devapps : deux enfants à 1 Go chacun, aucun n'explique 80 % des 2 Go, il reste.
        // Downloads a diminué : absent. backups est nouveau : +500 Mo.
        #expect(report.map(\.path) == ["Library/Caches/com.openai.codex", "devapps", "devapps/a", "devapps/b", "backups"])
        #expect(report[0].delta == 3 * gb)
        #expect(report.last?.before == 0)
    }

    @Test func smallChangesAreIgnoredAndLimitApplies() {
        let old = snapshot(0, ["a": 1 * gb, "b": 1 * gb, "c": 1 * gb])
        let new = snapshot(1, ["a": 1 * gb + 50 * mb, "b": 2 * gb, "c": 3 * gb])
        #expect(GrowthReport.growth(from: old, to: new).map(\.path) == ["c", "b"])
        #expect(GrowthReport.growth(from: old, to: new, limit: 1).map(\.path) == ["c"])
    }

    /// Accès complet au disque accordé entre deux scans : Mail passe de 0 (illisible) à 35 Go.
    @Test func foldersThatBecameReadableAreNotGrowth() {
        var old = snapshot(0, ["Library": 100 * gb, "Library/Caches": 9 * gb, "devapps": 60 * gb])
        old.unreadable = ["Library/Mail", "Library/Safari"]
        var new = snapshot(1, [
            "Library": 135 * gb, "Library/Caches": 9 * gb, "Library/Mail": 35 * gb, "Library/Mail/V10": 35 * gb,
            "devapps": 62 * gb,
        ])
        new.unreadable = ["Library/Safari"]

        let report = GrowthReport.growth(from: old, to: new)
        #expect(report.map(\.path) == ["devapps"])
        #expect(GrowthReport.notable(from: old, to: new, threshold: 5 * gb) == nil)
    }

    /// Renommer `devapps/foo` en `devapps/bar`, ou déplacer un dossier de Téléchargements vers devapps.
    @Test func movesAreLabelledAndNeverNotified() {
        let old = snapshot(0, ["devapps": 60 * gb, "devapps/foo": 20 * gb, "Downloads": 30 * gb, "Downloads/iso": 8 * gb])
        let new = snapshot(1, ["devapps": 68 * gb, "devapps/bar": 20 * gb, "devapps/iso": 8 * gb, "Downloads": 22 * gb])

        let report = GrowthReport.growth(from: old, to: new)
        let bar = report.first { $0.path == "devapps/bar" }
        let iso = report.first { $0.path == "devapps/iso" }
        #expect(bar?.movedFrom == "devapps/foo")
        #expect(iso?.movedFrom == "Downloads/iso")
        #expect(GrowthReport.notable(from: old, to: new, threshold: 5 * gb) == nil)
    }

    /// devapps +8 Go, dont 5 Go de vidéos venues de Téléchargements : seuls 3 Go sont une vraie croissance.
    @Test func parentGrowthExcludesWhatWasMovedIn() {
        let old = snapshot(0, ["devapps": 60 * gb, "devapps/vitalis": 10 * gb, "Downloads": 19 * gb, "Downloads/videos": 5 * gb])
        let new = snapshot(1, ["devapps": 68 * gb, "devapps/vitalis": 13 * gb, "devapps/videos": 5 * gb, "Downloads": 14 * gb])

        let report = GrowthReport.growth(from: old, to: new)
        // devapps : 3 Go réels, entièrement expliqués par vitalis, donc masqué.
        #expect(report.map(\.path) == ["devapps/videos", "devapps/vitalis"])
        #expect(report[0].movedFrom == "Downloads/videos")
        #expect(GrowthReport.notable(from: old, to: new, threshold: 5 * gb) == nil)
    }

    @Test func realGrowthIsStillNotified() {
        let old = snapshot(0, ["Library": 100 * gb, "Library/Caches": 9 * gb, "Library/Caches/codex": 3 * gb])
        let new = snapshot(1, ["Library": 108 * gb, "Library/Caches": 17 * gb, "Library/Caches/codex": 11 * gb])
        let notable = GrowthReport.notable(from: old, to: new, threshold: 5 * gb)
        #expect(notable?.path == "Library/Caches/codex")
        #expect(notable?.delta == 8 * gb)
    }

    @Test func dailyScanIsDue() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        #expect(DailyScan.isDue(lastSnapshot: nil, now: now))
        #expect(!DailyScan.isDue(lastSnapshot: now.addingTimeInterval(-3600), now: now))
        #expect(DailyScan.isDue(lastSnapshot: now.addingTimeInterval(-24 * 3600), now: now))
        // Instantané daté du futur (horloge en avance) : sans ça, plus jamais de scan.
        #expect(DailyScan.isDue(lastSnapshot: now.addingTimeInterval(86_400), now: now))
    }

    @Test func baselinePerPeriod() {
        let snapshots = [snapshot(0, [:]), snapshot(20, [:]), snapshot(26, [:]), snapshot(30, [:])]
        #expect(GrowthReport.baseline(in: snapshots, period: .lastScan)?.date == snapshots[2].date)
        #expect(GrowthReport.baseline(in: snapshots, period: .days(7))?.date == snapshots[1].date)
        #expect(GrowthReport.baseline(in: snapshots, period: .days(90))?.date == snapshots[0].date)
        #expect(GrowthReport.baseline(in: [snapshot(0, [:])], period: .lastScan) == nil)
    }
}

@Suite struct HistoryStorageTests {
    @Test func snapshotsAreSavedLoadedAndPruned() throws {
        let fixture = try Fixture()
        let store = SnapshotStore(directory: fixture.url("history"), maxCount: 3)
        for day in [5, 1, 4, 2, 3] {
            try store.save(snapshot(day, ["devapps": Int64(day) * gb]))
        }
        let loaded = store.load()
        #expect(loaded.map { Int($0.date.timeIntervalSince1970 / 86_400) } == [3, 4, 5])
        #expect(loaded.last?.sizes["devapps"] == 5 * gb)
    }

    /// Plusieurs scans manuels par jour ne doivent pas raccourcir l'historique.
    @Test func olderThanAWeekKeepsOnePerDay() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let recent = (0..<5).map { now.addingTimeInterval(-Double($0) * 3600) }
        let oldDay = (0..<4).map { Date(timeIntervalSince1970: 50 * 86_400 + Double($0) * 3600) }
        let pruned = SnapshotStore.datesToPrune(recent + oldDay, now: now, maxCount: 90, calendar: calendar)
        #expect(pruned == Set(oldDay.dropLast()))
        #expect(SnapshotStore.datesToPrune(recent + oldDay, now: now, maxCount: 3, calendar: calendar).count == 6)
    }

    @Test func futureSnapshotsAreIgnored() throws {
        let fixture = try Fixture()
        let store = SnapshotStore(directory: fixture.url("history"))
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        try store.save(DiskSnapshot(date: now.addingTimeInterval(-86_400), scannedBytes: 0, diskFree: 1, sizes: [:]), now: now)
        try store.save(DiskSnapshot(date: now.addingTimeInterval(30 * 86_400), scannedBytes: 0, diskFree: 2, sizes: [:]), now: now)
        #expect(store.load(now: now).map(\.diskFree) == [1])
    }

    @Test func oldSnapshotsWithoutUnreadableStillDecode() throws {
        let json = #"{"date":"2026-10-01T00:00:00Z","scannedBytes":1,"diskFree":2,"sizes":{"a":3}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiskSnapshot.self, from: Data(json.utf8))
        #expect(decoded.unreadable.isEmpty)
        #expect(decoded.sizes == ["a": 3])
    }

    @Test func freeSpaceLogKeepsNinetyDays() throws {
        let fixture = try Fixture()
        let log = FreeSpaceLog(url: fixture.url("history/free.jsonl"), retention: 90 * 86_400)
        try log.append(FreeSpaceSample(date: Date(timeIntervalSince1970: 0), diskFree: 1, swapUsed: 0))
        try log.append(FreeSpaceSample(date: Date(timeIntervalSince1970: 50 * 86_400), diskFree: 2, swapUsed: 0))
        try log.append(FreeSpaceSample(date: Date(timeIntervalSince1970: 100 * 86_400), diskFree: 3, swapUsed: 0))
        #expect(log.read().map(\.diskFree) == [2, 3])
    }
}
