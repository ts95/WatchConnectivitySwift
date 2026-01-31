//
//  HealthTracker.swift
//  WatchConnectivitySwift
//

import Foundation

/// Tracks session health based on consecutive failures.
///
/// This class monitors communication success/failure patterns and determines
/// when the session should be considered unhealthy. After 5 consecutive
/// failures, the session is marked unhealthy with a recovery suggestion.
///
/// Based on known WCSession issues from Apple Developer Forums:
/// - WCSession can enter permanent failure modes requiring watch reboot
/// - `isReachable=true` doesn't guarantee messages will be delivered
/// - Some failures only resolve after rebooting both devices
@MainActor
final class HealthTracker: Sendable {

    // MARK: - Configuration

    /// Number of consecutive failures before transitioning to unhealthy.
    private let unhealthyThreshold: Int

    // MARK: - State

    /// Current health state.
    private(set) var health: SessionHealth = .healthy

    /// Count of consecutive failures (resets on success).
    private var consecutiveFailures: Int = 0

    // MARK: - Initialization

    init(unhealthyThreshold: Int = 5) {
        self.unhealthyThreshold = unhealthyThreshold
    }

    // MARK: - Recording

    /// Records a successful communication.
    ///
    /// - Returns: The new health state and whether it changed.
    @discardableResult
    func recordSuccess() -> (health: SessionHealth, changed: Bool) {
        let previousHealth = health
        consecutiveFailures = 0
        health = .healthy

        return (health, previousHealth != health)
    }

    /// Records a failed communication.
    ///
    /// - Returns: The new health state and whether it changed.
    @discardableResult
    func recordFailure() -> (health: SessionHealth, changed: Bool) {
        let previousHealth = health
        consecutiveFailures += 1

        // Determine new health state based on threshold
        if consecutiveFailures >= unhealthyThreshold {
            health = .unhealthy(suggestion: .restartWatch)
        }

        return (health, previousHealth != health)
    }

    /// Resets the health tracker to healthy state.
    func reset() {
        health = .healthy
        consecutiveFailures = 0
    }
}
