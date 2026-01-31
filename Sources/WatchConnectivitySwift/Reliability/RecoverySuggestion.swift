//
//  RecoverySuggestion.swift
//  WatchConnectivitySwift
//

import Foundation

/// User-facing suggestions for recovering from connectivity issues.
///
/// These suggestions are based on known WCSession failure modes that
/// require user intervention (from Apple Developer Forums research).
///
/// ## Localization
///
/// The `localizedDescription` property uses Swift's `String(localized:)` API.
/// To provide translations, add entries to your app's Localizable.strings file
/// using the keys shown in the implementation.
///
/// ## Example
///
/// ```swift
/// if case .unhealthy(let suggestion) = connection.sessionHealth {
///     showAlert(
///         title: "Connection Issue",
///         message: suggestion.localizedDescription
///     )
/// }
/// ```
public enum RecoverySuggestion: String, Sendable, Hashable, CaseIterable {

    /// Suggests restarting the Apple Watch.
    ///
    /// Emitted after persistent failures that indicate a system-level issue.
    case restartWatch

    /// Suggests opening the companion app on the other device.
    ///
    /// Emitted when the counterpart app isn't reachable but devices are paired.
    case openCompanionApp

    /// Suggests restarting both devices.
    ///
    /// Emitted when persistent failures don't resolve with simpler actions.
    case restartBothDevices

    // MARK: - Localized Description

    /// Localized description using Swift's String(localized:) API.
    ///
    /// Apps can provide translations in their Localizable.strings file.
    /// The keys are:
    /// - "recovery.restartWatch"
    /// - "recovery.openCompanionApp"
    /// - "recovery.restartBothDevices"
    public var localizedDescription: String {
        switch self {
        case .restartWatch:
            return String(
                localized: "recovery.restartWatch",
                defaultValue: "Try restarting your Apple Watch",
                bundle: .main,
                comment: "Recovery suggestion when watch connectivity fails"
            )
        case .openCompanionApp:
            return String(
                localized: "recovery.openCompanionApp",
                defaultValue: "Open the companion app on your iPhone",
                bundle: .main,
                comment: "Recovery suggestion to open companion app"
            )
        case .restartBothDevices:
            return String(
                localized: "recovery.restartBothDevices",
                defaultValue: "Restart both your iPhone and Apple Watch",
                bundle: .main,
                comment: "Recovery suggestion for persistent failures"
            )
        }
    }
}

// MARK: - CustomStringConvertible

extension RecoverySuggestion: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}
