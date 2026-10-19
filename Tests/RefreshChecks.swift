import Foundation
import Combine

@MainActor
final class RefreshFixture {
    var calls: [Bool] = []
    var scanCount = 0
    var failQuota = false
    var apiFirst = true
    var activitySignature = "initial"
    var mismatchedScans = 0

    func readers() -> UsageReaders {
        UsageReaders(quotas: { [self] force in
            calls.append(force)
            try await Task.sleep(nanoseconds: apiFirst ? 250_000_000 : 10_000_000)
            if failQuota { throw URLError(.timedOut) }
            return Data(#"{"generatedAt":"2026-10-19T01:00:00Z","providers":{"codex":{"fetchedAt":"2026-10-19T01:00:00Z","resources":{"weekly":{"remaining":20,"limit":100,"windowSeconds":604800}}}}}"#.utf8)
        }, openUsage: { [self] in
            if !apiFirst { try await Task.sleep(nanoseconds: 100_000_000) }
            return Data(#"[{"providerId":"codex","fetchedAt":"2026-10-19T02:00:00Z","lines":[{"type":"progress","label":"weekly","used":30,"limit":100,"periodDurationMs":604800000}]}]"#.utf8)
        }, history: { [self] _ in
            scanCount += 1
            return HistoryResult(days: [UsageDay(provider: "codex", date: "2026-10-19", total: 42, cost: nil, requests: 1, detailed: true)], sources: ["codex": "fixture"], updatedAt: Date(), warnings: [], timeZoneIdentifier: scanCount <= mismatchedScans ? "stale-zone" : HistoryAnalyzer.zone.identifier)
        }, activity: { [self] in activitySignature })
    }
}

@main
struct RefreshChecks {
    @MainActor static func main() async throws {
        let fixture = RefreshFixture()
        let store = UsageStore(restoreHistory: false, readers: fixture.readers())
        var publishedWhileRefreshing = false
        let observation = store.$history.dropFirst().sink { _ in
            if store.isRefreshing { publishedWhileRefreshing = true }
        }
        let refresh = Task { await store.refresh(force: true) }
        try await Task.sleep(nanoseconds: 70_000_000)
        assert(store.isRefreshing && store.history.days.first?.total == 42, "local statistics must publish before a slow remote quota finishes")
        await store.refresh(force: true)
        await store.refresh(force: true)
        await refresh.value
        assert(publishedWhileRefreshing && !store.isRefreshing)
        assert(fixture.calls == [true] && fixture.scanCount == 1, "repeated requests must coalesce into one forced refresh")
        assert(abs((store.providers.first?.metrics.first?.remaining ?? 0) - 0.7) < 0.001, "newer OpenUsage quota must survive a slower helper response")
        withExtendedLifetime(observation) {}

        let escalation = RefreshFixture()
        let cachedStore = UsageStore(restoreHistory: false, readers: escalation.readers())
        let cachedRefresh = Task { await cachedStore.refresh(force: false) }
        try await Task.sleep(nanoseconds: 50_000_000)
        await cachedStore.refresh(force: true)
        await cachedStore.refresh(force: true)
        await cachedRefresh.value
        assert(escalation.calls == [false, true] && escalation.scanCount == 2, "a forced request during a cached refresh must run once afterwards")

        let reverse = RefreshFixture()
        reverse.apiFirst = false
        let reverseStore = UsageStore(restoreHistory: false, readers: reverse.readers())
        await reverseStore.refresh(force: true)
        assert(abs((reverseStore.providers.first?.metrics.first?.remaining ?? 0) - 0.7) < 0.001, "the newer API wins in either completion order")

        let failing = RefreshFixture()
        failing.failQuota = true
        let failingStore = UsageStore(restoreHistory: false, readers: failing.readers())
        await failingStore.refresh(force: true)
        assert(!failingStore.isRefreshing && failingStore.history.days.first?.total == 42 && failingStore.error != nil, "a failed quota request must not discard local history or leave refresh stuck")
        let active = RefreshFixture()
        let activeStore = UsageStore(restoreHistory: false, readers: active.readers())
        await activeStore.checkRealtimeActivity()
        active.activitySignature = "new-local-message"
        await activeStore.checkRealtimeActivity()
        assert(active.scanCount == 1 && active.calls.isEmpty && activeStore.history.days.first?.total == 42,
               "local activity must update history without making remote quota requests")
        await activeStore.checkRealtimeActivity()
        assert(active.scanCount == 1, "an unchanged signature must not rescan")

        let movedZone = RefreshFixture()
        movedZone.mismatchedScans = 1
        let zoneStore = UsageStore(restoreHistory: false, readers: movedZone.readers())
        await zoneStore.refresh(force: true)
        assert(movedZone.scanCount == 2 && movedZone.calls == [true] && zoneStore.history.days.first?.total == 42,
               "a time-zone change during scanning must retry only the local collection")

        var planLookups = 0
        var cliLookups = 0
        let agReaders = UsageReaders(quotas: { _ in
            Data(#"{"providers":{"antigravity":{"plan":"Gemini","resources":{"nonGeminiSession":{"remaining":100,"limit":100,"windowSeconds":18000}}}}}"#.utf8)
        }, openUsage: { Data("[]".utf8) }, history: { _ in
            HistoryResult(days: [], sources: [:], updatedAt: Date(), warnings: [], timeZoneIdentifier: HistoryAnalyzer.zone.identifier)
        }, antigravity: {
            cliLookups += 1
            return AntigravitySupplement(windows: [.init(id: "geminiSession", remaining: 0.75, reset: nil)], plan: "Pro")
        }, antigravityPlan: {
            planLookups += 1
            return nil // No client running and no Runway auth cache: CLI-only login.
        })
        let agStore = UsageStore(restoreHistory: false, readers: agReaders)
        await agStore.refresh(force: true)
        assert(agStore.providers.first?.plan == "Pro", "a CLI-only subscription must populate the plan label")
        await agStore.refresh(force: true)
        assert(agStore.providers.first?.plan == "Pro" && cliLookups == 2 && planLookups == 1,
               "subsequent generic helper plans must retain the real subscription without duplicate remote lookups")
        assert(agStore.providers.first?.statusBarMetric()?.id == "geminiSession")

        print("PASS: early local publication, request coalescing, forced escalation, quota ordering, failure recovery and local-only activity updates and CLI-only subscription plans")
    }
}
