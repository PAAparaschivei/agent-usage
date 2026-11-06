public enum UsageAlertPolicy {
    public static let thresholds = [20, 10, 5]

    public static func nextThreshold(
        leftPercent: Int,
        alreadySent: Set<Int>
    ) -> Int? {
        thresholds
            .filter { leftPercent <= $0 && !alreadySent.contains($0) }
            .min()
    }
}
