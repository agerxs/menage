import Foundation

/// Tailles en unités décimales (comme le Finder) et à la française : « 33,2 Go », « 142 Go », « 650 Mo ».
public enum ByteFormat {
    private static let units = ["octets", "Ko", "Mo", "Go", "To"]

    public static func string(_ bytes: Int64) -> String {
        guard bytes >= 1000 else { return "\(max(bytes, 0)) octets" }
        var value = Double(bytes)
        var unit = 0
        while value >= 999.95 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let digits = value < 100 ? 1 : 0
        let number = String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
        return "\(number) \(units[unit])"
    }

    public static func gigabytes(_ value: Double) -> Int64 {
        Int64(value * 1_000_000_000)
    }

    /// La RAM se compte en unités binaires : un Mac « 24 Go » a 24 × 2³⁰ octets, soit 25,8 Go décimaux.
    public static func ramGigabytes(_ bytes: Int64) -> Double {
        Double(bytes) / 1_073_741_824
    }

    public static func ram(_ bytes: Int64) -> String {
        "\(Int(ramGigabytes(bytes).rounded())) Go"
    }
}
