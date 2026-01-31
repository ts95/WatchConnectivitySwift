//
//  MockSession.swift
//  WatchConnectivitySwift
//

import Foundation
import WatchConnectivity
@testable import WatchConnectivitySwift

/// A mock implementation of SessionProviding for testing.
///
/// This mock allows you to control session behavior and verify interactions
/// in unit tests without requiring actual WatchConnectivity.
final class MockSession: SessionProviding, @unchecked Sendable {

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

    // MARK: - Test Configuration

    /// Error to throw on sendMessageData (nil = success)
    var sendMessageError: Error?

    /// Simulated response data for sendMessageData
    var sendMessageResponse: Data?

    /// Delay before responding to sendMessageData (in milliseconds)
    var sendMessageDelayMs: Int64 = 0

    /// Whether to automatically call the reply handler
    var autoReply: Bool = true

    /// Error to throw on updateApplicationContext
    var updateContextError: Error?

    /// Callback when sendMessageData is called
    var onSendMessageData: (@Sendable (Data) -> Void)?

    /// Callback when transferUserInfo is called
    var onTransferUserInfo: (@Sendable ([String: Any]) -> Void)?

    /// Callback when updateApplicationContext is called
    var onUpdateApplicationContext: (@Sendable ([String: Any]) -> Void)?

    /// Callback when activate is called
    var onActivate: (@Sendable () -> Void)?

    /// Callback when transferFile is called
    var onTransferFile: (@Sendable (URL, [String: Any]?) -> Void)?

    /// Whether to auto-complete file transfers
    var autoCompleteFileTransfer: Bool = true

    /// Error to return for file transfers (nil = success)
    var transferFileError: Error?

    // MARK: - Call Tracking

    private(set) var activateCallCount = 0
    private(set) var sendMessageDataCallCount = 0
    private(set) var transferUserInfoCallCount = 0
    private(set) var updateApplicationContextCallCount = 0

    private(set) var lastSentMessageData: Data?
    private(set) var lastTransferredUserInfo: [String: Any]?
    private(set) var lastUpdatedApplicationContext: [String: Any]?
    private(set) var lastTransferredFileURL: URL?
    private(set) var lastTransferredFileMetadata: [String: Any]?
    private(set) var transferFileCallCount = 0

    // MARK: - Session Lifecycle

    func activate() {
        activateCallCount += 1
        onActivate?()

        // Simulate activation completion
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
        // Not used in this implementation - we use sendMessageData
    }

    func sendMessageData(
        _ data: Data,
        replyHandler: ((Data) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {
        sendMessageDataCallCount += 1
        lastSentMessageData = data
        onSendMessageData?(data)

        guard autoReply else { return }

        let error = sendMessageError
        let response = sendMessageResponse
        let delayMs = sendMessageDelayMs

        // Execute synchronously for simplicity in tests
        if let error {
            errorHandler?(error)
        } else if let response {
            replyHandler?(response)
        } else {
            // Generate a default success response
            let wireResponse = WireResponse(
                outcome: .success(Data()),
                requestID: UUID(),
                timestamp: Date()
            )
            if let responseData = try? JSONEncoder().encode(wireResponse) {
                replyHandler?(responseData)
            }
        }
    }

    // MARK: - Background Transfers

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        updateApplicationContextCallCount += 1
        lastUpdatedApplicationContext = applicationContext
        onUpdateApplicationContext?(applicationContext)

        if let error = updateContextError {
            throw error
        }

        self.applicationContext = applicationContext
    }

    @discardableResult
    func transferUserInfo(_ userInfo: [String: Any]) -> WCSessionUserInfoTransfer {
        transferUserInfoCallCount += 1
        lastTransferredUserInfo = userInfo
        onTransferUserInfo?(userInfo)

        // Return a placeholder - we can't create a real WCSessionUserInfoTransfer
        return WCSession.default.transferUserInfo([:])
    }

    @discardableResult
    func transferFile(_ file: URL, metadata: [String: Any]?) -> WCSessionFileTransfer {
        transferFileCallCount += 1
        lastTransferredFileURL = file
        lastTransferredFileMetadata = metadata
        onTransferFile?(file, metadata)

        // Return a placeholder - we can't create a real WCSessionFileTransfer
        // In real tests, we'd need to use a more sophisticated mock or test on device
        return WCSession.default.transferFile(file, metadata: metadata)
    }

    // MARK: - Test Helpers

    /// Resets all call tracking and state
    func reset() {
        activateCallCount = 0
        sendMessageDataCallCount = 0
        transferUserInfoCallCount = 0
        updateApplicationContextCallCount = 0
        transferFileCallCount = 0

        lastSentMessageData = nil
        lastTransferredUserInfo = nil
        lastUpdatedApplicationContext = nil
        lastTransferredFileURL = nil
        lastTransferredFileMetadata = nil

        sendMessageError = nil
        sendMessageResponse = nil
        sendMessageDelayMs = 0
        autoReply = true
        updateContextError = nil
        transferFileError = nil
        autoCompleteFileTransfer = true

        applicationContext = [:]
        receivedApplicationContext = [:]
    }

    /// Simulates receiving a message from the counterpart
    func simulateReceivedMessage(_ data: Data, replyHandler: @escaping (Data) -> Void) {
        delegate?.session?(
            WCSession.default,
            didReceiveMessageData: data,
            replyHandler: replyHandler
        )
    }

    /// Simulates receiving a message without reply handler
    func simulateReceivedMessage(_ data: Data) {
        delegate?.session?(
            WCSession.default,
            didReceiveMessageData: data
        )
    }

    /// Simulates receiving user info
    func simulateReceivedUserInfo(_ userInfo: [String: Any]) {
        delegate?.session?(
            WCSession.default,
            didReceiveUserInfo: userInfo
        )
    }

    /// Simulates receiving application context
    func simulateReceivedApplicationContext(_ context: [String: Any]) {
        receivedApplicationContext = context
        delegate?.session?(
            WCSession.default,
            didReceiveApplicationContext: context
        )
    }

    /// Simulates reachability change
    func simulateReachabilityChange(_ reachable: Bool) {
        isReachable = reachable
    }

    /// Simulates receiving a file from the counterpart
    ///
    /// Note: This requires a real WCSessionFile which can only be created by the system.
    /// For testing file receipt, use integration tests on real devices.
    func simulateFileReceived(_ file: WCSessionFile) {
        delegate?.session?(WCSession.default, didReceive: file)
    }

    /// Simulates a file transfer completion
    ///
    /// Note: This requires a real WCSessionFileTransfer which can only be created by the system.
    /// For testing transfer completion, use integration tests on real devices.
    func simulateFileTransferFinished(_ transfer: WCSessionFileTransfer, error: Error?) {
        delegate?.session?(WCSession.default, didFinish: transfer, error: error)
    }
}
