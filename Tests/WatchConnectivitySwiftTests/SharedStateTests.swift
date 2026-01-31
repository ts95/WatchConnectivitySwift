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
        let mockSession = MockSession()
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
        let mockSession = MockSession()
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
        let mockSession = MockSession()
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
        let mockSession = MockSession()
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
        let mockSession = MockSession()
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
        let mockSession = MockSession()

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
}

// MARK: - Test Types

struct TestState: Codable, Sendable, Equatable {
    var count: Int
}
