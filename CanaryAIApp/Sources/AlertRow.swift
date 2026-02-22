import SwiftUI

struct AlertRow: View {
    @Environment(ScannerService.self) private var scanner
    let alert: AlertItem
    @State private var isExpanded = false

    private var isDismissed: Bool {
        scanner.dismissedAlertIDs.contains(alert.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack(alignment: .top, spacing: 6) {
                // Severity badge
                Text(alert.severity)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(alert.severityLevel.color, in: RoundedRectangle(cornerRadius: 3))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(alert.ruleId)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                        Text(alert.ruleName)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Text(alert.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                }

                Spacer(minLength: 0)

                if isDismissed {
                    Button {
                        scanner.restoreAlert(alert)
                    } label: {
                        Text("Undo")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button {
                        scanner.dismissAlert(alert)
                    } label: {
                        Text("Resolve")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.borderless)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }

            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    detailRow("Session", value: String(alert.sessionId.prefix(16)) + "...")
                    detailRow("Tool", value: "\(alert.toolName) (#\(alert.toolIndex))")
                    if !alert.related.isEmpty {
                        detailRow("Related", value: "\(alert.related.count) tool call(s)")
                    }
                    HStack(spacing: 10) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(alert.sessionId, forType: .string)
                        } label: {
                            Label("Copy Session ID", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)

                        Button {
                            runInTerminal(sessionId: alert.sessionId)
                        } label: {
                            Label("Investigate in Terminal", systemImage: "terminal")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.leading, 38)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(alert.severityLevel.color.opacity(isDismissed ? 0.02 : 0.04))
        .opacity(isDismissed ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private func runInTerminal(sessionId: String) {
        // Validate sessionId is a UUID before embedding in AppleScript
        guard UUID(uuidString: sessionId) != nil else { return }

        // Command typed directly into Terminal — fully visible, no hidden scripts
        // Use AppleScript's `quote` constant to inject " without escaping nightmares
        let pyCmd = "import sys,json;[print('['+b.get('name','')+'] '+str(b.get('input',''))[:200]) for l in sys.stdin for b in (json.loads(l).get('message') or {}).get('content',[]) if isinstance(b,dict) and b.get('type')=='tool_use']"

        let appleScript = """
        tell application "Terminal"
            set cmd to "cat $(find ~/.claude/projects -name " & quote & "\(sessionId).jsonl" & quote & " 2>/dev/null | head -1) | python3 -c " & quote & "\(pyCmd)" & quote
            do script cmd
            activate
        end tell
        """
        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = ["-e", appleScript]
        try? osascript.run()
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption2)
                .monospaced()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
