import Foundation

@main
struct HistoryChecks {
    static func main() throws {
        let zoneName = ProcessInfo.processInfo.environment["TZ"] ?? TimeZone.current.identifier
        let expectedZone = TimeZone(identifier: zoneName)!
        let utc = HistoryAnalyzer.parseDate("2026-10-12T20:00:00.000Z")!
        let referenceFormatter = DateFormatter()
        referenceFormatter.locale = Locale(identifier: "en_US_POSIX")
        referenceFormatter.timeZone = expectedZone
        referenceFormatter.dateFormat = "yyyy-MM-dd"
        assert(HistoryAnalyzer.zone.secondsFromGMT(for: utc) == expectedZone.secondsFromGMT(for: utc), "use the device zone")
        assert(HistoryAnalyzer.dayFormatter.string(from: utc) == referenceFormatter.string(from: utc), "local midnight must follow the device")
        let january = HistoryAnalyzer.parseDate("2026-01-03T12:00:00Z")!
        let december = HistoryAnalyzer.apiDate("12月31日", reference: january)!
        assert(HistoryAnalyzer.dayFormatter.string(from: december) == "2025-12-31", "API chart years must cross the year boundary")
        let first = UsageRecord(date: utc, model: "known", input: 10, cached: 20, written: 5, output: 2, total: 37, cost: 0.2)
        let second = UsageRecord(date: utc, model: "unknown", input: 5, cached: 0, written: 0, output: 1, total: 6, cost: nil)
        let summary = HistoryAnalyzer.aggregate([first, second], provider: "fixture")[0]
        assert(summary.date == referenceFormatter.string(from: utc))
        assert(summary.total == 43 && summary.requests == 2 && summary.cost == nil, "unknown pricing must not become zero")
        assert(summary.pricedCost == 0.2, "known costs must survive mixed pricing")
        assert(summary.models.first(where: { $0.name == "known" })?.cost == 0.2)

        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        assert(HistoryAnalyzer.aggregate([first], provider: "fixture", timeZone: pacific)[0].date == "2026-10-12")
        assert(HistoryAnalyzer.aggregate([first], provider: "fixture", timeZone: tokyo)[0].date == "2026-10-13")
        assert(HistoryAnalyzer.dayFormatter(timeZone: pacific).string(from: utc) == "2026-10-12", "formatter must not retain the previous zone")
        let spring = HistoryAnalyzer.parseDate("2026-03-08T12:00:00Z")!
        let fall = HistoryAnalyzer.parseDate("2026-11-01T12:00:00Z")!
        let calendar = HistoryAnalyzer.calendar(timeZone: pacific)
        assert(calendar.dateInterval(of: .day, for: spring)!.duration == 23 * 3600, "spring DST day")
        assert(calendar.dateInterval(of: .day, for: fall)!.duration == 25 * 3600, "fall DST day")
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("aicost-fixture-" + UUID().uuidString)
        let pacificArchive = HistoryAnalyzer.archiveURL(support: support, timeZone: pacific)
        let tokyoArchive = HistoryAnalyzer.archiveURL(support: support, timeZone: tokyo)
        assert(pacificArchive != tokyoArchive, "never reuse buckets from another zone")
        assert(pacificArchive != support.appendingPathComponent("Aicost/history-v1.json"), "preserve legacy daily history")
        let legacy = Data(#"{"days":[],"sources":{},"updatedAt":0,"warnings":[]}"#.utf8)
        let legacyResult = try JSONDecoder().decode(HistoryResult.self, from: legacy)
        assert(legacyResult.timeZoneIdentifier == nil)
        let zoned = HistoryResult(days: [summary], sources: [:], updatedAt: utc, warnings: [], timeZoneIdentifier: zoneName)
        let decoded = try JSONDecoder().decode(HistoryResult.self, from: JSONEncoder().encode(zoned))
        assert(decoded.timeZoneIdentifier == zoneName)
        for diagnostic in [UsageDiagnostic.quotaReadFailed, .loginUpdateFailed] {
            let english = diagnostic.message(isEnglish: true)
            assert(english.unicodeScalars.allSatisfy { $0.value < 128 }, "English errors must not inherit Chinese OS text")
            assert(diagnostic.message(isEnglish: false) != english, "existing errors must change language")
        }
        print("PASS [\(zoneName)]: local days, zone isolation, DST, year rollover, pricing and diagnostics")
    }
}
