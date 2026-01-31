//
//  WatchConnectionTests.swift
//  WatchConnectivitySwift
//

import Foundation
import Testing
@testable import WatchConnectivitySwift

/// Thread-safe counter for testing
@MainActor
final class TestCounter {
    var value = 0
    func increment() { value += 1 }
}

@Suite("WatchConnection")
struct WatchConnectionTests {

    // MARK: - Initialization Tests

    @Test("Initial state is correct")
    @MainActor
    func initialState() async {
        let mockSession = MockSession()
        let connection = WatchConnection(session: mockSession)

        #expect(connection.isReachable)
        #expect(connection.pendingRequestCount == 0)

        if case .success(.activated) = connection.activationState {
            // Expected
        } else {
            Issue.record("Expected activated state")
        }
    }

    @Test("Activation is called on init")
    @MainActor
    func activationOnInit() async throws {
        let mockSession = MockSession()
        _ = WatchConnection(session: mockSession)

        // Wait for activation
        try await Task.sleep(for: .milliseconds(50))

        #expect(mockSession.activateCallCount == 1)
    }

    // MARK: - Handler Registration Tests

    @Test("Register handler and process request")
    @MainActor
    func registerHandler() async throws {
        let mockSession = MockSession()
        let connection = WatchConnection(session: mockSession)

        // Define a test request
        struct TestRequest: WatchRequest {
            typealias Response = String
            let value: Int
        }

        let counter = TestCounter()

        connection.register(TestRequest.self) { [counter] request in
            await counter.increment()
            return "Response for \(request.value)"
        }

        // Simulate receiving the request
        let wireRequest = try WireRequest(request: TestRequest(value: 42), isFireAndForget: false)
        let requestData = try JSONEncoder().encode(wireRequest)

        var responseData: Data?
        mockSession.simulateReceivedMessage(requestData) { data in
            responseData = data
        }

        // Wait for async processing
        try await Task.sleep(for: .milliseconds(100))

        #expect(counter.value == 1)
        #expect(responseData != nil)

        // Verify response
        if let data = responseData {
            let wireResponse = try JSONDecoder().decode(WireResponse.self, from: data)
            if case .success(let payload) = wireResponse.outcome {
                let response = try JSONDecoder().decode(String.self, from: payload)
                #expect(response == "Response for 42")
            } else {
                Issue.record("Expected success response")
            }
        }
    }

    @Test("Unregistered handler returns error")
    @MainActor
    func unregisteredHandlerReturnsError() async throws {
        let mockSession = MockSession()
        let connection = WatchConnection(session: mockSession)

        struct UnknownRequest: WatchRequest {
            typealias Response = String
        }

        let wireRequest = try WireRequest(request: UnknownRequest(), isFireAndForget: false)
        let requestData = try JSONEncoder().encode(wireRequest)

        var responseData: Data?
        mockSession.simulateReceivedMessage(requestData) { data in
            responseData = data
        }

        try await Task.sleep(for: .milliseconds(100))

        #expect(responseData != nil)

        if let data = responseData {
            let wireResponse = try JSONDecoder().decode(WireResponse.self, from: data)
            if case .failure(let error) = wireResponse.outcome {
                if case .handlerNotRegistered = error {
                    // Expected
                } else {
                    Issue.record("Expected handlerNotRegistered error")
                }
            } else {
                Issue.record("Expected failure response")
            }
        }
    }

    // MARK: - Queue Management Tests

    @Test("Cancel all queued requests")
    @MainActor
    func cancelAllQueuedRequests() {
        let mockSession = MockSession()
        let connection = WatchConnection(session: mockSession)

        #expect(connection.pendingRequestCount == 0)
        connection.cancelAllQueuedRequests()
        #expect(connection.pendingRequestCount == 0)
    }

    // MARK: - Session Health Tests

    @Test("Initial health is healthy")
    @MainActor
    func initialHealthIsHealthy() {
        let mockSession = MockSession()
        let connection = WatchConnection(session: mockSession)

        #expect(connection.sessionHealth == .healthy)
    }

    // MARK: - Reachability Tests

    @Test("Reachability reflects session")
    @MainActor
    func reachabilityReflectsSession() {
        let mockSession = MockSession()
        let connection = WatchConnection(session: mockSession)

        #expect(connection.isReachable)

        mockSession.simulateReachabilityChange(false)
        // Note: In real tests, we'd need to trigger the KVO observation
    }

    // MARK: - Recovery Tests

    @Test("Attempt recovery triggers activation")
    @MainActor
    func attemptRecovery() async {
        let mockSession = MockSession()
        let connection = WatchConnection(session: mockSession)

        let initialActivateCount = mockSession.activateCallCount

        await connection.attemptRecovery()

        #expect(mockSession.activateCallCount > initialActivateCount)
    }

    // MARK: - Application Context Stream Tests

    @Test("Application context stream receives updates")
    @MainActor
    func applicationContextStream() async throws {
        let mockSession = MockSession()
        let connection = WatchConnection(session: mockSession)

        // Start consuming the stream
        var receivedContexts: [[String: Any]] = []
        let streamTask = Task {
            for await context in connection.receivedApplicationContexts {
                receivedContexts.append(context)
                if receivedContexts.count >= 1 { break }
            }
        }

        // Give the stream time to set up
        try await Task.sleep(for: .milliseconds(50))

        // Simulate receiving application context
        mockSession.simulateReceivedApplicationContext(["testKey": "testValue"])

        // Wait for async processing
        try await Task.sleep(for: .milliseconds(100))

        streamTask.cancel()

        #expect(receivedContexts.count == 1)
        #expect(receivedContexts.first?["testKey"] as? String == "testValue")
    }
}

// MARK: - Test Request Types

struct SimpleRequest: WatchRequest {
    typealias Response = SimpleResponse
    let id: String
}

struct SimpleResponse: Codable, Sendable, Equatable {
    let message: String
}

struct FireAndForgetTestRequest: FireAndForgetRequest {
    let eventName: String
}
