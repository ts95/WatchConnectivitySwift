//
//  WatchConnectionError.swift
//  WatchConnectivitySwift
//

import Foundation
import WatchConnectivity

/// Errors that can occur during watch connectivity operations.
///
/// This enum provides a type-safe, Codable error type that maps WCSession errors
/// to meaningful cases and can be transmitted across devices.
public enum WatchConnectionError: Error, Codable, Sendable, Hashable {

    // MARK: - Session State Errors

    /// The WCSession has not been activated yet.
    /// Wait for activation to complete before sending messages.
    case notActivated

    /// The counterpart device is not reachable.
    /// This can happen when the Watch app is not in the foreground or devices are disconnected.
    case notReachable

    /// No Apple Watch is paired with this iPhone (iOS only).
    case notPaired

    /// The Watch app is not installed on the paired Apple Watch (iOS only).
    case watchAppNotInstalled

    // MARK: - Communication Errors

    /// The message payload could not be delivered.
    case deliveryFailed(reason: String)

    /// The request timed out waiting for a response or connectivity.
    case timeout

    /// The operation was cancelled.
    case cancelled

    /// The reply handler failed on the remote device.
    case replyFailed(reason: String)

    // MARK: - Encoding/Decoding Errors

    /// Failed to encode the request for transmission.
    case encodingFailed(description: String)

    /// Failed to decode the response from the remote device.
    case decodingFailed(description: String)

    // MARK: - Handler Errors

    /// No handler is registered for this request type.
    case handlerNotRegistered(requestType: String)

    /// The handler threw an error while processing the request.
    case handlerError(description: String)

    // MARK: - Remote Errors

    /// An error occurred on the remote device.
    case remoteError(description: String)

    // MARK: - Session Errors

    /// A WCSession error occurred.
    case sessionError(code: Int, description: String)

    /// The session is in an unhealthy state and may require a device restart.
    case sessionUnhealthy(reason: String)

    // MARK: - File Transfer Errors

    /// The file to transfer was not found at the specified URL.
    case fileNotFound(url: String)

    /// Access to the file was denied.
    case fileAccessDenied(url: String)

    /// Not enough storage space on the device to receive the file.
    case insufficientSpace
}

// MARK: - WCError Mapping

extension WatchConnectionError {

    /// Creates a `WatchConnectionError` from a `WCError`.
    ///
    /// This maps the various WCErrorDomain error codes to meaningful error cases.
    public init(wcError: WCError) {
        switch wcError.code {
        case .genericError:
            self = .sessionError(code: wcError.code.rawValue, description: wcError.localizedDescription)

        case .sessionNotSupported:
            self = .sessionError(code: wcError.code.rawValue, description: "WCSession is not supported on this device")

        case .sessionMissingDelegate:
            self = .sessionError(code: wcError.code.rawValue, description: "WCSession delegate is not set")

        case .sessionNotActivated:
            self = .notActivated

        case .deviceNotPaired:
            self = .notPaired

        case .watchAppNotInstalled:
            self = .watchAppNotInstalled

        case .notReachable:
            self = .notReachable

        case .invalidParameter:
            self = .encodingFailed(description: "Invalid parameter in message")

        case .payloadTooLarge:
            self = .encodingFailed(description: "Payload too large for transmission")

        case .payloadUnsupportedTypes:
            self = .encodingFailed(description: "Payload contains unsupported types")

        case .messageReplyFailed:
            self = .replyFailed(reason: wcError.localizedDescription)

        case .messageReplyTimedOut:
            self = .timeout

        case .fileAccessDenied:
            self = .fileAccessDenied(url: "")

        case .deliveryFailed:
            self = .deliveryFailed(reason: wcError.localizedDescription)

        case .insufficientSpace:
            self = .insufficientSpace

        case .sessionInactive:
            self = .notActivated

        case .transferTimedOut:
            self = .timeout

        case .companionAppNotInstalled:
            self = .watchAppNotInstalled

        case .watchOnlyApp:
            self = .sessionError(code: wcError.code.rawValue, description: "This is a watch-only app")

        @unknown default:
            self = .sessionError(code: wcError.code.rawValue, description: wcError.localizedDescription)
        }
    }

    /// Creates a `WatchConnectionError` from any `Error`.
    ///
    /// If the error is already a `WatchConnectionError`, it returns it as-is.
    /// If it's a `WCError`, it maps it appropriately.
    /// Otherwise, it wraps it in a generic session error.
    public init(error: Error) {
        if let watchError = error as? WatchConnectionError {
            self = watchError
        } else if let wcError = error as? WCError {
            self.init(wcError: wcError)
        } else {
            self = .sessionError(code: -1, description: error.localizedDescription)
        }
    }
}

// MARK: - LocalizedError

extension WatchConnectionError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .notActivated:
            return "WCSession has not been activated"
        case .notReachable:
            return "The counterpart device is not reachable"
        case .notPaired:
            return "No Apple Watch is paired with this device"
        case .watchAppNotInstalled:
            return "The Watch app is not installed"
        case .deliveryFailed(let reason):
            return "Message delivery failed: \(reason)"
        case .timeout:
            return "The operation timed out"
        case .cancelled:
            return "The operation was cancelled"
        case .replyFailed(let reason):
            return "Reply failed: \(reason)"
        case .encodingFailed(let description):
            return "Encoding failed: \(description)"
        case .decodingFailed(let description):
            return "Decoding failed: \(description)"
        case .handlerNotRegistered(let requestType):
            return "No handler registered for request type: \(requestType)"
        case .handlerError(let description):
            return "Handler error: \(description)"
        case .remoteError(let description):
            return "Remote error: \(description)"
        case .sessionError(let code, let description):
            return "Session error (\(code)): \(description)"
        case .sessionUnhealthy(let reason):
            return "Session unhealthy: \(reason)"
        case .fileNotFound(let url):
            return "File not found: \(url)"
        case .fileAccessDenied(let url):
            return url.isEmpty ? "File access denied" : "File access denied: \(url)"
        case .insufficientSpace:
            return "Insufficient storage space on device"
        }
    }
}
