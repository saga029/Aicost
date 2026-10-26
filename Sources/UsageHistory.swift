import Foundation
import CryptoKit
import SQLite3
import Darwin

/// Bounded local reads: a child ignoring SIGTERM, closing stdout early, or
/// leaving stdout open in a descendant must not hold a refresh indefinitely.
enum LocalCommand {
    enum Failure: Error { case timedOut, outputTooLarge, readFailed }
    struct Result {
        let data: Data
        let status: Int32
    }

    static func run(executable: URL, arguments: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval, maxOutputBytes: Int = 8_388_608) throws -> Result {
        let process = Process()
        let pipe = Pipe()
        let exited = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        try? pipe.fileHandleForWriting.close()
        defer {
            if process.isRunning {
                process.terminate()
                if exited.wait(timeout: .now() + 0.2) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    _ = exited.wait(timeout: .now() + 1)
                }
            }
            try? pipe.fileHandleForReading.close()
        }
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else { throw Failure.readFailed }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw Failure.timedOut }
            var descriptorState = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
            let ready = poll(&descriptorState, 1, Int32(min(100, remaining * 1000)))
            if ready < 0 {
                if errno == EINTR { continue }
                throw Failure.readFailed
            }
            guard ready > 0 else { continue }
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard count <= maxOutputBytes - data.count else { throw Failure.outputTooLarge }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK {
                throw Failure.readFailed
            }
        }
        // EOF is not proof of process exit: a child can close stdout then hang.
        let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        guard exited.wait(timeout: .now() + remaining) == .success else { throw Failure.timedOut }
        return Result(data: data, status: process.terminationStatus)
    }
}

struct AntigravitySupplement {
    var windows: [AntigravityGeminiQuota.PoolWindow] = []
    var plan: String? = nil
}

