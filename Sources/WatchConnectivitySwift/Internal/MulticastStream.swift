//
//  MulticastStream.swift
//  WatchConnectivitySwift
//

import Foundation

/// A broadcast mechanism that supports multiple AsyncStream consumers.
///
/// Unlike a single AsyncStream.Continuation, this allows multiple subscribers
/// to receive the same values. Each call to `makeStream()` returns a new
/// AsyncStream that receives all future values.
@MainActor
final class MulticastStream<Element: Sendable> {
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    /// Creates a new AsyncStream that receives all values yielded to this multicast.
    func makeStream() -> AsyncStream<Element> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Yields a value to all active streams.
    func yield(_ value: Element) {
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    /// Finishes all active streams.
    func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
