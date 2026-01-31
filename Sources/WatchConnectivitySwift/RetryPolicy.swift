//
//  RetryPolicy.swift
//  WatchConnectivitySwift
//

import Foundation
import WatchConnectivity

/// Configuration for retry behavior when sending messages.
///
/// Controls how many times to retry and the overall timeout.
/// Uses a fixed 200ms delay between retries.
public struct RetryPolicy: Sendable {

    /// Maximum number of attempts (including the initial attempt).
    public let maxAttempts: Int

    /// Maximum total time before the entire operation times out.
    public let timeout: Duration

    /// Creates a retry policy.
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (including initial).
    ///   - timeout: Maximum total time for all attempts.
    public init(maxAttempts: Int, timeout: Duration) {
        self.maxAttempts = max(1, maxAttempts)
        self.timeout = timeout
    }

    /// Returns true if the error should be retried.
    func shouldRetry(_ error: Error) -> Bool {
        if let watchError = error as? WatchConnectionError {
            switch watchError {
            case .notReachable, .deliveryFailed, .replyFailed:
                return true
            default:
                return false
            }
        }
        if let wcError = error as? WCError {
            switch wcError.code {
            case .notReachable, .deliveryFailed, .messageReplyFailed:
                return true
            default:
                return false
            }
        }
        return false
    }
}

// MARK: - Predefined Policies

extension RetryPolicy {

    /// Default retry policy.
    ///
    /// - 3 attempts
    /// - 10 second timeout
    /// - 200ms delay between retries
    public static let `default` = RetryPolicy(maxAttempts: 3, timeout: .seconds(10))

    /// No retries - fail immediately on first error.
    ///
    /// - 1 attempt (no retries)
    /// - 10 second timeout
    public static let none = RetryPolicy(maxAttempts: 1, timeout: .seconds(10))

    /// Patient policy for important requests that can wait.
    ///
    /// - 5 attempts
    /// - 30 second timeout
    /// - 200ms delay between retries
    public static let patient = RetryPolicy(maxAttempts: 5, timeout: .seconds(30))
}