/// Query only the current user's Antigravity loopback servers. The CLI started
/// by Aicost gets a fresh CSRF token, so no Keychain prompt or token export is
/// needed to read its subscription type. Never log process arguments or bodies.
enum AntigravityLocalPlan {
    static func flag(_ name: String, in command: String) -> String? {
        let pattern = "(?:^|\\s)" + NSRegularExpression.escapedPattern(for: name) + "(?:=|\\s+)([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
              let range = Range(match.range(at: 1), in: command) else { return nil }
        let value = String(command[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return value.isEmpty ? nil : value
    }

    static func ports(from listing: String) -> [Int] {
        Array(Set(listing.split(whereSeparator: \.isNewline).compactMap { line -> Int? in
            guard line.hasPrefix("n"), let last = line.split(separator: ":").last,
                  let port = Int(last), (1...65535).contains(port) else { return nil }
            return port
        })).sorted()
    }

    static func read(expectedCSRF: String? = nil, waitForLaunch: Bool = false) -> String? {
        let deadline = ProcessInfo.processInfo.systemUptime + (waitForLaunch ? 8 : 3)
        repeat {
            guard let listing = try? LocalCommand.run(executable: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-U", String(getuid()), "-ww", "-o", "pid=,args="], timeout: 0.5), listing.status == 0 else { return nil }
            let rows = String(decoding: listing.data, as: UTF8.self).split(whereSeparator: \.isNewline)
            for row in rows {
                let fields = row.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard fields.count == 2, let pid = Int32(fields[0]) else { continue }
                let command = String(fields[1])
                let executable = command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
                let isCLI = URL(fileURLWithPath: executable).lastPathComponent == "agy"
                let isClient = executable.lowercased().contains("antigravity") && executable.contains("language_server")
                guard isCLI || isClient,
                      let csrf = flag("--csrf_token", in: command),
                      expectedCSRF == nil || csrf == expectedCSRF else { continue }
                guard let listeners = try? LocalCommand.run(executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
                    arguments: ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"], timeout: 0.7) else { continue }
                var available = ports(from: String(decoding: listeners.data, as: UTF8.self))
                if let value = flag("--extension_server_port", in: command), let port = Int(value),
                   (1...65535).contains(port), !available.contains(port) { available.append(port) }
                for port in available.prefix(4) {
                    for scheme in ["https", "http"] {
                        let remaining = deadline - ProcessInfo.processInfo.systemUptime
                        guard remaining > 0.1 else { return nil }
                        let timeout = min(1.5, remaining)
                        let url = "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus"
                        let body = #"{"metadata":{"ideName":"antigravity","extensionName":"antigravity","ideVersion":"unknown","locale":"en"}}"#
                        let arguments = ["--silent", "--fail", "--insecure", "--noproxy", "*", "--connect-timeout", "0.3",
                            "--max-time", String(timeout), "-H", "Content-Type: application/json", "-H", "Connect-Protocol-Version: 1",
                            "-H", "x-codeium-csrf-token: " + csrf, "-d", body, url]
                        if let result = try? LocalCommand.run(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                            arguments: arguments, timeout: timeout + 0.2, maxOutputBytes: 2_097_152), result.status == 0,
                           let plan = AntigravityGeminiQuota.subscriptionPlan(from: result.data) { return plan }
                    }
                }
            }
            if !waitForLaunch { return nil }
            Thread.sleep(forTimeInterval: 0.15)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return nil
    }
}

struct UsageModel: Codable, Identifiable {
    var id: String { name }
    let name: String
    var input: Double = 0
    var cached: Double = 0
    var written: Double = 0
    var output: Double = 0
    var total: Double = 0
    var cost: Double? = 0
    var knownCost: Double? = nil
    var requests: Int = 0
    var pricedCost: Double { knownCost ?? cost ?? 0 }
}

struct UsageDay: Codable, Identifiable {
    var id: String { provider + ":" + date }
    let provider: String
    let date: String
    var input: Double = 0
    var cached: Double = 0
    var written: Double = 0
    var output: Double = 0
    var total: Double = 0
    var cost: Double? = 0
    var knownCost: Double? = nil
    var requests: Int? = 0
    var models: [UsageModel] = []
    var detailed: Bool = true
    var pricedCost: Double { knownCost ?? cost ?? 0 }
    var dateValue: Date { HistoryAnalyzer.dayFormatter.date(from: date) ?? Date.distantPast }
}

struct HistoryResult: Codable {
    var days: [UsageDay]
    var sources: [String: String]
    var updatedAt: Date
    var warnings: [String]
    var timeZoneIdentifier: String? = nil
    var antigravityHistoryVersion: Int? = nil
}

// Store diagnostic identities rather than language-specific text. The UI can
// then change language immediately, even while an error is still displayed.
enum UsageDiagnostic: String, Codable {
    case quotaReadFailed
    case loginUpdateFailed

    func message(isEnglish: Bool) -> String {
        switch self {
        case .quotaReadFailed:
            return isEnglish
                ? "Could not read quotas. Previous results were kept. Try rescanning in Settings."
                : "额度读取失败，已保留上次结果。可在设置里重新扫描。"
        case .loginUpdateFailed:
            return isEnglish
                ? "Could not update launch at login. Try again or check Login Items in System Settings."
                : "登录项设置未完成。请重试，或在系统设置的登录项中检查。"
        }
    }
}

struct UsageRecord: Codable {
    let date: Date
    let model: String
    let input: Double
    let cached: Double
    let written: Double
    let output: Double
    let total: Double
    let cost: Double?
}

struct CodexFileCache: Codable {
    let size: UInt64
    let modified: Date
    let records: [UsageRecord]
}

/// Contains only hashed message identities and numeric usage metadata.
struct ClaudeFileCache: Codable {
    let size: UInt64
    let modified: Date
    let messages: [String: UsageRecord]
}

struct AntigravityFileCache: Codable {
    let dbSize: UInt64
    let dbModified: Date
    let walSize: UInt64
    let walModified: Date
    let records: [UsageRecord]
}

struct PriceCatalog {
    private var prices: [String: [String: Double]] = [:]
    private var aliases: [(NSRegularExpression, String)] = []
    private var fast: [String: Double] = [:]

    init(base: URL) {
        let support = base.deletingLastPathComponent().deletingLastPathComponent()
        let pricingDirs = [
            support.appendingPathComponent("OpenUsage/pricing"),
            support.appendingPathComponent("Runway/pricing"),
            base
        ]
        for dir in pricingDirs {
            for name in ["litellm.json", "models_dev.json"] {
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = root["models"] as? [String: [String: Any]] else { continue }
                for (model, value) in rows {
                    var entry: [String: Double] = [
                        "i": value["i"] as? Double ?? 0,
                        "o": value["o"] as? Double ?? 0,
                        "cr": value["cr"] as? Double ?? 0,
                        "cw": value["cw"] as? Double ?? 0
                    ]
                    if let v = value["i200"] as? Double { entry["i200"] = v }
                    if let v = value["o200"] as? Double { entry["o200"] = v }
                    if let v = value["cr200"] as? Double { entry["cr200"] = v }
                    if let v = value["cw200"] as? Double { entry["cw200"] = v }
                    prices[model.lowercased()] = entry
                }
            }
            if let data = try? Data(contentsOf: dir.appendingPathComponent("supplement.json")),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (model, value) in root["pricing"] as? [String: [String: Any]] ?? [:] {
                    var entry: [String: Double] = [
                        "i": value["input_per_million"] as? Double ?? 0,
                        "o": value["output_per_million"] as? Double ?? 0,
                        "cr": value["cache_read_per_million"] as? Double ?? 0,
                        "cw": value["cache_write_per_million"] as? Double ?? 0
                    ]
                    if let v = value["input_per_million_above_200k"] as? Double { entry["i200"] = v }
                    if let v = value["output_per_million_above_200k"] as? Double { entry["o200"] = v }
                    if let v = value["cache_read_per_million_above_200k"] as? Double { entry["cr200"] = v }
                    if let v = value["cache_write_per_million_above_200k"] as? Double { entry["cw200"] = v }
                    prices[model.lowercased()] = entry
                }
                if let f = root["fast_multipliers"] as? [String: Double], !f.isEmpty {
                    fast = f
                }
                let parsedAliases = (root["alias_rules"] as? [[String: String]] ?? []).compactMap { row -> (NSRegularExpression, String)? in
                    guard let pattern = row["pattern"], let name = row["canonical"],
                          let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
                    return (regex, name.lowercased())
                }
                if !parsedAliases.isEmpty {
                    aliases = parsedAliases
                }
            }
        }
    }

    func canonicalModel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var canonical = trimmed.lowercased()
        for (regex, name) in aliases {
            if regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
                || regex.firstMatch(in: canonical, range: NSRange(canonical.startIndex..., in: canonical)) != nil {
                canonical = name
                break
            }
        }
        if canonical.hasPrefix("gemini-3.8-flash") { return "gemini-3.8-flash" }
        if canonical.hasPrefix("gemini-3.7-flash") { return "gemini-3.7-flash" }
        if canonical.hasPrefix("gemini-3.6-flash") { return "gemini-3.6-flash" }
        if canonical.hasPrefix("gemini-3.5-flash") { return "gemini-3.5-flash" }
        if canonical.hasPrefix("gemini-3.1-pro") { return "gemini-3.1-pro-preview" }
        return canonical
    }

    func estimate(model: String, input: Double, cached: Double, written: Double, output: Double, isFast: Bool = false) -> Double? {
        let canonical = canonicalModel(model)
        let candidates = [
            canonical,
            "google/" + canonical,
            "gemini/" + canonical,
            "vertex_ai/" + canonical,
            "openai/" + canonical,
            "anthropic/" + canonical,
            "xai/" + canonical
        ]
        guard let price = candidates.compactMap({ prices[$0] }).first else { return nil }
        let multiplier = isFast && !canonical.hasSuffix("-fast") ? (fast[canonical] ?? 1) : 1
        let isLongContext = (input + cached + written) > 200_000
        let iRate = (isLongContext ? price["i200"] : nil) ?? price["i", default: 0]
        let crRate = (isLongContext ? price["cr200"] : nil) ?? price["cr", default: 0]
        let cwRate = (isLongContext ? price["cw200"] : nil) ?? price["cw", default: 0]
        let oRate = (isLongContext ? price["o200"] : nil) ?? price["o", default: 0]
        return (input * iRate + cached * crRate + written * cwRate + output * oRate) / 1_000_000 * multiplier
    }
}

enum HistoryAnalyzer {
    static let antigravityHistoryVersion = 5
    static var zone: TimeZone { .autoupdatingCurrent }
    static var dayFormatter: DateFormatter { dayFormatter(timeZone: zone) }

    static func dayFormatter(timeZone: TimeZone) -> DateFormatter {
        let key = ("Aicost.dayFormatter." + timeZone.identifier) as NSString
        if let existing = Thread.current.threadDictionary[key] as? DateFormatter {
            return existing
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        Thread.current.threadDictionary[key] = formatter
        return formatter
    }
    static var calendar: Calendar { calendar(timeZone: zone) }
    static func calendar(timeZone: TimeZone) -> Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = timeZone; return value
    }

    static func archiveURL(support: URL, timeZone: TimeZone = zone) -> URL {
        // Already grouped daily totals cannot be moved accurately to another
        // time zone. Keep separate archives and reuse timestamped record caches.
        let digest = SHA256.hash(data: Data(timeZone.identifier.utf8)).map { String(format: "%02x", $0) }.joined()
        return storageFolder(support: support).appendingPathComponent("history-v2-\(digest).json")
    }

    static func storageFolder(support: URL) -> URL {
        let aicost = support.appendingPathComponent("Aicost")
        let legacy = support.appendingPathComponent("RunwayCustom")
        let fm = FileManager.default
        if !fm.fileExists(atPath: aicost.appendingPathComponent("history-v1.json").path),
           fm.fileExists(atPath: legacy.path) {
            try? fm.createDirectory(at: aicost, withIntermediateDirectories: true)
            for item in (try? fm.contentsOfDirectory(atPath: legacy.path)) ?? [] {
                let src = legacy.appendingPathComponent(item)
                let dst = aicost.appendingPathComponent(item)
                if !fm.fileExists(atPath: dst.path) {
                    try? fm.copyItem(at: src, to: dst)
                }
            }
        }
        return aicost
    }

    static func restoredDays(from prior: HistoryResult) -> [UsageDay] {
        // Old daily buckets can retain incorrectly dated usage even after the
        // per-file cache is rebuilt. Reconstruct only the affected provider.
        prior.days.filter { $0.provider != "antigravity" || prior.antigravityHistoryVersion == antigravityHistoryVersion }
    }

    static func collect(apiData: Data?) -> HistoryResult {
        // Freeze the zone for this scan if the device changes zones mid-refresh.
        let collectionZone = TimeZone(identifier: zone.identifier) ?? .current
        let dayFormatter = dayFormatter(timeZone: collectionZone)
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let base = support.appendingPathComponent("OpenUsage")
        let archive = archiveURL(support: support, timeZone: collectionZone)
        let catalog = PriceCatalog(base: base.appendingPathComponent("pricing"))
        var merged: [String: UsageDay] = [:]
        var sources: [String: String] = [:]
        var warnings: [String] = []
        var observedCodexPrices: [String: Double] = [:]
        if let data = try? Data(contentsOf: archive), let prior = try? JSONDecoder().decode(HistoryResult.self, from: data) {
            for day in restoredDays(from: prior) { merged[day.id] = day }
            sources = prior.sources
        }

        if let apiData, let rows = try? JSONSerialization.jsonObject(with: apiData) as? [[String: Any]] {
            for row in rows {
                guard let provider = row["providerId"] as? String else { continue }
                let fetched = (row["fetchedAt"] as? String).flatMap(parseDate) ?? Date()
                let lines = row["lines"] as? [[String: Any]] ?? []
                let chart = lines.first { $0["type"] as? String == "barChart" }
                for point in chart?["points"] as? [[String: Any]] ?? [] {
                    guard let label = point["label"] as? String, let total = point["value"] as? Double,
                          let date = apiDate(label, reference: fetched, timeZone: collectionZone) else { continue }
                    let day = UsageDay(provider: provider, date: dayFormatter.string(from: date), total: total,
                                       cost: nil, requests: nil, detailed: false)
                    if merged[day.id]?.detailed != true {
                        merged[day.id] = day
                    }
                }
                if sources[provider] == nil {
                    sources[provider] = "openusage"
                }
            }
        }

        let cache = base.appendingPathComponent("log-scan-cache")
        for provider in ["codex", "grok"] {
            var records: [UsageRecord] = []
            var stamp: Date?
            var cacheChanged = false
            for folder in (try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)) ?? [] {
                guard folder.lastPathComponent.hasPrefix(provider + "-") else { continue }
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.plist")),
                      let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let files = root["files"] as? [String: [String: Any]] else { continue }
                stamp = root["generatedAt"] as? Date
                for (path, file) in files {
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                       let size = attributes[.size] as? NSNumber,
                       let storedSize = file["size"] as? NSNumber, size != storedSize { cacheChanged = true }
                    guard let name = file["recordFileName"] as? String,
                          let data = try? Data(contentsOf: folder.appendingPathComponent("files/" + name)),
                          let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                    for item in object["items"] as? [[String: Any]] ?? [] {
                        guard let date = item["timestamp"] as? Date, let model = item["model"] as? String else { continue }
                        let tokens = provider == "grok" ? (item["tokens"] as? [String: Any] ?? [:]) : item
                        let number: (String) -> Double = { tokens[$0] as? Double ?? 0 }
                        let cached = number(provider == "grok" ? "cacheRead" : "cached")
                        let written = number("cacheWrite5m") + number("cacheWrite1h")
                        let input = provider == "codex" ? max(0, number("input") - cached) : number("input")
                        let output = number("output")
                        let total = provider == "codex" ? number("total") : input + cached + written + output
                        let cost = item["carriedCost"] as? Double ?? catalog.estimate(model: model, input: input, cached: cached,
                                        written: written, output: output, isFast: item["isFast"] as? Bool ?? tokens["isFast"] as? Bool ?? false)
                        let record = UsageRecord(date: date, model: model, input: input, cached: cached,
                                                 written: written, output: output, total: total, cost: cost)
                        records.append(record)
                        if provider == "codex", let cost { observedCodexPrices[recordKey(record)] = cost }
                    }
                }
            }
            if !records.isEmpty {
                for day in aggregate(records, provider: provider, timeZone: collectionZone) { merged[day.id] = day }
                sources[provider] = "local-log-cache"
                if cacheChanged, let stamp, Date().timeIntervalSince(stamp) > 300 {
                    warnings.append("logs-pending:" + provider)
                }
            }
        }

        // Read older and newly appended Codex logs as well, so custom ranges do
        // not depend on the rolling month retained by OpenUsage's scan cache.
        let codexRecords = scanCodex(catalog: catalog, support: support).map { record in
            // The upstream cache records Fast mode, which older raw transcripts
            // do not expose. Preserve that better pricing evidence when present.
            UsageRecord(date: record.date, model: record.model, input: record.input, cached: record.cached,
                        written: record.written, output: record.output, total: record.total,
                        cost: observedCodexPrices[recordKey(record)] ?? record.cost)
        }
        if !codexRecords.isEmpty {
            for day in aggregate(codexRecords, provider: "codex", timeZone: collectionZone) { merged[day.id] = day }
            sources["codex"] = "codex-local-logs"
            warnings.removeAll { $0 == "logs-pending:codex" }
        }

        let grokRecords = scanGrok(catalog: catalog, support: support)
        if !grokRecords.isEmpty {
            for day in aggregate(grokRecords, provider: "grok", timeZone: collectionZone) { merged[day.id] = day }
            sources["grok"] = "grok-local-usage"
            warnings.removeAll { $0 == "logs-pending:grok" }
        }

        let claudeRecords = scanClaude(catalog: catalog, support: support)
        if !claudeRecords.isEmpty {
            for day in aggregate(claudeRecords, provider: "claude", timeZone: collectionZone) { merged[day.id] = day }
            sources["claude"] = "claude-local-logs"
        }

        let antigravityRecords = scanAntigravity(catalog: catalog, support: support)
        if !antigravityRecords.isEmpty {
            for day in aggregate(antigravityRecords, provider: "antigravity", timeZone: collectionZone) { merged[day.id] = day }
            sources["antigravity"] = "antigravity-local-database"
        }

        let result = HistoryResult(days: merged.values.sorted { $0.date == $1.date ? $0.provider < $1.provider : $0.date < $1.date },
                                   sources: sources, updatedAt: Date(), warnings: warnings,
                                   timeZoneIdentifier: collectionZone.identifier,
                                   antigravityHistoryVersion: antigravityHistoryVersion)
        try? FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(result) { try? data.write(to: archive, options: .atomic) }
        return result
    }

    static func aggregate(_ records: [UsageRecord], provider: String, timeZone: TimeZone = zone) -> [UsageDay] {
        let dayFormatter = dayFormatter(timeZone: timeZone)
        var groups: [String: UsageDay] = [:]
        for record in records {
            let date = dayFormatter.string(from: record.date)
            var day = groups[date] ?? UsageDay(provider: provider, date: date)
            day.input += record.input; day.cached += record.cached; day.written += record.written
            day.output += record.output; day.total += record.total; day.requests = (day.requests ?? 0) + 1
            day.knownCost = (day.knownCost ?? 0) + (record.cost ?? 0)
            if let cost = record.cost, let prior = day.cost { day.cost = prior + cost } else { day.cost = nil }
            var model = day.models.first { $0.name == record.model } ?? UsageModel(name: record.model)
            model.input += record.input; model.cached += record.cached; model.written += record.written
            model.output += record.output; model.total += record.total; model.requests += 1
            model.knownCost = (model.knownCost ?? 0) + (record.cost ?? 0)
            if let cost = record.cost, let prior = model.cost { model.cost = prior + cost } else { model.cost = nil }
            day.models.removeAll { $0.name == model.name }; day.models.append(model)
            groups[date] = day
        }
        return groups.values.sorted { $0.date < $1.date }
    }

    /// Desktop app, `agy` CLI and Antigravity IDE each keep their own conversation databases.
    static func antigravityConversationRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let gemini = home.appendingPathComponent(".gemini")
        return [
            "antigravity/conversations",
            "antigravity-cli/conversations",
            "antigravity-ide/conversations"
        ].map { gemini.appendingPathComponent($0) }
    }

    static func scanAntigravity(catalog: PriceCatalog, support: URL, roots: [URL]? = nil) -> [UsageRecord] {
        let cache = storageFolder(support: support).appendingPathComponent("antigravity-db-cache-v\(antigravityHistoryVersion)")
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let fm = FileManager.default
        var records: [UsageRecord] = []
        var seenRoots = Set<String>()
        for root in roots ?? antigravityConversationRoots() {
            let resolved = root.resolvingSymlinksInPath().standardizedFileURL
            guard seenRoots.insert(resolved.path).inserted,
                  let urls = try? fm.contentsOfDirectory(at: resolved, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            records.append(contentsOf: scanAntigravityDatabases(urls, catalog: catalog, cache: cache, fileManager: fm))
        }
        return records
    }

    private static func scanAntigravityDatabases(_ urls: [URL], catalog: PriceCatalog, cache: URL, fileManager: FileManager) -> [UsageRecord] {
        var records: [UsageRecord] = []
        for url in urls where url.pathExtension == "db" {
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let dbSize = (attrs[.size] as? NSNumber)?.uint64Value,
                  let dbModified = attrs[.modificationDate] as? Date else { continue }
            let walAttrs = try? fileManager.attributesOfItem(atPath: url.path + "-wal")
            let walSize = (walAttrs?[.size] as? NSNumber)?.uint64Value ?? 0
            let walModified = (walAttrs?[.modificationDate] as? Date) ?? Date.distantPast
            let name = SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
            let file = cache.appendingPathComponent(name + ".json")
            if let data = try? Data(contentsOf: file),
               let prior = try? JSONDecoder().decode(AntigravityFileCache.self, from: data),
               prior.dbSize == dbSize, prior.dbModified == dbModified,
               prior.walSize == walSize, prior.walModified == walModified {
                records.append(contentsOf: prior.records)
                continue
            }
            let parsed = parseAntigravityDB(url, catalog: catalog)
            if let data = try? JSONEncoder().encode(AntigravityFileCache(
                dbSize: dbSize, dbModified: dbModified, walSize: walSize, walModified: walModified, records: parsed
            )) {
                try? data.write(to: file, options: .atomic)
            }
            records.append(contentsOf: parsed)
        }
        return records
    }

    static func parseAntigravityDB(_ url: URL, catalog: PriceCatalog) -> [UsageRecord] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)

        var hasSteps = false
        var checkStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT 1 FROM pragma_table_info('steps') WHERE name = 'metadata'", -1, &checkStmt, nil) == SQLITE_OK {
            if sqlite3_step(checkStmt) == SQLITE_ROW { hasSteps = true }
            sqlite3_finalize(checkStmt)
        }

