//
//  DeliveryMode.swift
//  WatchConnectivitySwift
//

import Foundation

/// Controls when a request should be delivered.
///
/// - `immediate`: Fail immediately if the device is not reachable.
/// - `queued`: Queue the request and send when the device becomes reachable.
public enum DeliveryMode: Sendable, Hashable {

    /// Send immediately, fail if not reachable.
    ///
    /// Use this for real-time features where delayed requests are useless.
    case immediate

    /// Queue the request if not reachable, send when connectivity is restored.
    ///
    /// The async call suspends until the response is received or timeout expires.
    case queued

    /// Whether this mode requires immediate reachability.
    var requiresImmediateReachability: Bool {
        self == .immediate
    }
}
