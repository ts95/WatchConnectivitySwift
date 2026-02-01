//
//  SharedStateTests.swift
//  WatchConnectivitySwift
//

import Foundation
import Testing
@testable import WatchConnectivitySwift

@Suite("SharedState")
struct SharedStateTests {

    // MARK: - Initialization Tests

    @Test("Initial value is set correctly")
    @MainActor
    func initialValue() {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)
        let state = SharedState(
            initialValue: TestState(count: 0),
            connection: connection
        )

        #expect(state.value.count == 0)
    }

    // MARK: - Update Tests

    @Test("Local update applies immediately")
    @MainActor
    func localUpdate() async throws {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)
        let state = SharedState(
            initialValue: TestState(count: 0),
            connection: connection
        )

        try state.update(TestState(count: 5))

        // Wait for background sync task to run
        try await Task.sleep(for: .milliseconds(50))

        #expect(state.value.count == 5)
        #expect(mockSession.updateApplicationContextCallCount == 1)
    }

    @Test("Multiple updates each trigger sync")
    @MainActor
    func multipleUpdates() async throws {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)
        let state = SharedState(
            initialValue: TestState(count: 0),
            connection: connection
        )

        try state.update(TestState(count: 1))
        try state.update(TestState(count: 2))
        try state.update(TestState(count: 3))

        // Wait for background sync tasks to run
        try await Task.sleep(for: .milliseconds(100))

        #expect(state.value.count == 3)
        // Each update triggers a sync immediately (no rate limiting)
        #expect(mockSession.updateApplicationContextCallCount == 3)
    }

    @Test("No update for same value")
    @MainActor
    func noUpdateForSameValue() throws {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)
        let state = SharedState(
            initialValue: TestState(count: 5),
            connection: connection
        )

        try state.update(TestState(count: 5))

        #expect(mockSession.updateApplicationContextCallCount == 0)
    }

    // MARK: - Context Reception Tests

    @Test("Receives application context updates")
    @MainActor
    func receivesContextUpdates() async throws {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)
        let state = SharedState(
            initialValue: TestState(count: 0),
            connection: connection
        )

        // Simulate receiving application context with updated state
        let encoder = JSONEncoder()
        let remoteState = TestState(count: 42)
        let stateKey = "WatchConnectivitySwift.TestState"
        let remoteData = try encoder.encode(remoteState)

        mockSession.simulateReceivedApplicationContext([stateKey: remoteData])

        // Wait for async processing
        try await Task.sleep(for: .milliseconds(100))

        #expect(state.value.count == 42)
    }

    // MARK: - Restoration Tests

    @Test("Restores from received application context on init")
    @MainActor
    func restoresFromContext() throws {
        let mockSession = MockWCSession()

        // Pre-populate the received application context
        let encoder = JSONEncoder()
        let existingState = TestState(count: 99)
        let stateKey = "WatchConnectivitySwift.TestState"
        let existingData = try encoder.encode(existingState)
        mockSession.receivedApplicationContext = [stateKey: existingData]

        let connection = WatchConnection(session: mockSession)
        let state = SharedState(
            initialValue: TestState(count: 0),
            connection: connection
        )

        // Should have restored from context
        #expect(state.value.count == 99)
    }

    // MARK: - Multiple SharedState Tests (Multicast)

    @Test("Multiple SharedState instances all receive context updates")
    @MainActor
    func multipleSharedStateInstances() async throws {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)

        // Create three SharedState instances sharing the same connection
        // This simulates the real-world scenario where multiple SharedState
        // instances are created for different state types
        let state1 = SharedState(
            initialValue: TestState(count: 0),
            connection: connection
        )

        let state2 = SharedState(
            initialValue: AnotherState(name: "initial"),
            connection: connection
        )

        let state3 = SharedState(
            initialValue: ThirdState(enabled: false),
            connection: connection
        )

        // Simulate receiving updates for all three state types
        let encoder = JSONEncoder()

        // Update TestState
        let testStateKey = "WatchConnectivitySwift.TestState"
        let testStateData = try encoder.encode(TestState(count: 42))
        mockSession.simulateReceivedApplicationContext([testStateKey: testStateData])

        try await Task.sleep(for: .milliseconds(100))

        // Update AnotherState
        let anotherStateKey = "WatchConnectivitySwift.AnotherState"
        let anotherStateData = try encoder.encode(AnotherState(name: "updated"))
        mockSession.simulateReceivedApplicationContext([anotherStateKey: anotherStateData])

        try await Task.sleep(for: .milliseconds(100))

        // Update ThirdState
        let thirdStateKey = "WatchConnectivitySwift.ThirdState"
        let thirdStateData = try encoder.encode(ThirdState(enabled: true))
        mockSession.simulateReceivedApplicationContext([thirdStateKey: thirdStateData])

        try await Task.sleep(for: .milliseconds(100))

        // All three should have received their respective updates
        #expect(state1.value.count == 42, "TestState should be updated to count=42")
        #expect(state2.value.name == "updated", "AnotherState should be updated to name='updated'")
        #expect(state3.value.enabled == true, "ThirdState should be updated to enabled=true")
    }

    @Test("Late SharedState instance receives future updates")
    @MainActor
    func lateSharedStateInstance() async throws {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)

        // Create first SharedState
        let state1 = SharedState(
            initialValue: TestState(count: 0),
            connection: connection
        )

        // Send first update - only state1 is listening
        let encoder = JSONEncoder()
        let testStateKey = "WatchConnectivitySwift.TestState"
        let firstData = try encoder.encode(TestState(count: 10))
        mockSession.simulateReceivedApplicationContext([testStateKey: firstData])

        try await Task.sleep(for: .milliseconds(100))

        // Create second SharedState (late subscriber)
        let state2 = SharedState(
            initialValue: TestState(count: 0),
            connection: connection
        )

        // Second update - both are listening
        let secondData = try encoder.encode(TestState(count: 20))
        mockSession.simulateReceivedApplicationContext([testStateKey: secondData])

        try await Task.sleep(for: .milliseconds(100))

        // Both should have the latest value (20)
        #expect(state1.value.count == 20, "state1 should have count=20")
        #expect(state2.value.count == 20, "state2 should have count=20")
    }

    @Test("Multiple SharedState instances for same type all sync")
    @MainActor
    func multipleSharedStateSameType() async throws {
        let mockSession = MockWCSession()
        let connection = WatchConnection(session: mockSession)

        // Create multiple SharedState instances for the same type
        // This simulates the scenario described in the bug report
        let state1 = SharedState(
            initialValue: TestState(count: 0),
            connection: connection
        )

        let state2 = SharedState(
            initialValue: TestState(count: 0),
            connection: connection
        )

        let state3 = SharedState(
            initialValue: TestState(count: 0),
            connection: connection
        )

        // Simulate receiving an update
        let encoder = JSONEncoder()
        let testStateKey = "WatchConnectivitySwift.TestState"
        let stateData = try encoder.encode(TestState(count: 100))
        mockSession.simulateReceivedApplicationContext([testStateKey: stateData])

        try await Task.sleep(for: .milliseconds(150))

        // All three should receive the update
        // Before the fix, only state3 (the last one) would receive updates
        #expect(state1.value.count == 100, "state1 should receive update (was broken before multicast fix)")
        #expect(state2.value.count == 100, "state2 should receive update (was broken before multicast fix)")
        #expect(state3.value.count == 100, "state3 should receive update")
    }
}

// MARK: - Test Types

struct TestState: Codable, Sendable, Equatable {
    var count: Int
}

struct AnotherState: Codable, Sendable, Equatable {
    var name: String
}

struct ThirdState: Codable, Sendable, Equatable {
    var enabled: Bool
}
