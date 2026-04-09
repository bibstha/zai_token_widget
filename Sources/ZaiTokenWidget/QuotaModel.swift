import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class QuotaModel: ObservableObject {
    /// Seconds between automatic quota fetches (also shown in the menu).
    static let autoRefreshIntervalSeconds: TimeInterval = 300

    /// Menu bar label, e.g. "Z.ai 96%"
    @Published private(set) var barTitle: String = "Z.ai"
    @Published private(set) var barTooltip: String = "Z.AI token quota"
    /// Lines shown at the top of the menu (numbers / windows).
    @Published private(set) var quotaMenuLines: [String] = ["Open Preferences to set your API key."]
    /// Countdown until the next automatic fetch, e.g. "Auto refresh in 4:32 (272s)".
    @Published private(set) var autoRefreshLabel: String = ""

    private let client = QuotaClient()
    private var cancellables = Set<AnyCancellable>()
    private var nextAutoRefreshAt = Date().addingTimeInterval(300)
    private var isRefreshing = false

    init() {
        NSApp.setActivationPolicy(.accessory)

        if isatty(STDIN_FILENO) != 0 {
            let cwd = FileManager.default.currentDirectoryPath
            fputs(
                "\nZaiTokenWidget: started from Terminal — do not Ctrl+C if you want the menu item to stay. "
                    + "Prefer: open \"\(cwd)/ZaiTokenWidget.app\"\n\n",
                stderr
            )
        }

        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
            .store(in: &cancellables)

        updateAutoRefreshLabel()
        Task { await refresh() }
    }

    private func tick() {
        updateAutoRefreshLabel()
        guard !isRefreshing, Date() >= nextAutoRefreshAt else { return }
        Task { await refresh() }
    }

    private func updateAutoRefreshLabel() {
        let totalSec = max(0, Int(nextAutoRefreshAt.timeIntervalSinceNow.rounded(.down)))
        let m = totalSec / 60
        let s = totalSec % 60
        autoRefreshLabel = "Auto refresh in \(m):\(String(format: "%02d", s)) (\(totalSec)s)"
    }

    private func scheduleNextAutoRefresh() {
        nextAutoRefreshAt = Date().addingTimeInterval(QuotaModel.autoRefreshIntervalSeconds)
        updateAutoRefreshLabel()
    }

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            scheduleNextAutoRefresh()
        }

        let key = resolvedAPIKey()
        guard let key, !key.isEmpty else {
            barTitle = "Z.ai —"
            barTooltip = "Set your API key in Preferences (or ZAI_API_KEY / GLM_API_KEY)."
            quotaMenuLines = ["No API key — open Preferences…"]
            return
        }

        barTitle = "Z.ai …"
        barTooltip = "Loading…"
        quotaMenuLines = ["Loading quota…"]

        do {
            let summary = try await client.fetchQuota(apiKey: key)
            guard let primary = summary.primary else {
                barTitle = "Z.ai ?"
                barTooltip = "No token quota in response."
                quotaMenuLines = ["No TOKENS_LIMIT in API response."]
                return
            }

            barTitle = "Z.ai \(primary.remainingPercent)%"
            barTooltip = tooltip(for: summary)
            quotaMenuLines = menuLines(from: summary)
        } catch {
            barTitle = "Z.ai !"
            barTooltip = error.localizedDescription
            quotaMenuLines = ["Error: \(error.localizedDescription)"]
        }
    }

    private func menuLines(from summary: QuotaSummary) -> [String] {
        var lines: [String] = []
        if let w = summary.weekly {
            lines.append(
                "7-day: \(w.remainingPercent)% left · \(formatTokens(w.remaining)) tokens remaining "
                    + "(used \(w.usedPercent)% of \(formatTokens(w.usageTotal)) cap)"
            )
        }
        if let s = summary.session {
            lines.append(
                "5-hour: \(s.remainingPercent)% left · \(formatTokens(s.remaining)) tokens remaining "
                    + "(used \(s.usedPercent)% of \(formatTokens(s.usageTotal)) cap)"
            )
        }
        if lines.isEmpty {
            lines.append("No token windows returned.")
        }
        return lines
    }

    func preferencesDidSave() {
        Task { await refresh() }
    }

    private func tooltip(for summary: QuotaSummary) -> String {
        var lines: [String] = []
        if let s = summary.session {
            lines.append(sessionLine(label: "5h window", window: s))
        }
        if let w = summary.weekly {
            lines.append(sessionLine(label: "7-day window", window: w))
        }
        return lines.joined(separator: "\n")
    }

    private func sessionLine(label: String, window: TokenWindow) -> String {
        let rem = formatTokens(window.remaining)
        let next = formatReset(window.nextResetMs)
        return "\(label): \(window.remainingPercent)% tokens left (~\(rem) remaining)\(next)"
    }

    private func formatReset(_ ms: Int64?) -> String {
        guard let ms else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return " · next reset \(f.string(from: date))"
    }

    private func formatTokens(_ n: Int64) -> String {
        let d = Double(n)
        if n >= 1_000_000_000 {
            return String(format: "%.2fB", d / 1_000_000_000)
        }
        if n >= 1_000_000 {
            return String(format: "%.1fM", d / 1_000_000)
        }
        if n >= 1_000 {
            return String(format: "%.1fK", d / 1_000)
        }
        return "\(n)"
    }

    private func resolvedAPIKey() -> String? {
        if let k = KeychainStore.load(), !k.isEmpty { return k }
        if let env = ProcessInfo.processInfo.environment["ZAI_API_KEY"], !env.isEmpty { return env }
        if let env = ProcessInfo.processInfo.environment["GLM_API_KEY"], !env.isEmpty { return env }
        return nil
    }
}
