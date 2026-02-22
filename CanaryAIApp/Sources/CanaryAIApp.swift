import SwiftUI

@main
struct CanaryAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var scanner = ScannerService()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(scanner)
                .onAppear { appDelegate.scanner = scanner }
        } label: {
            MenuBarLabel(state: scanner.menuBarState, count: scanner.filteredAlerts.count)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var scanner: ScannerService?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let scanner {
            SettingsWindowController.shared.open(scanner: scanner)
        }
        return true
    }
}

struct MenuBarLabel: View {
    let state: MenuBarState
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            switch state {
            case .clean:
                Image(systemName: "bird.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
            case .scanning:
                Image(systemName: "bird.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
                    .symbolEffect(.pulse, isActive: true)
            case .alerts(let severity):
                Image(systemName: "bird.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(severity.color, severity.color)
            case .error:
                Image(systemName: "bird.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
            case .notConfigured:
                Image(systemName: "bird.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.tertiary)
            }

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.default, value: count)
            }
        }
    }
}

// MARK: - Settings Window Controller

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func open(scanner: ScannerService) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environment(scanner)

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "CanaryAI Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 500, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
