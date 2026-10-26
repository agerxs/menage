import Foundation
import Testing
@testable import MenageCore

@Suite struct ProtectedPathsTests {
    let home = URL(fileURLWithPath: "/Users/test")
    var protected: ProtectedPaths {
        .standard(home: home, projectRoots: [URL(fileURLWithPath: "/Users/test/devapps")])
    }

    @Test func sanctuaryAndEverythingInsideIsRefused() {
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users/test/ai-brain")))
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users/test/ai-brain/projects/menage")))
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users/test/.ssh/id_ed25519")))
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/x/y")))
    }

    @Test func anchorItselfAndItsParentsAreRefused() {
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users/test/Downloads")))
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users/test/devapps")))
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users/test")))
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users")))
        #expect(protected.isProtected(URL(fileURLWithPath: "/")))
        // Parent d'un sanctuaire : le supprimer supprimerait le sanctuaire.
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/..")))
    }

    @Test func insideAnAnchorIsAllowed() {
        #expect(!protected.isProtected(URL(fileURLWithPath: "/Users/test/Downloads/DaVinci.dmg")))
        #expect(!protected.isProtected(URL(fileURLWithPath: "/Users/test/Library/Caches/com.openai.codex")))
        #expect(!protected.isProtected(URL(fileURLWithPath: "/Users/test/devapps/vitalis/node_modules")))
    }

    @Test func dotDotCannotSneakIntoASanctuary() {
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users/test/Downloads/../ai-brain/HOME.md")))
    }

    @Test func caseDoesNotBypassProtection() {
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users/test/AI-BRAIN/x")))
        #expect(protected.isProtected(URL(fileURLWithPath: "/Users/test/documents/contrat.pdf")))
        #expect(protected.isProtected(URL(fileURLWithPath: "/users/TEST/downloads")))
    }

    /// `standardizingPath` réécrit /private/var en /var pour un chemin qui existe : les deux restent protégés.
    @Test func privateAndItsShortFormsAreProtected() {
        for path in ["/private/var/db", "/var/db", "/private/etc/hosts", "/etc/hosts", "/private/tmp", "/tmp/x"] {
            #expect(protected.isProtected(URL(fileURLWithPath: path)), "\(path)")
        }
    }

    @Test func refusalExplainsWhy() {
        #expect(protected.refusal(for: URL(fileURLWithPath: "/Users/test/.ssh"))?.contains(".ssh") == true)
    }
}

@Suite struct DirectorySizeTests {
    @Test func countsAllocatedBytesAndIgnoresSymlinks() throws {
        let fixture = try Fixture()
        try fixture.file("dir/a", bytes: 100_000)
        try fixture.file("dir/sub/b", bytes: 200_000)
        let outside = try fixture.file("outside", bytes: 5 * megabyte)
        try FileManager.default.createSymbolicLink(at: fixture.url("dir/link"), withDestinationURL: outside)

        let size = DirectorySize.of(fixture.url("dir"))
        #expect(size >= 300_000)
        #expect(size < 1_000_000)
        #expect(DirectorySize.of(fixture.url("dir/link")) == 0)
        #expect(DirectorySize.of(fixture.url("missing")) == 0)
    }
}

@Suite struct ProcessRunnerTests {
    @Test func stuckCommandIsStoppedAfterTimeout() {
        let start = Date()
        let result = ProcessRunner(timeout: 1).run(URL(fileURLWithPath: "/bin/sleep"), ["10"], in: nil)
        #expect(result == nil)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func outputIsCaptured() {
        let result = ProcessRunner().run(URL(fileURLWithPath: "/bin/echo"), ["bonjour"], in: nil)
        #expect(result == CommandResult(status: 0, output: "bonjour\n"))
    }
}

@Suite struct ActionJournalTests {
    @Test func appendsAndReadsNewestFirst() throws {
        let fixture = try Fixture()
        let journal = ActionJournal(url: fixture.url("support/journal.jsonl"))
        let first = JournalEntry(date: Date(timeIntervalSince1970: 1), ruleID: "a", title: "A", method: .corbeille, items: ["/x"], bytes: 10, errors: [])
        let second = JournalEntry(date: Date(timeIntervalSince1970: 2), ruleID: "b", title: "B", method: .commande, items: ["docker image prune -f"], bytes: 20, errors: [])
        try journal.append(first)
        try journal.append(second)
        #expect(journal.read().map(\.ruleID) == ["b", "a"])
        #expect(journal.read().last == first)
    }
}

