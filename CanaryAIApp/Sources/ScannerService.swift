import Foundation
import UserNotifications
import SwiftUI

@MainActor
@Observable
final class ScannerService {
    var output: ScanOutput?
    var lastScanDate: Date?
    var isScanning: Bool = false
    var errorMessage: String?
    var settings: AppSettings = AppSettings()
    var ruleStats: RuleStats?

    private var seenAlertIDs: Set<String> = []
    var dismissedAlertIDs: Set<String> = []
    var showDismissed: Bool = false
    private var periodicTask: Task<Void, Never>?
    private var updateCheckTask: Task<Void, Never>?

    // Cached so the UI never blocks on a shell spawn during re-renders
    private(set) var resolvedBinaryPath: String?

    // Non-nil when brew has a newer version available
    var updateAvailable: String?

    var menuBarState: MenuBarState {
        if isScanning { return .scanning }
        if let error = errorMessage { return .error(error) }
        guard resolvedBinaryPath != nil else { return .notConfigured }
        guard output != nil else { return .clean }
        let filtered = filteredAlerts
        if filtered.isEmpty { return .clean }
        let maxSeverity = filtered.map(\.severityLevel).max() ?? .low
        return .alerts(maxSeverity)
    }

    var filteredAlerts: [AlertItem] {
        guard let output else { return [] }
        return output.alerts.filter { alert in
            alert.severityLevel >= settings.minSeverity &&
            (showDismissed || !dismissedAlertIDs.contains(alert.id))
        }
    }

    var dismissedCount: Int {
        guard let output else { return 0 }
        return output.alerts.filter { dismissedAlertIDs.contains($0.id) }.count
    }

    func dismissAlert(_ alert: AlertItem) {
        dismissedAlertIDs.insert(alert.id)
        saveDismissedAlertIDs()
    }

    func restoreAlert(_ alert: AlertItem) {
        dismissedAlertIDs.remove(alert.id)
        saveDismissedAlertIDs()
    }

    func clearAllDismissed() {
        dismissedAlertIDs.removeAll()
        saveDismissedAlertIDs()
    }

    func resolveAllAlerts() {
        guard let output else { return }
        for alert in output.alerts {
            dismissedAlertIDs.insert(alert.id)
        }
        saveDismissedAlertIDs()
    }

    var summaryByLevel: [(SeverityLevel, Int)] {
        SeverityLevel.allCases.reversed().compactMap { level in
            let count = filteredAlerts.filter { $0.severityLevel == level }.count
            return count > 0 ? (level, count) : nil
        }
    }

