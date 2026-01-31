//
//  DiagnosticEvent.swift
//  WatchConnectivitySwift
//

import Foundation

/// Events emitted by WatchConnection for debugging and monitoring.
///
/// Subscribe to these events to understand connectivity behavior and
/// troubleshoot issues during development.
///
/// ## Example
///
/// ```swift
/// Task {
///     for await event in connection.diagnosticEvents {
///         switch event {
///         case .deliveryFailed(let type, let error, let willRetry):
///             print("[\(type)] failed: \(error), retry: \(willRetry)")
///         case .fallbackUsed(let from, let to):
///             print("Fallback: \(from) -> \(to)")
///         case .healthChanged(let from, let to):
///             print("Health: \(from) -> \(to)")
///         default:
///             break
///         }
///     }
/// }
/// ```
public enum DiagnosticEvent: Sendable {

    // MARK: - Session Lifecycle

    /// The WCSession was successfully activated.
    case sessionActivated

    /// The WCSession was deactivated (iOS only, during watch switching).
    case sessionDeactivated

    /// The session became inactive (iOS only, during watch switching).
    case sessionBecameInactive

    // MARK: - Reachability

    /// The reachability state changed.
    ///
    /// - Parameter isReachable: Whether the counterpart is now reachable.
    case reachabilityChanged(isReachable: Bool)

    // MARK: - Message Events

    /// A message was successfully sent.
    ///
    /// - Parameters:
    ///   - requestType: The type name of the request sent.
    ///   - duration: How long the round-trip took.
    case messageSent(requestType: String, duration: Duration)

    /// A message was received from the counterpart.
    ///
    /// - Parameter requestType: The type name of the received request.
    case messageReceived(requestType: String)

    /// A message delivery failed.
    ///
    /// - Parameters:
    ///   - requestType: The type name of the request.
    ///   - error: The error that occurred.
    ///   - willRetry: Whether the library will automatically retry.
    case deliveryFailed(requestType: String, error: WatchConnectionError, willRetry: Bool)

    /// A fallback delivery method was used.
    ///
    /// This occurs when the primary delivery method fails and the strategy
    /// specifies a fallback (e.g., sendMessage fails, transferUserInfo used).
    ///
    /// - Parameters:
    ///   - from: The primary method that failed.
    ///   - to: The fallback method being used.
    case fallbackUsed(from: DeliveryMethod, to: DeliveryMethod)

    // MARK: - Queue Events

    /// A request was added to the queue (waiting for connectivity).
    ///
    /// - Parameters:
    ///   - requestType: The type name of the queued request.
    ///   - queueSize: The total number of requests now in the queue.
    case requestQueued(requestType: String, queueSize: Int)

    /// The request queue was flushed after connectivity was restored.
    ///
    /// - Parameter count: The number of requests that were sent.
    case queueFlushed(count: Int)

    /// A queued request expired before it could be sent.
    ///
    /// - Parameter requestType: The type name of the expired request.
    case requestExpired(requestType: String)

    // MARK: - Health Events

    /// The session health state changed.
    ///
    /// - Parameters:
    ///   - from: The previous health state.
    ///   - to: The new health state.
    case healthChanged(from: SessionHealth, to: SessionHealth)

    // MARK: - Recovery Events

    /// A session recovery attempt was initiated.
    case recoveryAttempted

    /// A session recovery attempt succeeded.
    case recoverySucceeded

    /// A session recovery attempt failed.
    ///
    /// - Parameter error: The error that prevented recovery.
    case recoveryFailed(error: WatchConnectionError)

    // MARK: - File Transfer Events

    /// A file transfer was started.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of the file being transferred.
    ///   - hasMetadata: Whether metadata was included.
    case fileTransferStarted(fileURL: URL, hasMetadata: Bool)

    /// A file transfer completed successfully.
    ///
    /// - Parameter fileURL: The URL of the file that was transferred.
    case fileTransferCompleted(fileURL: URL)

    /// A file transfer failed.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of the file that failed to transfer.
    ///   - error: The error that occurred.
    case fileTransferFailed(fileURL: URL, error: WatchConnectionError)

    /// A file was received from the counterpart.
    ///
    /// - Parameters:
    ///   - fileURL: The URL where the file was received.
    ///   - hasMetadata: Whether metadata was included.
    case fileReceived(fileURL: URL, hasMetadata: Bool)

    // MARK: - Application Context Events

    /// Application context was received from the counterpart.
    case applicationContextReceived
}

// MARK: - CustomStringConvertible

extension DiagnosticEvent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .sessionActivated:
            return "Session activated"
        case .sessionDeactivated:
            return "Session deactivated"
        case .sessionBecameInactive:
            return "Session became inactive"
        case .reachabilityChanged(let isReachable):
            return "Reachability: \(isReachable ? "reachable" : "not reachable")"
        case .messageSent(let type, let duration):
            return "Sent \(type) (\(duration))"
        case .messageReceived(let type):
            return "Received \(type)"
        case .deliveryFailed(let type, let error, let willRetry):
            return "Delivery failed: \(type) - \(error)\(willRetry ? " (will retry)" : "")"
        case .fallbackUsed(let from, let to):
            return "Fallback: \(from) -> \(to)"
        case .requestQueued(let type, let size):
            return "Queued \(type) (queue size: \(size))"
        case .queueFlushed(let count):
            return "Queue flushed: \(count) requests"
        case .requestExpired(let type):
            return "Request expired: \(type)"
        case .healthChanged(let from, let to):
            return "Health: \(from) -> \(to)"
        case .recoveryAttempted:
            return "Recovery attempted"
        case .recoverySucceeded:
            return "Recovery succeeded"
        case .recoveryFailed(let error):
            return "Recovery failed: \(error)"
        case .fileTransferStarted(let url, let hasMetadata):
            return "File transfer started: \(url.lastPathComponent)\(hasMetadata ? " (with metadata)" : "")"
        case .fileTransferCompleted(let url):
            return "File transfer completed: \(url.lastPathComponent)"
        case .fileTransferFailed(let url, let error):
            return "File transfer failed: \(url.lastPathComponent) - \(error)"
        case .fileReceived(let url, let hasMetadata):
            return "File received: \(url.lastPathComponent)\(hasMetadata ? " (with metadata)" : "")"
        case .applicationContextReceived:
            return "Application context received"
        }
    }
}
