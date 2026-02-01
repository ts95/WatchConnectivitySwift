//
//  PreviewWCSession.swift
//  WatchConnectivitySwift
//
//  A mock session for SwiftUI previews and testing.
//

import Foundation
@preconcurrency import WatchConnectivity

/// A mock implementation of `WCSessionProviding` for SwiftUI previews and testing.
///
/// Use this class to create a `WatchConnection` that doesn't require actual
/// Watch connectivity, making it perfect for SwiftUI previews and unit tests.
///
/// ## Example: SwiftUI Preview
///
/// ```swift
/// struct RecipeListView: View {
///     @StateObject var viewModel: RecipeViewModel
///
///     var body: some View {
///         // ... your view code
///     }
/// }
///
/// #Preview {
///     // Create a preview session with custom state
///     let previewSession = PreviewWCSession()
///     previewSession.isReachable = true
///     previewSession.isPaired = true
///
///     // Create connection with the preview session
///     let connection = WatchConnection(session: previewSession)
///
///     return RecipeListView(
///         viewModel: RecipeViewModel(connection: connection)
///     )
/// }
/// ```
///
/// ## Example: Unit Test
///
/// ```swift
/// @Test func testSendRequest() async throws {
///     let session = PreviewWCSession()
///     session.isReachable = true
///
///     // Configure mock response
///     let mockUser = User(id: "1", name: "Test")
///     session.setMockResponse(mockUser, for: FetchUserRequest.self)
///
///     let connection = WatchConnection(session: session)
///     let result = try await connection.send(FetchUserRequest(userID: "1"))
///
///     #expect(result.name == "Test")
/// }
/// ```
public final class PreviewWCSession: WCSessionProviding, @unchecked Sendable {

    // MARK: - Session State

    /// The current activation state.
    public var activationState: WCSessionActivationState = .activated

    /// Whether the counterpart device is currently reachable.
    public var isReachable: Bool = true

    /// The current application context.
    public var applicationContext: [String: Any] = [:]

    /// The received application context from the counterpart.
    public var receivedApplicationContext: [String: Any] = [:]

    #if os(iOS)
    /// Whether an Apple Watch is paired (iOS only).
    public var isPaired: Bool = true

    /// Whether the Watch app is installed (iOS only).
    public var isWatchAppInstalled: Bool = true
    #endif

    // MARK: - Delegate

    /// The session delegate.
    public weak var delegate: (any WCSessionDelegate)?

    // MARK: - Outstanding Transfers

    /// Outstanding user info transfers.
    public var outstandingUserInfoTransfers: [WCSessionUserInfoTransfer] = []

    /// Outstanding file transfers.
    public var outstandingFileTransfers: [WCSessionFileTransfer] = []

    // MARK: - Mock Configuration

    /// Error to return when sending messages. Set to `nil` for success.
    public var sendMessageError: Error?

    /// Whether to automatically reply to messages.
    public var autoReply: Bool = true

    /// Error to return when updating application context.
    public var updateContextError: Error?

    // MARK: - Response Storage

    private var mockResponses: [String: Any] = [:]

    // MARK: - Initialization

    /// Creates a new preview session with default values.
    public init() {}

    /// Creates a preview session configured for a connected state.
    public static var connected: PreviewWCSession {
        let session = PreviewWCSession()
        session.activationState = .activated
        session.isReachable = true
        #if os(iOS)
        session.isPaired = true
        session.isWatchAppInstalled = true
        #endif
        return session
    }

    /// Creates a preview session configured for a disconnected state.
    public static var disconnected: PreviewWCSession {
        let session = PreviewWCSession()
        session.activationState = .activated
        session.isReachable = false
        #if os(iOS)
        session.isPaired = true
        session.isWatchAppInstalled = true
        #endif
        return session
    }

