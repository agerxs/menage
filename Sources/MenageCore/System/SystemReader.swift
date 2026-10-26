import Darwin
import Foundation

/// Lecture des mesures système, sans outil externe ni privilège administrateur.
public enum SystemReader {
    public static func read(volume: URL = URL(fileURLWithPath: "/"), topCount: Int = 5) -> SystemSnapshot {
        let disk = diskSpace(volume: volume)
        let swap = swapUsage()
        return SystemSnapshot(
            diskFree: disk.free,
            diskTotal: disk.total,
            swapUsed: swap.used,
            swapTotal: swap.total,
            physicalMemory: Int64(ProcessInfo.processInfo.physicalMemory),
            pressure: pressure(),
            topApps: Array(ProcessGrouping.group(processFootprints()).prefix(topCount))
        )
    }

    /// Espace réellement libre (comme `df`), sans compter l'espace purgeable que macOS
    /// promet de libérer : quand le swap grossit, ce n'est pas lui qui sauve la mise.
    public static func diskSpace(volume: URL) -> (free: Int64, total: Int64) {
        let values = try? volume.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        return (Int64(values?.volumeAvailableCapacity ?? 0), Int64(values?.volumeTotalCapacity ?? 0))
    }

    public static func swapUsage() -> (used: Int64, total: Int64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (Int64(usage.xsu_used), Int64(usage.xsu_total))
    }

    public static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normale
        }
        return MemoryPressure(sysctlLevel: level)
    }

    /// Processus lisibles par l'utilisateur courant. Ceux de root (WindowServer, kernel_task)
    /// sont refusés par le noyau et ignorés : ce ne sont pas des apps qu'on peut quitter.
    public static func processFootprints() -> [ProcessFootprint] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }

        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(count).compactMap { pid in
            guard pid > 0 else { return nil }
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0 else { return nil }
            let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard length > 0 else { return nil }
            let path = String(decoding: pathBuffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return ProcessFootprint(pid: pid, executablePath: path, bytes: Int64(info.ri_phys_footprint))
        }
    }
}
