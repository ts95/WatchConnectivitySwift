//
//  DeliveryStrategyTests.swift
//  WatchConnectivitySwift
//

import Foundation
import Testing
@testable import WatchConnectivitySwift

@Suite("DeliveryStrategy")
struct DeliveryStrategyTests {

    // MARK: - Primary Method Tests

    @Test("messageWithUserInfoFallback primary method is message")
    func messageWithUserInfoFallbackPrimaryMethod() {
        let strategy = DeliveryStrategy.messageWithUserInfoFallback
        #expect(strategy.primaryMethod == .message)
    }

    @Test("messageWithContextFallback primary method is message")
    func messageWithContextFallbackPrimaryMethod() {
        let strategy = DeliveryStrategy.messageWithContextFallback
        #expect(strategy.primaryMethod == .message)
    }

    @Test("messageOnly primary method is message")
    func messageOnlyPrimaryMethod() {
        let strategy = DeliveryStrategy.messageOnly
        #expect(strategy.primaryMethod == .message)
    }

    @Test("userInfoOnly primary method is userInfo")
    func userInfoOnlyPrimaryMethod() {
        let strategy = DeliveryStrategy.userInfoOnly
        #expect(strategy.primaryMethod == .userInfo)
    }

    @Test("contextOnly primary method is context")
    func contextOnlyPrimaryMethod() {
        let strategy = DeliveryStrategy.contextOnly
        #expect(strategy.primaryMethod == .context)
    }

    // MARK: - Fallback Method Tests

    @Test("messageWithUserInfoFallback falls back to userInfo")
    func messageWithUserInfoFallbackFallbackMethod() {
        let strategy = DeliveryStrategy.messageWithUserInfoFallback
        #expect(strategy.fallbackMethod == .userInfo)
    }

    @Test("messageWithContextFallback falls back to context")
    func messageWithContextFallbackFallbackMethod() {
        let strategy = DeliveryStrategy.messageWithContextFallback
        #expect(strategy.fallbackMethod == .context)
    }

    @Test("messageOnly has no fallback")
    func messageOnlyFallbackMethod() {
        let strategy = DeliveryStrategy.messageOnly
        #expect(strategy.fallbackMethod == nil)
    }

    @Test("userInfoOnly has no fallback")
    func userInfoOnlyFallbackMethod() {
        let strategy = DeliveryStrategy.userInfoOnly
        #expect(strategy.fallbackMethod == nil)
    }

    @Test("contextOnly has no fallback")
    func contextOnlyFallbackMethod() {
        let strategy = DeliveryStrategy.contextOnly
        #expect(strategy.fallbackMethod == nil)
    }

    // MARK: - HasFallback Tests

    @Test("Strategies with fallback return true for hasFallback")
    func hasFallbackTrue() {
        #expect(DeliveryStrategy.messageWithUserInfoFallback.hasFallback)
        #expect(DeliveryStrategy.messageWithContextFallback.hasFallback)
    }

    @Test("Strategies without fallback return false for hasFallback")
    func hasFallbackFalse() {
        #expect(!DeliveryStrategy.messageOnly.hasFallback)
        #expect(!DeliveryStrategy.userInfoOnly.hasFallback)
        #expect(!DeliveryStrategy.contextOnly.hasFallback)
    }

    // MARK: - Codable Tests

    @Test("Strategies are codable")
    func strategyCodable() throws {
        let strategies: [DeliveryStrategy] = [
            .messageWithUserInfoFallback,
            .messageWithContextFallback,
            .messageOnly,
            .userInfoOnly,
            .contextOnly
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for strategy in strategies {
            let data = try encoder.encode(strategy)
            let decoded = try decoder.decode(DeliveryStrategy.self, from: data)
            #expect(strategy == decoded)
        }
    }

    // MARK: - Hashable Tests

    @Test("Strategies are hashable")
    func strategyHashable() {
        var set = Set<DeliveryStrategy>()

        set.insert(.messageWithUserInfoFallback)
        set.insert(.messageWithContextFallback)
        set.insert(.messageOnly)
        set.insert(.messageWithUserInfoFallback) // Duplicate

        #expect(set.count == 3)
    }
}

@Suite("DeliveryMethod")
struct DeliveryMethodTests {

    @Test("Methods have correct raw values")
    func methodRawValues() {
        #expect(DeliveryMethod.message.rawValue == "message")
        #expect(DeliveryMethod.userInfo.rawValue == "userInfo")
        #expect(DeliveryMethod.context.rawValue == "context")
    }

    @Test("Methods are codable")
    func methodCodable() throws {
        let methods: [DeliveryMethod] = [.message, .userInfo, .context]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for method in methods {
            let data = try encoder.encode(method)
            let decoded = try decoder.decode(DeliveryMethod.self, from: data)
            #expect(method == decoded)
        }
    }
}
