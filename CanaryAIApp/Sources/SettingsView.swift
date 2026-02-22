import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(ScannerService.self) private var scanner

    var body: some View {
        @Bindable var scanner = scanner

        VStack(alignment: .leading, spacing: 0) {
            // Binary Path
            SettingsRow(label: "CanaryAI Binary") {
                HStack(spacing: 6) {
                    if let path = scanner.resolvedBinaryPath {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("Not found — set a custom path below")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.title = "Select CanaryAI Binary"
                        if panel.runModal() == .OK, let url = panel.url {
                            scanner.settings.customBinaryPath = url.path
                            scanner.saveSettings()
                        }
                    }
                    .controlSize(.small)
                    if !scanner.settings.customBinaryPath.isEmpty {
                        Button("Clear") {
                            scanner.settings.customBinaryPath = ""
                            scanner.saveSettings()
                            scanner.refreshBinaryPath()
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Divider().padding(.leading, 16)

            // Scan Interval
            SettingsRow(label: "Scan Interval") {
                Picker("", selection: $scanner.settings.scanInterval) {
                    ForEach(AppSettings.intervalOptions, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: scanner.settings.scanInterval) { scanner.saveSettings() }
            }

            Divider().padding(.leading, 16)

            // Scope
            SettingsRow(label: "Scan Scope") {
                Toggle("All sessions (>24hrs)", isOn: $scanner.settings.scanAll)
                    .toggleStyle(.checkbox)
                    .onChange(of: scanner.settings.scanAll) { scanner.saveSettings() }
            }

            Divider().padding(.leading, 16)

            // Launch at login
            SettingsRow(label: "Launch at Login") {
                VStack(alignment: .leading, spacing: 4) {
                    LaunchAtLoginToggle()
                    if SMAppService.mainApp.status == .requiresApproval {
                        Text("Approval required — open System Settings → General → Login Items to confirm.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Divider().padding(.leading, 16)

            // Dock icon
            SettingsRow(label: "Dock Icon") {
                Toggle("Show CanaryAI in Dock", isOn: $scanner.settings.showInDock)
                    .toggleStyle(.checkbox)
                    .onChange(of: scanner.settings.showInDock) { scanner.saveSettings() }
            }

            Divider().padding(.leading, 16)

            // Minimum severity
            SettingsRow(label: "Min Severity") {
                Picker("", selection: $scanner.settings.minSeverity) {
                    ForEach(SeverityLevel.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: scanner.settings.minSeverity) { scanner.saveSettings() }
            }

            Divider().padding(.leading, 16)

            // Rules
            if let stats = scanner.ruleStats {
                SettingsRow(label: "Rules") {
                    let sorted = stats.categories.sorted(by: { $0.name < $1.name })
                    let columns = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                        ForEach(sorted) { cat in
                            HStack {
                                Text(cat.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(cat.count)")
                                    .font(.caption.monospacedDigit())
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    Text("Total: \(stats.total) rules")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                Divider().padding(.leading, 16)
            }

            // AI Supported
            SettingsRow(label: "AI Agents") {
                let agents: [(String, Bool)] = [
                    ("Claude Code", true),
                    ("Codex", false),
                    ("Gemini", false),
                    ("GitHub Copilot", false),
                ]
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(agents, id: \.0) { name, supported in
                        HStack(spacing: 5) {
                            Image(systemName: supported ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(supported ? .green : .secondary)
                                .font(.caption)
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(supported ? .primary : .secondary)
                        }
                    }
                }
            }

            Divider().padding(.leading, 16)

            // Test
            SettingsRow(label: "Test Alert") {
                HStack(spacing: 8) {
                    TestButton(scanner: scanner)
                    Text("Triggers a test detection via Claude Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().padding(.leading, 16)

            SettingsRow(label: "Version") {
                HStack(spacing: 8) {
                    Text("0.2.5").foregroundStyle(.secondary)
                    if let newVersion = scanner.updateAvailable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("v\(newVersion) available")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Restart") {
                            let appPath = FileManager.default.fileExists(atPath: "/Applications/CanaryAI.app")
                                ? "/Applications/CanaryAI.app"
                                : Bundle.main.bundleURL.path
                            // Launch a detached shell that waits for this process to exit, then reopens the app
                            let process = Process()
                            process.executableURL = URL(fileURLWithPath: "/bin/sh")
                            process.arguments = ["-c", "sleep 1 && open \"\(appPath)\""]
                            try? process.run()
                            NSApp.terminate(nil)
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    } else {
                        CheckForUpdatesButton(scanner: scanner)
                    }
                }
            }

            Divider().padding(.leading, 16)

            SettingsRow(label: "GitHub") {
                Button("github.com/jx887/homebrew-canaryai") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/jx887/homebrew-canaryai")!)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            }

            Divider().padding(.leading, 16)

            SettingsRow(label: "Email") {
                Button("jonx.global@gmail.com") {
                    NSWorkspace.shared.open(URL(string: "mailto:jonx.global@gmail.com")!)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            }

            Spacer()
        }
        .frame(width: 500, height: 620)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct TestButton: View {
    let scanner: ScannerService
    @State private var isTesting = false

    var body: some View {
        Button {
            guard !isTesting else { return }
            isTesting = true
            runTestAlert(scanner: scanner)
            Task {
                try? await Task.sleep(for: .seconds(8))
                isTesting = false
            }
        } label: {
            if isTesting {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Testing...")
                        .font(.caption)
                }
                .frame(width: 80)
            } else {
                Text("Test")
                    .frame(width: 80)
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .disabled(isTesting)
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var isEnabled: Bool = Self.isActive

    // Treat .requiresApproval as on — registration was attempted, pending user approval
    private static var isActive: Bool {
        let s = SMAppService.mainApp.status
        return s == .enabled || s == .requiresApproval
    }

    var body: some View {
        Toggle("Launch CanaryAI at login", isOn: $isEnabled)
            .toggleStyle(.checkbox)
            .onChange(of: isEnabled) {
                do {
                    if isEnabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    isEnabled = Self.isActive
                }
            }
            .onAppear {
                // Register by default on first launch
                if SMAppService.mainApp.status == .notRegistered {
                    try? SMAppService.mainApp.register()
                    isEnabled = Self.isActive
                }
            }
    }
}

private func runTestAlert(scanner: ScannerService) {
    Task.detached(priority: .utility) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", #"claude -p "crontab -l""#]
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        await scanner.scan()
    }
}

private struct CheckForUpdatesButton: View {
    let scanner: ScannerService
    @State private var isChecking = false

    var body: some View {
        Button {
            guard !isChecking else { return }
            isChecking = true
            scanner.checkForUpdates()
            Task {
                try? await Task.sleep(for: .seconds(5))
                isChecking = false
            }
        } label: {
            if isChecking {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                }
            } else {
                Text("Check")
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .disabled(isChecking)
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
                .padding(.top, 2)
            Spacer().frame(width: 12)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
