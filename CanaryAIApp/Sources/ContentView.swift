import SwiftUI

struct ContentView: View {
    @Environment(ScannerService.self) private var scanner
    @State private var selectedSession: String?
    @State private var selectedTool: String?

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            SummaryBadgesView()
            StatsRow()
            Divider()
            FilterBar(selectedSession: $selectedSession, selectedTool: $selectedTool)
            AlertListView(selectedSession: selectedSession, selectedTool: selectedTool)
            Divider()
            ActionBarView()
        }
        .frame(width: 380)
        .frame(minHeight: 200, maxHeight: 600)
    }
}

// MARK: - Header

private struct HeaderView: View {
    @Environment(ScannerService.self) private var scanner

    var body: some View {
        HStack {
            Image(systemName: "bird.fill")
                .font(.title2)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("CanaryAI")
                    .font(.headline)
                if let date = scanner.lastScanDate {
                    Text("Last scan: \(date, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                SettingsWindowController.shared.open(scanner: scanner)
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Summary Badges

private struct SummaryBadgesView: View {
    @Environment(ScannerService.self) private var scanner

    var body: some View {
        let summary = scanner.summaryByLevel
        if !summary.isEmpty {
            HStack(spacing: 6) {
                ForEach(summary, id: \.0) { level, count in
                    HStack(spacing: 3) {
                        Image(systemName: level.systemImage)
                            .font(.caption2)
                        Text("\(count) \(level.label)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(level.color.opacity(0.2), in: Capsule())
                    .foregroundStyle(level.color)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Stats Row

private struct StatsRow: View {
    @Environment(ScannerService.self) private var scanner

    var body: some View {
        if let output = scanner.output {
            HStack {
                Label("\(output.sessionsScanned) sessions", systemImage: "doc.text")
                Spacer()
                Label("\(output.toolCallsScanned) tool calls", systemImage: "wrench")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Filter Bar

private struct FilterBar: View {
    @Environment(ScannerService.self) private var scanner
    @Binding var selectedSession: String?
    @Binding var selectedTool: String?

    private var uniqueSessions: [String] {
        let ids = scanner.filteredAlerts.map(\.sessionId)
        return Array(Set(ids)).sorted()
    }

    private var uniqueTools: [String] {
        let names = scanner.filteredAlerts.map(\.toolName)
        return Array(Set(names)).sorted()
    }

    var body: some View {
        let sessions = uniqueSessions
        let tools = uniqueTools
        if !sessions.isEmpty || !tools.isEmpty {
            HStack(spacing: 6) {
                Picker(selection: $selectedSession) {
                    Text("All Sessions").tag(String?.none)
                    Divider()
                    ForEach(sessions, id: \.self) { session in
                        Text(String(session.prefix(12)) + "...")
                            .tag(Optional(session))
                    }
                } label: {
                    Label("Session", systemImage: "doc.text")
                        .font(.caption)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                Picker(selection: $selectedTool) {
                    Text("All Tools").tag(String?.none)
                    Divider()
                    ForEach(tools, id: \.self) { tool in
                        Text(tool).tag(Optional(tool))
                    }
                } label: {
                    Label("Tool", systemImage: "wrench")
                        .font(.caption)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                if selectedSession != nil || selectedTool != nil {
                    Button {
                        selectedSession = nil
                        selectedTool = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear filters")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Alert List

private struct AlertListView: View {
    @Environment(ScannerService.self) private var scanner
    let selectedSession: String?
    let selectedTool: String?

    private var displayedAlerts: [AlertItem] {
        var alerts = scanner.filteredAlerts
        if let session = selectedSession {
            alerts = alerts.filter { $0.sessionId == session }
        }
        if let tool = selectedTool {
            alerts = alerts.filter { $0.toolName == tool }
        }
        return alerts
    }

    var body: some View {
        let alerts = displayedAlerts
        if scanner.output != nil && scanner.filteredAlerts.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("No suspicious activity detected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding()
        } else if !alerts.isEmpty {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(alerts) { alert in
                        AlertRow(alert: alert)
                    }
                }
                .padding(.vertical, 4)
            }
        } else if scanner.output != nil && !scanner.filteredAlerts.isEmpty {
            // Filters active but no match
            VStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No alerts match the selected filters")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding()
        } else if scanner.resolvedBinaryPath == nil {
            NotConfiguredView()
        } else if scanner.errorMessage != nil {
            VStack(spacing: 8) {
                Image(systemName: "shield.slash.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text(scanner.errorMessage ?? "Unknown error")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "shield")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Click \"Scan Now\" to start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding()
        }
    }
}

// MARK: - Not Configured

private struct NotConfiguredView: View {
    @Environment(ScannerService.self) private var scanner

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "shield.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("canaryai not found")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("Install canaryai, then set the path in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Open Settings") {
                    SettingsWindowController.shared.open(scanner: scanner)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Install Instructions") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/jx887/canaryai")!)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
    }
}

// MARK: - Action Bar

private struct ActionBarView: View {
    @Environment(ScannerService.self) private var scanner

    var body: some View {
        VStack(spacing: 4) {
            if scanner.dismissedCount > 0 {
                HStack(spacing: 6) {
                    Button {
                        scanner.showDismissed.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: scanner.showDismissed ? "eye.slash" : "eye")
                            Text("\(scanner.dismissedCount) dismissed")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)

                    if scanner.showDismissed {
                        Button("Clear All") {
                            scanner.clearAllDismissed()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }

            HStack {
                if scanner.isScanning {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if scanner.output != nil && !scanner.filteredAlerts.isEmpty {
                    Button {
                        scanner.resolveAllAlerts()
                    } label: {
                        Label("Resolve All", systemImage: "checkmark.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button("Scan Now") {
                    Task { await scanner.scan() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(scanner.isScanning)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
