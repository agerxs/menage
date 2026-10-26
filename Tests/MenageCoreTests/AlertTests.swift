import Foundation
import Testing
@testable import MenageCore

private let gb: Int64 = 1_000_000_000
private let thresholds = Thresholds(diskAttentionGB: 40, diskCritiqueGB: 20, swapAttentionGB: 6, swapCritiqueGB: 12)

private func snapshot(diskFreeGB: Int64 = 100, swapGB: Int64 = 1, pressure: MemoryPressure = .normale) -> SystemSnapshot {
    SystemSnapshot(
        diskFree: diskFreeGB * gb,
        diskTotal: 500 * gb,
        swapUsed: swapGB * gb,
        swapTotal: 12 * gb,
        physicalMemory: 24 * gb,
        pressure: pressure,
        topApps: [AppMemory(id: "/Applications/Firefox.app", name: "Firefox", bundlePath: "/Applications/Firefox.app", bytes: 3_100_000_000, processCount: 5)]
    )
}

@Suite struct ThresholdTests {
    @Test func standardThresholdsFollowRam() {
        let standard = Thresholds.standard(physicalMemory: 24 * 1_073_741_824)
        #expect(standard.swapAttentionGB == 6)
        #expect(standard.swapCritiqueGB == 12)
        #expect(standard.diskAttentionGB == 40)
    }

    @Test func levelsPerSignal() {
        #expect(thresholds.level(of: .disque, in: snapshot(diskFreeGB: 100)) == .normal)
        #expect(thresholds.level(of: .disque, in: snapshot(diskFreeGB: 33)) == .attention)
        #expect(thresholds.level(of: .disque, in: snapshot(diskFreeGB: 15)) == .critique)
        #expect(thresholds.level(of: .swap, in: snapshot(swapGB: 5)) == .normal)
        #expect(thresholds.level(of: .swap, in: snapshot(swapGB: 11)) == .attention)
        #expect(thresholds.level(of: .swap, in: snapshot(swapGB: 13)) == .critique)
        #expect(thresholds.level(of: .memoire, in: snapshot(pressure: .elevee)) == .attention)
    }

    @Test func overallIsTheWorstSignal() {
        #expect(thresholds.overall(in: snapshot()) == .normal)
        #expect(thresholds.overall(in: snapshot(diskFreeGB: 33, pressure: .critique)) == .critique)
    }

    @Test func unreadableDiskIsNotAnAlert() {
        var unreadable = snapshot(diskFreeGB: 0)
        unreadable.diskTotal = 0
        #expect(thresholds.level(of: .disque, in: unreadable) == .normal)
    }

    @Test func inconsistentSavedThresholdsAreRejected() {
        #expect(thresholds.isConsistent)
        #expect(Thresholds.standard(physicalMemory: 24 * 1_073_741_824).isConsistent)
        #expect(!Thresholds(diskAttentionGB: 8, diskCritiqueGB: 20, swapAttentionGB: 6, swapCritiqueGB: 12).isConsistent)
        #expect(!Thresholds(diskAttentionGB: 40, diskCritiqueGB: 20, swapAttentionGB: 6, swapCritiqueGB: 6).isConsistent)
    }

    @Test func pressureMapsKernelValues() {
        #expect(MemoryPressure(sysctlLevel: 1) == .normale)
        #expect(MemoryPressure(sysctlLevel: 2) == .elevee)
        #expect(MemoryPressure(sysctlLevel: 4) == .critique)
        #expect(MemoryPressure(sysctlLevel: 0) == .normale)
    }
}

@Suite struct AlertPolicyTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func alreadyBadAtLaunchNotifiesOnce() {
        var policy = AlertPolicy()
        let first = policy.alerts(for: snapshot(diskFreeGB: 33), thresholds: thresholds, now: start)
        #expect(first.map(\.signal) == [.disque])
        #expect(first[0].level == .attention)
        #expect(first[0].body.contains("33,0 Go"))

        let again = policy.alerts(for: snapshot(diskFreeGB: 32), thresholds: thresholds, now: start + 5)
        #expect(again.isEmpty)
    }

    @Test func escalationToCritiqueNotifiesImmediately() {
        var policy = AlertPolicy()
        _ = policy.alerts(for: snapshot(swapGB: 8), thresholds: thresholds, now: start)
        let escalated = policy.alerts(for: snapshot(swapGB: 13), thresholds: thresholds, now: start + 60)
        #expect(escalated.map(\.level) == [.critique])
        #expect(escalated[0].body.contains("Firefox (3,1 Go)"))
    }

    @Test func oscillationIsSilencedUntilCooldown() {
        var policy = AlertPolicy(cooldown: 1800)
        #expect(policy.alerts(for: snapshot(diskFreeGB: 39), thresholds: thresholds, now: start).count == 1)
        #expect(policy.alerts(for: snapshot(diskFreeGB: 41), thresholds: thresholds, now: start + 60).isEmpty)
        #expect(policy.alerts(for: snapshot(diskFreeGB: 39), thresholds: thresholds, now: start + 120).isEmpty)
        #expect(policy.alerts(for: snapshot(diskFreeGB: 41), thresholds: thresholds, now: start + 1900).isEmpty)
        #expect(policy.alerts(for: snapshot(diskFreeGB: 39), thresholds: thresholds, now: start + 1950).count == 1)
    }

    /// Un disque qui oscille autour du seuil critique ne renotifie pas « critique » avant 30 min.
    @Test func critiqueOscillationIsSilencedToo() {
        var policy = AlertPolicy(cooldown: 1800)
        #expect(policy.alerts(for: snapshot(diskFreeGB: 19), thresholds: thresholds, now: start).map(\.level) == [.critique])
        #expect(policy.alerts(for: snapshot(diskFreeGB: 21), thresholds: thresholds, now: start + 60).isEmpty)
        #expect(policy.alerts(for: snapshot(diskFreeGB: 19), thresholds: thresholds, now: start + 120).isEmpty)
    }

    @Test func goingBackToNormalNeverNotifies() {
        var policy = AlertPolicy()
        _ = policy.alerts(for: snapshot(pressure: .critique), thresholds: thresholds, now: start)
        #expect(policy.alerts(for: snapshot(pressure: .normale), thresholds: thresholds, now: start + 10).isEmpty)
    }
}

@Suite struct ByteFormatTests {
    @Test func frenchDecimalUnits() {
        #expect(ByteFormat.string(512) == "512 octets")
        #expect(ByteFormat.string(650_000_000) == "650 Mo")
        #expect(ByteFormat.string(33_240_000_000) == "33,2 Go")
        #expect(ByteFormat.string(142_000_000_000) == "142 Go")
        #expect(ByteFormat.string(999_990_000) == "1,0 Go")
        #expect(ByteFormat.string(2_500_000_000_000) == "2,5 To")
    }

    @Test func ramUsesBinaryUnitsLikeApple() {
        #expect(ByteFormat.ram(25_769_803_776) == "24 Go")
    }
}

@Suite struct SystemReaderTests {
    /// Lecture réelle : vérifie que les appels système répondent sur ce Mac.
    @Test func readsPlausibleValuesFromThisMac() {
        let snapshot = SystemReader.read()
        #expect(snapshot.diskTotal > 50 * gb)
        #expect(snapshot.diskFree > 0 && snapshot.diskFree < snapshot.diskTotal)
        #expect(snapshot.swapUsed <= snapshot.swapTotal)
        #expect(snapshot.physicalMemory > 4 * gb)
        #expect(!snapshot.topApps.isEmpty)
    }
}
