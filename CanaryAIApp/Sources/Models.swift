import SwiftUI

// MARK: - JSON Output Models

struct ScanOutput: Codable {
    let sessionsScanned: Int
    let toolCallsScanned: Int
    let alertCount: Int
    let alerts: [AlertItem]

    enum CodingKeys: String, CodingKey {
        case sessionsScanned = "sessions_scanned"
        case toolCallsScanned = "tool_calls_scanned"
        case alertCount = "alert_count"
        case alerts
    }
}

struct AlertItem: Codable, Identifiable {
    var id: String { "\(ruleId)-\(sessionId)-\(toolIndex)" }

    let ruleId: String
    let ruleName: String
    let severity: String
    let message: String
    let sessionId: String
    let toolName: String
    let toolIndex: Int
    let related: [RelatedTool]

    enum CodingKeys: String, CodingKey {
        case ruleId = "rule_id"
        case ruleName = "rule_name"
        case severity, message
        case sessionId = "session_id"
        case toolName = "tool_name"
        case toolIndex = "tool_index"
        case related
    }

    var severityLevel: SeverityLevel {
        SeverityLevel(rawValue: severity) ?? .low
    }
}

struct RelatedTool: Codable {
    let toolName: String
    let toolIndex: Int

    enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case toolIndex = "tool_index"
    }
}

// MARK: - Severity

enum SeverityLevel: String, CaseIterable, Comparable, Codable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case critical = "CRITICAL"

    static func < (lhs: SeverityLevel, rhs: SeverityLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    var rank: Int {
        switch self {
        case .low: 1
        case .medium: 2
        case .high: 3
        case .critical: 4
        }
    }

    var color: Color {
        switch self {
        case .critical: .red
        case .high: Color(red: 1.0, green: 0.4, blue: 0.0)
        case .medium: .yellow
        case .low: .blue
        }
    }

    var label: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .critical: "exclamationmark.octagon.fill"
        case .high: "exclamationmark.triangle.fill"
        case .medium: "exclamationmark.circle.fill"
        case .low: "info.circle.fill"
        }
    }
}

// MARK: - Rule Stats

struct RuleCategory: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let count: Int
}

struct RuleStats: Decodable {
    let total: Int
    let categories: [RuleCategory]
}

// MARK: - App State

enum MenuBarState: Equatable {
    case notConfigured
    case clean
    case scanning
    case alerts(SeverityLevel)
    case error(String)
}

struct AppSettings {
    var customBinaryPath: String = ""
    var scanInterval: TimeInterval = 300
    var minSeverity: SeverityLevel = .low
    var scanAll: Bool = false
    var notifyOnCritical: Bool = true
    var notifyOnHigh: Bool = true
    var showInDock: Bool = true

    var sinceArgument: String? {
        scanAll ? nil : "24h"
    }

    static let intervalOptions: [(String, TimeInterval)] = [
        ("Manual only", 0),
        ("Every minute", 60),
        ("Every 5 minutes", 300),
        ("Every 15 minutes", 900),
        ("Every 30 minutes", 1800),
        ("Every hour", 3600),
    ]
}