        var stepStmt: OpaquePointer?
        if hasSteps {
            sqlite3_prepare_v2(db, "SELECT metadata FROM steps WHERE idx = ? LIMIT 1", -1, &stepStmt, nil)
        }
        defer { if let stepStmt { sqlite3_finalize(stepStmt) } }

        let sql = "SELECT g.idx, g.data FROM gen_metadata g WHERE g.data IS NOT NULL AND length(g.data) <= 524288 ORDER BY g.idx"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var records: [UsageRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let gIdx = sqlite3_column_int64(stmt, 0)
            guard let blobPtr = sqlite3_column_blob(stmt, 1) else { continue }
            let blobLen = Int(sqlite3_column_bytes(stmt, 1))
            guard blobLen > 0 else { continue }
            let genData = Data(bytes: blobPtr, count: blobLen)
            var stepData: Data? = nil
            if let stepStmt, let msg1 = pbBytes(1, in: genData) {
                // Legacy records omit the reference. An explicit reference must
                // never fall back to a different sequence's coincident index.
                let stepIdx = pbLastStepIndex(in: msg1) ?? gIdx
                sqlite3_bind_int64(stepStmt, 1, stepIdx)
                if sqlite3_step(stepStmt) == SQLITE_ROW, let stepPtr = sqlite3_column_blob(stepStmt, 0) {
                    let stepLen = Int(sqlite3_column_bytes(stepStmt, 0))
                    if stepLen > 0 { stepData = Data(bytes: stepPtr, count: stepLen) }
                }
                sqlite3_reset(stepStmt)
                sqlite3_clear_bindings(stepStmt)
            }
            if let record = decodeAntigravityRow(genData: genData, stepData: stepData, catalog: catalog) {
                records.append(record)
            }
        }
        return records
    }

    static func decodeAntigravityRow(genData: Data, stepData: Data?, catalog: PriceCatalog) -> UsageRecord? {
        guard let msg1 = pbBytes(1, in: genData), let usageMsg = pbBytes(4, in: msg1) else { return nil }
        let modelId = pbString(19, in: msg1)
        let modelLabel = pbString(21, in: msg1)
        let u1 = pbVarint(1, in: usageMsg) ?? 0
        let u2 = pbVarint(2, in: usageMsg) ?? 0
        let u3 = pbVarint(3, in: usageMsg) ?? 0
        let u5 = pbVarint(5, in: usageMsg) ?? 0
        guard u1 >= 0, u2 >= 0, u3 >= 0, u5 >= 0 else { return nil }
        guard u1 <= Int64.max - u2 else { return nil }
        let input = Double(u1 + u2)
        let output = Double(u3)
        let cached = Double(u5)
        if u2 == 0 && u3 == 0 && u5 == 0 {
            if (modelId == nil && modelLabel == nil) || input == 0 { return nil }
        }
        let total = input + output + cached
        guard total > 0 else { return nil }

        var tsSeconds: Int64?
        if let msg9 = pbBytes(9, in: msg1), let msg9_4 = pbBytes(4, in: msg9), let secs = pbVarint(1, in: msg9_4), secs > 0 {
            tsSeconds = secs
        } else if let stepData, let step1 = pbBytes(1, in: stepData), let secs = pbVarint(1, in: step1), secs > 0 {
            tsSeconds = secs
        }
        guard let secs = tsSeconds, secs <= 253_402_300_799 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(secs))

        let cleanedId: String? = modelId.flatMap { raw in
            let s = raw.hasSuffix("-tiered") ? String(raw.dropLast("-tiered".count)) : raw
            return s.isEmpty ? nil : s
        }
        let candidates: [String]
        if let cid = cleanedId, cid.hasSuffix("-default") {
            candidates = [modelLabel, cleanedId].compactMap { $0 }
        } else {
            candidates = [cleanedId, modelLabel].compactMap { $0 }
        }

        var resolvedModel = "unknown"
        var resolvedCost: Double? = nil
        for candidate in candidates {
            if let cost = catalog.estimate(model: candidate, input: input, cached: cached, written: 0, output: output) {
                var canon = catalog.canonicalModel(candidate)
                if canon.hasSuffix("-preview") { canon = String(canon.dropLast("-preview".count)) }
                resolvedModel = canon
                resolvedCost = cost
                break
            }
        }
        if resolvedCost == nil, let first = candidates.first {
            var canon = catalog.canonicalModel(first)
            if canon.hasSuffix("-preview") { canon = String(canon.dropLast("-preview".count)) }
            resolvedModel = canon
        }
        return UsageRecord(date: date, model: resolvedModel, input: input, cached: cached, written: 0, output: output, total: total, cost: resolvedCost)
    }

    private static func pbReadVarint(_ data: Data, _ idx: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while idx < data.count {
            let byte = data[idx]
            idx += 1
            // A UInt64 varint has at most one payload bit in its tenth byte.
            guard shift < 63 || byte <= 1 else { return nil }
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 { return result }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    private static func pbVarint(_ targetField: Int, in data: Data) -> Int64? {
        var idx = 0
        while idx < data.count {
            guard let tag = pbReadVarint(data, &idx) else { return nil }
            let field = Int(tag >> 3)
            let wire = Int(tag & 0x7)
            switch wire {
            case 0:
                guard let val = pbReadVarint(data, &idx) else { return nil }
                if field == targetField { return Int64(bitPattern: val) }
            case 1:
                idx += 8
                if idx > data.count { return nil }
            case 2:
                guard let len = pbReadVarint(data, &idx) else { return nil }
                guard let length = Int(exactly: len), length <= data.count - idx else { return nil }
                idx += length
            case 5:
                idx += 4
                if idx > data.count { return nil }
            default:
                return nil
            }
        }
        return nil
    }

    private static func pbBytes(_ targetField: Int, in data: Data) -> Data? {
        var idx = 0
        while idx < data.count {
            guard let tag = pbReadVarint(data, &idx) else { return nil }
            let field = Int(tag >> 3)
            let wire = Int(tag & 0x7)
            switch wire {
            case 0:
                guard pbReadVarint(data, &idx) != nil else { return nil }
            case 1:
                idx += 8
                if idx > data.count { return nil }
            case 2:
                guard let len = pbReadVarint(data, &idx) else { return nil }
                guard let length = Int(exactly: len), length <= data.count - idx else { return nil }
                if field == targetField { return Data(data[idx..<(idx + length)]) }
                idx += length
            case 5:
                idx += 4
                if idx > data.count { return nil }
            default:
                return nil
            }
        }
        return nil
    }

    private static func pbString(_ targetField: Int, in data: Data) -> String? {
        guard let bytes = pbBytes(targetField, in: data),
              let str = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else { return nil }
        return str
    }

    private static func pbLastStepIndex(in msg1: Data) -> Int64? {
        var idx = 0
        var lastStepIndex: Int64?
        while idx < msg1.count {
            guard let tag = pbReadVarint(msg1, &idx) else { return nil }
            let field = Int(tag >> 3)
            let wire = Int(tag & 0x7)
            switch wire {
            case 0:
                guard pbReadVarint(msg1, &idx) != nil else { return nil }
            case 1:
                idx += 8
                if idx > msg1.count { return nil }
            case 2:
                guard let len = pbReadVarint(msg1, &idx) else { return nil }
                guard let length = Int(exactly: len), length <= msg1.count - idx else { return nil }
                if field == 20 {
                    let sub = Data(msg1[idx..<(idx + length)])
                    if pbString(1, in: sub) == "last_step_index",
                       let valStr = pbString(2, in: sub),
                       let stepIdx = Int64(valStr) {
                        lastStepIndex = stepIdx
                    }
                }
                idx += length
            case 5:
                idx += 4
                if idx > msg1.count { return nil }
            default:
                return nil
            }
        }
        return lastStepIndex
    }

    /// Turn totals in `~/.grok/sessions/*/usage.json`. Cached tokens are already inside `inputTokens`,
    /// matching the OpenUsage split of fresh input plus cache read.
    static func parseGrokUsage(_ data: Data, catalog: PriceCatalog) -> [UsageRecord]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func number(_ object: [String: Any], _ key: String) -> Double {
            if let value = object[key] as? Double { return value }
            if let value = object[key] as? Int { return Double(value) }
            if let value = object[key] as? NSNumber { return value.doubleValue }
            return 0
        }
        func record(model: String, stats: [String: Any], date: Date) -> UsageRecord? {
            let rawInput = number(stats, "inputTokens")
            let cached = number(stats, "cachedReadTokens")
            let written = number(stats, "cacheCreationTokens")
            let output = number(stats, "outputTokens")
            guard [rawInput, cached, written, output].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
            let input = max(0, rawInput - cached)
            let total = input + cached + written + output
            guard total.isFinite, total > 0 else { return nil }
            let name = model.isEmpty ? "unknown" : model
            let cost = catalog.estimate(model: name, input: input, cached: cached, written: written, output: output)
            return UsageRecord(date: date, model: name, input: input, cached: cached, written: written, output: output, total: total, cost: cost)
        }
        var records: [UsageRecord] = []
        for turn in root["turns"] as? [[String: Any]] ?? [] {
            guard let date = (turn["endedAt"] as? String).flatMap(parseDate) else { continue }
            let usage = turn["modelUsage"] as? [String: Any] ?? [:]
            if usage.isEmpty {
                let model = turn["primaryModelId"] as? String ?? "unknown"
                if let row = record(model: model, stats: turn, date: date) { records.append(row) }
            } else {
                for (model, value) in usage {
                    let stats = value as? [String: Any] ?? [:]
                    if let row = record(model: model, stats: stats, date: date) { records.append(row) }
                }
            }
        }
        return records
    }

    private static func mergeClaudeRecord(_ incoming: UsageRecord, with previous: UsageRecord?, catalog: PriceCatalog) -> UsageRecord {
        let input = max(previous?.input ?? 0, incoming.input)
        let cached = max(previous?.cached ?? 0, incoming.cached)
        let written = max(previous?.written ?? 0, incoming.written)
        let output = max(previous?.output ?? 0, incoming.output)
        let total = input + cached + written + output
        // Individually valid streaming fragments can overflow when merged.
        guard total.isFinite else { return previous ?? incoming }
        return UsageRecord(date: min(previous?.date ?? incoming.date, incoming.date), model: incoming.model,
                           input: input, cached: cached, written: written, output: output,
                           total: total,
                           cost: catalog.estimate(model: incoming.model, input: input, cached: cached, written: written, output: output))
    }

    static func scanClaude(catalog: PriceCatalog, support: URL, root: URL? = nil) -> [UsageRecord] {
        let root = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let cache = storageFolder(support: support).appendingPathComponent("claude-file-cache-v1")
        let fm = FileManager.default
        try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
        var messages: [String: UsageRecord] = [:]
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl", let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let size = (attrs[.size] as? NSNumber)?.uint64Value, let modified = attrs[.modificationDate] as? Date else { continue }
            let name = SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
            let file = cache.appendingPathComponent(name + ".json")
            let parsed: [String: UsageRecord]
            if let data = try? Data(contentsOf: file), let prior = try? JSONDecoder().decode(ClaudeFileCache.self, from: data),
               prior.size == size, prior.modified == modified {
                parsed = prior.messages
            } else {
                guard let fresh = parseClaudeFile(url, catalog: catalog) else { continue }
                parsed = fresh
                if let data = try? JSONEncoder().encode(ClaudeFileCache(size: size, modified: modified, messages: parsed)) {
                    try? data.write(to: file, options: .atomic)
                }
            }
            for (key, record) in parsed {
                messages[key] = mergeClaudeRecord(record, with: messages[key], catalog: catalog)
            }
        }
        return Array(messages.values)
    }

    static func parseClaudeFile(_ url: URL, catalog: PriceCatalog) -> [String: UsageRecord]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var messages: [String: UsageRecord] = [:]
        var lineNumber = 0
        func consume(_ line: Data.SubSequence) {
            lineNumber += 1
            guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  row["type"] as? String == "assistant",
                  let message = row["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let date = (row["timestamp"] as? String).flatMap(parseDate),
                  let model = message["model"] as? String, !model.contains("synthetic") else { return }
            let identity = (message["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (row["uuid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? "\(url.path):\(lineNumber)"
            let rawKey = identity + ":" + (row["requestId"] as? String ?? "")
            let key = SHA256.hash(data: Data(rawKey.utf8)).map { String(format: "%02x", $0) }.joined()
            let input = usage["input_tokens"] as? Double ?? 0
            let cached = usage["cache_read_input_tokens"] as? Double ?? 0
            let written = usage["cache_creation_input_tokens"] as? Double ?? 0
            let output = usage["output_tokens"] as? Double ?? 0
            let total = input + cached + written + output
            guard [input, cached, written, output, total].allSatisfy({ $0.isFinite && $0 >= 0 }), total > 0 else { return }
            let record = UsageRecord(date: date, model: model, input: input, cached: cached, written: written,
                                     output: output, total: total, cost: nil)
            messages[key] = mergeClaudeRecord(record, with: messages[key], catalog: catalog)
        }
        var buffer = Data()
        do {
            while let chunk = try handle.read(upToCount: 2_097_152), !chunk.isEmpty {
                buffer.append(chunk)
                var offset = buffer.startIndex
                while offset < buffer.endIndex, let newline = buffer[offset...].firstIndex(of: 10) {
                    consume(buffer[offset..<newline]); offset = newline + 1
                }
                if offset > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<offset) }
            }
        } catch { return nil }
        if !buffer.isEmpty { consume(buffer[...]) }
        return messages
    }

    static func scanGrok(catalog: PriceCatalog, support: URL) -> [UsageRecord] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/sessions")
        let cache = storageFolder(support: support).appendingPathComponent("grok-usage-cache")
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let fm = FileManager.default
        guard let workspaces = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var records: [UsageRecord] = []
        for workspace in workspaces {
            guard let sessions = try? fm.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for session in sessions {
                let url = session.appendingPathComponent("usage.json")
                guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                      let size = (attrs[.size] as? NSNumber)?.uint64Value,
                      let modified = attrs[.modificationDate] as? Date else { continue }
                let name = SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
                let file = cache.appendingPathComponent(name + ".json")
                if let cached = try? Data(contentsOf: file),
                   let prior = try? JSONDecoder().decode(CodexFileCache.self, from: cached),
                   prior.size == size, prior.modified == modified {
                    records.append(contentsOf: prior.records)
                    continue
                }
                guard let data = try? Data(contentsOf: url), let parsed = parseGrokUsage(data, catalog: catalog) else { continue }
                if let encoded = try? JSONEncoder().encode(CodexFileCache(size: size, modified: modified, records: parsed)) {
                    try? encoded.write(to: file, options: .atomic)
                }
                records.append(contentsOf: parsed)
            }
        }
        return records
    }

    static func scanCodex(catalog: PriceCatalog, support: URL) -> [UsageRecord] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        let cache = storageFolder(support: support).appendingPathComponent("codex-file-cache")
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var records: [UsageRecord] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl", let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = (attrs[.size] as? NSNumber)?.uint64Value, let modified = attrs[.modificationDate] as? Date else { continue }
            let name = SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
            let file = cache.appendingPathComponent(name + ".json")
            if let data = try? Data(contentsOf: file), let prior = try? JSONDecoder().decode(CodexFileCache.self, from: data),
               prior.size == size, prior.modified == modified {
                records.append(contentsOf: prior.records); continue
            }
            let parsed = parseCodexFile(url, catalog: catalog)
            if let data = try? JSONEncoder().encode(CodexFileCache(size: size, modified: modified, records: parsed)) {
                try? data.write(to: file, options: .atomic)
            }
            records.append(contentsOf: parsed)
        }
        // Forked transcripts may carry identical earlier events.
        var seen = Set<String>()
        return records.filter { record in
            seen.insert(recordKey(record)).inserted
        }
    }

    static func recordKey(_ record: UsageRecord) -> String {
        "\(Int((record.date.timeIntervalSince1970 * 1000).rounded())):\(record.model):\(record.input):\(record.cached):\(record.written):\(record.output)"
    }

    static func parseCodexFile(_ url: URL, catalog: PriceCatalog) -> [UsageRecord] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        var records: [UsageRecord] = []
        var model = "unknown"
        var previousTotal: Double = -1
        func consume(_ line: Data.SubSequence) {
            let head = String(decoding: line.prefix(500), as: UTF8.self)
            guard head.contains("token_count") || head.contains("turn_context"),
                  let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = row["payload"] as? [String: Any] else { return }
            if row["type"] as? String == "turn_context" {
                model = payload["model"] as? String ?? model; return
            }
            guard payload["type"] as? String == "token_count", let info = payload["info"] as? [String: Any],
                  let usage = info["last_token_usage"] as? [String: Any],
                  let date = (row["timestamp"] as? String).flatMap(parseDate) else { return }
            let cumulative = (info["total_token_usage"] as? [String: Any])?["total_tokens"] as? Double ?? -1
            if cumulative == previousTotal && cumulative >= 0 { return }
            previousTotal = cumulative
            let cached = usage["cached_input_tokens"] as? Double ?? 0
            let written = usage["cache_write_input_tokens"] as? Double ?? 0
            let rawInput = usage["input_tokens"] as? Double ?? 0
            let input = max(0, rawInput - cached - written)
            let output = usage["output_tokens"] as? Double ?? 0
            let total = rawInput + output
            guard total > 0 else { return }
            let cost = catalog.estimate(model: model, input: input, cached: cached, written: written, output: output)
            records.append(UsageRecord(date: date, model: model, input: input, cached: cached, written: written, output: output, total: total, cost: cost))
        }
        var buffer = Data()
        while let chunk = try? handle.read(upToCount: 2_097_152), !chunk.isEmpty {
            buffer.append(chunk)
            var offset = buffer.startIndex
            while offset < buffer.endIndex, let newline = buffer[offset...].firstIndex(of: 10) {
                consume(buffer[offset..<newline]); offset = newline + 1
            }
            if offset > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<offset) }
        }
        if !buffer.isEmpty { consume(buffer[...]) }
        return records
    }

    static func parseDate(_ value: String) -> Date? {
        let key = "Aicost.ISO8601Formatters"
        let formatters: [ISO8601DateFormatter]
        if let prior = Thread.current.threadDictionary[key] as? [ISO8601DateFormatter] {
            formatters = prior
        } else {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatters = [fractional, ISO8601DateFormatter()]
            Thread.current.threadDictionary[key] = formatters
        }
        return formatters[0].date(from: value) ?? formatters[1].date(from: value)
    }

    static func apiDate(_ label: String, reference: Date, timeZone: TimeZone = zone) -> Date? {
        // Chinese month/day labels are part of the upstream data format.
        let calendar = calendar(timeZone: timeZone)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy年M月d日"
        let year = calendar.component(.year, from: reference)
        guard var date = formatter.date(from: "\(year)年" + label) else { return nil }
        if date > calendar.startOfDay(for: reference) { date = calendar.date(byAdding: .year, value: -1, to: date) ?? date }
        return date
    }
}

