//
//  DeliveryMode.swift
//  WatchConnectivitySwift
//

import Foundation

/// Controls when a request should be delivered.
///
/// - `immediate`: Fail immediately if the device is not reachable.
/// - `queued`: Don't require reachability; let the delivery strategy get the request there.
public enum DeliveryMode: Sendable, Hashable {

    /// Send immediately, fail if not reachable.
    ///
    /// Use this for real-time features where delayed requests are useless.
    case immediate

    /// Don't require reachability up front. If the counterpart isn't reachable, a strategy
    /// with a fallback (`.messageWithUserInfoFallback`, `.messageWithContextFallback`) sends
    /// the request that way, and the system delivers it when it can. A strategy without one
    /// (`.messageOnly`) still fails.
    ///
    /// The async call suspends until the response is received or timeout expires.
    case queued

    /// Whether this mode requires immediate reachability.
    var requiresImmediateReachability: Bool {
        self == .immediate
    }
}