    /// Creates a preview session configured for an unpaired state (iOS only).
    #if os(iOS)
    public static var unpaired: PreviewWCSession {
        let session = PreviewWCSession()
        session.activationState = .activated
        session.isReachable = false
        session.isPaired = false
        session.isWatchAppInstalled = false
        return session
    }
    #endif

    // MARK: - Mock Response Configuration

    /// Sets a mock response for a specific request type.
    ///
    /// When a request of this type is sent, the mock response will be returned.
    ///
    /// - Parameters:
    ///   - response: The response to return.
    ///   - requestType: The type of request this response is for.
    public func setMockResponse<R: WatchRequest>(_ response: R.Response, for requestType: R.Type) {
        let key = String(describing: R.self)
        mockResponses[key] = response
    }

    /// Clears all mock responses.
    public func clearMockResponses() {
        mockResponses.removeAll()
    }

    // MARK: - WCSessionProviding Implementation

    public func activate() {
        // Simulate activation completion
        Task { @MainActor in
            delegate?.session(
                WCSession.default,
                activationDidCompleteWith: activationState,
                error: nil
            )
        }
    }

    public func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {
        // Not used - we use sendMessageData
    }

    public func sendMessageData(
        _ data: Data,
        replyHandler: ((Data) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {
        guard autoReply else { return }

        if let error = sendMessageError {
            errorHandler?(error)
            return
        }

        // Try to decode the request to find the type
        if let wireRequest = try? JSONDecoder().decode(WireRequest.self, from: data) {
            let requestTypeName = wireRequest.typeName

            // Check if we have a mock response
            if let mockResponse = mockResponses[requestTypeName] {
                // Encode the response
                if let encodable = mockResponse as? any Encodable,
                   let responseData = try? JSONEncoder().encode(AnyEncodable(encodable)) {
                    let wireResponse = WireResponse(
                        outcome: .success(responseData),
                        requestID: wireRequest.requestID,
                        timestamp: Date()
                    )
                    if let finalData = try? JSONEncoder().encode(wireResponse) {
                        replyHandler?(finalData)
                        return
                    }
                }
            }
        }

        // Default: return empty success
        let wireResponse = WireResponse(
            outcome: .success(Data()),
            requestID: UUID(),
            timestamp: Date()
        )
        if let responseData = try? JSONEncoder().encode(wireResponse) {
            replyHandler?(responseData)
        }
    }

    public func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        if let error = updateContextError {
            throw error
        }
        self.applicationContext = applicationContext
    }

    @discardableResult
    public func transferUserInfo(_ userInfo: [String: Any]) -> WCSessionUserInfoTransfer {
        // Return a placeholder - can't create a real transfer
        return WCSession.default.transferUserInfo([:])
    }

    @discardableResult
    public func transferFile(_ file: URL, metadata: [String: Any]?) -> WCSessionFileTransfer {
        // Return a placeholder - can't create a real transfer
        return WCSession.default.transferFile(file, metadata: metadata)
    }

    // MARK: - Simulation Methods

    /// Simulates receiving a message from the counterpart device.
    ///
    /// - Parameters:
    ///   - data: The message data.
    ///   - replyHandler: Handler for the reply.
    public func simulateReceivedMessage(_ data: Data, replyHandler: @escaping (Data) -> Void) {
        delegate?.session?(
            WCSession.default,
            didReceiveMessageData: data,
            replyHandler: replyHandler
        )
    }

    /// Simulates a reachability change.
    ///
    /// - Parameter reachable: Whether the counterpart is now reachable.
    public func simulateReachabilityChange(_ reachable: Bool) {
        isReachable = reachable
    }

    /// Simulates receiving application context from the counterpart.
    ///
    /// - Parameter context: The received context.
    public func simulateReceivedApplicationContext(_ context: [String: Any]) {
        receivedApplicationContext = context
        delegate?.session?(
            WCSession.default,
            didReceiveApplicationContext: context
        )
    }
}

// MARK: - Helper Types

/// Type-erased Encodable wrapper.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