/// Gemini is the Antigravity subscription that Pro accounts can spend. `agy /usage` reports both
/// pools. The Cloud Code summary often copies the other-model pool into the Gemini slots, so those
/// summary values must not replace a Gemini reading already learned from `agy`.
enum AntigravityGeminiQuota {
    struct Window {
        var remaining: Double
        var reset: Date?
    }

    struct PoolWindow {
        var id: String
        var remaining: Double
        var reset: Date?
        var kind: QuotaWindowKind {
            let key = id.lowercased()
            if key.contains("week") { return .weekly }
            if key.contains("month") { return .monthly }
            return .session
        }
    }

    static func merging(_ windows: [PoolWindow], into existing: [Metric]) -> [Metric] {
        let incoming = windows.map { Metric(id: $0.id, remaining: $0.remaining, reset: $0.reset, kind: $0.kind) }
        let updated = Set(incoming.map(\.id))
        return distinctMetrics(incoming + existing.filter { !updated.contains($0.labelID ?? $0.id) })
    }

    /// Keep the last Gemini windows. A summary refresh may update the other-model pool, but its
    /// Gemini slots are not authoritative and must not move the menu bar onto that pool.
    static func mergingProvider(incoming: [Metric], retained: [Metric]) -> [Metric] {
        let others = incoming.filter { QuotaWindows.pool(of: $0.id) != "gemini" }
        let replaced = Set(others.map { $0.labelID ?? $0.id })
        let kept = retained.filter { metric in
            let pool = QuotaWindows.pool(of: metric.id)
            if pool == "gemini" { return true }
            return pool == "other" && !replaced.contains(metric.labelID ?? metric.id)
        }
        return distinctMetrics(kept + others)
    }

