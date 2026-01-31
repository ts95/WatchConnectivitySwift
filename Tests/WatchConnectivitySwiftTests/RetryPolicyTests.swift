//
//  RetryPolicyTests.swift
//  WatchConnectivitySwift
//

import Foundation
import Testing
@testable import WatchConnectivitySwift

@Suite("RetryPolicy")
struct RetryPolicyTests {

    // MARK: - Predefined Policy Tests

    @Test("Default policy has expected values")
    func defaultPolicy() {
        let policy = RetryPolicy.default

        #expect(policy.maxAttempts == 3)
        #expect(policy.timeout == .seconds(10))
    }

    @Test("None policy has single attempt")
    func nonePolicy() {
        let policy = RetryPolicy.none

        #expect(policy.maxAttempts == 1)
        #expect(policy.timeout == .seconds(10))
    }

    @Test("Patient policy has many attempts")
    func patientPolicy() {
        let policy = RetryPolicy.patient

        #expect(policy.maxAttempts == 5)
        #expect(policy.timeout == .seconds(30))
    }

    // MARK: - shouldRetry Tests

    @Test("shouldRetry returns true for transient errors")
    func shouldRetryTransientErrors() {
        let policy = RetryPolicy.default

        // Should retry on notReachable
        #expect(policy.shouldRetry(WatchConnectionError.notReachable))

        // Should retry on delivery failed
        #expect(policy.shouldRetry(WatchConnectionError.deliveryFailed(reason: "test")))

        // Should retry on reply failed
        #expect(policy.shouldRetry(WatchConnectionError.replyFailed(reason: "test")))
    }

    @Test("shouldRetry returns false for non-transient errors")
    func shouldNotRetryNonTransientErrors() {
        let policy = RetryPolicy.default

        // Should NOT retry on timeout
        #expect(!policy.shouldRetry(WatchConnectionError.timeout))

        // Should NOT retry on encoding errors
        #expect(!policy.shouldRetry(WatchConnectionError.encodingFailed(description: "test")))

        // Should NOT retry on handler not registered
        #expect(!policy.shouldRetry(WatchConnectionError.handlerNotRegistered(requestType: "Test")))
    }

    // MARK: - Initialization Tests

    @Test("Custom policy with valid values")
    func customPolicy() {
        let policy = RetryPolicy(maxAttempts: 10, timeout: .seconds(60))

        #expect(policy.maxAttempts == 10)
        #expect(policy.timeout == .seconds(60))
    }

    @Test("maxAttempts is clamped to minimum of 1")
    func maxAttemptsClampedToMinimum() {
        let policy = RetryPolicy(maxAttempts: 0, timeout: .seconds(5))

        #expect(policy.maxAttempts == 1)
    }
}
