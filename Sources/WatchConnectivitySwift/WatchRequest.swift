//
//  WatchRequest.swift
//  WatchConnectivitySwift
//

import Foundation

/// Base protocol for all watch connectivity requests.
///
/// Each request type declares its own response type via the associated `Response` type.
/// This enables fully type-safe request/response pairs where the compiler enforces
/// that each request returns the correct response type.
///
/// ## Example
///
/// ```swift
/// struct FetchRecipeRequest: WatchRequest {
///     typealias Response = Recipe
///     let id: String
/// }
///
/// // Usage - response type is inferred
/// let recipe: Recipe = try await connection.send(FetchRecipeRequest(id: "123"))
/// ```
public protocol WatchRequest: Codable, Sendable {
    /// The response type this request produces.
    associatedtype Response: Codable & Sendable
}

/// Marker protocol for requests that don't need a response (fire-and-forget).
///
/// Use this for analytics, logging, or non-critical updates where you don't
/// need to wait for or process a response.
///
/// ## Example
///
/// ```swift
/// struct LogEventRequest: FireAndForgetRequest {
///     let name: String
///     let parameters: [String: String]
/// }
///
/// // Usage - no response, doesn't block
/// await connection.send(LogEventRequest(name: "screen_view", parameters: [:]))
/// ```
public protocol FireAndForgetRequest: WatchRequest where Response == VoidResponse {}

/// A Codable void response type for fire-and-forget requests.
///
/// This exists because `Void` doesn't conform to `Codable`.
public struct VoidResponse: Codable, Sendable, Hashable {
    public init() {}
}
