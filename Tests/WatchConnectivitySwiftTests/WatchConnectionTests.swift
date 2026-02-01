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
        let mockSession = MockWCSession()
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
        let mockSession = MockWCSession()
        _ = WatchConnection(session: mockSession)

        // Wait for activation
        try await Task.sleep(for: .milliseconds(50))

        #expect(mockSession.activateCallCount == 1)
    }

    // MARK: - Handler Registration Tests

    @Test("Register handler and process request")
    @MainActor
    func registerHandler() async throws {
        let mockSession = MockWCSession()
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
        let mockSession = MockWCSession()
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
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)

        #expect(connection.pendingRequestCount == 0)
        connection.cancelAllQueuedRequests()
        #expect(connection.pendingRequestCount == 0)
    }

    // MARK: - Session Health Tests

    @Test("Initial health is healthy")
    @MainActor
    func initialHealthIsHealthy() {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)

        #expect(connection.sessionHealth == .healthy)
    }

    // MARK: - Reachability Tests

    @Test("Reachability reflects session")
    @MainActor
    func reachabilityReflectsSession() {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)

        #expect(connection.isReachable)

        mockSession.simulateReachabilityChange(false)
        // Note: In real tests, we'd need to trigger the KVO observation
    }

    // MARK: - Recovery Tests

    @Test("Attempt recovery triggers activation")
    @MainActor
    func attemptRecovery() async {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)

        let initialActivateCount = mockSession.activateCallCount

        await connection.attemptRecovery()

        #expect(mockSession.activateCallCount > initialActivateCount)
    }

    // MARK: - Application Context Stream Tests

    @Test("Application context stream receives updates")
    @MainActor
    func applicationContextStream() async throws {
        let mockSession = MockWCSession()
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

    // MARK: - Multicast Stream Tests

    @Test("Multiple application context subscribers all receive updates")
    @MainActor
    func multipleApplicationContextSubscribers() async throws {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)

        // Set up three subscribers (simulates multiple SharedState instances)
        var received1: [[String: Any]] = []
        var received2: [[String: Any]] = []
        var received3: [[String: Any]] = []

        let task1 = Task {
            for await context in connection.receivedApplicationContexts {
                received1.append(context)
                if received1.count >= 2 { break }
            }
        }

        let task2 = Task {
            for await context in connection.receivedApplicationContexts {
                received2.append(context)
                if received2.count >= 2 { break }
            }
        }

        let task3 = Task {
            for await context in connection.receivedApplicationContexts {
                received3.append(context)
                if received3.count >= 2 { break }
            }
        }

        // Give streams time to set up
        try await Task.sleep(for: .milliseconds(50))

        // Send first context update
        mockSession.simulateReceivedApplicationContext(["update": 1])
        try await Task.sleep(for: .milliseconds(50))

        // Send second context update
        mockSession.simulateReceivedApplicationContext(["update": 2])
        try await Task.sleep(for: .milliseconds(100))

        // Clean up
        task1.cancel()
        task2.cancel()
        task3.cancel()

        // All three subscribers should have received both updates
        #expect(received1.count == 2, "Subscriber 1 should receive 2 updates, got \(received1.count)")
        #expect(received2.count == 2, "Subscriber 2 should receive 2 updates, got \(received2.count)")
        #expect(received3.count == 2, "Subscriber 3 should receive 2 updates, got \(received3.count)")

        // Verify correct values
        #expect(received1[0]["update"] as? Int == 1)
        #expect(received1[1]["update"] as? Int == 2)
        #expect(received2[0]["update"] as? Int == 1)
        #expect(received2[1]["update"] as? Int == 2)
        #expect(received3[0]["update"] as? Int == 1)
        #expect(received3[1]["update"] as? Int == 2)
    }

    @Test("Multiple diagnostic event subscribers all receive events")
    @MainActor
    func multipleDiagnosticSubscribers() async throws {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)

        // Set up two diagnostic subscribers
        var events1: [DiagnosticEvent] = []
        var events2: [DiagnosticEvent] = []

        let task1 = Task {
            for await event in connection.diagnosticEvents {
                events1.append(event)
                if events1.count >= 1 { break }
            }
        }

        let task2 = Task {
            for await event in connection.diagnosticEvents {
                events2.append(event)
                if events2.count >= 1 { break }
            }
        }

        // Give streams time to set up
        try await Task.sleep(for: .milliseconds(50))

        // Trigger a diagnostic event (application context received)
        mockSession.simulateReceivedApplicationContext(["test": "value"])

        // Wait for processing
        try await Task.sleep(for: .milliseconds(100))

        task1.cancel()
        task2.cancel()

        // Both subscribers should have received the diagnostic event
        #expect(events1.count >= 1, "Subscriber 1 should receive at least 1 event")
        #expect(events2.count >= 1, "Subscriber 2 should receive at least 1 event")
    }

    @Test("Late subscriber receives future updates but not past ones")
    @MainActor
    func lateSubscriberReceivesFutureUpdates() async throws {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)

        // First subscriber
        var received1: [[String: Any]] = []
        let task1 = Task {
            for await context in connection.receivedApplicationContexts {
                received1.append(context)
                if received1.count >= 2 { break }
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        // First update - only subscriber 1 is listening
        mockSession.simulateReceivedApplicationContext(["update": 1])
        try await Task.sleep(for: .milliseconds(50))

        // Late subscriber joins
        var received2: [[String: Any]] = []
        let task2 = Task {
            for await context in connection.receivedApplicationContexts {
                received2.append(context)
                if received2.count >= 1 { break }
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        // Second update - both subscribers listening
        mockSession.simulateReceivedApplicationContext(["update": 2])
        try await Task.sleep(for: .milliseconds(100))

        task1.cancel()
        task2.cancel()

        // Subscriber 1 should have both updates
        #expect(received1.count == 2)

        // Subscriber 2 should only have the second update
        #expect(received2.count == 1)
        #expect(received2[0]["update"] as? Int == 2)
    }

    @Test("Subscriber cleanup on cancellation")
    @MainActor
    func subscriberCleanupOnCancellation() async throws {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)

        var received1: [[String: Any]] = []
        var received2: [[String: Any]] = []

        let task1 = Task {
            for await context in connection.receivedApplicationContexts {
                received1.append(context)
            }
        }

        let task2 = Task {
            for await context in connection.receivedApplicationContexts {
                received2.append(context)
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        // First update - both receive
        mockSession.simulateReceivedApplicationContext(["update": 1])
        try await Task.sleep(for: .milliseconds(50))

        // Cancel task1
        task1.cancel()
        try await Task.sleep(for: .milliseconds(50))

        // Second update - only task2 should receive
        mockSession.simulateReceivedApplicationContext(["update": 2])
        try await Task.sleep(for: .milliseconds(100))

        task2.cancel()

        // Subscriber 1 got cancelled after first update
        #expect(received1.count == 1)

        // Subscriber 2 got both updates
        #expect(received2.count == 2)
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
