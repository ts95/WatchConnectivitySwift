//
//  WireProtocol.swift
//  WatchConnectivitySwift
//

import Foundation

/// Wire format for requests sent between devices.
///
/// This type encapsulates the request payload along with metadata needed
/// for routing and processing on the receiving end.
struct WireRequest: Codable, Sendable {

    /// The type name of the request (e.g., "FetchRecipeRequest").
    /// Used to look up the appropriate handler on the receiving end.
    let typeName: String

    /// The JSON-encoded request payload.
    let payload: Data

    /// Unique identifier for this request (for correlation with responses).
    let requestID: UUID

    /// Whether this is a fire-and-forget request (no response expected).
    let isFireAndForget: Bool

    /// Timestamp when the request was created.
    let timestamp: Date

    /// Creates a wire request from a typed request.
    init<R: WatchRequest>(request: R, isFireAndForget: Bool = false) throws {
        let encoder = JSONEncoder()
        self.typeName = String(describing: R.self)
        self.payload = try encoder.encode(request)
        self.requestID = UUID()
        self.isFireAndForget = isFireAndForget
        self.timestamp = Date()
    }

    /// Decodes the payload to the specified request type.
    func decodePayload<R: WatchRequest>(as type: R.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> R {
        try decoder.decode(R.self, from: payload)
    }
}

/// Wire format for responses sent between devices.
///
/// This type wraps the response (or error) and correlates it with the original request.
struct WireResponse: Codable, Sendable {

    /// The outcome of the request.
    let outcome: Outcome

    /// The request ID this response is for.
    let requestID: UUID

    /// Timestamp when the response was created.
    let timestamp: Date

    /// The possible outcomes of a request.
    enum Outcome: Codable, Sendable {
        /// The request succeeded with the given response payload.
        case success(Data)

        /// The request failed with the given error.
        case failure(WatchConnectionError)
    }

    /// Creates a successful response with already-encoded payload.
    static func success(
        _ payload: Data,
        requestID: UUID
    ) -> WireResponse {
        WireResponse(
            outcome: .success(payload),
            requestID: requestID,
            timestamp: Date()
        )
    }

    /// Creates a successful response by encoding the response object.
    static func success<R: Codable & Sendable>(
        _ response: R,
        requestID: UUID,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> WireResponse {
        let payload = try encoder.encode(response)
        return WireResponse(
            outcome: .success(payload),
            requestID: requestID,
            timestamp: Date()
        )
    }

    /// Creates a failure response.
    static func failure(
        _ error: WatchConnectionError,
        requestID: UUID
    ) -> WireResponse {
        WireResponse(
            outcome: .failure(error),
            requestID: requestID,
            timestamp: Date()
        )
    }

    /// Decodes the success payload to the specified type.
    func decodeSuccess<R: Codable & Sendable>(
        as type: R.Type,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> R {
        switch outcome {
        case .success(let data):
            return try decoder.decode(R.self, from: data)
        case .failure(let error):
            throw error
        }
    }

    /// Returns the error if this is a failure response.
    var error: WatchConnectionError? {
        switch outcome {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}

// MARK: - User Info Wire Format

/// Wire format for user info transfers.
///
/// This wraps a request for queued delivery via `transferUserInfo`.
struct WireUserInfo: Codable, Sendable {

    /// Key used in the user info dictionary.
    static let key = "WatchConnectivitySwift.Request"

    /// The wire request being transferred.
    let request: WireRequest

    /// Converts to a dictionary for `transferUserInfo`.
    func toDictionary(encoder: JSONEncoder = JSONEncoder()) throws -> [String: Any] {
        let data = try encoder.encode(self)
        return [Self.key: data]
    }

    /// Creates from a dictionary received in `didReceiveUserInfo`.
    static func from(dictionary: [String: Any], decoder: JSONDecoder = JSONDecoder()) throws -> WireUserInfo {
        guard let data = dictionary[Self.key] as? Data else {
            throw WatchConnectionError.decodingFailed(description: "Missing WireUserInfo data in user info dictionary")
        }
        return try decoder.decode(WireUserInfo.self, from: data)
    }
}
