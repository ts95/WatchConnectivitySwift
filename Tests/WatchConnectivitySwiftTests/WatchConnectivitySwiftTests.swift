//
//  WatchConnectivitySwiftTests.swift
//  WatchConnectivitySwift
//

import Testing
import Foundation
@testable import WatchConnectivitySwift

@Suite("WatchConnectionError")
struct WatchConnectionErrorTests {

    // MARK: - Codable Tests

    @Test("All errors are codable")
    func errorCodable() throws {
        let errors: [WatchConnectionError] = [
            .notActivated,
            .notReachable,
            .notPaired,
            .watchAppNotInstalled,
            .deliveryFailed(reason: "Test failure"),
            .timeout,
            .cancelled,
            .replyFailed(reason: "Reply error"),
            .encodingFailed(description: "Encoding issue"),
            .decodingFailed(description: "Decoding issue"),
            .handlerNotRegistered(requestType: "TestRequest"),
            .handlerError(description: "Handler threw"),
            .remoteError(description: "Remote failed"),
            .sessionError(code: 123, description: "Session error"),
            .sessionUnhealthy(reason: "Unhealthy")
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for error in errors {
            let data = try encoder.encode(error)
            let decoded = try decoder.decode(WatchConnectionError.self, from: data)
            #expect(error == decoded)
        }
    }

    // MARK: - Hashable Tests

    @Test("Errors are hashable")
    func errorHashable() {
        var set = Set<WatchConnectionError>()

        set.insert(.notActivated)
        set.insert(.notReachable)
        set.insert(.timeout)
        set.insert(.notActivated) // Duplicate

        #expect(set.count == 3)
    }

    // MARK: - LocalizedDescription Tests

    @Test("Errors have localized descriptions")
    func localizedDescriptions() {
        #expect(!WatchConnectionError.notActivated.localizedDescription.isEmpty)
        #expect(!WatchConnectionError.notReachable.localizedDescription.isEmpty)
        #expect(!WatchConnectionError.timeout.localizedDescription.isEmpty)
    }
}

@Suite("DeliveryMode")
struct DeliveryModeTests {

    @Test("queued does not require immediate reachability")
    func queued() {
        let mode = DeliveryMode.queued
        #expect(!mode.requiresImmediateReachability)
    }

    @Test("immediate requires immediate reachability")
    func immediate() {
        let mode = DeliveryMode.immediate
        #expect(mode.requiresImmediateReachability)
    }

    @Test("DeliveryMode is hashable")
    func hashable() {
        var set = Set<DeliveryMode>()

        set.insert(.immediate)
        set.insert(.queued)
        set.insert(.immediate) // Duplicate

        #expect(set.count == 2)
    }
}
