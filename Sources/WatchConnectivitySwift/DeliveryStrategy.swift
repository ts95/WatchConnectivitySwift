//
//  DeliveryStrategy.swift
//  WatchConnectivitySwift
//

import Foundation

/// Strategy for delivering messages with fallback options.
///
/// WCSession provides multiple transport mechanisms with different characteristics:
/// - `sendMessage`: Real-time, requires both apps active, can fail
/// - `transferUserInfo`: Queued, guaranteed delivery, but slower
/// - `applicationContext`: Latest-value-wins, guaranteed delivery
///
/// This strategy controls which mechanism to use and how to fall back
/// when the primary mechanism fails.
///
/// ## Example
///
/// ```swift
/// // Default: try sendMessage, fall back to transferUserInfo
/// let response = try await connection.send(request)
///
/// // For state that only needs latest value
/// let response = try await connection.send(
///     request,
///     strategy: .messageWithContextFallback
/// )
///
/// // For real-time only (fail if sendMessage fails)
/// let response = try await connection.send(
///     request,
///     strategy: .messageOnly
/// )
/// ```
public enum DeliveryStrategy: String, Sendable, Hashable, Codable {

    /// Try `sendMessage` first, fall back to `transferUserInfo` if unreachable.
    ///
    /// This is the default strategy and provides the best balance of:
    /// - Fast delivery when both apps are active
    /// - Guaranteed eventual delivery via queued transfer
    ///
    /// **Note:** `transferUserInfo` queues messages, so they will be delivered
    /// when the receiving app becomes active, even if it's not running now.
    case messageWithUserInfoFallback

    /// Try `sendMessage` first, fall back to `applicationContext`.
    ///
    /// Use this when only the latest value matters (e.g., settings sync).
    /// If multiple requests fail while offline, only the last one will be
    /// delivered when connectivity is restored.
    case messageWithContextFallback

    /// Only use `sendMessage`. Fail if not reachable.
    ///
    /// Use this for real-time features where:
    /// - Stale requests are useless
    /// - You need immediate feedback
    /// - The request is time-sensitive
    case messageOnly

    /// Only use `transferUserInfo`. Guaranteed queued delivery.
    ///
    /// Use this when you need guaranteed delivery and order preservation,
    /// but don't need immediate response. Messages are queued and delivered
    /// in order when the receiving app becomes active.
    case userInfoOnly

    /// Only use `applicationContext`. Latest value wins.
    ///
    /// Use this for state synchronization where only the latest value matters.
    /// Previous values are overwritten if not yet delivered.
    case contextOnly

    /// The primary delivery method for this strategy.
    public var primaryMethod: DeliveryMethod {
        switch self {
        case .messageWithUserInfoFallback, .messageWithContextFallback, .messageOnly:
            return .message
        case .userInfoOnly:
            return .userInfo
        case .contextOnly:
            return .context
        }
    }

    /// The fallback delivery method, if any.
    public var fallbackMethod: DeliveryMethod? {
        switch self {
        case .messageWithUserInfoFallback:
            return .userInfo
        case .messageWithContextFallback:
            return .context
        case .messageOnly, .userInfoOnly, .contextOnly:
            return nil
        }
    }

    /// Whether this strategy supports fallback.
    public var hasFallback: Bool {
        fallbackMethod != nil
    }
}

/// The underlying WCSession delivery method.
public enum DeliveryMethod: String, Sendable, Hashable, Codable {
    /// `sendMessage` / `sendMessageData` - real-time, requires counterpart active
    case message

    /// `transferUserInfo` - queued, guaranteed delivery in order
    case userInfo

    /// `updateApplicationContext` - latest value wins
    case context
}
