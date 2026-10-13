import Foundation

@main
struct HistoryChecks {
    static func main() throws {
        let utc = HistoryAnalyzer.parseDate("2026-10-12T20:00:00.000Z")!
        assert(HistoryAnalyzer.dayFormatter.string(from: utc) == "2026-10-13", "local midnight must use Asia/Shanghai")
        let january = HistoryAnalyzer.parseDate("2026-01-03T12:00:00Z")!
        let december = HistoryAnalyzer.apiDate("12月31日", reference: january)!
        assert(HistoryAnalyzer.dayFormatter.string(from: december) == "2025-12-31", "API chart years must cross the year boundary")
        let first = UsageRecord(date: utc, model: "known", input: 10, cached: 20, written: 5, output: 2, total: 37, cost: 0.2)
        let second = UsageRecord(date: utc, model: "unknown", input: 5, cached: 0, written: 0, output: 1, total: 6, cost: nil)
        let summary = HistoryAnalyzer.aggregate([first, second], provider: "fixture")[0]
        assert(summary.total == 43 && summary.requests == 2 && summary.cost == nil, "unknown pricing must not become zero")
        assert(summary.pricedCost == 0.2, "known costs must survive mixed pricing")
        assert(summary.models.first(where: { $0.name == "known" })?.cost == 0.2)
        print("PASS: timezone, year rollover, aggregation and pricing coverage")
    }
}
