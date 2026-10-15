//
//  SharedState.swift
//  WatchConnectivitySwift
//

import Foundation
import Observation
@preconcurrency import WatchConnectivity

/// A synchronized state container for sharing data between iOS and watchOS.
///
/// `SharedState` provides automatic synchronization of state between devices
/// using WCSession's `applicationContext`. Updates are sent immediately with
/// no rate limiting - WCSession already coalesces rapid updates internally.
///
/// ## Example
///
/// ```swift
/// // Define your state type
/// struct UserPreferences: Codable, Sendable, Equatable {
///     var usesMetricUnits: Bool = true
///     var maxResults: Int = 10
/// }
///
/// // Create shared state connected to WatchConnection
/// let preferences = SharedState(
///     initialValue: UserPreferences(),
///     connection: watchConnection
/// )
///
/// // Update the state - syncs immediately
/// try preferences.update(UserPreferences(usesMetricUnits: false, maxResults: 20))
/// ```
///
/// ## Nested Observation
///
/// `SharedState` uses `@Observable`, so it works seamlessly when embedded
/// in other `@Observable` view models:
///
/// ```swift
/// @Observable @MainActor
/// final class ViewModel {
///     private let sharedState: SharedState<MyState>
///
///     var items: [Item] { sharedState.value.items }  // Just works
/// }
/// ```
@Observable
@MainActor
public final class SharedState<State: Codable & Sendable & Equatable> {

    // MARK: - Observable Properties

    /// The current state value.
    public private(set) var value: State

    /// The error from the last failed sync attempt, or `nil` if the last sync succeeded.
    ///
    /// This is set when `updateApplicationContext` fails (e.g., data too large,
    /// session not activated). It is cleared on the next successful `update()` call.
    public private(set) var lastSyncError: WatchConnectionError?

    // MARK: - Private Properties

    private let connection: WatchConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let stateKey: String
    private var observationTask: Task<Void, Never>?
    /// The last write of this state to the application context, which the next one waits for
    private var syncTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a new SharedState.
    ///
    /// - Parameters:
    ///   - initialValue: The initial state value.
    ///   - connection: The WatchConnection to use for synchronization.
    ///   - encoder: JSON encoder for serialization.
    ///   - decoder: JSON decoder for deserialization.
    public init(
        initialValue: State,
        connection: WatchConnection,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.value = initialValue
        self.connection = connection
        self.encoder = encoder
        self.decoder = decoder
        self.stateKey = "WatchConnectivitySwift.\(String(describing: State.self))"

        // Try to restore from received application context
        restoreFromContext()

        // Start observing incoming context updates
        startObserving()
    }

    isolated deinit {
        observationTask?.cancel()
    }

    // MARK: - Public Methods

    /// Updates the state and immediately syncs to the counterpart device.
    ///
    /// - Parameter newValue: The new state value.
    /// - Throws: `WatchConnectionError.encodingFailed` if serialization fails.
    public func update(_ newValue: State) throws {
        guard newValue != value else { return }

        // Apply locally
        value = newValue

        // Sync to remote immediately
        try syncToRemote()
    }

    // MARK: - Private Methods

    private func restoreFromContext() {
        let context = connection.session.receivedApplicationContext
        guard let data = context[stateKey] as? Data,
              let remoteState = try? decoder.decode(State.self, from: data) else {
            return
        }
        value = remoteState
    }

    private func startObserving() {
        // The stream is taken out before the loop, and `self` only held for one context at a
        // time, so that waiting for the next context doesn't keep this object alive
        let contexts = connection.receivedApplicationContexts
        observationTask = Task { [weak self] in
            for await context in contexts {
                guard let self else { return }
                guard let data = context[self.stateKey] as? Data,
                      let remoteState = try? self.decoder.decode(State.self, from: data),
                      remoteState != self.value else {
                    continue
                }
                self.value = remoteState
            }
        }
    }

    private func syncToRemote() throws {
        guard connection.session.activationState == .activated else {
            lastSyncError = .notActivated
            return
        }

        let data = try encoder.encode(value)
        let session = connection.session
        let key = stateKey

        // Run updateApplicationContext off the main thread, where it can block. Each write
        // waits for the one before it, so that an older value can't land after a newer one.
        let previous = syncTask
        syncTask = Task { [weak self] in
            await previous?.value
            do {
                try await ApplicationContextWriter.shared.write(data, forKey: key, to: session)
                self?.lastSyncError = nil
            } catch {
                self?.lastSyncError = WatchConnectionError(error: error)
            }
        }
    }
}

/// Writes keys into the application context one at a time.
///
/// The context is written whole, so writing a key means reading the context, changing it
/// and writing it back. Two of those at once (from two `SharedState`s) would each write back
/// a context without the other's key, and one key would be lost.
actor ApplicationContextWriter {
    static let shared = ApplicationContextWriter()

    func write(_ data: Data, forKey key: String, to session: any WCSessionProviding) throws {
        var context = session.applicationContext
        context[key] = data
        try session.updateApplicationContext(context)
    }
}
