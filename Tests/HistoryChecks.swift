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
        let session = QuotaWindows.reading(id: "session", remaining: 0.15, windowSeconds: 18_000)
        let weekly = QuotaWindows.reading(id: "weekly", remaining: 0, windowSeconds: 604_800)
        let codex = [session, weekly]
        assert(session.kind == .session && session.isFiveHour && session.id == "session")
        assert(weekly.kind == .weekly && !weekly.isFiveHour)
        assert(QuotaWindows.orderedIndices(codex).map { codex[$0].id } == ["session", "weekly"])
        assert(QuotaWindows.primaryIndex(codex, mode: "current").map { codex[$0].id } == "weekly", "a used-up weekly window blocks the leftover 5-hour balance")
        assert(QuotaWindows.primaryIndex(codex, mode: "weekly").map { codex[$0].id } == "weekly")
        let openWeek = [
            QuotaWindows.reading(id: "session", remaining: 0.15, windowSeconds: 18_000),
            QuotaWindows.reading(id: "weekly", remaining: 0.40, windowSeconds: 604_800)
        ]
        assert(QuotaWindows.primaryIndex(openWeek, mode: "current").map { openWeek[$0].id } == "session")
        assert(QuotaWindows.primaryIndex(openWeek, mode: "weekly").map { openWeek[$0].id } == "weekly")
        assert(QuotaWindows.primaryIndex(openWeek, mode: "minimum").map { openWeek[$0].id } == "session")
        let monthLabeledSession = QuotaWindows.reading(id: "session", remaining: 0.62, windowSeconds: 2_592_000)
        assert(monthLabeledSession.id == "monthly" && monthLabeledSession.kind == .monthly && !monthLabeledSession.isFiveHour, "a 30-day window is monthly even when the slot is named session")
        let bothBlocked = [
            QuotaWindows.reading(id: "session", remaining: 0.15, windowSeconds: 18_000),
            QuotaWindows.reading(id: "weekly", remaining: 0, windowSeconds: 604_800),
            QuotaWindows.reading(id: "monthly", remaining: 0, windowSeconds: 2_592_000)
        ]
        assert(QuotaWindows.primaryIndex(bothBlocked, mode: "current").map { bothBlocked[$0].id } == "monthly")
        assert(QuotaWindows.primaryIndex(bothBlocked, mode: "monthly").map { bothBlocked[$0].id } == "monthly")
        let gemini = QuotaWindows.reading(id: "geminiSession", remaining: 0.20, windowSeconds: 18_000)
        let geminiWeek = QuotaWindows.reading(id: "geminiWeekly", remaining: 0, windowSeconds: 604_800)
        assert(gemini.id == "geminiSession" && gemini.isFiveHour)
        assert(QuotaWindows.primaryIndex([gemini, geminiWeek], mode: "current").map { [gemini, geminiWeek][$0].id } == "geminiWeekly")
        let cursor = [QuotaWindows.reading(id: "totalUsage", remaining: 0.33, windowSeconds: nil)]
        assert(cursor[0].kind == .other)
        assert(QuotaWindows.primaryIndex(cursor, mode: "current") == 0)
        assert(QuotaWindows.statusBarIndex(openWeek).map { openWeek[$0].id } == "session", "an open weekly allowance keeps the 5-hour figure on the menu bar")
        assert(!QuotaWindows.hidesSessionOnStatusBar(openWeek))
        assert(QuotaWindows.statusBarIndex(codex).map { codex[$0].id } == "weekly")
        assert(QuotaWindows.hidesSessionOnStatusBar(codex))
        let monthOnly = [QuotaWindows.reading(id: "monthly", remaining: 0.55, windowSeconds: 2_592_000)]
        assert(QuotaWindows.statusBarIndex(monthOnly).map { monthOnly[$0].id } == "monthly")
        let monthOpen = [
            QuotaWindows.reading(id: "session", remaining: 0.15, windowSeconds: 18_000),
            QuotaWindows.reading(id: "monthly", remaining: 0.70, windowSeconds: 2_592_000)
        ]
        assert(QuotaWindows.statusBarIndex(monthOpen).map { monthOpen[$0].id } == "session")
        let monthBlocked = [
            QuotaWindows.reading(id: "session", remaining: 0.15, windowSeconds: 18_000),
            QuotaWindows.reading(id: "monthly", remaining: 0, windowSeconds: 2_592_000)
        ]
        assert(QuotaWindows.statusBarIndex(monthBlocked).map { monthBlocked[$0].id } == "monthly")
        assert(QuotaWindows.hidesSessionOnStatusBar(monthBlocked))
        assert(QuotaWindows.statusBarIndex(cursor) == 0)
        let mixed = [
            QuotaWindows.reading(id: "geminiSession", remaining: 0.80, windowSeconds: 18_000),
            QuotaWindows.reading(id: "geminiWeekly", remaining: 0.60, windowSeconds: 604_800),
            QuotaWindows.reading(id: "nonGeminiSession", remaining: 0.05, windowSeconds: 18_000),
            QuotaWindows.reading(id: "nonGeminiWeekly", remaining: 0, windowSeconds: 604_800)
        ]
        let grokUsage = Data(#"""
        {"turns":[
          {"endedAt":"2026-10-17T01:00:00Z","inputTokens":150,"outputTokens":20,"cachedReadTokens":100,"cacheCreationTokens":5,"primaryModelId":"grok-4.7-build","modelUsage":{"grok-4.7-build":{"inputTokens":150,"outputTokens":20,"cachedReadTokens":100,"cacheCreationTokens":5},"grok-4.6-build":{"inputTokens":10,"outputTokens":1,"cachedReadTokens":4,"cacheCreationTokens":0}}},
          {"endedAt":"2026-10-17T02:00:00Z","inputTokens":40,"outputTokens":10,"cachedReadTokens":0,"cacheCreationTokens":0,"primaryModelId":"grok-4.5"}
        ]}
        """#.utf8)
        let fixtures = FileManager.default.temporaryDirectory.appendingPathComponent("aicost-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtures) }
        let grokCatalog = PriceCatalog(base: fixtures.appendingPathComponent("isolated/pricing"))
        let grokRecords = HistoryAnalyzer.parseGrokUsage(grokUsage, catalog: grokCatalog) ?? []
        assert(grokRecords.count == 3, "each Grok model in a turn is its own row, and a turn without modelUsage still counts")
        let grokBuild = grokRecords.first { $0.model == "grok-4.7-build" }
        assert(grokBuild?.input == 50 && grokBuild?.cached == 100 && grokBuild?.written == 5 && grokBuild?.output == 20 && grokBuild?.total == 175)
        assert(grokRecords.contains { $0.model == "grok-4.6-build" && $0.total == 11 })
        assert(grokRecords.contains { $0.model == "grok-4.5" && $0.input == 40 && $0.total == 50 })
        assert(HistoryAnalyzer.parseGrokUsage(Data("{}".utf8), catalog: grokCatalog)?.isEmpty == true)
        assert(HistoryAnalyzer.parseGrokUsage(Data("not-json".utf8), catalog: grokCatalog) == nil)
        let geminiQuota = Data(#"""
        {"buckets":[
          {"modelId":"claude-opus-4-6-thinking","remainingFraction":0.1,"resetTime":"2026-10-17T17:00:00Z"},
          {"modelId":"gemini-3.5-flash","remainingFraction":0.4,"resetTime":"2026-10-17T16:00:00Z"},
          {"modelId":"gemini-3-flash","remainingFraction":0.7,"resetTime":"2026-10-17T18:00:00Z"}
        ]}
        """#.utf8)
        let agyUsage = Data(#"""
        {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[
          {"name":"Gemini Models","buckets":[
            {"id":"gemini-weekly","window":"weekly","remaining_fraction":0.76,"reset_time":"2026-10-24T02:07:14Z"},
            {"id":"gemini-5h","window":"5h","remaining_fraction":1,"reset_time":"2026-10-17T17:07:14Z"},
            {"id":"gemini-5h","window":"5h","remaining_fraction":0,"disabled":true}
          ]},
          {"name":"Claude and GPT models","buckets":[
            {"id":"3p-weekly","window":"weekly","remaining_fraction":1},
            {"id":"3p-5h","window":"5h","remaining_fraction":1}
          ]}
        ]}}}
        """#.utf8)
        let agyWindows = AntigravityGeminiQuota.pools(fromAgy: agyUsage)
        assert(agyWindows.map(\.id) == ["geminiSession", "geminiWeekly"], "Antigravity keeps Gemini 5h and weekly, and leaves out other models")
        assert(agyWindows[0].remaining == 1 && agyWindows[1].remaining == 0.76)
        assert(agyWindows[1].reset == HistoryAnalyzer.parseDate("2026-10-24T02:07:14Z"))
        let geminiWindow = AntigravityGeminiQuota.session(from: geminiQuota)
        assert(geminiWindow?.remaining == 0.4, "the main Antigravity subscription uses the tightest Gemini window")
        assert(geminiWindow?.reset == HistoryAnalyzer.parseDate("2026-10-17T16:00:00Z"))
        assert(AntigravityGeminiQuota.session(from: Data(#"{"buckets":[{"modelId":"claude-sonnet-4-6","remainingFraction":0.2}]}"#.utf8)) == nil)
        assert(QuotaWindows.statusBarIndex(mixed).map { mixed[$0].id } == "geminiSession", "Antigravity's menu bar follows the Gemini pool")
        assert(QuotaWindows.primaryIndex(mixed, mode: "current").map { mixed[$0].id } == "geminiSession")
        assert(!QuotaWindows.hidesSessionOnStatusBar(mixed))

        let codexWithSpark = openWeek + [
            QuotaWindows.reading(id: "spark", remaining: 0, windowSeconds: nil),
            QuotaWindows.reading(id: "sparkWeekly", remaining: 0, windowSeconds: 604_800)
        ]
        assert(codexWithSpark[2].kind == .session)
        assert(QuotaWindows.statusBarIndex(codexWithSpark) == 0, "an exhausted optional Spark pool must not block regular Codex quota")
        assert(!QuotaWindows.hidesSessionOnStatusBar(codexWithSpark))
        assert(QuotaWindows.orderedIndices(codexWithSpark).count == 4, "the quota card retains both pools")
        assert(QuotaWindows.statusBarIndex(Array(codexWithSpark.suffix(2))) == 1, "Spark-only results still show their exhausted week")

        let almostUsedWeek = [session, QuotaWindows.reading(id: "weekly", remaining: 0.004, windowSeconds: 604_800)]
        assert(!QuotaWindows.isExhausted(0.004), "a positive sub-percent quota is not exhausted")
        assert(QuotaWindows.statusBarIndex(almostUsedWeek) == 0)
        assert(!QuotaWindows.hidesSessionOnStatusBar(almostUsedWeek))
        assert(QuotaWindows.percentageText(0.004) == "<1%")
        assert(QuotaWindows.displayedPercent(0.004) > 0, "the badge must not say depleted")
        assert(QuotaWindows.percentageText(0) == "0%" && QuotaWindows.percentageText(1) == "100%")
        assert(QuotaWindows.percentageText(.infinity) == "—")
        let duplicateWindows = distinctMetrics([
            Metric(id: "monthly", remaining: 0.2, reset: nil, kind: .monthly),
            Metric(id: "monthly", remaining: 0.4, reset: nil, kind: .monthly)
        ])
        assert(Set(duplicateWindows.map(\.id)).count == 2)
        assert(duplicateWindows[1].labelID == "monthly", "UI identities must not leak suffixes into translated names")
        let partialGemini = AntigravityGeminiQuota.merging([
            AntigravityGeminiQuota.PoolWindow(id: "geminiSession", remaining: 0.8, reset: nil)
        ], into: [Metric(id: "geminiWeekly", remaining: 0, reset: nil, kind: .weekly)])
        assert(partialGemini.contains { $0.id == "geminiWeekly" && $0.remaining == 0 }, "partial responses must retain a known blocking week")
        let errorResponse = Data(#"{"status":"ERROR","groups":[{"buckets":[{"id":"gemini-5h","remaining_fraction":1}]}]}"#.utf8)
        assert(AntigravityGeminiQuota.pools(fromAgy: errorResponse).isEmpty)
        let invalidGrok = Data(#"{"turns":[{"endedAt":"2026-10-17T01:00:00Z","inputTokens":10,"outputTokens":-1},{"endedAt":"2026-10-17T01:00:00Z","inputTokens":1e308,"outputTokens":1e308}]}"#.utf8)
        assert(HistoryAnalyzer.parseGrokUsage(invalidGrok, catalog: grokCatalog)?.isEmpty == true)
        checkMalformedHistory(catalog: grokCatalog)
        try checkLocalCommands()

        for diagnostic in [UsageDiagnostic.quotaReadFailed, .loginUpdateFailed] {
            let english = diagnostic.message(isEnglish: true)
            assert(english.unicodeScalars.allSatisfy { $0.value < 128 }, "English errors must not inherit Chinese OS text")
            assert(diagnostic.message(isEnglish: false) != english, "existing errors must change language")
        }
        print("PASS [\(zoneName)]: local days, zone isolation, DST, year rollover, pricing, diagnostics and quota windows")
    }

    static func varint(_ value: UInt64) -> Data {
        var value = value
        var bytes = Data()
        while value >= 128 {
            bytes.append(UInt8(value & 127) | 128)
            value >>= 7
        }
        bytes.append(UInt8(value))
        return bytes
    }

    static func field(_ number: UInt64, _ contents: Data) -> Data {
        varint(number * 8 + 2) + varint(UInt64(contents.count)) + contents
    }

    static func checkMalformedHistory(catalog: PriceCatalog) {
        let oversized = Data([0x0A]) + Data(repeating: 0xFF, count: 9) + Data([0x01])
        assert(HistoryAnalyzer.decodeAntigravityRow(genData: oversized, stepData: nil, catalog: catalog) == nil)
        let overflowingVarint = Data([0x0A]) + Data(repeating: 0xFF, count: 9) + Data([0x02])
        assert(HistoryAnalyzer.decodeAntigravityRow(genData: overflowingVarint, stepData: nil, catalog: catalog) == nil)
        let timestamp = field(1, Data([0x08]) + varint(1_760_000_000))
        let usage = Data([0x08, 5, 0x18, 2])
        let valid = field(1, field(4, usage) + field(19, Data("fixture".utf8)))
        let parsed = HistoryAnalyzer.decodeAntigravityRow(genData: valid, stepData: timestamp, catalog: catalog)
        assert(parsed?.model == "fixture" && parsed?.total == 7)
        let largeUsage = Data([0x08]) + varint(UInt64(Int64.max)) + Data([0x10, 1])
        assert(HistoryAnalyzer.decodeAntigravityRow(genData: field(1, field(4, largeUsage)), stepData: timestamp, catalog: catalog) == nil)
        let skippedOversized = field(1, Data([0x12]) + varint(UInt64(Int.max)) + field(4, usage))
        assert(HistoryAnalyzer.decodeAntigravityRow(genData: skippedOversized, stepData: timestamp, catalog: catalog) == nil)
        let invalidUsage = field(1, field(4, Data([0x12]) + varint(UInt64.max)))
        assert(HistoryAnalyzer.decodeAntigravityRow(genData: invalidUsage, stepData: timestamp, catalog: catalog) == nil)
        let badTimestamp = field(1, Data([0x08]) + varint(UInt64(Int64.max)))
        assert(HistoryAnalyzer.decodeAntigravityRow(genData: valid, stepData: badTimestamp, catalog: catalog) == nil)
    }

    static func checkLocalCommands() throws {
        let shell = URL(fileURLWithPath: "/bin/sh")
        let result = try LocalCommand.run(executable: shell, arguments: ["-c", "printf fixture"], timeout: 2)
        assert(result.status == 0 && result.data == Data("fixture".utf8))
        let failure = try LocalCommand.run(executable: shell, arguments: ["-c", "exit 7"], timeout: 2)
        assert(failure.status == 7)
        do {
            _ = try LocalCommand.run(executable: shell, arguments: ["-c", "printf 123456789"], timeout: 2, maxOutputBytes: 4)
            assertionFailure("oversized stdout must be rejected")
        } catch LocalCommand.Failure.outputTooLarge {}
        for script in ["trap '' TERM; while :; do sleep 1; done", "exec 1>&-; sleep 2", "sleep 2 & exit 0"] {
            let start = ProcessInfo.processInfo.systemUptime
            do {
                _ = try LocalCommand.run(executable: shell, arguments: ["-c", script], timeout: 0.15)
                assertionFailure("a hung command must time out")
            } catch LocalCommand.Failure.timedOut {}
            assert(ProcessInfo.processInfo.systemUptime - start < 1.8, "timeout includes a bounded termination grace period")
        }
    }

}