    static func pools(fromAgy data: Data) -> [PoolWindow] {
        let payloads = agyPayloads(data)
        var windows: [PoolWindow] = []
        for payload in payloads {
            guard let groups = payload["groups"] as? [[String: Any]] else { continue }
            for group in groups {
                for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                    if bucket["disabled"] as? Bool == true { continue }
                    let bucketID = (bucket["id"] as? String)?.lowercased() ?? ""
                    let groupName = (group["name"] as? String)?.lowercased() ?? ""
                    guard let fraction = finiteFraction(bucket["remaining_fraction"] ?? bucket["remainingFraction"]) else { continue }
                    let window = (bucket["window"] as? String)?.lowercased() ?? ""
                    let weekly = bucketID.contains("week") || window == "weekly"
                    let gemini = bucketID.contains("gemini") || groupName.contains("gemini")
                    let reset = (bucket["reset_time"] as? String ?? bucket["resetTime"] as? String).flatMap(HistoryAnalyzer.parseDate)
                    let id = gemini ? (weekly ? "geminiWeekly" : "geminiSession") : (weekly ? "nonGeminiWeekly" : "nonGeminiSession")
                    guard !windows.contains(where: { $0.id == id }) else { continue }
                    windows.append(PoolWindow(id: id, remaining: min(1, max(0, fraction)), reset: reset))
                }
            }
            if !windows.isEmpty { break }
        }
        return windows.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            let lhsOther = lhs.id.lowercased().contains("nongemini")
            let rhsOther = rhs.id.lowercased().contains("nongemini")
            if lhsOther != rhsOther { return !lhsOther }
            return lhs.id < rhs.id
        }
    }

    private static func agyPayloads(_ data: Data) -> [[String: Any]] {
        var payloads: [[String: Any]] = []
        func collect(_ root: [String: Any]) {
            if let status = root["status"] as? String,
               ["error", "failed", "failure"].contains(status.lowercased()) { return }
            if let command = root["command"] as? [String: Any], let payload = command["data"] as? [String: Any] {
                payloads.append(payload)
            } else if root["groups"] != nil {
                payloads.append(root)
            }
        }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            collect(root)
        }
        if payloads.isEmpty, let text = String(data: data, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                guard let lineData = line.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
                collect(root)
            }
        }
        return payloads
    }

    private static func finiteFraction(_ value: Any?) -> Double? {
        let number: Double?
        if let value = value as? Double {
            number = value
        } else if let value = value as? Int {
            number = Double(value)
        } else if let value = value as? NSNumber {
            number = value.doubleValue
        } else {
            number = nil
        }
        guard let number, number.isFinite else { return nil }
        return number
    }

    static func session(from data: Data) -> Window? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = root["buckets"] as? [[String: Any]] else { return nil }
        var worst: Double?
        var reset: Date?
        for bucket in buckets {
            guard let model = (bucket["modelId"] as? String)?.lowercased(), model.contains("gemini") else { continue }
            guard let fraction = finiteFraction(bucket["remainingFraction"]) else { continue }
            let clamped = min(1, max(0, fraction))
            if worst == nil || clamped < worst! {
                worst = clamped
                reset = (bucket["resetTime"] as? String).flatMap(HistoryAnalyzer.parseDate)
            }
        }
        guard let worst else { return nil }
        return Window(remaining: worst, reset: reset)
    }

    /// `paidTier.id` from Cloud Code `loadCodeAssist`. The display name is longer and less stable.
    private static let paidTierPlans = [
        "g1-pro-tier": "Pro",
        "g1-ultra-tier": "Ultra",
        "g1-ultra-lite-tier": "Ultra Lite"
    ]

    /// Subscription type for the card corner. Gemini is a quota pool, not a plan name.
    static func subscriptionPlan(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else { return nil }
        let status = root["userStatus"] as? [String: Any] ?? root
        // The actual subscription tier takes precedence over the inherited
        // language-server plan, which can say Pro for an Ultra account.
        for key in ["userTier", "paidTier"] {
            if let tier = status[key] as? [String: Any] {
                if let id = tier["id"] as? String, let known = paidTierPlans[id] { return known }
                if let label = planLabel(tier["name"] as? String) { return label }
            }
        }
        if let current = status["currentTier"] as? [String: Any] {
            if let id = current["id"] as? String, let known = paidTierPlans[id] { return known }
            if let label = planLabel(current["name"] as? String) { return label }
        }
        if let planStatus = status["planStatus"] as? [String: Any],
           let info = planStatus["planInfo"] as? [String: Any] {
            return planLabel(info["planName"] as? String)
        }
        return nil
    }

    private static func planLabel(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        let folded = trimmed.lowercased()
        if folded == "gemini" || folded == "antigravity" { return nil }
        let prefix = "google ai "
        if folded.hasPrefix(prefix) {
            let rest = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? nil : rest
        }
        for keyword in ["Ultra Lite", "Ultra", "Pro", "Free"] {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: keyword) + "\\b"
            if trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return keyword }
        }
        return trimmed
    }
}

