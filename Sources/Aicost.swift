import AppKit
import SwiftUI
import Charts
import Combine
import ServiceManagement

#if !AICOST_TESTING
@main
#endif
@MainActor
struct AicostApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AicostStatusDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

let providerNames = ["cursor": "Cursor", "grok": "Grok", "codex": "Codex", "antigravity": "Antigravity", "claude": "Claude Code", "opencode": "OpenCode", "copilot": "Copilot", "devin": "Devin"]
let quotaOrder = ["cursor", "grok", "codex", "antigravity"]
let supportedOrder = quotaOrder + ["claude", "copilot", "devin", "opencode"]
extension Notification.Name { static let restoreAicostMenu = Notification.Name("AicostRestoreMenu") }

func shortTokens(_ value: Double) -> String {
    if value >= 1_000_000_000 { return String(format: "%.2fB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return String(format: "%.0f", value)
}
func money(_ value: Double) -> String { String(format: "$%.2f", value) }
func providerColor(_ id: String) -> Color {
    switch id {
    case "cursor": return Color(red: 0.25, green: 0.48, blue: 0.84)
    case "codex": return Color(red: 0.13, green: 0.55, blue: 0.42)
    case "claude": return Color(red: 0.74, green: 0.42, blue: 0.29)
    case "antigravity": return Color(red: 0.49, green: 0.40, blue: 0.72)
    case "grok": return Color(red: 0.21, green: 0.29, blue: 0.35)
    case "opencode": return Color(red: 0.70, green: 0.56, blue: 0.19)
    case "copilot": return Color(red: 0.34, green: 0.44, blue: 0.70)
    case "devin": return Color(red: 0.20, green: 0.59, blue: 0.67)
    default: return .secondary
    }
}

@MainActor
private var providerIconCache: [String: NSImage] = [:]

@MainActor
func providerIcon(_ id: String, size: CGFloat = 14) -> NSImage? {
    let px = max(1, Int((size * 2).rounded()))
    let key = "\(id):\(px)"
    if let cached = providerIconCache[key] { return cached }
    let bundleURL = Bundle.main.bundleURL
        .appendingPathComponent("Contents/Resources/Runway_Runway.bundle/Contents/Resources/ProviderIcons/\(id).svg")
    guard let raw = NSImage(contentsOf: bundleURL),
          raw.size.width > 0, raw.size.height > 0,
          let rep = NSBitmapImageRep(
              bitmapDataPlanes: nil,
              pixelsWide: px,
              pixelsHigh: px,
              bitsPerSample: 8,
              samplesPerPixel: 4,
              hasAlpha: true,
              isPlanar: false,
              colorSpaceName: .deviceRGB,
              bytesPerRow: 0,
              bitsPerPixel: 0
          ) else { return nil }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.current = ctx
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let src = raw.size
        let scale = min(rect.width / src.width, rect.height / src.height)
        let w = src.width * scale
        let h = src.height * scale
        let target = NSRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h)
        raw.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor.black.set()
        rect.fill(using: .sourceAtop)
    }
    NSGraphicsContext.restoreGraphicsState()
    let img = NSImage(size: NSSize(width: size, height: size))
    img.addRepresentation(rep)
    img.isTemplate = true
    providerIconCache[key] = img
    return img
}

@MainActor
func aicostAppIcon() -> NSImage? {
    let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
    return NSImage(contentsOf: url)
}

struct AicostBrandIcon: View {
    var size: CGFloat = 24
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.16, green: 0.44, blue: 0.95), Color(red: 0.07, green: 0.66, blue: 0.56)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let vec = providerIcon("aicost", size: size * 0.64) {
                Image(nsImage: vec)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.62, height: size * 0.62)
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: size * 0.52, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.12, green: 0.45, blue: 0.85).opacity(0.22), radius: 3, y: 1)
    }
}

struct ProviderBadge: View {
    let id: String
    var size: CGFloat = 14
    var body: some View {
        if let icon = providerIcon(id, size: size) {
            Image(nsImage: icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(providerColor(id))
        } else {
            Circle().fill(providerColor(id)).frame(width: max(6, size * 0.55), height: max(6, size * 0.55))
                .frame(width: size, height: size)
        }
    }
}

@MainActor
func renderStatusBarImage(items: [(id: String, text: String)]) -> NSImage {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let iconSize: CGFloat = 13
    let iconTextSpacing: CGFloat = 3.5
    let itemSpacing: CGFloat = 9
    let barHeight: CGFloat = 18

    var measured: [(icon: NSImage?, text: NSString, textSize: NSSize)] = []
    var totalWidth: CGFloat = 2
    for (idx, item) in items.enumerated() {
        if idx > 0 { totalWidth += itemSpacing }
        let icon = providerIcon(item.id, size: iconSize)
        if icon != nil { totalWidth += iconSize + (item.text.isEmpty ? 0 : iconTextSpacing) }
        let nsText = item.text as NSString
        let tSize = item.text.isEmpty ? .zero : nsText.size(withAttributes: attrs)
        totalWidth += ceil(tSize.width)
        measured.append((icon, nsText, tSize))
    }
    totalWidth += 2

    let image = NSImage(size: NSSize(width: max(18, totalWidth), height: barHeight), flipped: false) { _ in
        var x: CGFloat = 1
        for (idx, entry) in measured.enumerated() {
            if idx > 0 { x += itemSpacing }
            if let icon = entry.icon {
                let iconRect = NSRect(x: x, y: (barHeight - iconSize) / 2, width: iconSize, height: iconSize)
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                x += iconSize + (entry.text.length > 0 ? iconTextSpacing : 0)
            }
            if entry.text.length > 0 {
                let textY = (barHeight - entry.textSize.height) / 2
                entry.text.draw(at: NSPoint(x: x, y: textY), withAttributes: attrs)
                x += ceil(entry.textSize.width)
            }
        }
        return true
    }
    image.isTemplate = true
    return image
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var section = "analysis"
    @Published var provider = "all"

    func selectSection(_ value: String) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            if value == "analysis" && provider != "all" {
                provider = "all"
            }
            if section != value {
                section = value
            }
        }
    }

    func selectProvider(_ id: String) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            if provider != id {
                provider = id
            }
            if section != "analysis" {
                section = "analysis"
            }
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static weak var shared: AppSettings?

    @Published var language: String // "zh-Hans", "en", "system"
    @Published var menuStyle: String
    @Published var shownProviders: Set<String>
    @Published var refreshInterval: Double
    @Published var defaultRange: Int
    private let defaults = UserDefaults.standard

    var isEnglish: Bool {
        if language == "en" { return true }
        if language == "system" {
            let pref = Locale.preferredLanguages.first ?? "zh"
            return !pref.hasPrefix("zh")
        }
        return false
    }

    func t(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }

    func monthDayString(_ date: Date) -> String {
        let cal = HistoryAnalyzer.calendar
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        if isEnglish {
            let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            let mName = (m >= 1 && m <= 12) ? months[m] : "\(m)"
            return "\(mName) \(d)"
        } else {
            return "\(m)月\(d)日"
        }
    }

    func resetText(_ date: Date, compact: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
        formatter.timeZone = HistoryAnalyzer.zone
        formatter.dateFormat = isEnglish ? "MMM d, HH:mm" : "M月d日 HH:mm"
        let value = formatter.string(from: date)
        return compact ? value : t("\(value) 重置", "Resets \(value)")
    }

    func localizedMetricName(_ metric: Metric) -> String {
        let id = metric.labelID ?? metric.id
        let generic = ["session", "weekly", "daily", "monthly", "primary", "secondary"]
        if generic.contains(id.lowercased()) {
            switch metric.kind {
            case .session: return t("5h内额度", "5h Session")
            case .daily: return t("每日", "Daily")
            case .weekly: return t("每周", "Weekly")
            case .monthly: return t("每月", "Monthly")
            case .other: break
            }
        }
        let zhNames = [
            "daily": "每日", "chat": "聊天额度", "completions": "代码补全", "premiumRequests": "高级请求",
            "totalUsage": "总额度", "autoUsage": "Cursor 模型", "apiUsage": "其他模型",
            "session": "5h内额度", "weekly": "每周", "monthly": "每月",
            "geminiSession": "5h内额度", "geminiWeekly": "每周",
            "nonGeminiSession": "其他模型 · 5h内额度", "nonGeminiWeekly": "其他模型 · 每周",
            "spark": "Spark · 5h内额度", "sparkWeekly": "Spark · 每周"
        ]
        let enNames = [
            "daily": "Daily", "chat": "Chat Quota", "completions": "Completions", "premiumRequests": "Premium Requests",
            "totalUsage": "Total Quota", "autoUsage": "Cursor Models", "apiUsage": "Other Models",
            "session": "5h Session", "weekly": "Weekly", "monthly": "Monthly",
            "geminiSession": "5h Session", "geminiWeekly": "Weekly",
            "nonGeminiSession": "Other models · 5h Session", "nonGeminiWeekly": "Other models · Weekly",
            "spark": "Spark · 5h Session", "sparkWeekly": "Spark · Weekly"
        ]
        return isEnglish ? (enNames[id] ?? id) : (zhNames[id] ?? id)
    }

    var refreshIntervalLabel: String {
        if isEnglish {
            return refreshInterval < 60 ? "Updates every \(Int(refreshInterval))s" : "Updates every \(Int(refreshInterval / 60))m"
        } else {
            return refreshInterval < 60 ? "每 \(Int(refreshInterval)) 秒更新" : "每 \(Int(refreshInterval / 60)) 分钟更新"
        }
    }

    init() {
        language = defaults.string(forKey: "custom.language") ?? "system"
        if defaults.integer(forKey: "custom.menuStyleVersion") < 2 {
            defaults.set("icons", forKey: "custom.menuStyle")
            defaults.set(2, forKey: "custom.menuStyleVersion")
        }
        menuStyle = defaults.string(forKey: "custom.menuStyle") ?? "icons"
        shownProviders = Set(defaults.stringArray(forKey: "custom.shownProviders") ?? quotaOrder)
        if defaults.integer(forKey: "custom.refreshIntervalVersion") < 2 {
            let current = defaults.object(forKey: "custom.refreshInterval") as? Double ?? 300
            if current >= 300 { defaults.set(60.0, forKey: "custom.refreshInterval") }
            defaults.set(2, forKey: "custom.refreshIntervalVersion")
        }
        refreshInterval = defaults.object(forKey: "custom.refreshInterval") as? Double ?? 60
        if defaults.integer(forKey: "custom.defaultRangeVersion") < 2 {
            defaults.set(0, forKey: "custom.defaultRange")
            defaults.set(2, forKey: "custom.defaultRangeVersion")
        }
        defaultRange = defaults.object(forKey: "custom.defaultRange") as? Int ?? 0
        Self.shared = self
    }
    func save() {
        defaults.set(language, forKey: "custom.language")
        defaults.set(menuStyle, forKey: "custom.menuStyle")
        defaults.set(Array(shownProviders), forKey: "custom.shownProviders")
        defaults.set(refreshInterval, forKey: "custom.refreshInterval")
        defaults.set(defaultRange, forKey: "custom.defaultRange")
    }
}

enum ScrollWheelGate {
    private static var lastScrollUptime: TimeInterval = 0
    private static var installed = false

    static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDragged]) { event in
            lastScrollUptime = ProcessInfo.processInfo.systemUptime
            return event
        }
    }

    static var isScrolling: Bool {
        (ProcessInfo.processInfo.systemUptime - lastScrollUptime) < 0.25
    }
}

struct OverlayScrollerBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollerObserverView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ScrollerObserverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureEnclosingScrollView()
            DispatchQueue.main.async { [weak self] in
                self?.configureEnclosingScrollView()
            }
        }
        override func layout() {
            super.layout()
            configureEnclosingScrollView()
        }
        private func configureEnclosingScrollView() {
            var current: NSView? = self
            while let v = current {
                if let sv = v as? NSScrollView {
                    if sv.scrollerStyle != .overlay {
                        sv.scrollerStyle = .overlay
                    }
                    break
                }
                current = v.superview
            }
        }
    }
}

