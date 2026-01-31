//
//  FlakySession.swift
//  WatchConnectivitySwift
//

import Foundation
import WatchConnectivity
@testable import WatchConnectivitySwift

/// A simulated flaky session for reliability testing.
///
/// This mock simulates the unreliable behavior of WCSession to test
/// that the library's reliability features work correctly.
final class FlakySession: SessionProviding, @unchecked Sendable {

    // MARK: - Flakiness Configuration

    /// Probability of a message failing (0.0 to 1.0)
    var failureProbability: Double = 0.3

    /// Probability of isReachable lying (saying true when actually not reachable)
    var phantomReachabilityProbability: Double = 0.1

    /// Probability of a random delay occurring
    var delayProbability: Double = 0.2

    /// Errors to randomly choose from on failure
    var possibleErrors: [Error] = [
        NSError(domain: "WCErrorDomain", code: 7007, userInfo: [NSLocalizedDescriptionKey: "Not reachable"]),
        NSError(domain: "WCErrorDomain", code: 7014, userInfo: [NSLocalizedDescriptionKey: "Delivery failed"]),
        NSError(domain: "WCErrorDomain", code: 7012, userInfo: [NSLocalizedDescriptionKey: "Transfer timed out"])
    ]

    /// Whether the session is in a "stuck" state that requires restart
    var isStuck: Bool = false

    // MARK: - State Properties

    var activationState: WCSessionActivationState = .activated
    var isReachable: Bool = true
    var applicationContext: [String: Any] = [:]
    var receivedApplicationContext: [String: Any] = [:]

    #if os(iOS)
    var isPaired: Bool = true
    var isWatchAppInstalled: Bool = true
    #endif

    // MARK: - Delegate

    weak var delegate: (any WCSessionDelegate)?

    // MARK: - Outstanding Transfers

    var outstandingUserInfoTransfers: [WCSessionUserInfoTransfer] = []
    var outstandingFileTransfers: [WCSessionFileTransfer] = []

    // MARK: - Statistics

    private(set) var totalAttempts = 0
    private(set) var successfulAttempts = 0
    private(set) var failedAttempts = 0

    // MARK: - Session Lifecycle

    func activate() {
        if isStuck {
            // Stuck sessions don't complete activation
            return
        }

        Task { @MainActor in
            delegate?.session(
                WCSession.default,
                activationDidCompleteWith: activationState,
                error: nil
            )
        }
    }

    // MARK: - Live Messaging

    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {
        // Not used
    }

    func sendMessageData(
        _ data: Data,
        replyHandler: ((Data) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {
        totalAttempts += 1

        // Simulate stuck session
        if isStuck {
            // Never respond - session is stuck
            return
        }

        // Simulate phantom reachability (isReachable is true but actually not)
        if isReachable && Double.random(in: 0...1) < phantomReachabilityProbability {
            self.failedAttempts += 1
            errorHandler?(possibleErrors.randomElement()!)
            return
        }

        // Simulate random failure
        if Double.random(in: 0...1) < failureProbability {
            self.failedAttempts += 1
            errorHandler?(possibleErrors.randomElement()!)
            return
        }

        // Success
        self.successfulAttempts += 1
        let wireResponse = WireResponse(
            outcome: .success(Data()),
            requestID: UUID(),
            timestamp: Date()
        )
        if let responseData = try? JSONEncoder().encode(wireResponse) {
            replyHandler?(responseData)
        }
    }

    // MARK: - Background Transfers

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        if isStuck {
            throw NSError(domain: "WCErrorDomain", code: 7014, userInfo: nil)
        }

        self.applicationContext = applicationContext
    }

    @discardableResult
    func transferUserInfo(_ userInfo: [String: Any]) -> WCSessionUserInfoTransfer {
        // Simulate: return placeholder
        return WCSession.default.transferUserInfo([:])
    }

    @discardableResult
    func transferFile(_ file: URL, metadata: [String: Any]?) -> WCSessionFileTransfer {
        // Simulate: return placeholder (this will fail in tests without real device)
        return WCSession.default.transferFile(file, metadata: metadata)
    }

    // MARK: - Test Helpers

    /// Resets statistics and state
    func reset() {
        totalAttempts = 0
        successfulAttempts = 0
        failedAttempts = 0
        isStuck = false
        applicationContext = [:]
        receivedApplicationContext = [:]
    }

    /// Makes the session get stuck (simulates permanent failure mode)
    func simulateStuck() {
        isStuck = true
    }

    /// Recovers from stuck state
    func simulateRecovery() {
        isStuck = false
    }

    /// Returns the success rate
    var successRate: Double {
        guard totalAttempts > 0 else { return 1.0 }
        return Double(successfulAttempts) / Double(totalAttempts)
    }
}