    // Resolves once in the background; call refreshBinaryPath() when settings change
    func refreshBinaryPath() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let path = await self.findBinaryPath()
            await MainActor.run { self.resolvedBinaryPath = path }
        }
    }

    private func findBinaryPath() async -> String? {
        // 1. User-configured path
        let configured = await MainActor.run { settings.customBinaryPath }
        if !configured.isEmpty {
            let path = (configured as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // 2. Bundled binary inside .app (self-contained DMG install)
        if let resourcePath = Bundle.main.resourcePath {
            let bundledPath = resourcePath + "/canaryai"
            if FileManager.default.isExecutableFile(atPath: bundledPath) {
                return bundledPath
            }
        }
        // 3. Shell PATH lookup (covers pip, pipx, brew, etc.)
        if let shellPath = try? runShellWhich() {
            return shellPath
        }
        // 4. Local dev fallback (debug builds only — stripped from release/brew builds)
        #if DEBUG
        let devPath = NSHomeDirectory() + "/Developer/AI-Agent-Check/canaryai/.venv/bin/canaryai"
        if FileManager.default.isExecutableFile(atPath: devPath) {
            return devPath
        }
        #endif
        return nil
    }

    init() {
        loadSettings()
        loadSeenAlertIDs()
        loadDismissedAlertIDs()
        requestNotificationPermission()
        startPeriodicScan()
        startUpdateCheckTimer()
        Task {
            let path = await findBinaryPath()
            resolvedBinaryPath = path
            await scan()
            await loadRuleStats()
        }
        checkForUpdates()
    }

    func loadRuleStats() async {
        guard let binaryPath = resolvedBinaryPath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["rules", "list", "--json"]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = NSHomeDirectory()
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let stats = try JSONDecoder().decode(RuleStats.self, from: data)
            ruleStats = stats
        } catch {}
    }

    // MARK: - Scan

    func scan() async {
        guard let binaryPath = resolvedBinaryPath else {
            errorMessage = "canaryai binary not found"
            return
        }

        isScanning = true
        errorMessage = nil

        do {
            let result = try await runScan(binaryPath: binaryPath)
            output = result
            lastScanDate = Date()
            errorMessage = nil
            await fireNotificationsIfNeeded(for: result)
        } catch {
            errorMessage = error.localizedDescription
        }

        isScanning = false
    }

    private func runScan(binaryPath: String) async throws -> ScanOutput {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)

            var arguments = ["scan", "--json"]
            if let since = settings.sinceArgument {
                arguments += ["--since", since]
            }
            process.arguments = arguments

            var environment = ProcessInfo.processInfo.environment
            environment["HOME"] = NSHomeDirectory()
            process.environment = environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { _ in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let exitCode = process.terminationStatus

                // Exit code 0 = clean, 1 = alerts found — both are valid
                guard exitCode == 0 || exitCode == 1 else {
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: ScanError.processError(exitCode, errStr))
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    let scanOutput = try decoder.decode(ScanOutput.self, from: data)
                    continuation.resume(returning: scanOutput)
                } catch {
                    continuation.resume(throwing: ScanError.parseError(error.localizedDescription))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Periodic Scan

    func startPeriodicScan() {
        periodicTask?.cancel()
        guard settings.scanInterval > 0 else { return }

        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.settings.scanInterval ?? 300))
                guard !Task.isCancelled else { break }
                await self?.scan()
            }
        }
    }

    func startUpdateCheckTimer() {
        updateCheckTask?.cancel()
        updateCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1800)) // 30 minutes
                guard !Task.isCancelled else { break }
                await MainActor.run { self?.checkForUpdates() }
            }
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    private func fireNotificationsIfNeeded(for result: ScanOutput) async {
        let notifiable = result.alerts.filter { alert in
            let level = alert.severityLevel
            let shouldNotify = (level == .critical && settings.notifyOnCritical) ||
                               (level == .high && settings.notifyOnHigh)
            return shouldNotify && !seenAlertIDs.contains(alert.id)
        }

        guard !notifiable.isEmpty else { return }

        // Mark as seen
        for alert in notifiable {
            seenAlertIDs.insert(alert.id)
        }
        saveSeenAlertIDs()

        let content = UNMutableNotificationContent()
        content.sound = .default

        if notifiable.count == 1, let alert = notifiable.first {
            content.title = "[\(alert.severity)] \(alert.ruleName)"
            content.body = alert.message
        } else {
            let critCount = notifiable.filter { $0.severityLevel == .critical }.count
            let highCount = notifiable.filter { $0.severityLevel == .high }.count
            var parts: [String] = []
            if critCount > 0 { parts.append("\(critCount) CRITICAL") }
            if highCount > 0 { parts.append("\(highCount) HIGH") }
            content.title = "canaryai: \(parts.joined(separator: ", ")) alerts detected"
            content.body = notifiable.first?.message ?? ""
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Settings Persistence

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(settings.customBinaryPath, forKey: "customBinaryPath")
        defaults.set(settings.scanInterval, forKey: "scanInterval")
        defaults.set(settings.minSeverity.rawValue, forKey: "minSeverity")
        defaults.set(settings.scanAll, forKey: "scanAll")
        defaults.set(settings.notifyOnCritical, forKey: "notifyOnCritical")
        defaults.set(settings.notifyOnHigh, forKey: "notifyOnHigh")
        defaults.set(settings.showInDock, forKey: "showInDock")
        applyDockPolicy()
        refreshBinaryPath()
        startPeriodicScan()
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "customBinaryPath") {
            settings.customBinaryPath = path
        }
        let interval = defaults.double(forKey: "scanInterval")
        settings.scanInterval = interval > 0 ? interval : 300
        if let sev = defaults.string(forKey: "minSeverity"),
           let level = SeverityLevel(rawValue: sev) {
            settings.minSeverity = level
        }
        if defaults.object(forKey: "scanAll") != nil {
            settings.scanAll = defaults.bool(forKey: "scanAll")
        }
        if defaults.object(forKey: "notifyOnCritical") != nil {
            settings.notifyOnCritical = defaults.bool(forKey: "notifyOnCritical")
        } else {
            settings.notifyOnCritical = true
        }
        if defaults.object(forKey: "notifyOnHigh") != nil {
            settings.notifyOnHigh = defaults.bool(forKey: "notifyOnHigh")
        } else {
            settings.notifyOnHigh = true
        }
        if defaults.object(forKey: "showInDock") != nil {
            settings.showInDock = defaults.bool(forKey: "showInDock")
        } else {
            settings.showInDock = true
        }
        applyDockPolicy()
    }

    func applyDockPolicy() {
        NSApplication.shared.setActivationPolicy(settings.showInDock ? .regular : .accessory)
    }

    private func loadSeenAlertIDs() {
        if let arr = UserDefaults.standard.stringArray(forKey: "seenAlertIDs") {
            seenAlertIDs = Set(arr)
        }
    }

    private func saveSeenAlertIDs() {
        UserDefaults.standard.set(Array(seenAlertIDs), forKey: "seenAlertIDs")
    }

    private func loadDismissedAlertIDs() {
        if let arr = UserDefaults.standard.stringArray(forKey: "dismissedAlertIDs") {
            dismissedAlertIDs = Set(arr)
        }
    }

    private func saveDismissedAlertIDs() {
        UserDefaults.standard.set(Array(dismissedAlertIDs), forKey: "dismissedAlertIDs")
    }

    // MARK: - Update Check

    func checkForUpdates() {
        Task.detached(priority: .background) { [weak self] in
            guard let url = URL(string: "https://api.github.com/repos/jx887/homebrew-canaryai/releases/latest") else { return }
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            guard !currentVersion.isEmpty else { return }

            let detectedVersion: String?
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = json["tag_name"] as? String {
                let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                detectedVersion = latestVersion != currentVersion ? latestVersion : nil
            } else {
                detectedVersion = nil
            }

            guard let self else { return }
            await MainActor.run { self.updateAvailable = detectedVersion }
        }
    }

    // MARK: - Helpers

    // Runs `which canaryai` through the user's login shell so it picks up
    // PATH from .zshrc / .bash_profile / etc. — Finder-launched apps
    // don't inherit the terminal's PATH.
    private nonisolated func runShellWhich() throws -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "which canaryai"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }
}

enum ScanError: LocalizedError {
    case processError(Int32, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .processError(let code, let msg):
            "Process exited with code \(code): \(msg)"
        case .parseError(let msg):
            "Failed to parse output: \(msg)"
        }
    }
}
