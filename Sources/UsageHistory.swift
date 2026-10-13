import Foundation
import CryptoKit
import SQLite3

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
    static let zone = TimeZone(identifier: "Asia/Shanghai")!
    static var dayFormatter: DateFormatter {
        let key = "Aicost.dayFormatter" as NSString
        if let existing = Thread.current.threadDictionary[key] as? DateFormatter {
            return existing
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        Thread.current.threadDictionary[key] = formatter
        return formatter
    }
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = zone; return value
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

    static func collect(apiData: Data?) -> HistoryResult {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let base = support.appendingPathComponent("OpenUsage")
        let aicostDir = storageFolder(support: support)
        let archive = aicostDir.appendingPathComponent("history-v1.json")
        let catalog = PriceCatalog(base: base.appendingPathComponent("pricing"))
        var merged: [String: UsageDay] = [:]
        var sources: [String: String] = [:]
        var warnings: [String] = []
        var observedCodexPrices: [String: Double] = [:]
        if let data = try? Data(contentsOf: archive), let prior = try? JSONDecoder().decode(HistoryResult.self, from: data) {
            for day in prior.days { merged[day.id] = day }
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
                          let date = apiDate(label, reference: fetched) else { continue }
                    let day = UsageDay(provider: provider, date: dayFormatter.string(from: date), total: total,
                                       cost: nil, requests: nil, detailed: false)
                    if merged[day.id]?.detailed != true {
                        merged[day.id] = day
                    }
                }
                if sources[provider] == nil {
                    sources[provider] = "OpenUsage · " + dayFormatter.string(from: fetched)
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
                for day in aggregate(records, provider: provider) { merged[day.id] = day }
                sources[provider] = "本机日志缓存 · " + (stamp.map { $0.formatted(date: .omitted, time: .shortened) } ?? "已读取")
                if cacheChanged, let stamp, Date().timeIntervalSince(stamp) > 300 {
                    warnings.append((provider == "codex" ? "Codex" : "Grok") + " 日志有新记录，当前图表暂使用上次统计缓存。")
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
            for day in aggregate(codexRecords, provider: "codex") { merged[day.id] = day }
            sources["codex"] = "Codex 本机日志 · 增量扫描"
            warnings.removeAll { $0.hasPrefix("Codex") }
        }

        let claude = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        var messages: [String: UsageRecord] = [:]
        let enumerator = FileManager.default.enumerator(at: claude, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl", let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      row["type"] as? String == "assistant",
                      let message = row["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let date = (row["timestamp"] as? String).flatMap(parseDate),
                      let model = message["model"] as? String, !model.contains("synthetic") else { continue }
                let key = (message["id"] as? String ?? row["uuid"] as? String ?? "") + ":" + (row["requestId"] as? String ?? "")
                let previous = messages[key]
                let input = max(previous?.input ?? 0, usage["input_tokens"] as? Double ?? 0)
                let cached = max(previous?.cached ?? 0, usage["cache_read_input_tokens"] as? Double ?? 0)
                let written = max(previous?.written ?? 0, usage["cache_creation_input_tokens"] as? Double ?? 0)
                let output = max(previous?.output ?? 0, usage["output_tokens"] as? Double ?? 0)
                let total = input + cached + written + output
                guard total > 0 else { continue }
                let cost = catalog.estimate(model: model, input: input, cached: cached, written: written, output: output)
                messages[key] = UsageRecord(date: previous?.date ?? date, model: model, input: input, cached: cached,
                                           written: written, output: output, total: total, cost: cost)
            }
        }
        if !messages.isEmpty {
            for day in aggregate(Array(messages.values), provider: "claude") { merged[day.id] = day }
            sources["claude"] = "Claude Code 本机日志 · 刚刚扫描"
        }

        let antigravityRecords = scanAntigravity(catalog: catalog, support: support)
        if !antigravityRecords.isEmpty {
            for day in aggregate(antigravityRecords, provider: "antigravity") { merged[day.id] = day }
            sources["antigravity"] = "Antigravity 本机数据库 · 增量扫描"
        }

        let result = HistoryResult(days: merged.values.sorted { $0.date == $1.date ? $0.provider < $1.provider : $0.date < $1.date },
                                   sources: sources, updatedAt: Date(), warnings: warnings)
        try? FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(result) { try? data.write(to: archive, options: .atomic) }
        return result
    }

    static func aggregate(_ records: [UsageRecord], provider: String) -> [UsageDay] {
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

    static func scanAntigravity(catalog: PriceCatalog, support: URL) -> [UsageRecord] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity/conversations")
        let cache = storageFolder(support: support).appendingPathComponent("antigravity-db-cache-v1")
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var records: [UsageRecord] = []
        for url in urls where url.pathExtension == "db" {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let dbSize = (attrs[.size] as? NSNumber)?.uint64Value,
                  let dbModified = attrs[.modificationDate] as? Date else { continue }
            let walAttrs = try? fm.attributesOfItem(atPath: url.path + "-wal")
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

        let sql = hasSteps
            ? "SELECT g.idx, g.data, (SELECT metadata FROM steps WHERE idx = g.idx) FROM gen_metadata g WHERE g.data IS NOT NULL AND length(g.data) <= 524288 ORDER BY g.idx"
            : "SELECT g.idx, g.data, NULL FROM gen_metadata g WHERE g.data IS NOT NULL AND length(g.data) <= 524288 ORDER BY g.idx"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var records: [UsageRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let blobPtr = sqlite3_column_blob(stmt, 1) else { continue }
            let blobLen = Int(sqlite3_column_bytes(stmt, 1))
            guard blobLen > 0 else { continue }
            let genData = Data(bytes: blobPtr, count: blobLen)
            var stepData: Data? = nil
            if sqlite3_column_type(stmt, 2) != SQLITE_NULL, let stepPtr = sqlite3_column_blob(stmt, 2) {
                let stepLen = Int(sqlite3_column_bytes(stmt, 2))
                if stepLen > 0 { stepData = Data(bytes: stepPtr, count: stepLen) }
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
        guard let secs = tsSeconds else { return nil }
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
                let length = Int(len)
                guard length >= 0, idx + length <= data.count else { return nil }
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
                let length = Int(len)
                guard length >= 0, idx + length <= data.count else { return nil }
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func apiDate(_ label: String, reference: Date) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = zone
        formatter.dateFormat = "yyyy年M月d日"
        let year = calendar.component(.year, from: reference)
        guard var date = formatter.date(from: "\(year)年" + label) else { return nil }
        if date > calendar.startOfDay(for: reference) { date = calendar.date(byAdding: .year, value: -1, to: date) ?? date }
        return date
    }
}