@Suite struct CleanerExecutionTests {
    @Test func trashesSelectionRefusesProtectedAndWritesJournal() throws {
        let fixture = try Fixture()
        let cache = try fixture.file("home/Library/Caches/app/blob", bytes: 1000).deletingLastPathComponent()
        let secret = try fixture.file("home/.ssh/id_ed25519", bytes: 10)
        let trasher = RecordingTrasher()
        let journal = ActionJournal(url: fixture.url("journal.jsonl"))
        let cleaner = Cleaner(
            rules: [], protected: fixture.protected(), trasher: trasher, journal: journal
        )
        let report = RuleReport(id: "caches", title: "Caches", explanation: "", risk: .sansRisque, candidates: [], note: nil)
        let good = Candidate(id: "1", title: "app", detail: "", bytes: 1000, action: .trash([cache]), location: cache)
        let bad = Candidate(id: "2", title: "ssh", detail: "", bytes: 10, action: .trash([secret]), location: secret)

        let result = cleaner.execute([(report, [good, bad])], runner: StubRunner(result: nil))

        #expect(trasher.trashed == [cache])
        #expect(result.trashedBytes == 1000)
        #expect(result.refused.count == 1)
        #expect(result.refused[0].contains(".ssh"))
        #expect(result.failedCandidates == ["2"])
        let entries = journal.read()
        #expect(entries.count == 1)
        #expect(entries[0].items == [cache.path])
        #expect(entries[0].bytes == 1000)
    }

    @Test func vanishedFilesAreNotCountedAsFreed() throws {
        let fixture = try Fixture()
        let cleaner = Cleaner(
            rules: [], protected: fixture.protected(), trasher: RecordingTrasher(),
            journal: ActionJournal(url: fixture.url("journal.jsonl"))
        )
        let gone = fixture.url("home/Library/Caches/gone")
        let report = RuleReport(id: "caches", title: "Caches", explanation: "", risk: .sansRisque, candidates: [], note: nil)
        let candidate = Candidate(id: "g", title: "gone", detail: "", bytes: 999, action: .trash([gone]), location: gone)

        let result = cleaner.execute([(report, [candidate])], runner: StubRunner(result: nil))

        #expect(result.trashedBytes == 0)
        #expect(result.failedCandidates.isEmpty)
        #expect(ActionJournal(url: fixture.url("journal.jsonl")).read().isEmpty)
    }

    @Test func commandsAreRunAndFailuresReported() throws {
        let fixture = try Fixture()
        let runner = StubRunner(result: CommandResult(status: 1, output: ""))
        let cleaner = Cleaner(
            rules: [], protected: fixture.protected(), trasher: RecordingTrasher(),
            journal: ActionJournal(url: fixture.url("journal.jsonl"))
        )
        let command = Command(executable: URL(fileURLWithPath: "/usr/local/bin/docker"), arguments: ["image", "prune", "-f"])
        let report = RuleReport(id: "docker", title: "Docker", explanation: "", risk: .regenerable, candidates: [], note: nil)
        let candidate = Candidate(id: "d", title: "images", detail: "", bytes: 500, action: .command(command), location: nil)

        let result = cleaner.execute([(report, [candidate])], runner: runner)

        #expect(runner.calls == ["docker image prune -f"])
        #expect(result.deletedBytes == 0)
        #expect(result.errors == ["docker image prune -f a échoué"])
    }

    @Test func scanDropsCandidatesThatTouchProtectedPaths() async throws {
        struct RogueRule: CleanupRule {
            let id = "rogue"
            let title = "Rogue"
            let explanation = ""
            let risk = Risk.sansRisque
            let home: URL
            func scan(_ context: CleanupContext) -> RuleScan {
                RuleScan(candidates: [
                    .trash(home.appendingPathComponent("ai-brain"), detail: "", bytes: 1),
                    .trash(home.appendingPathComponent("Library/Caches/ok"), detail: "", bytes: 1),
                ])
            }
        }
        let fixture = try Fixture()
        let home = fixture.url("home")
        let cleaner = Cleaner(
            rules: [RogueRule(home: home)], protected: fixture.protected(), trasher: RecordingTrasher(),
            journal: ActionJournal(url: fixture.url("journal.jsonl"))
        )
        let reports = await cleaner.scan(fixture.context())
        #expect(reports[0].candidates.map(\.title) == ["ok"])
    }
}