enum QuotaWindowKind: Int, Comparable {
    case session = 0
    case daily = 1
    case weekly = 2
    case monthly = 3
    case other = 4

    static func < (lhs: QuotaWindowKind, rhs: QuotaWindowKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct QuotaReading: Equatable {
    var id: String
    var remaining: Double?
    var kind: QuotaWindowKind
    var isFiveHour: Bool { kind == .session }
}

enum QuotaWindows {
    static let fiveHourSeconds = 18_000
    static let daySeconds = 86_400
    static let weekSeconds = 604_800
    static let monthSeconds = 2_592_000

    static func seconds(from value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let seconds = number.doubleValue
        guard seconds > 0, seconds < Double(Int.max) else { return nil }
        return Int(seconds.rounded())
    }

    static func kind(id: String, windowSeconds: Int?) -> QuotaWindowKind {
        if let windowSeconds, windowSeconds > 0 {
            if abs(windowSeconds - fiveHourSeconds) <= 15 * 60 { return .session }
            if abs(windowSeconds - daySeconds) <= 2 * 60 * 60 { return .daily }
            if abs(windowSeconds - weekSeconds) <= 12 * 60 * 60 { return .weekly }
            if abs(windowSeconds - monthSeconds) <= 2 * daySeconds { return .monthly }
        }
        let key = id.lowercased()
        if key.contains("month") { return .monthly }
        if key.contains("week") { return .weekly }
        if key.contains("daily") || key == "day" { return .daily }
        if key.contains("session") || key.contains("5h") || key == "spark" { return .session }
        return .other
    }

    static func canonicalID(id: String, kind: QuotaWindowKind) -> String {
        let generic = ["session", "weekly", "daily", "monthly", "primary", "secondary"]
        guard generic.contains(id.lowercased()) else { return id }
        switch kind {
        case .session: return "session"
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .other: return id
        }
    }

    static func reading(id: String, remaining: Double?, windowSeconds: Int?) -> QuotaReading {
        let resolved = kind(id: id, windowSeconds: windowSeconds)
        return QuotaReading(id: canonicalID(id: id, kind: resolved), remaining: remaining, kind: resolved)
    }

    static func isExhausted(_ remaining: Double) -> Bool {
        remaining.isFinite && remaining <= 0
    }

    static func displayedPercent(_ remaining: Double) -> Int {
        guard remaining.isFinite else { return 0 }
        let clamped = max(0, min(1, remaining))
        // Keep a positive sub-percent allowance distinct from exhausted quota.
        return clamped > 0 ? max(1, Int((clamped * 100).rounded())) : 0
    }

    static func percentageText(_ remaining: Double) -> String {
        guard remaining.isFinite else { return "—" }
        return remaining > 0 && remaining < 0.01 ? "<1%" : "\(displayedPercent(remaining))%"
    }

    /// Quota-page rows. Antigravity shows the Gemini pool only.
    static func cardReadings(_ readings: [QuotaReading], provider: String) -> [QuotaReading] {
        let ordered = orderedIndices(readings).map { readings[$0] }
        guard provider == "antigravity" else { return ordered }
        return ordered.filter { pool(of: $0.id) == "gemini" }
    }

    /// Menu-bar text for Antigravity: Gemini's 5-hour window and its week, together.
    static func antigravityMenuLabel(_ readings: [QuotaReading], english: Bool) -> String? {
        let preferred = preferredPoolIndices(readings)
        guard !preferred.isEmpty else { return nil }
        let selected = orderedIndices(preferred.map { readings[$0] }).map { readings[preferred[$0]] }
        let hasSession = selected.contains { $0.kind == .session }
        let parts = selected.map { reading -> String in
            let percent = percentageText(reading.remaining ?? 0)
            switch reading.kind {
            case .session:
                return english ? "Gemini·5h \(percent)" : "Gemini·5h内额度 \(percent)"
            case .weekly:
                if hasSession { return english ? "Weekly \(percent)" : "每周 \(percent)" }
                return english ? "Gemini·Weekly \(percent)" : "Gemini·每周 \(percent)"
            case .monthly:
                return english ? "Monthly \(percent)" : "每月 \(percent)"
            case .daily:
                return english ? "Daily \(percent)" : "每日 \(percent)"
            case .other:
                return "\(reading.id) \(percent)"
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Antigravity reports two independent pools. Gemini is the only pool on the menu bar and quota card.
    /// Spark stays off the menu bar while a regular pool exists.
    static func pool(of id: String) -> String {
        let key = id.lowercased()
        if key.contains("nongemini") { return "other" }
        if key.contains("gemini") { return "gemini" }
        if key.hasPrefix("spark") { return "spark" }
        return "main"
    }

    static func preferredPoolIndices(_ readings: [QuotaReading]) -> [Int] {
        let available = readings.indices.filter { readings[$0].remaining != nil }
        let gemini = available.filter { pool(of: readings[$0].id) == "gemini" }
        if !gemini.isEmpty { return Array(gemini) }
        let main = available.filter { pool(of: readings[$0].id) == "main" }
        if !main.isEmpty { return Array(main) }
        return available.filter { pool(of: readings[$0].id) != "other" }
    }

    static func orderedIndices(_ readings: [QuotaReading]) -> [Int] {
        readings.enumerated().filter { $0.element.remaining != nil }.sorted { lhs, rhs in
            if lhs.element.kind != rhs.element.kind { return lhs.element.kind < rhs.element.kind }
            return lhs.offset < rhs.offset
        }.map(\.offset)
    }

    /// The headline window. A used-up weekly or monthly window blocks the account even when the
    /// 5-hour window still has a balance, so that longer window wins over the selected priority.
    static func primaryIndex(_ readings: [QuotaReading], mode: String) -> Int? {
        let available = preferredPoolIndices(readings)
        guard !available.isEmpty else { return nil }
        let blocked = available.filter { isExhausted(readings[$0].remaining ?? 1) }
        if let blocker = blocked.max(by: { lhs, rhs in
            if readings[lhs].kind != readings[rhs].kind { return readings[lhs].kind < readings[rhs].kind }
            return (readings[lhs].remaining ?? 1) > (readings[rhs].remaining ?? 1)
        }) {
            return blocker
        }
        func tightest(_ indices: [Int]) -> Int? {
            indices.min { (readings[$0].remaining ?? 1) < (readings[$1].remaining ?? 1) }
        }
        switch mode {
        case "weekly":
            return tightest(available.filter { readings[$0].kind == .weekly }) ?? available.first
        case "monthly":
            return tightest(available.filter { readings[$0].kind == .monthly }) ?? available.first
        case "minimum":
            return tightest(Array(available))
        default:
            return tightest(available.filter { readings[$0].kind == .session }) ?? available.first
        }
    }

    /// Menu-bar figure. While weekly and monthly allowances remain, show the 5-hour window, or the
    /// monthly window when the account has no 5-hour window. Once either longer allowance is used up,
    /// show that allowance and leave the 5-hour balance off the menu bar.
    static func statusBarIndex(_ readings: [QuotaReading]) -> Int? {
        let available = preferredPoolIndices(readings)
        guard !available.isEmpty else { return nil }
        func tightest(_ indices: [Int]) -> Int? {
            indices.min { (readings[$0].remaining ?? 1) < (readings[$1].remaining ?? 1) }
        }
        let allowance = available.filter { readings[$0].kind == .weekly || readings[$0].kind == .monthly }
        let blocked = allowance.filter { isExhausted(readings[$0].remaining ?? 1) }
        if let blocker = blocked.max(by: { lhs, rhs in
            if readings[lhs].kind != readings[rhs].kind { return readings[lhs].kind < readings[rhs].kind }
            return (readings[lhs].remaining ?? 1) > (readings[rhs].remaining ?? 1)
        }) {
            return blocker
        }
        if let session = tightest(available.filter { readings[$0].kind == .session }) {
            return session
        }
        if let month = tightest(available.filter { readings[$0].kind == .monthly }) {
            return month
        }
        return available.first
    }

    static func hidesSessionOnStatusBar(_ readings: [QuotaReading]) -> Bool {
        preferredPoolIndices(readings).contains {
            let reading = readings[$0]
            return (reading.kind == .weekly || reading.kind == .monthly) && reading.remaining.map(isExhausted) == true
        }
    }
}

func distinctMetrics(_ metrics: [Metric]) -> [Metric] {
    var seen = Set<String>()
    return metrics.map { metric in
        var id = metric.id
        var suffix = 2
        while !seen.insert(id).inserted {
            id = "\(metric.id)#\(suffix)"
            suffix += 1
        }
        guard id != metric.id else { return metric }
        return Metric(id: id, remaining: metric.remaining, reset: metric.reset, kind: metric.kind, labelID: metric.labelID ?? metric.id)
    }
}

struct Metric: Identifiable {
    let id: String
    let remaining: Double?
    let reset: Date?
    var kind: QuotaWindowKind = .other
    var labelID: String? = nil
}