@MainActor
final class AicostStatusDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let usage = UsageStore()
    private let settings = AppSettings()
    private let navigation = AppNavigation()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var dashboardWindow: NSWindow?
    private var refreshTimer: Timer?
    private var activityTimer: Timer?
    private var scheduledInterval: Double = 0
    private var appliedLanguage: Bool?
    private var subscriptions = Set<AnyCancellable>()
    private var menuRepairObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var localPopoverMonitor: Any?
    private var globalPopoverMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Aicost remains available in the menu bar")
        ScrollWheelGate.installIfNeeded()
        if let appIcon = aicostAppIcon() {
            NSApp.applicationIconImage = appIcon
        }
        installMainMenu()
        let positionKey = "NSStatusItem Preferred Position AicostSubscriptionQuota"
        if UserDefaults.standard.object(forKey: positionKey) == nil { UserDefaults.standard.set(450.0, forKey: positionKey) }
        createStatusItem()
        menuRepairObserver = NotificationCenter.default.addObserver(forName: .restoreAicostMenu, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restoreMenuPosition(nil) }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.usage.refresh(force: true) }
        }
        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 408, height: 500)
        popover.contentViewController = NSHostingController(rootView:
            QuickSummaryView(
                openFull: { [weak self] in self?.openDashboard(nil) },
                openQuota: { [weak self] in self?.openQuota(nil) },
                openProvider: { [weak self] id in self?.openProvider(id) },
                openSettings: { [weak self] in self?.openSettings(nil) }
            )
            .environmentObject(usage).environmentObject(settings))
        usage.onRefresh = { [weak self] in self?.updateStatus() }
        usage.$providers.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateStatus()
        }.store(in: &subscriptions)
        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applySettings() }
        }.store(in: &subscriptions)
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.usage.checkRealtimeActivity() }
            }.store(in: &subscriptions)
        }
        applySettings()
        startActivityMonitor()
        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.openDashboard(nil)
            }
        }
        Task { await usage.refresh(force: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let frame = self.statusItem.button?.window?.frame else { return }
            if !NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) { self.restoreMenuPosition(nil) }
            NSLog("[Aicost] native status frame %@", NSStringFromRect(self.statusItem.button?.window?.frame ?? .zero))
        }
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "AicostSubscriptionQuota"
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = providerIcon("aicost", size: 15) ?? NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Aicost")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.target = self
            button.action = #selector(toggleSummary(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    @objc private func restoreMenuPosition(_ sender: Any?) {
        popover?.performClose(sender)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        UserDefaults.standard.set(450.0, forKey: "NSStatusItem Preferred Position AicostSubscriptionQuota")
        createStatusItem()
        updateStatus()
    }

    private func applySettings() {
        settings.save()
        if appliedLanguage != settings.isEnglish {
            appliedLanguage = settings.isEnglish
            installMainMenu()
            dashboardWindow?.title = settings.t("Aicost · 用量分析", "Aicost · Usage Analysis")
        }
        updateStatus()
        guard refreshTimer == nil || scheduledInterval != settings.refreshInterval else { return }
        refreshTimer?.invalidate()
        scheduledInterval = settings.refreshInterval
        let timer = Timer(timeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.usage.refresh(force: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func startActivityMonitor() {
        activityTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.usage.checkRealtimeActivity() }
        }
        RunLoop.main.add(timer, forMode: .common)
        activityTimer = timer
    }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        let compact = ["cursor": "Cursor", "grok": "Grok", "codex": "Codex", "antigravity": "AG", "claude": "Claude", "copilot": "Copilot", "devin": "Devin", "opencode": "OC"]
        let providers = usage.providers.filter { settings.shownProviders.contains($0.id) }
        if (settings.menuStyle == "icons" || settings.menuStyle == "icon_names"), !providers.isEmpty {
            let items = providers.map { provider -> (id: String, text: String) in
                let metric = provider.statusBarMetric()
                let pctText = metric?.remaining.map { QuotaWindows.percentageText($0) } ?? "—"
                if settings.menuStyle == "icon_names" {
                    let shortName = compact[provider.id, default: provider.name]
                    return (provider.id, shortName + " " + pctText)
                }
                return (provider.id, pctText)
            }
            button.image = renderStatusBarImage(items: items)
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            let appIcon = providerIcon("aicost", size: 15) ?? NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Aicost")
            appIcon?.isTemplate = true
            button.image = appIcon
            button.imagePosition = settings.menuStyle == "icon" ? .imageOnly : .imageLeading
            let pieces = providers.compactMap { provider -> String? in
                let metric = provider.statusBarMetric()
                let name = settings.menuStyle == "names" ? provider.name : compact[provider.id, default: provider.name]
                return name + " " + (metric?.remaining.map { QuotaWindows.percentageText($0) } ?? "—")
            }
            button.title = settings.menuStyle == "icon" ? "" : (pieces.isEmpty ? " Aicost" : " " + pieces.joined(separator: "  "))
        }
        let defaultAccountLabel = self.settings.isEnglish ? "Local Account" : "本机账户"
        let quotaHelp = usage.providers.map { (provider: ProviderUsage) -> String in
            let planText = provider.plan ?? defaultAccountLabel
            let metricsText = provider.statusBarMetrics.map { metric in
                let remaining = QuotaWindows.percentageText(metric.remaining ?? 0)
                let used = QuotaWindows.percentageText(1 - (metric.remaining ?? 0))
                let detail = settings.t("剩余 \(remaining) · 已用 \(used)", "Remaining \(remaining) · Used \(used)")
                return "  \(settings.localizedMetricName(metric)): \(detail)"
            }.joined(separator: "\n")
            return "\(provider.name) · \(planText)\n\(metricsText)"
        }.joined(separator: "\n\n")
        button.setAccessibilityLabel(settings.t("Aicost · 订阅额度与今日用量", "Aicost · Subscription Quotas & Today"))
        button.setAccessibilityHelp(usage.providers.isEmpty ? (usage.error?.message(isEnglish: settings.isEnglish) ?? settings.t("正在读取本机用量", "Reading local usage")) : quotaHelp)
        updateStatusToolTip()
        button.needsDisplay = true
    }
    private func updateStatusToolTip() {
        // Keep the system hover panel from covering the interactive summary,
        // including when a background refresh updates the status item.
        statusItem?.button?.toolTip = popover?.isShown == true ? nil : settings.t("Aicost · 点击查看订阅额度与今日用量", "Aicost · Click to view quotas & today's usage")
    }
    @objc private func toggleSummary(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            stopPopoverMonitors()
            popover.performClose(sender)
            button.toolTip = nil
            NSMenu.popUpContextMenu(actionMenu(), with: event, for: button)
            updateStatusToolTip()
        } else if popover.isShown {
            stopPopoverMonitors()
            popover.performClose(sender)
        } else {
            button.toolTip = nil
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            startPopoverMonitors()
            if Date().timeIntervalSince(usage.lastUpdated ?? .distantPast) > 15 {
                Task { await usage.refresh(force: true) }
            }
        }
    }
    private func startPopoverMonitors() {
        stopPopoverMonitors()
        globalPopoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.popover.isShown else { return }
                self.stopPopoverMonitors()
                self.popover.performClose(nil)
            }
        }
        localPopoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem?.button?.window
            if let eventWindow = event.window {
                if eventWindow === popoverWindow || eventWindow.parent === popoverWindow || eventWindow === statusWindow {
                    return event
                }
            }
            self.stopPopoverMonitors()
            self.popover.performClose(nil)
            return event
        }
    }
    private func stopPopoverMonitors() {
        if let monitor = globalPopoverMonitor {
            NSEvent.removeMonitor(monitor)
            globalPopoverMonitor = nil
        }
        if let monitor = localPopoverMonitor {
            NSEvent.removeMonitor(monitor)
            localPopoverMonitor = nil
        }
    }
    func popoverWillShow(_ notification: Notification) {
        statusItem?.button?.toolTip = nil
    }
    func popoverDidClose(_ notification: Notification) {
        stopPopoverMonitors()
        updateStatusToolTip()
    }
    @objc func openDashboard(_ sender: Any?) {
        navigation.section = "analysis"
        navigation.provider = "all"
        showDashboard(sender)
    }
    @objc func openQuota(_ sender: Any?) {
        navigation.section = "quota"
        showDashboard(sender)
    }
    func openProvider(_ id: String) {
        navigation.section = "analysis"
        navigation.provider = id
        showDashboard(nil)
    }
    private func showDashboard(_ sender: Any?) {
        popover?.performClose(sender)
        if dashboardWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = settings.t("Aicost · 用量分析", "Aicost · Usage Analysis")
            window.contentMinSize = NSSize(width: 860, height: 650)
            window.isReleasedWhenClosed = false
            let hosting = NSHostingController(rootView:
                DashboardView(openSettings: { [weak self] in self?.openSettings(nil) })
                    .environmentObject(usage).environmentObject(settings).environmentObject(navigation))
            hosting.sizingOptions = [.minSize]
            window.contentViewController = hosting
            window.delegate = self
            window.setContentSize(NSSize(width: 1040, height: 760))
            window.center()
            dashboardWindow = window
        } else {
            dashboardWindow?.title = settings.t("Aicost · 用量分析", "Aicost · Usage Analysis")
        }
        show(dashboardWindow!, sender: sender)
        if Date().timeIntervalSince(usage.lastUpdated ?? .distantPast) > 15 {
            Task { await usage.refresh(force: true) }
        }
    }
    @objc func openSettings(_ sender: Any?) {
        navigation.section = "settings"
        showDashboard(sender)
    }
    private func show(_ window: NSWindow, sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func refreshNow(_ sender: Any?) { Task { await usage.refresh(force: true) } }
    @objc private func quit(_ sender: Any?) { NSApp.terminate(sender) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboard(nil); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.dashboardWindow?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
        }
    }
    private func actionMenu() -> NSMenu {
        let menu = NSMenu()
        let items: [(String, Selector, String)] = [
            (settings.t("打开用量分析", "Open Usage Analysis"), #selector(openDashboard(_:)), ""),
            (settings.t("打开订阅额度", "Open Subscription Quotas"), #selector(openQuota(_:)), ""),
            (settings.t("设置…", "Settings…"), #selector(openSettings(_:)), ","),
            (settings.t("刷新用量", "Refresh Usage"), #selector(refreshNow(_:)), "r"),
            (settings.t("恢复菜单栏位置", "Reset Menu Bar Position"), #selector(restoreMenuPosition(_:)), ""),
            (settings.t("退出 Aicost", "Quit Aicost"), #selector(quit(_:)), "q")
        ]
        for (title, action, key) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        return menu
    }
    private func installMainMenu() {
        let menu = NSMenu(); let appMenu = NSMenuItem(); menu.addItem(appMenu)
        appMenu.submenu = actionMenu()
        let edit = NSMenuItem(title: settings.t("编辑", "Edit"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: settings.t("编辑", "Edit"))
        for (title, action, key) in [
            (settings.t("复制", "Copy"), #selector(NSText.copy(_:)), "c"),
            (settings.t("全选", "Select All"), #selector(NSText.selectAll(_:)), "a")
        ] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
    }
}

struct ProviderUsage: Identifiable {
    let id: String
    let name: String
    let plan: String?
    let metrics: [Metric]
    let stale: Bool
    var fetchedAt: Date? = nil
    /// Antigravity's quota card and menu bar stay on Gemini. Other-model windows are kept for refresh, not shown.
    private var quotaMetrics: [Metric] { metrics }
    private var readings: [QuotaReading] {
        quotaMetrics.map { QuotaReading(id: $0.id, remaining: $0.remaining, kind: $0.kind) }
    }
    /// Readings for the clicked status-bar caption. Antigravity uses these for `Gemini·5h内额度 · 每周`.
    var menuReadings: [QuotaReading] { readings }
    var visibleMetrics: [Metric] {
        QuotaWindows.orderedIndices(readings).map { quotaMetrics[$0] }
    }
    var cardMetrics: [Metric] {
        let allowed = QuotaWindows.cardReadings(readings, provider: id).map(\.id)
        return allowed.compactMap { metricID in quotaMetrics.first { $0.id == metricID } }
    }
    func primary(_ mode: String = "current") -> Metric? {
        guard let index = QuotaWindows.primaryIndex(readings, mode: mode) else { return nil }
        return quotaMetrics[index]
    }
    func statusBarMetric() -> Metric? {
        guard let index = QuotaWindows.statusBarIndex(readings) else { return nil }
        return quotaMetrics[index]
    }
    var statusBarMetrics: [Metric] {
        let preferred = QuotaWindows.preferredPoolIndices(readings)
        let subset = preferred.map { readings[$0] }
        let rows = QuotaWindows.orderedIndices(subset).map { quotaMetrics[preferred[$0]] }
        if id == "antigravity" { return rows }
        guard QuotaWindows.hidesSessionOnStatusBar(readings) else { return rows }
        return rows.filter { $0.kind != .session }
    }
}
struct ProviderStats: Identifiable {
    let id: String
    let name: String
    let today: String?
    let yesterday: String?
    let monthly: String?
}

/// Keep collection independent from UI state so refresh scheduling can be
/// checked with fixture readers, without accounts, APIs or personal logs.
struct UsageReaders {
    var quotas: (Bool) async throws -> Data
    var openUsage: () async throws -> Data
    var history: (Data?) async -> HistoryResult
    var activity: () async -> String = { "" }
    var antigravity: () async -> AntigravitySupplement = { await UsageStore.fetchAgyGeminiSnapshot() }
    var antigravityPlan: () async -> String? = { await UsageStore.fetchAntigravityPlan() }

    static var live: UsageReaders {
        UsageReaders(quotas: { force in
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/runway")
            return try await Task.detached(priority: .userInitiated) {
                let result = try LocalCommand.run(executable: helper, arguments: force ? ["--force"] : [], timeout: 45)
                if result.status != 0 && result.data.isEmpty {
                    throw NSError(domain: "Aicost", code: Int(result.status))
                }
                return result.data
            }.value
        }, openUsage: {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:6736/v1/usage")!)
            request.timeoutInterval = 2
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }, history: { data in
            await Task.detached(priority: .userInitiated) { HistoryAnalyzer.collect(apiData: data) }.value
        }, activity: {
            await Task.detached(priority: .utility) { UsageStore.activitySignature() }.value
        })
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var providers: [ProviderUsage] = []
    @Published var stats: [ProviderStats] = []
    @Published var history = HistoryResult(days: [], sources: [:], updatedAt: Date.distantPast, warnings: [])
    @Published var availableProviders: [String] = ["codex", "claude", "cursor", "grok", "antigravity"]
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false
    @Published var error: UsageDiagnostic?
    @Published private(set) var calendarContext = HistoryAnalyzer.zone.identifier + "|" + HistoryAnalyzer.dayFormatter.string(from: Date())
    @Published var apiConnected = false
    var onRefresh: (() -> Void)?
    private var lastAPIData: Data?
    private var pendingForceRefresh = false
    private var pendingLocalRefresh = false
    private var isForceRefreshing = false
    private var isCheckingActivity = false
    private var lastLocalRefreshAt = Date.distantPast
    private var localRefreshTask: Task<Void, Never>?
    private var lastActivitySignature = ""
    private var snapshotCache: [String: AnalysisSnapshot] = [:]
    private let readers: UsageReaders

    init(restoreHistory: Bool = true, readers: UsageReaders = .live) {
        self.readers = readers
        guard restoreHistory else { return }
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let archive = HistoryAnalyzer.archiveURL(support: support)
        if let data = try? Data(contentsOf: archive),
           let prior = try? JSONDecoder().decode(HistoryResult.self, from: data) {
            self.history = prior
            rebuildAvailableProviders()
            invalidateSnapshots()
        }
    }

    private func rebuildAvailableProviders() {
        let ids = Set(["codex", "claude", "cursor", "grok", "antigravity"])
            .union(history.days.map(\.provider))
            .union(providers.map(\.id))
        let list = ["codex", "claude", "cursor", "grok", "antigravity", "copilot", "devin", "opencode"].filter { ids.contains($0) }
        if availableProviders != list {
            availableProviders = list
        }
    }

    func snapshot(fromDate: Date, throughDate: Date, provider: String, rangePreset: Int) -> AnalysisSnapshot {
        let fKey = HistoryAnalyzer.dayFormatter.string(from: fromDate)
        let tKey = HistoryAnalyzer.dayFormatter.string(from: throughDate)
        let key = "\(calendarContext)|\(fKey)|\(tKey)|\(provider)|\(rangePreset)|\(history.days.count)"
        if let cached = snapshotCache[key] {
            return cached
        }
        let built = AnalysisSnapshot.build(
            historyDays: history.days,
            stats: stats,
            fromDate: fromDate,
            throughDate: throughDate,
            provider: provider,
            rangePreset: rangePreset
        )
        snapshotCache[key] = built
        return built
    }

    private func invalidateSnapshots() {
        // Build only the visible range on demand; warming every provider and
        // preset blocks the main actor for views that may never be opened.
        snapshotCache.removeAll(keepingCapacity: true)
    }

    func checkRealtimeActivity() async {
        if updateCalendarContext() {
            await refresh(force: true)
            return
        }
        guard !isRefreshing, !isCheckingActivity else { return }
        isCheckingActivity = true
        defer { isCheckingActivity = false }
        let signature = await readers.activity()
        guard !isRefreshing else { return }
        if lastActivitySignature.isEmpty {
            lastActivitySignature = signature
            return
        }
        guard signature != lastActivitySignature else { return }
        guard Date().timeIntervalSince(lastLocalRefreshAt) >= 5 else { return }
        lastActivitySignature = signature
        // New local messages need a rescan, not another round of requests to
        // every quota service. The timer and manual refresh update quotas.
        await refreshLocalUsage()
    }

    @discardableResult private func updateCalendarContext() -> Bool {
        let zone = HistoryAnalyzer.zone.identifier
        let context = zone + "|" + HistoryAnalyzer.dayFormatter.string(from: Date())
        guard context != calendarContext else { return false }
        if !calendarContext.hasPrefix(zone + "|") {
            // Do not show daily totals from the previous zone during the rescan.
            history = HistoryResult(days: [], sources: [:], updatedAt: .distantPast, warnings: [], timeZoneIdentifier: zone)
        }
        calendarContext = context
        invalidateSnapshots()
        onRefresh?()
        return true
    }

    nonisolated static func activitySignature() -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var parts: [String] = []
        func stamp(_ url: URL) -> String {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return "" }
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            let mod = ((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0).bitPattern
            return "\(url.path):\(size):\(mod)"
        }
        let directFiles = [
            home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb-wal")
        ]
        for file in directFiles { parts.append(stamp(file)) }
        for cacheDir in [
            home.appendingPathComponent("Library/Application Support/OpenUsage/log-scan-cache")
        ] {
            for folder in (try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)) ?? [] {
                parts.append(stamp(folder.appendingPathComponent("manifest.plist")))
            }
        }
        let todayPath = HistoryAnalyzer.dayFormatter.string(from: Date()).replacingOccurrences(of: "-", with: "/")
        let codexToday = home.appendingPathComponent(".codex/sessions/" + todayPath)
        for file in (try? fm.contentsOfDirectory(at: codexToday, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "jsonl" {
            parts.append(stamp(file))
        }
        let claude = home.appendingPathComponent(".claude/projects")
        let claudeFiles = fm.enumerator(at: claude, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])
        while let file = claudeFiles?.nextObject() as? URL {
            if file.pathExtension == "jsonl" { parts.append(stamp(file)) }
        }
        let brain = home.appendingPathComponent(".gemini/antigravity/brain")
        if let folders = try? fm.contentsOfDirectory(at: brain, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            let recent = folders.sorted {
                let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d0 > d1
            }.prefix(3)
            for folder in recent {
                parts.append(stamp(folder.appendingPathComponent(".system_generated/logs/transcript.jsonl")))
            }
        }
        let grokSessions = home.appendingPathComponent(".grok/sessions")
        if let workspaces = try? fm.contentsOfDirectory(at: grokSessions, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for workspace in workspaces {
                guard let sessions = try? fm.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for session in sessions {
                    let usage = session.appendingPathComponent("usage.json")
                    if fm.fileExists(atPath: usage.path) { parts.append(stamp(usage)) }
                }
            }
        }
        for root in HistoryAnalyzer.antigravityConversationRoots(home: home) {
            guard let files = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            let recent = files.sorted {
                let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d0 > d1
            }.prefix(4)
            for file in recent {
                parts.append(stamp(file))
            }
        }
        return parts.sorted().joined(separator: "|")
    }

    func refresh(force: Bool) async {
        if isRefreshing {
            // A forced scan already includes requests arriving while it runs.
            if force && !isForceRefreshing { pendingForceRefresh = true }
            return
        }
        updateCalendarContext()
        isRefreshing = true
        isForceRefreshing = force
        error = nil
        // Local totals and optional OpenUsage data can finish and publish while
        // the quota helper is still waiting on a remote provider.
        let hadAntigravity = providers.contains { $0.id == "antigravity" }
        async let localRefresh: Void = refreshLocalUsage()
        async let supplementalRefresh: Void = hadAntigravity ? supplementAntigravityGemini() : ()
        await refreshQuotas(force: force)
        if !hadAntigravity { await supplementAntigravityGemini() }
        await supplementalRefresh
        await localRefresh
        isRefreshing = false
        isForceRefreshing = false
        onRefresh?()
        if pendingForceRefresh {
            pendingForceRefresh = false
            await refresh(force: true)
        }
    }

    private func refreshQuotas(force: Bool) async {
        do {
            let data = try await readers.quotas(force)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = root["providers"] as? [String: [String: Any]], !rows.isEmpty else {
                throw NSError(domain: "Aicost", code: 1)
            }
            let providerOrder = supportedOrder.filter { rows[$0] != nil } + rows.keys.filter { !supportedOrder.contains($0) }.sorted()
            let retained = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.metrics) })
            let retainedPlans = Dictionary(uniqueKeysWithValues: providers.compactMap { provider -> (String, String)? in
                guard let plan = provider.plan, !plan.isEmpty else { return nil }
                return (provider.id, plan)
            })
            providers = providerOrder.compactMap { key in
                guard let row = rows[key] else { return nil }
                let resources = row["resources"] as? [String: [String: Any]] ?? [:]
                var order: [String]
                switch key {
                case "cursor": order = ["totalUsage", "autoUsage", "apiUsage"]
                case "codex": order = ["session", "weekly", "monthly", "spark", "sparkWeekly"]
                case "grok": order = ["weekly"]
                case "antigravity": order = ["geminiSession", "nonGeminiSession", "geminiWeekly", "nonGeminiWeekly"]
                default: order = ["session", "daily", "weekly", "monthly", "chat", "completions", "premiumRequests"]
                }
                order = order.filter { resources[$0] != nil } + resources.keys.filter { !order.contains($0) }.sorted()
                let parsed = distinctMetrics(order.compactMap { id -> Metric? in
                    guard let value = resources[id], let remaining = value["remaining"] as? Double else { return nil }
                    let limit = value["limit"] as? Double ?? 100
                    let ratio = limit > 0 ? max(0, min(1, remaining / limit)) : 0
                    let windowSeconds = QuotaWindows.seconds(from: value["windowSeconds"])
                    let reading = QuotaWindows.reading(id: id, remaining: ratio, windowSeconds: windowSeconds)
                    let reset = (value["resetsAt"] as? String).flatMap(HistoryAnalyzer.parseDate)
                    return Metric(id: reading.id, remaining: reading.remaining, reset: reset, kind: reading.kind)
                })
                let metrics = key == "antigravity"
                    ? AntigravityGeminiQuota.mergingProvider(incoming: parsed, retained: retained[key] ?? [])
                    : parsed
                let fetchedAt = (row["fetchedAt"] as? String).flatMap(HistoryAnalyzer.parseDate)
                let plan = Self.keptPlan(row["plan"] as? String, existing: retainedPlans[key])
                return ProviderUsage(id: key, name: providerNames[key] ?? row["displayName"] as? String ?? key, plan: plan, metrics: metrics, stale: row["stale"] as? Bool ?? false, fetchedAt: fetchedAt)
            }
            rebuildAvailableProviders()
            lastUpdated = (root["generatedAt"] as? String).flatMap(HistoryAnalyzer.parseDate) ?? Date()
            onRefresh?()
        } catch { self.error = .quotaReadFailed }
        // OpenUsage may have completed before the helper; apply its newer
        // windows again after the helper replaces the provider list.
        if let data = lastAPIData,
           let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            mergeNewerOpenUsageQuotas(rows)
        }
    }

    private func refreshLocalUsage() async {
        if let localRefreshTask {
            await localRefreshTask.value
            return
        }
        let task = Task { await performLocalRefresh() }
        localRefreshTask = task
        await task.value
        localRefreshTask = nil
        if pendingLocalRefresh {
            pendingLocalRefresh = false
            await refreshLocalUsage()
        }
    }

    private func performLocalRefresh() async {
        lastLocalRefreshAt = Date()
        do {
            let data = try await readers.openUsage()
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw URLError(.badServerResponse) }
            lastAPIData = data; apiConnected = true
            stats = rows.compactMap { row in
                guard let id = row["providerId"] as? String else { return nil }
                let lines = row["lines"] as? [[String: Any]] ?? []
                func text(_ label: String) -> String? { lines.first { $0["label"] as? String == label && $0["type"] as? String == "text" }?["value"] as? String }
                return ProviderStats(id: id, name: providerNames[id] ?? id, today: text("Today"), yesterday: text("Yesterday"), monthly: text("Last 30 Days"))
            }
            mergeNewerOpenUsageQuotas(rows)
        } catch { apiConnected = false }
        let data = lastAPIData
        let collected = await readers.history(data)
        updateCalendarContext()
        if collected.timeZoneIdentifier == HistoryAnalyzer.zone.identifier {
            invalidateSnapshots()
            history = collected
        } else {
            pendingLocalRefresh = true
        }
        rebuildAvailableProviders()
        onRefresh?()
    }

    private func mergeNewerOpenUsageQuotas(_ rows: [[String: Any]]) {
        let labelMap: [String: [String: String]] = [
            "cursor": ["total usage": "totalUsage", "cursor models": "autoUsage", "other models": "apiUsage"],
            "codex": ["session": "session", "weekly": "weekly", "monthly": "monthly"],
            "grok": ["weekly limit": "weekly", "weekly": "weekly"],
            "antigravity": ["session": "geminiSession", "weekly": "geminiWeekly", "claude": "nonGeminiSession", "claude weekly": "nonGeminiWeekly"]
        ]
        var updated = providers
        var changed = false
        for row in rows {
            guard let id = row["providerId"] as? String,
                  let map = labelMap[id],
                  let fetched = (row["fetchedAt"] as? String).flatMap(HistoryAnalyzer.parseDate),
                  let idx = updated.firstIndex(where: { $0.id == id }) else { continue }
            let existing = updated[idx]
            guard existing.stale || existing.metrics.isEmpty || fetched > (existing.fetchedAt ?? .distantPast) else { continue }
            let lines = row["lines"] as? [[String: Any]] ?? []
            let metrics = distinctMetrics(lines.compactMap { line -> Metric? in
                guard line["type"] as? String == "progress",
                      let rawLabel = (line["label"] as? String)?.lowercased(),
                      let mapped = map[rawLabel],
                      let used = line["used"] as? Double else { return nil }
                let limit = line["limit"] as? Double ?? 100
                let ratio = limit > 0 ? max(0, min(1, (limit - used) / limit)) : 0
                let periodMs = (line["periodDurationMs"] as? NSNumber)?.intValue
                let windowSeconds = periodMs.flatMap { $0 > 0 ? $0 / 1000 : nil }
                let reading = QuotaWindows.reading(id: mapped, remaining: ratio, windowSeconds: windowSeconds)
                let reset = (line["resetsAt"] as? String).flatMap(HistoryAnalyzer.parseDate)
                return Metric(id: reading.id, remaining: reading.remaining, reset: reset, kind: reading.kind)
            })
            guard !metrics.isEmpty else { continue }
            let merged = id == "antigravity"
                ? AntigravityGeminiQuota.mergingProvider(incoming: metrics, retained: existing.metrics)
                : metrics
            updated[idx] = ProviderUsage(id: existing.id, name: existing.name, plan: (row["plan"] as? String) ?? existing.plan, metrics: merged, stale: false, fetchedAt: fetched)
            changed = true
        }
        if changed {
            providers = updated
            lastUpdated = Date()
            onRefresh?()
        }
    }

    /// `agy` is the authority for both Antigravity pools. A summary that only echoes the
    /// other-model pool must not replace Gemini on the menu bar. The corner label is the
    /// subscription type, read from the client or CLI status when the quota feed leaves it blank.
    private func supplementAntigravityGemini() async {
        guard let provider = providers.first(where: { $0.id == "antigravity" }) else { return }
        let needsPlan = Self.planNeedsSubscriptionType(provider.plan)
        async let fetchedPlan: String? = needsPlan ? readers.antigravityPlan() : nil
        let snapshot = await readers.antigravity()
        var windows = snapshot.windows
        if windows.isEmpty,
           let latest = providers.first(where: { $0.id == "antigravity" }),
           !latest.metrics.contains(where: { QuotaWindows.pool(of: $0.id) == "gemini" }),
           let window = await Self.fetchAntigravityGeminiSession() {
            windows.append(AntigravityGeminiQuota.PoolWindow(id: "geminiSession", remaining: window.remaining, reset: window.reset))
        }
        let fallbackPlan = await fetchedPlan
        let plan = snapshot.plan ?? fallbackPlan
        // Local OpenUsage results can update this provider while the requests
        // above are suspended. Merge into the latest row rather than a copy.
        guard let index = providers.firstIndex(where: { $0.id == "antigravity" }) else { return }
        let current = providers[index]
        providers[index] = ProviderUsage(id: current.id, name: current.name,
                                        plan: plan ?? current.plan,
                                        metrics: AntigravityGeminiQuota.merging(windows, into: current.metrics),
                                        stale: current.stale, fetchedAt: current.fetchedAt)
    }

    private static func planNeedsSubscriptionType(_ plan: String?) -> Bool {
        guard let plan = plan?.trimmingCharacters(in: .whitespacesAndNewlines), !plan.isEmpty else { return true }
        let folded = plan.lowercased()
        return folded == "gemini" || folded == "antigravity"
    }

    /// Runway may leave Antigravity's plan empty. Keep the subscription type already read locally
    /// so a later quota refresh does not strip the Pro tag while the next lookup is still running.
    private static func keptPlan(_ incoming: String?, existing: String?) -> String? {
        if !planNeedsSubscriptionType(incoming) { return incoming }
        if !planNeedsSubscriptionType(existing) { return existing }
        return nil
    }

    nonisolated static func fetchAgyGeminiSnapshot() async -> AntigravitySupplement {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/agy"),
            URL(fileURLWithPath: "/opt/homebrew/bin/agy"),
            URL(fileURLWithPath: "/usr/local/bin/agy")
        ]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return AntigravitySupplement() }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(home.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        let csrf = UUID().uuidString + UUID().uuidString
        let commandEnvironment = environment
        let command = Task.detached(priority: .userInitiated) {
            try? LocalCommand.run(executable: executable,
                arguments: ["--csrf_token", csrf, "-p", "/usage", "--output-format", "json"],
                environment: commandEnvironment, timeout: 15)
        }
        async let plan: String? = Task.detached(priority: .utility) {
            AntigravityLocalPlan.read(expectedCSRF: csrf, waitForLaunch: true)
        }.value
        let result = await command.value
        let resolvedPlan = await plan
        guard let result, result.status == 0 else { return AntigravitySupplement(plan: resolvedPlan) }
        return AntigravitySupplement(windows: AntigravityGeminiQuota.pools(fromAgy: result.data), plan: resolvedPlan)
    }

    private static func fetchAntigravityGeminiSession() async -> AntigravityGeminiQuota.Window? {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Runway/antigravity/auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = root["accessToken"] as? String, !token.isEmpty else { return nil }
        if let expires = root["expiresAtMs"] as? Double, expires > 0, Date().timeIntervalSince1970 * 1000 > expires - 15_000 {
            return nil
        }
        let bases = [
            "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",
            "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
        ]
        for base in bases {
            guard let url = URL(string: base) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (body, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let window = AntigravityGeminiQuota.session(from: body) else { continue }
            return window
        }
        return nil
    }

    nonisolated static func fetchAntigravityPlan() async -> String? {
        await Task.detached(priority: .utility) { AntigravityLocalPlan.read() }.value
    }

}

struct QuickSummaryView: View {
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var settings: AppSettings
    let openFull: () -> Void
    let openQuota: () -> Void
    let openProvider: (String) -> Void
    let openSettings: () -> Void

    @State private var hoveredProvider: String?
    @State private var hoverPrimaryBtn = false
    @State private var hoverQuotaBtn = false
    @State private var hoverRefresh = false
    @State private var hoverGear = false

    private var todayStr: String {
        HistoryAnalyzer.dayFormatter.string(from: Date())
    }
    private var todayRows: [UsageDay] {
        usage.history.days.filter { $0.date == todayStr }
    }
    private var todayTokens: Double {
        todayRows.reduce(0) { $0 + $1.total }
    }
    private var todayCost: Double {
        todayRows.reduce(0) { $0 + $1.pricedCost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AicostBrandIcon(size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aicost")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(settings.t("订阅与今日用量", "Subscriptions & Today"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Circle()
                        .fill(usage.isRefreshing ? Color.orange : Color.green)
                        .frame(width: 5.5, height: 5.5)
                    Text(usage.isRefreshing ? settings.t("更新中…", "Updating…") : (usage.lastUpdated.map { $0.formatted(date: .omitted, time: .shortened) } ?? settings.t("读取中", "Loading…")))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: Capsule())
                .fixedSize()

                Button {
                    guard !usage.isRefreshing else { return }
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    Task { await usage.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(usage.isRefreshing ? 0.4 : 1.0)
                        .frame(width: 24, height: 24)
                        .background(hoverRefresh && !usage.isRefreshing ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { hoverRefresh = $0 }
                .help(settings.t("立即刷新", "Refresh Now"))

                Button {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(hoverGear ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { hoverGear = $0 }
                .help(settings.t("设置", "Settings"))
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(settings.t("今日 Token", "Today's Tokens"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(todayTokens > 0 ? shortTokens(todayTokens) : "—")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.05), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.teal)
                        Text(settings.t("今日估算", "Today's Cost"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(todayCost > 0 ? money(todayCost) : "$0.00")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.05), lineWidth: 0.5))
            }

            if usage.providers.isEmpty {
                if let error = usage.error {
                    Text(error.message(isEnglish: settings.isEnglish)).font(.caption).foregroundStyle(.red).padding(.vertical, 8)
                } else {
                    ProgressView(settings.t("正在读取账户…", "Loading accounts…")).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(usage.providers.filter { settings.shownProviders.contains($0.id) }) { provider in
                        providerRow(provider)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: openFull) {
                    HStack(spacing: 7) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 12, weight: .semibold))
                        Text(settings.t("打开用量分析", "Open Usage Analysis"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10.5, weight: .bold))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: hoverPrimaryBtn
                                ? [Color(red: 0.16, green: 0.44, blue: 0.96), Color(red: 0.10, green: 0.64, blue: 0.58)]
                                : [Color(red: 0.13, green: 0.38, blue: 0.88), Color(red: 0.08, green: 0.56, blue: 0.52)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { hoverPrimaryBtn = $0 }

                Button(action: openQuota) {
                    HStack(spacing: 5) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                            .font(.system(size: 12, weight: .medium))
                        Text(settings.t("订阅额度", "Quotas"))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        hoverQuotaBtn ? Color.primary.opacity(0.11) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { hoverQuotaBtn = $0 }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(14)
        .frame(width: 408, height: 500)
    }

    private func providerRow(_ provider: ProviderUsage) -> some View {
        let primary = provider.statusBarMetric()
        let ratio = max(0, min(1, primary?.remaining ?? 0))
        let pct = primary?.remaining.map { QuotaWindows.displayedPercent($0) }
        let isHovered = hoveredProvider == provider.id
        let detail = provider.id == "antigravity"
            ? QuotaWindows.antigravityMenuLabel(provider.menuReadings, english: settings.isEnglish)
            : nil
        return Button {
            openProvider(provider.id)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    ProviderBadge(id: provider.id, size: 15)
                    Text(provider.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let plan = provider.plan, !plan.isEmpty {
                        Text(plan)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    Spacer()
                    if let pct {
                        Text(settings.t("剩余 \(QuotaWindows.percentageText(ratio))", "\(QuotaWindows.percentageText(ratio)) left"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(pct == 0 ? Color.red : pct <= 20 ? Color.orange : Color.primary)
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(providerColor(provider.id))
                            .frame(width: max(0, geo.size.width * ratio))
                    }
                }.frame(height: 6)
                HStack {
                    if let detail {
                        Text(detail)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if provider.statusBarMetrics.count > 1 {
                        Text(provider.statusBarMetrics.map { metric in
                            return settings.localizedMetricName(metric) + " " + QuotaWindows.percentageText(metric.remaining ?? 0)
                        }.joined(separator: " · "))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(primary.map { settings.localizedMetricName($0) } ?? settings.t("未提供额度", "No quota"))
                    }
                    Spacer()
                    if let reset = primary?.reset {
                        Label(settings.resetText(reset, compact: true), systemImage: "clock")
                            .lineLimit(1)
                            .help(settings.resetText(reset))
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .padding(11)
            .background(
                isHovered ? Color.primary.opacity(0.05) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isHovered ? providerColor(provider.id).opacity(0.35) : Color.primary.opacity(0.05), lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { inside in
            if inside { hoveredProvider = provider.id }
            else if hoveredProvider == provider.id { hoveredProvider = nil }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var navigation: AppNavigation
    @State private var hoverTopRefresh = false
    @State private var hoverTopSettings = false
    private var section: String { navigation.section }
    let openSettings: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    AicostBrandIcon(size: 26)
                    Text("Aicost")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 22)
                sidebarButton(settings.t("用量分析", "Usage Analysis"), icon: "chart.bar.xaxis", value: "analysis")
                sidebarButton(settings.t("订阅额度", "Subscription Quotas"), icon: "gauge.with.dots.needle.50percent", value: "quota")
                sidebarButton(settings.t("设置", "Settings"), icon: "gearshape", value: "settings")
                Divider().padding(.vertical, 12)
                Text(settings.t("应用", "Apps")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 10)
                VStack(spacing: 3) {
                    appShortcut("all", name: settings.t("全部应用", "All Apps"))
                    ForEach(usage.availableProviders.filter { settings.shownProviders.contains($0) || $0 == "claude" || $0 == "opencode" }, id: \.self) { id in
                        appShortcut(id, name: providerNames[id] ?? id)
                    }
                }
                Spacer(minLength: 12)
                Text(settings.t("本机用量记录", "Local Usage Records")).font(.caption).foregroundStyle(.secondary)
                Label(usage.isRefreshing ? settings.t("正在更新", "Updating…") : settings.refreshIntervalLabel, systemImage: "arrow.clockwise")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 22)
            .frame(width: settings.isEnglish ? 216 : 188)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: true, vertical: false)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(section == "analysis" ? settings.t("用量分析", "Usage Analysis") : (section == "quota" ? settings.t("订阅额度", "Subscription Quotas") : settings.t("设置", "Settings")))
                        .font(.system(size: 21, weight: .semibold))
                    Spacer()
                    if usage.isRefreshing { ProgressView().controlSize(.small) }
                    Button {
                        guard !usage.isRefreshing else { return }
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        Task { await usage.refresh(force: true) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11.5, weight: .medium))
                            Text(settings.t("刷新", "Refresh"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            hoverTopRefresh && !usage.isRefreshing ? Color.primary.opacity(0.08) : Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .opacity(usage.isRefreshing ? 0.55 : 1.0)
                    .onHover { hoverTopRefresh = $0 }

                    Button {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(section == "settings" ? Color.accentColor : Color.primary)
                            .frame(width: 30, height: 28)
                            .background(
                                section == "settings"
                                    ? Color.accentColor.opacity(0.13)
                                    : (hoverTopSettings ? Color.primary.opacity(0.08) : Color(nsColor: .controlBackgroundColor)),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(section == "settings" ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08), lineWidth: 0.8)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .onHover { hoverTopSettings = $0 }
                    .help(settings.t("设置", "Settings"))
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 19)
                .frame(maxWidth: .infinity)

                Divider()

                ZStack(alignment: .topLeading) {
                    AnalysisView(provider: $navigation.provider)
                        .opacity(section == "analysis" ? 1 : 0)
                        .allowsHitTesting(section == "analysis")
                        .accessibilityHidden(section != "analysis")
                    QuotaView()
                        .opacity(section == "quota" ? 1 : 0)
                        .allowsHitTesting(section == "quota")
                        .accessibilityHidden(section != "quota")
                    SettingsView()
                        .opacity(section == "settings" ? 1 : 0)
                        .allowsHitTesting(section == "settings")
                        .accessibilityHidden(section != "settings")
                }
                .environmentObject(usage)
                .environmentObject(settings)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 860, maxWidth: .infinity, minHeight: 650, maxHeight: .infinity, alignment: .topLeading)
    }
    private func appShortcut(_ id: String, name: String) -> some View {
        let isSelected = section == "analysis" && navigation.provider == id
        return SidebarActionRow(
            isSelected: isSelected,
            selectedFill: Color.primary.opacity(0.075),
            hoverFill: Color.primary.opacity(0.04),
            cornerRadius: 6,
            action: { navigation.selectProvider(id) }
        ) {
            HStack(spacing: 9) {
                if id == "all" { Image(systemName: "square.grid.2x2").frame(width: 14) }
                else { ProviderBadge(id: id, size: 14) }
                Text(name).font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
    private func sidebarButton(_ title: String, icon: String, value: String) -> some View {
        let isSelected = section == value
        return SidebarActionRow(
            isSelected: isSelected,
            selectedFill: Color.accentColor.opacity(0.14),
            hoverFill: Color.primary.opacity(0.045),
            cornerRadius: 7,
            action: { navigation.selectSection(value) }
        ) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }
}

struct SidebarActionRow<Content: View>: View {
    let isSelected: Bool
    let selectedFill: Color
    let hoverFill: Color
    let cornerRadius: CGFloat
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? selectedFill : (isHovered ? hoverFill : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { inside in
                if isHovered != inside { isHovered = inside }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            action()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
    }
}

struct AppShare: Identifiable {
    let id: String
    var tokens: Double = 0
    var cost: Double = 0
}

struct StackedDayItem: Identifiable {
    var id: String { date + ":" + provider }
    let date: String
    let dateValue: Date
    let provider: String
    var tokens: Double = 0
    var cost: Double = 0
}

struct ChartDay: Identifiable {
    var id: String { date }
    let date: String
    let dateValue: Date
    var total: Double = 0
    var input: Double = 0
    var cached: Double = 0
    var written: Double = 0
    var output: Double = 0
    var knownCost: Double = 0
    var detailed = true
    var hasRecords = false
    var requests: Int = 0
}

struct CalendarPickerPopover: View {
    @EnvironmentObject var settings: AppSettings
    let selectedDate: Date
    let rangeStart: Date
    let rangeEnd: Date
    let minDate: Date?
    let maxDate: Date
    let onSelect: (Date) -> Void

    @State private var displayedMonth: Date
    @State private var hoveredDay: Date?

    private var cal: Calendar { HistoryAnalyzer.calendar }
    private var weekdays: [String] {
        settings.isEnglish ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] : ["日", "一", "二", "三", "四", "五", "六"]
    }

    init(selectedDate: Date, rangeStart: Date, rangeEnd: Date, minDate: Date? = nil, maxDate: Date, onSelect: @escaping (Date) -> Void) {
        let calendar = HistoryAnalyzer.calendar
        self.selectedDate = selectedDate
        self.rangeStart = calendar.startOfDay(for: min(rangeStart, rangeEnd))
        self.rangeEnd = calendar.startOfDay(for: max(rangeStart, rangeEnd))
        self.minDate = minDate.map { calendar.startOfDay(for: $0) }
        self.maxDate = calendar.startOfDay(for: maxDate)
        self.onSelect = onSelect
        let monthStart = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        _displayedMonth = State(initialValue: monthStart)
    }

    private var monthTitle: String {
        let y = cal.component(.year, from: displayedMonth)
        let m = cal.component(.month, from: displayedMonth)
        if settings.isEnglish {
            let names = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            let name = (m >= 1 && m <= 12) ? names[m] : "\(m)"
            return "\(name) \(y)"
        } else {
            return "\(y)年 \(m)月"
        }
    }

    private var canGoPrevMonth: Bool {
        guard let minDate else { return true }
        return displayedMonth > minDate
    }

    private var canGoNextMonth: Bool {
        guard let next = cal.date(byAdding: .month, value: 1, to: displayedMonth) else { return false }
        return next <= maxDate
    }

    private var daysInGrid: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstDay = interval.start
        let firstWeekday = cal.component(.weekday, from: firstDay) - 1
        let count = cal.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: max(0, firstWeekday))
        for offset in 0..<count {
            cells.append(cal.date(byAdding: .day, value: offset, to: firstDay))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    var body: some View {
        let today = cal.startOfDay(for: Date())
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(monthTitle)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if today <= maxDate && (minDate == nil || today >= minDate!) {
                    Button {
                        onSelect(today)
                    } label: {
                        Text(settings.t("今天", "Today"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
                Button {
                    if let prev = cal.date(byAdding: .month, value: -1, to: displayedMonth) {
                        displayedMonth = prev
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(!canGoPrevMonth)
                .opacity(canGoPrevMonth ? 1 : 0.35)
                Button {
                    if let next = cal.date(byAdding: .month, value: 1, to: displayedMonth) {
                        displayedMonth = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(!canGoNextMonth)
                .opacity(canGoNextMonth ? 1 : 0.35)
            }

            HStack(spacing: 2) {
                ForEach(weekdays, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 2)

            let cells = daysInGrid
            let rowsCount = cells.count / 7
            VStack(spacing: 3) {
                ForEach(0..<rowsCount, id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { c in
                            if let day = cells[r * 7 + c] {
                                dayButton(day, today: today)
                            } else {
                                Color.clear.frame(width: 34, height: 30)
                            }
                        }
                    }
                }
            }

            HStack {
                Text(settings.t("单次最长可选择 31 天（1 个月）", "Max range is 31 days (1 month)"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 276)
    }

    private func dayButton(_ day: Date, today: Date) -> some View {
        let dayStart = cal.startOfDay(for: day)
        let isSelected = cal.isDate(dayStart, inSameDayAs: selectedDate)
        let isToday = cal.isDate(dayStart, inSameDayAs: today)
        let inRange = dayStart >= rangeStart && dayStart <= rangeEnd
        let isDisabled = dayStart > maxDate || (minDate != nil && dayStart < minDate!)
        let isHovered = hoveredDay == dayStart && !isDisabled
        let num = cal.component(.day, from: dayStart)

        return Button {
            guard !isDisabled else { return }
            onSelect(dayStart)
        } label: {
            Text("\(num)")
                .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : (isDisabled ? Color.secondary.opacity(0.35) : (isToday ? Color.accentColor : Color.primary)))
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.1) : (inRange ? Color.accentColor.opacity(0.11) : Color.clear)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isToday && !isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(isDisabled)
        .onHover { inside in
            if inside {
                hoveredDay = dayStart
            } else if hoveredDay == dayStart {
                hoveredDay = nil
            }
        }
    }
}

struct ModelBreakdown: Identifiable {
    var id: String
    var provider: String
    var name: String
    var total: Double
    var cached: Double
    var output: Double
    var requests: Int
    var pricedCost: Double
}

struct AnalysisSnapshot {
    var start: Date = Date()
    var end: Date = Date()
    var range: Int = 1
    var dateRangeLabel: String = ""
    var rowsEmpty: Bool = true
    var totalTokens: Double = 0
    var costTotal: Double = 0
    var costText: String = "—"
    var hasDetail: Bool = false
    var totalRequests: Int = 0
    var cacheRate: String = "—"
    var activeDayCount: Int = 0
    var stackProviders: [String] = ["codex"]
    var scaleDomain: [String] = supportedOrder
    var stackedDaily: [StackedDayItem] = []
    var daily: [ChartDay] = []
    var activeDailyRows: [ChartDay] = []
    var dayProvidersByDate: [String: [String]] = [:]
    var dayPartsByDate: [String: [StackedDayItem]] = [:]
    var maxDayTokens: Double = 1
    var modelRows: [ModelBreakdown] = []
    var maxModelTokens: Double = 1
    var sharesByTokens: [AppShare] = []
    var sharesByCost: [AppShare] = []
    var allSharesTotalTokens: Double = 0
    var allSharesTotalCost: Double = 0

    static func build(
        historyDays: [UsageDay],
        stats: [ProviderStats],
        fromDate: Date,
        throughDate: Date,
        provider: String,
        rangePreset: Int
    ) -> AnalysisSnapshot {
        let cal = HistoryAnalyzer.calendar
        let start = cal.startOfDay(for: min(fromDate, throughDate))
        let rawEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(fromDate, throughDate)))!
        let maxEnd = cal.date(byAdding: .day, value: 31, to: start)!
        let end = min(rawEnd, maxEnd)
        let lastDay = cal.date(byAdding: .day, value: -1, to: end) ?? start
        let range = min(31, max(1, cal.dateComponents([.day], from: start, to: end).day ?? 1))
        let startKey = HistoryAnalyzer.dayFormatter.string(from: start)
        let endKey = HistoryAnalyzer.dayFormatter.string(from: lastDay)

        func shortDate(_ d: Date) -> String {
            "\(cal.component(.month, from: d))月\(cal.component(.day, from: d))日"
        }

        var rows: [UsageDay] = []
        var shareGroups: [String: AppShare] = [:]
        var allSharesTotalTokens: Double = 0
        var allSharesTotalCost: Double = 0

        for day in historyDays where day.date >= startKey && day.date <= endKey {
            allSharesTotalTokens += day.total
            allSharesTotalCost += day.pricedCost
            var share = shareGroups[day.provider] ?? AppShare(id: day.provider)
            share.tokens += day.total
            share.cost += day.pricedCost
            shareGroups[day.provider] = share

            if provider == "all" || day.provider == provider {
                rows.append(day)
            }
        }

        let presentProviders = Set(rows.filter { $0.total > 0 || $0.pricedCost > 0 }.map(\.provider))
        let orderedProviders = supportedOrder.filter { presentProviders.contains($0) } + presentProviders.filter { !supportedOrder.contains($0) }.sorted()
        let stackProviders = orderedProviders.isEmpty ? (provider == "all" ? ["codex"] : [provider]) : orderedProviders
        let allowedProviders = Set(stackProviders)

        var scaleDomain = stackProviders
        for p in supportedOrder where !scaleDomain.contains(p) { scaleDomain.append(p) }

        var stackedMap: [String: StackedDayItem] = [:]
        var daysMap: [String: ChartDay] = [:]
        var orderedDateLabels: [String] = []
        orderedDateLabels.reserveCapacity(range)

        for index in 0..<range {
            let date = cal.date(byAdding: .day, value: index, to: start)!
            let label = HistoryAnalyzer.dayFormatter.string(from: date)
            orderedDateLabels.append(label)
            daysMap[label] = ChartDay(date: label, dateValue: date)
            for p in stackProviders {
                stackedMap[label + ":" + p] = StackedDayItem(date: label, dateValue: date, provider: p)
            }
        }

        var totalTokens: Double = 0
        var costTotal: Double = 0
        var hasDetail = false
        var totalRequests = 0
        var detailedInputTotal: Double = 0
        var detailedCachedTotal: Double = 0
        var modelsMap: [String: ModelBreakdown] = [:]

        for row in rows {
            totalTokens += row.total
            costTotal += row.pricedCost
            totalRequests += row.requests ?? 0
            if row.detailed {
                if row.total > 0 { hasDetail = true }
                detailedInputTotal += row.input + row.cached + row.written
                detailedCachedTotal += row.cached
            }

            if allowedProviders.contains(row.provider) {
                let key = row.date + ":" + row.provider
                if var item = stackedMap[key] {
                    item.tokens += row.total
                    item.cost += row.pricedCost
                    stackedMap[key] = item
                }
            }

            if var day = daysMap[row.date] {
                day.hasRecords = true
                day.total += row.total
                day.input += row.input
                day.cached += row.cached
                day.written += row.written
                day.output += row.output
                day.requests += row.requests ?? 0
                day.knownCost += row.pricedCost
                if !row.detailed && row.total > 0 { day.detailed = false }
                daysMap[row.date] = day
            }

            for item in row.models where item.total > 0 || item.pricedCost > 0 {
                let id = row.provider + "\u{1f}" + item.name
                var model = modelsMap[id] ?? ModelBreakdown(id: id, provider: row.provider, name: item.name, total: 0, cached: 0, output: 0, requests: 0, pricedCost: 0)
                model.cached += item.cached
                model.output += item.output
                model.total += item.total
                model.requests += item.requests
                model.pricedCost += item.pricedCost
                modelsMap[id] = model
            }
        }

        var stackedDaily: [StackedDayItem] = []
        stackedDaily.reserveCapacity(range * stackProviders.count)
        var daily: [ChartDay] = []
        daily.reserveCapacity(range)
        var dayProvidersByDate: [String: [String]] = [:]
        var dayPartsByDate: [String: [StackedDayItem]] = [:]

        for (idx, label) in orderedDateLabels.enumerated() {
            if let d = daysMap[label] {
                daily.append(d)
            }
            var partsForDay: [StackedDayItem] = []
            for (pIdx, p) in stackProviders.enumerated() {
                if let item = stackedMap[label + ":" + p] {
                    let isBoundaryAnchor = (idx == 0 || idx == orderedDateLabels.count - 1) && pIdx == 0
                    if item.tokens > 0 || item.cost > 0 || isBoundaryAnchor {
                        stackedDaily.append(item)
                    }
                    if item.tokens > 0 || item.cost > 0 {
                        partsForDay.append(item)
                    }
                }
            }
            let sortedByTokens = partsForDay.sorted { $0.tokens > $1.tokens }
            dayPartsByDate[label] = sortedByTokens
            dayProvidersByDate[label] = sortedByTokens.map(\.provider)
        }

        let activeDailyRows = Array(daily.filter { $0.hasRecords && ($0.total > 0 || $0.knownCost > 0) }.reversed())
        let maxDayTokens = max(1, activeDailyRows.map(\.total).max() ?? 1)
        let modelRows = modelsMap.values.sorted { $0.total > $1.total }
        let maxModelTokens = max(1, modelRows.map(\.total).max() ?? 1)

        let costText: String
        if rows.isEmpty {
            costText = "—"
        } else if costTotal == 0, range == 30, rangePreset == 30, provider != "all",
                  let value = stats.first(where: { $0.id == provider })?.monthly {
            costText = value.components(separatedBy: " · ").first ?? money(0)
        } else {
            costText = money(costTotal)
        }

        let cacheRate = detailedInputTotal > 0 ? String(format: "%.1f%%", detailedCachedTotal / detailedInputTotal * 100) : "—"
        let sharesByTokens = shareGroups.values.filter { $0.tokens > 0 }.sorted { $0.tokens > $1.tokens }
        let sharesByCost = shareGroups.values.filter { $0.cost > 0 }.sorted { $0.cost > $1.cost }

        return AnalysisSnapshot(
            start: start,
            end: end,
            range: range,
            dateRangeLabel: shortDate(start) + " – " + shortDate(lastDay),
            rowsEmpty: rows.isEmpty,
            totalTokens: totalTokens,
            costTotal: costTotal,
            costText: costText,
            hasDetail: hasDetail,
            totalRequests: totalRequests,
            cacheRate: cacheRate,
            activeDayCount: activeDailyRows.count,
            stackProviders: stackProviders,
            scaleDomain: scaleDomain,
            stackedDaily: stackedDaily,
            daily: daily,
            activeDailyRows: activeDailyRows,
            dayProvidersByDate: dayProvidersByDate,
            dayPartsByDate: dayPartsByDate,
            maxDayTokens: maxDayTokens,
            modelRows: modelRows,
            maxModelTokens: maxModelTokens,
            sharesByTokens: sharesByTokens,
            sharesByCost: sharesByCost,
            allSharesTotalTokens: allSharesTotalTokens,
            allSharesTotalCost: allSharesTotalCost
        )
    }
}

struct AnalysisView: View {
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var settings: AppSettings
    @State private var rangePreset = 0
    @State private var fromDate = HistoryAnalyzer.calendar.dateInterval(of: .month, for: Date())!.start
    @State private var throughDate = HistoryAnalyzer.calendar.startOfDay(for: Date())
    @State private var showFromPicker = false
    @State private var showThroughPicker = false
    @State private var initializedRange = false
    @State private var selectionTimeZone = HistoryAnalyzer.zone.identifier
    @Binding var provider: String

    var body: some View {
        let snapshot = usage.snapshot(
            fromDate: fromDate,
            throughDate: throughDate,
            provider: provider,
            rangePreset: rangePreset
        )
        let hasHistory = !usage.history.days.isEmpty && (provider == "all" || usage.history.sources[provider] != nil)
        return GeometryReader { geometry in
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                filters(snapshot: snapshot)
                summary(snapshot: snapshot)
                TrendChartSection(
                    snapshot: snapshot,
                    hasHistory: hasHistory,
                    provider: $provider
                )
                ShareBreakdownSection(
                    snapshot: snapshot,
                    provider: $provider
                )
                UsageDetailSection(snapshot: snapshot)
                sourceNotes
            }
            .frame(width: max(0, geometry.size.width - 48), alignment: .topLeading)
            .padding(24)
            .background(OverlayScrollerBridge())
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if !initializedRange {
                applyRange(settings.defaultRange)
                initializedRange = true
            }
        }
        .onChange(of: usage.calendarContext) { _, _ in
            showFromPicker = false
            showThroughPicker = false
            let newZone = HistoryAnalyzer.zone.identifier
            if rangePreset >= 0 {
                applyRange(rangePreset)
            } else if newZone != selectionTimeZone,
                      let oldZone = TimeZone(identifier: selectionTimeZone) {
                // Custom ranges represent calendar dates, not absolute instants.
                let oldCalendar = HistoryAnalyzer.calendar(timeZone: oldZone)
                let newCalendar = HistoryAnalyzer.calendar
                fromDate = newCalendar.date(from: oldCalendar.dateComponents([.year, .month, .day], from: fromDate)) ?? fromDate
                throughDate = newCalendar.date(from: oldCalendar.dateComponents([.year, .month, .day], from: throughDate)) ?? throughDate
            }
            selectionTimeZone = newZone
        }
    }

    private func filters(snapshot: AnalysisSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                presetBar.fixedSize(horizontal: true, vertical: false)
                dateBounds(snapshot: snapshot)
                Spacer(minLength: 0)
                applicationPicker
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    presetBar
                    Spacer(minLength: 0)
                    applicationPicker
                }
                dateBounds(snapshot: snapshot)
            }
        }
    }
    private var presetBar: some View {
        HStack(spacing: 4) {
            presetButton(settings.t("今天", "Today"), tag: 1)
            presetButton(settings.t("近7天", "7 Days"), tag: 7)
            presetButton(settings.t("本月", "This Month"), tag: 0)
            presetButton(settings.t("近30天", "30 Days"), tag: 30)
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
    private func presetButton(_ title: String, tag: Int) -> some View {
        let active = rangePreset == tag
        return Button { applyRange(tag) } label: {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).focusEffectDisabled()
    }
    private var applicationPicker: some View {
        Picker(settings.t("应用", "Apps"), selection: $provider) {
            Text(settings.t("全部应用", "All Apps")).tag("all")
            ForEach(usage.availableProviders, id: \.self) { id in Text(providerNames[id] ?? id).tag(id) }
        }
        .labelsHidden()
        .frame(width: 140)
    }
    private func dateBounds(snapshot: AnalysisSnapshot) -> some View {
        let cal = HistoryAnalyzer.calendar
        let safeUpper = max(fromDate, throughDate)
        let safeLower = min(fromDate, throughDate)
        let maxSelectable = cal.startOfDay(for: max(Date(), safeUpper))
        let maxEndForFrom = min(maxSelectable, cal.date(byAdding: .day, value: 30, to: safeLower) ?? maxSelectable)
        return HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Button {
                showFromPicker.toggle()
            } label: {
                Text(HistoryAnalyzer.dayFormatter.string(from: fromDate))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(showFromPicker ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(showFromPicker ? Color.accentColor : Color.primary)
                    .contentShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .popover(isPresented: $showFromPicker, arrowEdge: .bottom) {
                CalendarPickerPopover(
                    selectedDate: fromDate,
                    rangeStart: fromDate,
                    rangeEnd: throughDate,
                    minDate: nil,
                    maxDate: maxSelectable
                ) { picked in
                    fromDate = picked
                    if throughDate < picked {
                        throughDate = picked
                    } else if (cal.dateComponents([.day], from: picked, to: throughDate).day ?? 0) > 30 {
                        throughDate = min(maxSelectable, cal.date(byAdding: .day, value: 30, to: picked) ?? throughDate)
                    }
                    rangePreset = -1
                    showFromPicker = false
                }
            }
            Text("→")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Button {
                showThroughPicker.toggle()
            } label: {
                Text(HistoryAnalyzer.dayFormatter.string(from: throughDate))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(showThroughPicker ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(showThroughPicker ? Color.accentColor : Color.primary)
                    .contentShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .popover(isPresented: $showThroughPicker, arrowEdge: .bottom) {
                CalendarPickerPopover(
                    selectedDate: throughDate,
                    rangeStart: fromDate,
                    rangeEnd: throughDate,
                    minDate: safeLower,
                    maxDate: maxEndForFrom
                ) { picked in
                    throughDate = picked
                    if fromDate > picked {
                        fromDate = picked
                    } else if (cal.dateComponents([.day], from: fromDate, to: picked).day ?? 0) > 30 {
                        fromDate = cal.date(byAdding: .day, value: -30, to: picked) ?? fromDate
                    }
                    rangePreset = -1
                    showThroughPicker = false
                }
            }
            Text(settings.isEnglish ? "\(snapshot.range) \(snapshot.range == 1 ? "Day" : "Days")" : "\(snapshot.range)天")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .fixedSize(horizontal: true, vertical: false)
    }
    private func applyRange(_ preset: Int) {
        var tx = Transaction(animation: nil)
        tx.disablesAnimations = true
        withTransaction(tx) {
            rangePreset = preset
            guard preset != -1 else { return }
            let today = HistoryAnalyzer.calendar.startOfDay(for: Date())
            fromDate = preset == 0 ? HistoryAnalyzer.calendar.dateInterval(of: .month, for: today)!.start
                : HistoryAnalyzer.calendar.date(byAdding: .day, value: -(preset - 1), to: today)!
            throughDate = today
        }
    }
    private func summary(snapshot: AnalysisSnapshot) -> some View {
        HStack(spacing: 14) {
            metric(
                settings.t("累计 Token", "Total Tokens"),
                icon: "sparkles",
                tint: Color(red: 0.22, green: 0.49, blue: 0.92),
                value: snapshot.rowsEmpty ? "—" : shortTokens(snapshot.totalTokens),
                sub: snapshot.rowsEmpty ? settings.t("当前区间无记录", "No records in range") : settings.t("日均 \(shortTokens(snapshot.totalTokens / Double(max(1, snapshot.activeDayCount)))) · 活跃 \(snapshot.activeDayCount) 天", "Avg \(shortTokens(snapshot.totalTokens / Double(max(1, snapshot.activeDayCount))))/day · \(snapshot.activeDayCount) active days")
            )
            metric(
                settings.t("估算费用", "Estimated Cost"),
                icon: "dollarsign.circle.fill",
                tint: Color(red: 0.12, green: 0.60, blue: 0.47),
                value: snapshot.costText,
                sub: settings.t("按模型 API 单价折算", "Calculated via model API rates")
            )
            metric(
                settings.t("记录次数", "Total Requests"),
                icon: "bolt.horizontal.fill",
                tint: Color(red: 0.52, green: 0.40, blue: 0.82),
                value: snapshot.hasDetail ? "\(snapshot.totalRequests)" : "—",
                sub: snapshot.hasDetail ? settings.t("共 \(snapshot.modelRows.count) 个细分模型", "\(snapshot.modelRows.count) distinct models") : settings.t("日汇总来源不含次数", "Daily summary source")
            )
            metric(
                settings.t("缓存读取率", "Cache Read Rate"),
                icon: "memorychip",
                tint: Color(red: 0.85, green: 0.52, blue: 0.18),
                value: snapshot.cacheRate,
                sub: settings.t("输入上下文缓存命中占比", "Prompt cache read hit ratio")
            )
        }
    }
    @ViewBuilder private var sourceNotes: some View {
        if let error = usage.error {
            Text(error.message(isEnglish: settings.isEnglish)).font(.system(size: 10)).foregroundStyle(.orange)
        }
    }
    private func metric(_ title: String, icon: String, tint: Color, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.05), lineWidth: 0.8))
    }
}

struct TrendChartSection: View {
    @EnvironmentObject var settings: AppSettings
    let snapshot: AnalysisSnapshot
    let hasHistory: Bool
    @Binding var provider: String
    @State private var chartMetric = "tokens"
    @State private var hoveredProvider: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(settings.t("每日用量", "Daily Usage")).font(.system(size: 14, weight: .semibold))
                Text(settings.monthDayString(snapshot.start) + " – " + settings.monthDayString(HistoryAnalyzer.calendar.date(byAdding: .day, value: -1, to: snapshot.end) ?? snapshot.start))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Picker(settings.t("图表指标", "Metric"), selection: $chartMetric) {
                    Text(settings.t("Token", "Tokens")).tag("tokens")
                    Text(settings.t("费用", "Cost")).tag("cost")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 120)
            }
            ZStack {
                VStack(alignment: .leading, spacing: 14) {
                    usageChart
                    stackLegend
                }
                .opacity(hasHistory ? 1 : 0)
                .allowsHitTesting(hasHistory)

                if !hasHistory {
                    ContentUnavailableView(settings.t("暂无历史用量", "No Usage History"), systemImage: "chart.bar")
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.05), lineWidth: 0.8))
    }

    private var stackLegend: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            ForEach(snapshot.stackProviders, id: \.self) { id in
                let isHovered = hoveredProvider == id
                Button {
                    var tx = Transaction(animation: nil)
                    tx.disablesAnimations = true
                    withTransaction(tx) {
                        provider = (provider == id ? "all" : id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        ProviderBadge(id: id, size: 13)
                        Text(providerNames[id] ?? id)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isHovered ? providerColor(id).opacity(0.14) : Color.primary.opacity(0.03), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { inside in
                    if ScrollWheelGate.isScrolling { return }
                    if inside {
                        if hoveredProvider != id { hoveredProvider = id }
                    } else if hoveredProvider == id {
                        hoveredProvider = nil
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private let plotLeft: CGFloat = 46
    private let plotRight: CGFloat = 6
    private let plotTop: CGFloat = 8
    private let plotBottom: CGFloat = 22

    private var chartScaleInfo: (maxY: Double, steps: Int) {
        var rawMax: Double = 0
        for day in snapshot.daily {
            let val = chartMetric == "tokens" ? day.total : day.knownCost
            if val > rawMax { rawMax = val }
        }
        guard rawMax > 0 else { return (1, 3) }
        let exp = floor(log10(rawMax))
        let mag = pow(10, exp)
        let norm = rawMax / mag
        if norm <= 1.2 { return (1.2 * mag, 3) }
        if norm <= 1.5 { return (1.5 * mag, 3) }
        if norm <= 2.0 { return (2.0 * mag, 4) }
        if norm <= 3.0 { return (3.0 * mag, 3) }
        if norm <= 4.0 { return (4.0 * mag, 4) }
        if norm <= 6.0 { return (6.0 * mag, 3) }
        if norm <= 8.0 { return (8.0 * mag, 4) }
        return (10.0 * mag, 4)
    }

    private var usageChart: some View {
        let scaleInfo = chartScaleInfo
        return Canvas { context, size in
            let plotRect = CGRect(
                x: plotLeft,
                y: plotTop,
                width: max(1, size.width - plotLeft - plotRight),
                height: max(1, size.height - plotTop - plotBottom)
            )
            let maxY = scaleInfo.maxY
            let steps = scaleInfo.steps
            for step in 0...steps {
                let frac = Double(step) / Double(steps)
                let y = plotRect.maxY - CGFloat(frac) * plotRect.height
                var hLine = Path()
                hLine.move(to: CGPoint(x: plotRect.minX, y: y))
                hLine.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                context.stroke(hLine, with: .color(.primary.opacity(0.08)), lineWidth: 0.6)

                let val = maxY * frac
                let labelStr = chartMetric == "tokens" ? shortTokens(val) : money(val)
                let resolved = context.resolve(
                    Text(labelStr)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                )
                context.draw(resolved, at: CGPoint(x: 0, y: y), anchor: .leading)
            }

            let count = snapshot.daily.count
            guard count > 0 else { return }
            let colWidth = plotRect.width / CGFloat(count)
            let barWidth = min(26, max(3, colWidth * 0.64))
            let xFontSize: CGFloat = snapshot.range <= 12 ? 10 : (snapshot.range <= 18 ? 9 : 8.5)
            let dashStyle = StrokeStyle(lineWidth: 0.5, dash: [2, 3])

            for i in 0..<count {
                let day = snapshot.daily[i]
                let centerX = plotRect.minX + (CGFloat(i) + 0.5) * colWidth

                var vLine = Path()
                vLine.move(to: CGPoint(x: centerX, y: plotRect.minY))
                vLine.addLine(to: CGPoint(x: centerX, y: plotRect.maxY))
                context.stroke(vLine, with: .color(.primary.opacity(0.07)), style: dashStyle)

                let dayText = xAxisDayText(day.dateValue)
                let resolvedX = context.resolve(
                    Text(dayText)
                        .font(.system(size: xFontSize))
                        .foregroundStyle(Color.secondary)
                )
                context.draw(resolvedX, at: CGPoint(x: centerX, y: plotRect.maxY + 12), anchor: .center)

                guard let parts = snapshot.dayPartsByDate[day.date], !parts.isEmpty else { continue }
                var currentBottom = plotRect.maxY
                for p in snapshot.stackProviders {
                    guard let item = parts.first(where: { $0.provider == p }) else { continue }
                    let val = chartMetric == "tokens" ? item.tokens : item.cost
                    guard val > 0 else { continue }
                    let h = max(1.5, min(currentBottom - plotRect.minY, CGFloat(val / maxY) * plotRect.height))
                    let rect = CGRect(x: centerX - barWidth * 0.5, y: currentBottom - h, width: barWidth, height: h)
                    let alpha = (hoveredProvider == nil || hoveredProvider == p) ? 1.0 : 0.22
                    let path = Path(roundedRect: rect, cornerRadius: min(2, h * 0.5))
                    context.fill(path, with: .color(providerColor(p).opacity(alpha)))
                    currentBottom -= h
                }
            }
        }
        .overlay {
            DailyChartHoverOverlay(
                plotInsets: EdgeInsets(top: plotTop, leading: plotLeft, bottom: plotBottom, trailing: plotRight),
                daily: snapshot.daily,
                dayPartsByDate: snapshot.dayPartsByDate,
                stackedDaily: snapshot.stackedDaily,
                chartMetric: chartMetric,
                hoveredProvider: hoveredProvider,
                totalTokens: snapshot.totalTokens
            )
        }
        .frame(height: 205)
    }

    private func xAxisDayText(_ date: Date) -> String {
        let cal = HistoryAnalyzer.calendar
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        if snapshot.range <= 16 {
            return settings.isEnglish ? "\(m)/\(d)" : "\(m)月\(d)日"
        } else if snapshot.range <= 35 {
            return "\(m)/\(d)"
        } else {
            return (d == 1 || cal.isDate(date, inSameDayAs: snapshot.start)) ? "\(m)/\(d)" : "\(d)"
        }
    }
}

struct ShareBreakdownSection: View {
    @EnvironmentObject var settings: AppSettings
    let snapshot: AnalysisSnapshot
    @Binding var provider: String
    @State private var shareMetric = "tokens"
    @State private var hoveredShareProvider: String?

    private var shares: [AppShare] {
        shareMetric == "tokens" ? snapshot.sharesByTokens : snapshot.sharesByCost
    }
    private var denominator: Double {
        shareMetric == "tokens" ? snapshot.allSharesTotalTokens : snapshot.allSharesTotalCost
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text(settings.t("各应用用量占比", "Usage Share by App")).font(.system(size: 14, weight: .semibold))
                if provider != "all" {
                    Button {
                        var tx = Transaction(animation: nil)
                        tx.disablesAnimations = true
                        withTransaction(tx) {
                            provider = "all"
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(settings.t("当前筛选：\(providerNames[provider] ?? provider)", "Filtered: \(providerNames[provider] ?? provider)"))
                            Image(systemName: "xmark.circle.fill")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
                Spacer()
                Picker(settings.t("占比指标", "Metric"), selection: $shareMetric) {
                    Text(settings.t("Token", "Tokens")).tag("tokens")
                    Text(settings.t("费用", "Cost")).tag("cost")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }
            if shares.isEmpty {
                Text(settings.t("当前时间段暂无记录", "No records in this time range"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            } else {
                HStack(spacing: 28) {
                    shareChart.frame(width: 186, height: 186)
                    VStack(spacing: 8) {
                        ForEach(shares) { value in
                            shareLegend(value)
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.05), lineWidth: 0.8))
    }

    private func hitTestSector(at point: CGPoint, in size: CGSize) -> String? {
        guard !shares.isEmpty else { return nil }
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let maxR = min(size.width, size.height) * 0.5
        let dist = hypot(dx, dy)
        guard dist >= maxR * 0.42 && dist <= maxR * 1.04 else { return nil }

        let chartTotal = shares.reduce(0.0) { $0 + (shareMetric == "tokens" ? $1.tokens : $1.cost) }
        guard chartTotal > 0 else { return nil }

        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let target = (angle / (2 * .pi)) * chartTotal

        var cumulative = 0.0
        for item in shares {
            let val = shareMetric == "tokens" ? item.tokens : item.cost
            cumulative += val
            if target <= cumulative {
                return item.id
            }
        }
        return shares.last?.id
    }

    private var shareChart: some View {
        let hoveredItem = hoveredShareProvider.flatMap { id in shares.first(where: { $0.id == id }) }
        return ZStack {
            Canvas { context, size in
                let chartTotal = shares.reduce(0.0) { $0 + (shareMetric == "tokens" ? $1.tokens : $1.cost) }
                guard chartTotal > 0 else { return }
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                let maxR = min(size.width, size.height) * 0.5
                let outerR = maxR * 0.95
                let innerR = maxR * 0.60
                let multi = shares.count > 1
                var startTheta = 0.0

                for value in shares {
                    let val = shareMetric == "tokens" ? value.tokens : value.cost
                    guard val > 0 else { continue }
                    let sweep = (val / chartTotal) * (2.0 * Double.pi)
                    let gap = multi ? min(0.032, sweep * 0.14) : 0.0
                    let a0 = startTheta + gap * 0.5
                    let a1 = startTheta + sweep - gap * 0.5
                    startTheta += sweep
                    guard a1 > a0 else { continue }

                    let segments = max(14, Int((a1 - a0) * 36))
                    var path = Path()
                    for s in 0...segments {
                        let t = a0 + (a1 - a0) * (Double(s) / Double(segments))
                        let pt = CGPoint(
                            x: center.x + outerR * CGFloat(sin(t)),
                            y: center.y - outerR * CGFloat(cos(t))
                        )
                        if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    for s in (0...segments).reversed() {
                        let t = a0 + (a1 - a0) * (Double(s) / Double(segments))
                        let pt = CGPoint(
                            x: center.x + innerR * CGFloat(sin(t)),
                            y: center.y - innerR * CGFloat(cos(t))
                        )
                        path.addLine(to: pt)
                    }
                    path.closeSubpath()
                    let isHovered = hoveredShareProvider == value.id
                    let alpha = (hoveredShareProvider == nil || isHovered) ? 1.0 : 0.26
                    context.fill(path, with: .color(providerColor(value.id).opacity(alpha)))
                }
            }

            VStack(spacing: 2) {
                if let hoveredItem {
                    let total = denominator
                    let amount = shareMetric == "tokens" ? hoveredItem.tokens : hoveredItem.cost
                    let pct = total > 0 ? max(0, min(100, (amount / total) * 100)) : 0
                    HStack(spacing: 4) {
                        ProviderBadge(id: hoveredItem.id, size: 11)
                        Text(providerNames[hoveredItem.id] ?? hoveredItem.id)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(providerColor(hoveredItem.id))
                            .lineLimit(1)
                    }
                    .frame(height: 14)
                    Text(shareMetric == "cost" ? money(hoveredItem.cost) : shortTokens(hoveredItem.tokens))
                        .font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(height: 20)
                    Text(String(format: "%.1f%% · %@", pct, shareMetric == "cost" ? shortTokens(hoveredItem.tokens) : money(hoveredItem.cost)))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(height: 13)
                } else {
                    Text(settings.t("全部占比", "Total Share"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: 14)
                    Text(shareMetric == "cost" ? money(snapshot.allSharesTotalCost) : shortTokens(snapshot.allSharesTotalTokens))
                        .font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(height: 20)
                    Text(shareMetric == "cost" ? shortTokens(snapshot.allSharesTotalTokens) : money(snapshot.allSharesTotalCost))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(height: 13)
                }
            }
            .frame(width: 106, height: 52)
            .allowsHitTesting(false)

            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if ScrollWheelGate.isScrolling { return }
                        switch phase {
                        case .active(let location):
                            let hit = hitTestSector(at: location, in: geo.size)
                            if hoveredShareProvider != hit {
                                hoveredShareProvider = hit
                            }
                        case .ended:
                            if hoveredShareProvider != nil {
                                hoveredShareProvider = nil
                            }
                        }
                    }
                    .onTapGesture { location in
                        if let hit = hitTestSector(at: location, in: geo.size) {
                            var tx = Transaction(animation: nil)
                            tx.disablesAnimations = true
                            withTransaction(tx) {
                                provider = (provider == hit ? "all" : hit)
                            }
                        }
                    }
            }
        }
    }

    private func shareLegend(_ value: AppShare) -> some View {
        let total = denominator
        let amount = shareMetric == "tokens" ? value.tokens : value.cost
        let ratio = total > 0 ? max(0, min(1, amount / total)) : 0
        let isHovered = hoveredShareProvider == value.id
        let isSelected = provider == value.id
        let color = providerColor(value.id)
        return Button {
            var tx = Transaction(animation: nil)
            tx.disablesAnimations = true
            withTransaction(tx) {
                provider = (provider == value.id ? "all" : value.id)
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ProviderBadge(id: value.id, size: 14)
                    Text(providerNames[value.id] ?? value.id)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    Spacer()
                    Text(shortTokens(value.tokens))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(shareMetric == "tokens" ? .primary : .secondary)
                        .monospacedDigit()
                    if value.cost > 0 {
                        Text("· " + money(value.cost))
                            .font(.system(size: 11))
                            .foregroundStyle(shareMetric == "cost" ? .primary : .secondary)
                            .monospacedDigit()
                    }
                    Text(String(format: "%.1f%%", ratio * 100))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(color)
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
                Canvas { context, size in
                    let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
                    context.fill(track, with: .color(.primary.opacity(0.06)))
                    let fillWidth = max(4, size.width * ratio)
                    let fillRect = CGRect(x: 0, y: 0, width: min(size.width, fillWidth), height: size.height)
                    let fillPath = Path(roundedRect: fillRect, cornerRadius: size.height / 2)
                    context.fill(fillPath, with: .color(color))
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? color.opacity(0.13)
                    : (isHovered ? color.opacity(0.07) : Color.primary.opacity(0.025)),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { inside in
            if ScrollWheelGate.isScrolling { return }
            if inside {
                if hoveredShareProvider != value.id { hoveredShareProvider = value.id }
            } else if hoveredShareProvider == value.id {
                hoveredShareProvider = nil
            }
        }
    }
}

struct UsageDetailSection: View {
    @EnvironmentObject var settings: AppSettings
    let snapshot: AnalysisSnapshot
    @State private var detail = "daily"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(settings.t("用量明细", "Usage Details")).font(.system(size: 14, weight: .semibold))
                Text(detail == "daily"
                     ? settings.t("共 \(snapshot.activeDailyRows.count) 天有记录", "\(snapshot.activeDailyRows.count) active days")
                     : settings.t("共 \(snapshot.modelRows.count) 个模型", "\(snapshot.modelRows.count) models"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker(settings.t("明细类型", "Detail Type"), selection: $detail) {
                    Text(settings.t("每日记录", "Daily Records")).tag("daily")
                    Text(settings.t("模型明细", "By Model")).tag("models")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170)
            }
            if detail == "daily" {
                if snapshot.activeDailyRows.isEmpty {
                    ContentUnavailableView(settings.t("当前时间范围暂无用量记录", "No usage records in range"), systemImage: "calendar.badge.exclamationmark")
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                } else {
                    dailyListView.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if snapshot.modelRows.isEmpty {
                    ContentUnavailableView(settings.t("暂无模型明细", "No model breakdown"), systemImage: "square.stack.3d.up")
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                } else {
                    modelListView
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.05), lineWidth: 0.8))
    }

    private func dateLabel(_ date: Date) -> String {
        settings.monthDayString(date)
    }

    private var dailyListView: some View {
        let maxDayTokens = snapshot.maxDayTokens
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(settings.t("日期", "Date")).frame(width: 70, alignment: .leading)
                Text(settings.t("活跃订阅", "Active Subscriptions")).frame(width: 104, alignment: .leading)
                Text(settings.t("总 Token", "Total Tokens")).frame(maxWidth: .infinity, alignment: .leading)
                Text(settings.t("输入", "Input")).frame(width: 64, alignment: .trailing)
                Text(settings.t("缓存读取", "Cache Read")).frame(width: 70, alignment: .trailing)
                Text(settings.t("输出", "Output")).frame(width: 60, alignment: .trailing)
                Text(settings.t("估算费用", "Est. Cost")).frame(width: 76, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))

            VStack(spacing: 2) {
                ForEach(snapshot.activeDailyRows) { day in
                    let dayProviders = snapshot.dayProvidersByDate[day.date] ?? []
                    let ratio = min(1, max(0.04, day.total / maxDayTokens))
                    HStack(spacing: 8) {
                        Text(dateLabel(day.dateValue))
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .frame(width: 70, alignment: .leading)

                        HStack(spacing: dayProviders.count > 6 ? 2 : 4) {
                            ForEach(dayProviders, id: \.self) { pid in
                                ProviderBadge(id: pid, size: dayProviders.count > 6 ? 11 : 13)
                                    .help(providerNames[pid] ?? pid)
                            }
                        }
                        .frame(width: 104, alignment: .leading)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                Text(shortTokens(day.total))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .frame(width: 62, alignment: .leading)
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.06))
                                        .frame(width: 76, height: 5)
                                    Capsule().fill(Color.accentColor.opacity(0.65))
                                        .frame(width: max(4, 76 * ratio), height: 5)
                                }
                            }
                            Text(shortTokens(day.total))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(day.detailed ? shortTokens(day.input) : "—")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)

                        Text(day.detailed ? shortTokens(day.cached) : "—")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)

                        Text(day.detailed ? shortTokens(day.output) : "—")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)

                        Text(day.knownCost > 0 ? money(day.knownCost) : "—")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(day.knownCost > 0 ? .primary : .secondary)
                            .monospacedDigit()
                            .frame(width: 76, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.015), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.top, 4)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var modelListView: some View {
        let maxModelTokens = snapshot.maxModelTokens
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(settings.t("模型名称", "Model Name")).frame(maxWidth: .infinity, alignment: .leading)
                Text(settings.t("总 Token", "Total Tokens")).frame(width: 140, alignment: .leading)
                Text(settings.t("缓存读取", "Cache Read")).frame(width: 84, alignment: .trailing)
                Text(settings.t("输出", "Output")).frame(width: 76, alignment: .trailing)
                Text(settings.t("请求次数", "Requests")).frame(width: 68, alignment: .trailing)
                Text(settings.t("估算费用", "Est. Cost")).frame(width: 84, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))

            VStack(spacing: 2) {
                ForEach(snapshot.modelRows) { model in
                    let ratio = min(1, max(0.04, model.total / maxModelTokens))
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            ProviderBadge(id: model.provider, size: 13)
                                .help(providerNames[model.provider] ?? model.provider)
                            Text(model.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 8) {
                            Text(shortTokens(model.total))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .frame(width: 58, alignment: .leading)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.06))
                                    .frame(width: 72, height: 5)
                                Capsule().fill(Color.accentColor.opacity(0.65))
                                    .frame(width: max(4, 72 * ratio), height: 5)
                            }
                        }
                        .frame(width: 140, alignment: .leading)

                        Text(shortTokens(model.cached))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 84, alignment: .trailing)

                        Text(shortTokens(model.output))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 76, alignment: .trailing)

                        Text("\(model.requests)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 68, alignment: .trailing)

                        Text(model.pricedCost > 0 ? money(model.pricedCost) : "—")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(model.pricedCost > 0 ? .primary : .secondary)
                            .monospacedDigit()
                            .frame(width: 84, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.015), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.top, 4)
        }
    }
}

struct DailyChartHoverOverlay: View {
    @EnvironmentObject var settings: AppSettings
    let plotInsets: EdgeInsets
    let daily: [ChartDay]
    let dayPartsByDate: [String: [StackedDayItem]]
    let stackedDaily: [StackedDayItem]
    let chartMetric: String
    let hoveredProvider: String?
    let totalTokens: Double
    @State private var hoveredIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let plotFrame = CGRect(
                x: plotInsets.leading,
                y: plotInsets.top,
                width: max(1, geo.size.width - plotInsets.leading - plotInsets.trailing),
                height: max(1, geo.size.height - plotInsets.top - plotInsets.bottom)
            )
            let count = max(1, daily.count)
            let colWidth = plotFrame.width / CGFloat(count)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if ScrollWheelGate.isScrolling { return }
                            guard plotFrame.width > 0, !daily.isEmpty else {
                                if hoveredIndex != nil { hoveredIndex = nil }
                                return
                            }
                            let relX = location.x - plotFrame.origin.x
                            guard relX >= 0, relX <= plotFrame.width,
                                  location.y >= plotFrame.minY, location.y <= plotFrame.maxY + 24 else {
                                if hoveredIndex != nil { hoveredIndex = nil }
                                return
                            }
                            let idx = min(daily.count - 1, max(0, Int((relX / plotFrame.width) * CGFloat(daily.count))))
                            if hoveredIndex != idx {
                                hoveredIndex = idx
                            }
                        case .ended:
                            if hoveredIndex != nil {
                                hoveredIndex = nil
                            }
                        }
                    }

                if let idx = hoveredIndex, idx >= 0, idx < daily.count, plotFrame.width > 0 {
                    let day = daily[idx]
                    let colX = plotFrame.origin.x + CGFloat(idx) * colWidth
                    let centerX = colX + colWidth * 0.5
                    let placeOnLeft = centerX > geo.size.width * 0.56

                    Rectangle()
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: max(2, colWidth - 1), height: plotFrame.height)
                        .offset(x: colX + 0.5, y: plotFrame.origin.y)
                        .allowsHitTesting(false)

                    Path { path in
                        path.move(to: CGPoint(x: centerX, y: plotFrame.minY))
                        path.addLine(to: CGPoint(x: centerX, y: plotFrame.maxY))
                    }
                    .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .allowsHitTesting(false)

                    dayHoverCard(for: day)
                        .frame(width: 215, alignment: .leading)
                        .offset(
                            x: placeOnLeft
                                ? max(44, centerX - 226)
                                : min(max(44, centerX + 12), max(44, geo.size.width - 222)),
                            y: 6
                        )
                        .allowsHitTesting(false)
                } else if let hoveredProvider {
                    HStack {
                        Spacer()
                        providerHoverCard(for: hoveredProvider)
                            .padding(.trailing, 8)
                            .padding(.top, 6)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .onChange(of: daily.count) { hoveredIndex = nil }
    }

    private func dayLabel(_ date: Date) -> String {
        settings.monthDayString(date)
    }

    private func dayHoverCard(for day: ChartDay) -> some View {
        let rawParts = dayPartsByDate[day.date] ?? []
        let parts = chartMetric == "tokens" ? rawParts : rawParts.sorted { $0.cost > $1.cost }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dayLabel(day.dateValue))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if day.hasRecords && (day.total > 0 || day.knownCost > 0) {
                    Text(shortTokens(day.total) + " · " + money(day.knownCost))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                } else {
                    Text(settings.t("无记录", "No records"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            if !parts.isEmpty {
                Divider()
                ForEach(parts) { item in
                    HStack(spacing: 6) {
                        ProviderBadge(id: item.provider, size: 11)
                        Text(providerNames[item.provider] ?? item.provider)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(chartMetric == "tokens" ? shortTokens(item.tokens) : money(item.cost))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private func providerHoverCard(for id: String) -> some View {
        let providerItems = stackedDaily.filter { $0.provider == id }
        let pTokens = providerItems.reduce(0) { $0 + $1.tokens }
        let pCost = providerItems.reduce(0) { $0 + $1.cost }
        let activeDays = providerItems.filter { $0.tokens > 0 || $0.cost > 0 }.count
        let sharePct = totalTokens > 0 ? (pTokens / totalTokens * 100) : 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ProviderBadge(id: id, size: 13)
                Text(providerNames[id] ?? id)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                Text(String(format: "%.1f%%", sharePct))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(providerColor(id))
                    .monospacedDigit()
            }
            Text(settings.t("累计 ", "Total ") + shortTokens(pTokens) + " · " + money(pCost))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
            Text(settings.t("活跃 \(activeDays) 天 · 点击可单独筛选", "\(activeDays) active days · Click to filter"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 195, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(providerColor(id).opacity(0.3), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

struct QuotaView: View {
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var settings: AppSettings
    private var activeProviders: [ProviderUsage] {
        usage.providers.filter { settings.shownProviders.contains($0.id) }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = usage.error {
                    Text(error.message(isEnglish: settings.isEnglish)).font(.caption).foregroundStyle(.orange)
                }
                overviewStrip
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(activeProviders) { provider in
                        providerCard(provider)
                    }
                }
            }
            .frame(width: max(0, geometry.size.width - 48), alignment: .topLeading)
            .padding(24)
            .background(OverlayScrollerBridge())
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var overviewStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ForEach(activeProviders) { provider in singleOverviewTile(provider) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(activeProviders) { provider in singleOverviewTile(provider) }
            }
        }
    }

    private func singleOverviewTile(_ provider: ProviderUsage) -> some View {
        let primary = provider.primary()
        let pct = primary?.remaining.map { QuotaWindows.displayedPercent($0) }
        let ratio = max(0, min(1, primary?.remaining ?? 0))
        return VStack(alignment: .leading, spacing: 8) {
            overviewHeader(provider)
            Text(primary?.remaining.map { QuotaWindows.percentageText($0) } ?? "—")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor(pct))
                .monospacedDigit()
                .lineLimit(1)
            Text(primary.map { settings.localizedMetricName($0) } ?? settings.t("无额度", "No Quota"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 26, alignment: .topLeading)
            quotaBar(ratio: ratio, tint: providerColor(provider.id))
        }
        .padding(14)
        .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func overviewHeader(_ provider: ProviderUsage) -> some View {
        HStack(spacing: 6) {
            ProviderBadge(id: provider.id, size: 14)
            Text(provider.name).font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if let plan = provider.plan, !plan.isEmpty {
                Text(plan)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func quotaBar(ratio: Double, tint: Color) -> some View {
        Canvas { context, size in
            let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            context.fill(track, with: .color(.primary.opacity(0.08)))
            let fillWidth = max(0, min(size.width, size.width * ratio))
            if fillWidth > 0 {
                let fillPath = Path(roundedRect: CGRect(x: 0, y: 0, width: fillWidth, height: size.height), cornerRadius: size.height / 2)
                context.fill(fillPath, with: .color(tint))
            }
        }.frame(height: 5)
    }

    private func providerCard(_ provider: ProviderUsage) -> some View {
        let metrics = provider.cardMetrics
        let headline = provider.primary()
        let primaryPct = headline?.remaining.map { QuotaWindows.displayedPercent($0) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                ProviderBadge(id: provider.id, size: 18)
                Text(provider.name).font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                if let plan = provider.plan, !plan.isEmpty {
                    Text(plan)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                Spacer()
                if provider.stale {
                    Label(settings.t("缓存", "Cached"), systemImage: "clock").font(.caption2).foregroundStyle(.orange)
                } else {
                    statusBadge(primaryPct)
                }
            }
            Divider()
            if metrics.isEmpty {
                Text(settings.t("未提供剩余额度", "No quota info available"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 68, alignment: .center)
            } else {
                VStack(spacing: 14) {
                    ForEach(metrics) { metric in
                        metricRow(metric, color: providerColor(provider.id))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metricRow(_ metric: Metric, color: Color, title: String? = nil) -> some View {
        let ratio = max(0, min(1, metric.remaining ?? 0))
        let remPct = QuotaWindows.displayedPercent(ratio)
        let usedPct = QuotaWindows.percentageText(1 - ratio)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title ?? settings.localizedMetricName(metric))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text(settings.t("剩余 \(QuotaWindows.percentageText(ratio))", "\(QuotaWindows.percentageText(ratio)) left"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor(remPct))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Canvas { context, size in
                let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
                context.fill(track, with: .color(.primary.opacity(0.08)))
                let fillWidth = max(0, min(size.width, size.width * ratio))
                if fillWidth > 0 {
                    let fillPath = Path(roundedRect: CGRect(x: 0, y: 0, width: fillWidth, height: size.height), cornerRadius: size.height / 2)
                    context.fill(fillPath, with: .color(color))
                }
            }.frame(height: 8)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let reset = metric.reset {
                    Label(settings.resetText(reset), systemImage: "clock")
                        .font(.system(size: 10))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(settings.t("已用 \(usedPct)", "\(usedPct) used"))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func statusBadge(_ pct: Int?) -> some View {
        if let pct {
            let text = pct == 0 ? settings.t("已用尽", "Depleted") : (pct <= 20 ? settings.t("额度偏紧", "Low Quota") : settings.t("充足", "Ample"))
            let tint: Color = pct == 0 ? .red : (pct <= 20 ? .orange : .green)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(tint.opacity(0.12), in: Capsule())
        }
    }

    private func statusColor(_ pct: Int?) -> Color {
        guard let pct else { return .secondary }
        if pct == 0 { return .red }
        if pct <= 20 { return .orange }
        return .primary
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var usage: UsageStore
    @State private var login = false
    @State private var requiresApproval = false
    @State private var isSyncingLogin = false
    @State private var loginError: UsageDiagnostic?

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        isSyncingLogin = true
        login = (status == .enabled)
        requiresApproval = (status == .requiresApproval)
        isSyncingLogin = false
    }

    var body: some View {
        Form {
            Section(settings.t("语言", "Language")) {
                Picker(settings.t("界面语言", "Interface Language"), selection: $settings.language) {
                    Text(settings.t("跟随系统", "System Default")).tag("system")
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }
            }
            Section(settings.t("菜单栏", "Menu Bar")) {
                Picker(settings.t("显示方式", "Display Style"), selection: $settings.menuStyle) {
                    Text(settings.t("订阅图标与剩余额度", "Icons & Remaining Quota")).tag("icons")
                    Text(settings.t("订阅图标、名称与剩余额度", "Icons, Names & Remaining Quota")).tag("icon_names")
                    Text(settings.t("简洁名称与剩余额度", "Compact Name & Remaining Quota")).tag("compact")
                    Text(settings.t("完整名称与剩余额度", "Full Name & Remaining Quota")).tag("names")
                    Text(settings.t("仅应用图标", "App Icon Only")).tag("icon")
                }
                ForEach(quotaOrder, id: \.self) { id in
                    Toggle(isOn: Binding(get: { settings.shownProviders.contains(id) }, set: { value in
                        if value { settings.shownProviders.insert(id) } else { settings.shownProviders.remove(id) }
                    })) {
                        HStack(spacing: 8) {
                            ProviderBadge(id: id, size: 14)
                            Text(providerNames[id] ?? id)
                        }
                    }
                }
                Button(settings.t("恢复菜单栏位置", "Reset Menu Bar Position")) {
                    NotificationCenter.default.post(name: .restoreAicostMenu, object: nil)
                }
                Text(settings.t("状态栏在周额度、月额度未用完时显示 5 小时剩余；没有 5 小时窗口时显示月额度。周额度或月额度用完后，状态栏显示 0%，不再显示 5 小时额度。点击状态栏后，Antigravity 显示 Gemini·5h内额度与每周。", "While the weekly and monthly allowances remain, the menu bar shows the 5-hour balance, or the monthly balance when there is no 5-hour window. Once either allowance is used up, the menu bar shows 0% and hides the 5-hour balance. The Antigravity row in the menu summary shows Gemini·5h and Weekly."))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Section(settings.t("其他订阅 / 应用（可选）", "Other Subscriptions / Apps (Optional)")) {
                ForEach(usage.providers.filter { !quotaOrder.contains($0.id) }) { provider in
                    Toggle(isOn: Binding(get: { settings.shownProviders.contains(provider.id) }, set: { value in
                        if value { settings.shownProviders.insert(provider.id) } else { settings.shownProviders.remove(provider.id) }
                    })) {
                        HStack(spacing: 8) {
                            ProviderBadge(id: provider.id, size: 14)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(provider.name + (provider.plan.map { " · " + $0 } ?? ""))
                                Text(provider.metrics.isEmpty
                                     ? settings.t("仅使用记录，来源未提供余额", "Usage records only, balance unavailable")
                                     : settings.t("可显示订阅剩余额度", "Remaining quota available"))
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }.accessibilityLabel(provider.name + (provider.plan.map { " · " + $0 } ?? ""))
                }
            }
            Section(settings.t("用量查询与更新", "Usage & Refresh")) {
                Picker(settings.t("默认查询范围", "Default Range"), selection: $settings.defaultRange) {
                    Text(settings.t("本月", "This Month")).tag(0)
                    Text(settings.t("今天", "Today")).tag(1)
                    Text(settings.t("近一周（7 天）", "Past 7 Days")).tag(7)
                    Text(settings.t("近一月（30 天）", "Past 30 Days")).tag(30)
                }
                Picker(settings.t("自动刷新", "Auto Refresh"), selection: $settings.refreshInterval) {
                    Text(settings.t("每 30 秒", "Every 30s")).tag(30.0)
                    Text(settings.t("每 1 分钟", "Every 1 min")).tag(60.0)
                    Text(settings.t("每 5 分钟", "Every 5 mins")).tag(300.0)
                    Text(settings.t("每 15 分钟", "Every 15 mins")).tag(900.0)
                }
                HStack {
                    Text(settings.t("数据来源", "Data Source")); Spacer()
                    Label(usage.apiConnected ? settings.t("OpenUsage 已连接", "OpenUsage Connected") : settings.t("本机日志 / 历史缓存", "Local Logs / Cache"),
                          systemImage: usage.apiConnected ? "checkmark.circle.fill" : "internaldrive")
                        .foregroundStyle(usage.apiConnected ? Color.green : Color.secondary)
                }
                HStack {
                    Text("Claude Code"); Spacer()
                    Text(usage.history.sources["claude"] == nil
                         ? settings.t("未发现用量记录", "No records found")
                         : settings.t("已读取本机日志", "Local logs detected"))
                        .foregroundStyle(.secondary)
                }
                Button(usage.isRefreshing ? settings.t("正在扫描…", "Scanning…") : settings.t("立即刷新并重新扫描", "Refresh & Rescan Now")) {
                    Task { await usage.refresh(force: true) }
                }.disabled(usage.isRefreshing)
            }
            Section(settings.t("启动与历史", "Startup & History")) {
                Toggle(settings.t("登录后启动 Aicost", "Launch Aicost at Login"), isOn: $login)
                    .onChange(of: login) { _, value in
                        guard !isSyncingLogin else { return }
                        do {
                            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                            refreshLoginStatus()
                        } catch {
                            loginError = .loginUpdateFailed
                            refreshLoginStatus()
                        }
                    }
                if let loginError { Text(loginError.message(isEnglish: settings.isEnglish)).font(.caption).foregroundStyle(.orange) }
                if requiresApproval {
                    Button(settings.t("在系统设置中启用登录项", "Enable in System Settings")) { SMAppService.openSystemSettingsLoginItems() }
                }
                Button(settings.t("打开用量历史目录", "Open History Directory")) {
                    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
                    let folder = HistoryAnalyzer.storageFolder(support: support)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
                Text(settings.t("仅保存用量数值、日期和模型；不保存会话正文。关闭应用窗口后，菜单栏继续运行。", "Only saves token counts, dates and models; never logs conversation text. Closes to menu bar."))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Section(settings.t("开源与致谢", "Open Source & Credits")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        AicostBrandIcon(size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Aicost")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                Text("v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(settings.t("MIT 开源", "MIT Open Source"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                            Text(settings.t("macOS 原生 AI 订阅额度与本机 Token 费用分析工具", "Native macOS AI subscription quota & token cost analyzer"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Text(settings.t("Aicost 基于 MIT 开源协议发布，所有订阅配额读取与 Token 用量统计均 100% 在本机完成，仅记录日期、模型与 Token 统计值，绝不采集或上传任何对话正文与私钥。", "Aicost is released under the MIT License. All subscription quota checks and token usage metrics are computed 100% locally on your device. Only dates, models and counts are logged; conversation contents and secret keys are never uploaded or collected."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.t("致谢开源项目与贡献者", "Credits & Acknowledgments"))
                            .font(.system(size: 11.5, weight: .semibold))
                        acknowledgmentRow(title: "Robin Ebers", detail: settings.t("上游订阅配额采集核心与多平台账单协议支持（MIT License）", "Upstream quota collection core & multi-provider protocol support (MIT License)"))
                        acknowledgmentRow(title: "OpenUsage · LiteLLM · models.dev", detail: settings.t("本机会话增量扫描缓存与开源 AI 模型实时定价目录", "Local session incremental cache & model pricing catalog"))
                        acknowledgmentRow(title: "Cursor · Codex · Claude Code · Grok · Antigravity", detail: settings.t("各 AI 编程工具的本机日志与订阅配额接口支持", "Local logs & subscription quota integrations for AI tools"))
                        acknowledgmentRow(title: "Apple SwiftUI & Swift Charts", detail: settings.t("macOS 原生状态栏、图表渲染与交互组件", "Native macOS status bar, charts rendering & UI components"))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { refreshLoginStatus() }
    }

    private func acknowledgmentRow(title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(Color.accentColor.opacity(0.75)).frame(width: 5, height: 5)
            Text(title).font(.system(size: 11, weight: .medium))
            Text("—").font(.system(size: 11)).foregroundStyle(.tertiary)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
