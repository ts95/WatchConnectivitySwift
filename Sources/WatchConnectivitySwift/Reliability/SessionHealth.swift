//
//  SessionHealth.swift
//  WatchConnectivitySwift
//

import Foundation

/// Represents the health state of the WCSession connection.
///
/// Use this to detect persistent connectivity issues and guide users
/// toward recovery actions (e.g., restarting their Watch).
///
/// ## Example
///
/// ```swift
/// switch connection.sessionHealth {
/// case .healthy:
///     // Normal operation
/// case .unhealthy(let suggestion):
///     showAlert(suggestion.localizedDescription)
/// }
/// ```
public enum SessionHealth: Sendable, Equatable {

    /// The session is functioning normally.
    ///
    /// Recent communication has succeeded without issues.
    case healthy

    /// The session has persistent failures and may require user intervention.
    ///
    /// Multiple consecutive failures have occurred, and the session is unlikely
    /// to recover without action.
    ///
    /// - Parameter suggestion: A recovery action to suggest to the user.
    case unhealthy(suggestion: RecoverySuggestion)

    /// Whether the session is in a healthy state.
    public var isHealthy: Bool {
        switch self {
        case .healthy:
            return true
        case .unhealthy:
            return false
        }
    }

    /// The recovery suggestion, if unhealthy.
    public var suggestion: RecoverySuggestion? {
        switch self {
        case .healthy:
            return nil
        case .unhealthy(let suggestion):
            return suggestion
        }
    }
}

// MARK: - Hashable

extension SessionHealth: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .healthy:
            hasher.combine(0)
        case .unhealthy(let suggestion):
            hasher.combine(1)
            hasher.combine(suggestion)
        }
    }
}

// MARK: - CustomStringConvertible

extension SessionHealth: CustomStringConvertible {
    public var description: String {
        switch self {
        case .healthy:
            return "healthy"
        case .unhealthy(let suggestion):
            return "unhealthy(\(suggestion))"
        }
    }
}
