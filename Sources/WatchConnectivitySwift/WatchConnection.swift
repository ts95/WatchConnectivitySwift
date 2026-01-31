//
//  WatchConnection.swift
//  WatchConnectivitySwift
//

import Foundation
@preconcurrency import WatchConnectivity
import Combine

/// The main entry point for watch connectivity communication.
///
/// `WatchConnection` provides a type-safe, async/await API for sending requests
/// between iOS and watchOS devices. It handles session management, retries,
/// fallback strategies, and offline queueing automatically.
///
/// ## Usage
///
/// ```swift
/// // Create a connection (typically store as a singleton or in your app's environment)
/// let connection = WatchConnection()
///
/// // Register handlers for incoming requests (on the receiving side)
/// connection.register(FetchRecipeRequest.self) { request in
///     return try await fetchRecipe(id: request.id)
/// }
///
/// // Send requests (on the sending side)
/// let recipe: Recipe = try await connection.send(FetchRecipeRequest(id: "123"))
/// ```
///
/// ## Thread Safety
///
/// `WatchConnection` is `@MainActor` isolated and uses `ObservableObject` for
/// SwiftUI integration. All published properties update on the main thread.
@MainActor
public final class WatchConnection: NSObject, ObservableObject {

    // MARK: - Published State

    /// The current activation state of the WCSession.
    @Published public private(set) var activationState: Result<WCSessionActivationState, WatchConnectionError>

    /// Whether the counterpart app is reachable for live messaging.
    @Published public private(set) var isReachable: Bool = false

    /// Number of requests waiting to be sent.
    @Published public private(set) var pendingRequestCount: Int = 0

    /// Number of file transfers in progress.
    @Published public private(set) var activeFileTransferCount: Int = 0

    /// The current health state of the session.
    ///
    /// Use this to detect persistent connectivity issues and guide users
    /// toward recovery actions (e.g., restarting their Watch).
    @Published public private(set) var sessionHealth: SessionHealth = .healthy

    #if os(iOS)
    /// Whether an Apple Watch is paired with this iPhone.
    @Published public private(set) var isPaired: Bool = false

    /// Whether the Watch app is installed on the paired Apple Watch.
    @Published public private(set) var isWatchAppInstalled: Bool = false
    #endif

    // MARK: - File Transfer Callbacks

    /// Called when a file is received from the counterpart device.
    ///
    /// **Important:** The file at `ReceivedFile.fileURL` will be deleted by the system
    /// after this handler returns. You must synchronously move or copy the file to a
    /// permanent location if you want to keep it.
    ///
    /// ```swift
    /// connection.onFileReceived = { file in
    ///     let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ///     let destination = documents.appendingPathComponent(file.fileURL.lastPathComponent)
    ///     try? FileManager.default.moveItem(at: file.fileURL, to: destination)
    /// }
    /// ```
    public var onFileReceived: (@MainActor @Sendable (ReceivedFile) -> Void)?

    /// Stream of received files from the counterpart device.
    ///
    /// This provides an alternative to `onFileReceived` using async/await patterns.
    ///
    /// **Important:** You must process the file synchronously within the for-await loop body.
    /// The file at `ReceivedFile.fileURL` will be deleted after your processing completes.
    ///
    /// ```swift
    /// Task {
    ///     for await file in connection.receivedFiles {
    ///         let destination = documentsDirectory.appendingPathComponent(file.fileURL.lastPathComponent)
    ///         try? FileManager.default.moveItem(at: file.fileURL, to: destination)
    ///     }
    /// }
    /// ```
    public var receivedFiles: AsyncStream<ReceivedFile> {
        AsyncStream { continuation in
            self.receivedFilesContinuation = continuation
        }
    }

    // MARK: - Application Context Stream

    /// Stream of application contexts received from the counterpart device.
    ///
    /// Use this to observe incoming application context updates. This is the
    /// delegate-based approach (via `session(_:didReceiveApplicationContext:)`)
    /// which is more reliable than KVO.
    ///
    /// ```swift
    /// Task {
    ///     for await context in connection.receivedApplicationContexts {
    ///         if let data = context["myKey"] as? Data {
    ///             // Process the data
    ///         }
    ///     }
    /// }
    /// ```
    public var receivedApplicationContexts: AsyncStream<[String: Any]> {
        AsyncStream { continuation in
            self.receivedApplicationContextsContinuation = continuation
        }
    }

    // MARK: - Diagnostics

    /// Stream of diagnostic events for debugging connectivity issues.
    ///
    /// Subscribe to this stream during development to understand
    /// connectivity behavior and troubleshoot issues.
    ///
    /// ```swift
    /// Task {
    ///     for await event in connection.diagnosticEvents {
    ///         print(event)
    ///     }
    /// }
    /// ```
    public var diagnosticEvents: AsyncStream<DiagnosticEvent> {
        AsyncStream { continuation in
            self.diagnosticContinuation = continuation
        }
    }

    // MARK: - Session Access

    /// The underlying session for direct access when needed.
    ///
    /// Use this to access session properties like `applicationContext` or
    /// `receivedApplicationContext` directly.
    public var session: any SessionProviding {
        _session
    }

    // MARK: - Private Properties

    private let _session: any SessionProviding
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Type-erased handler storage: [TypeName: (Data) async throws -> Data]
    private var handlers: [String: @Sendable (Data) async throws -> Data] = [:]

    /// Pending continuations waiting for responses: [RequestID: Continuation]
    private var pendingRequests: [UUID: CheckedContinuation<Data, any Error>] = [:]

    /// Queue for requests waiting to be sent when offline
    private var requestQueue: [QueuedRequest] = []

    /// Active file transfers being tracked
    private var activeFileTransfers: [WCSessionFileTransfer: FileTransfer] = [:]

    /// Health tracker for monitoring session health
    private let healthTracker = HealthTracker()

    /// Continuation for emitting diagnostic events
    private var diagnosticContinuation: AsyncStream<DiagnosticEvent>.Continuation?

    /// Continuation for emitting received files
    private var receivedFilesContinuation: AsyncStream<ReceivedFile>.Continuation?

    /// Continuation for emitting received application contexts
    private var receivedApplicationContextsContinuation: AsyncStream<[String: Any]>.Continuation?

    /// KVO observations
    private var reachabilityObservation: NSKeyValueObservation?
    #if os(iOS)
    private var isPairedObservation: NSKeyValueObservation?
    private var isWatchAppInstalledObservation: NSKeyValueObservation?
    #endif

    /// Task for processing the request queue
    private var queueProcessingTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a new WatchConnection.
    ///
    /// - Parameters:
    ///   - session: The WCSession to use. Defaults to `WCSession.default`.
    ///   - encoder: JSON encoder for serializing requests. Defaults to a new encoder.
    ///   - decoder: JSON decoder for deserializing responses. Defaults to a new decoder.
    public init(
        session: any SessionProviding = WCSession.default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self._session = session
        self.encoder = encoder
        self.decoder = decoder
        self.activationState = .success(session.activationState)
        self.isReachable = session.isReachable

        #if os(iOS)
        self.isPaired = session.isPaired
        self.isWatchAppInstalled = session.isWatchAppInstalled
        #endif

        super.init()

        setupSession()
        setupObservations()
    }

    deinit {
        reachabilityObservation?.invalidate()
        #if os(iOS)
        isPairedObservation?.invalidate()
        isWatchAppInstalledObservation?.invalidate()
        #endif
        queueProcessingTask?.cancel()
    }

    // MARK: - Setup

    private func setupSession() {
        // Only activate if supported
        if WCSession.isSupported() {
            _session.delegate = self
            _session.activate()
        }
    }

    private func setupObservations() {
        guard let wcSession = _session as? WCSession else { return }

        // Observe reachability changes (no delegate method for this)
        reachabilityObservation = wcSession.observe(\.isReachable, options: [.new, .old]) { [weak self] _, change in
            Task { @MainActor [weak self] in
                guard let self, let isReachable = change.newValue else { return }
                let previousValue = change.oldValue ?? false
                self.isReachable = isReachable

                // Emit diagnostic event if changed
                if isReachable != previousValue {
                    self.emitDiagnostic(.reachabilityChanged(isReachable: isReachable))
                }

                if isReachable {
                    self.processQueuedRequests()
                }
            }
        }

        #if os(iOS)
        isPairedObservation = wcSession.observe(\.isPaired, options: [.new]) { [weak self] _, change in
            Task { @MainActor [weak self] in
                guard let self, let isPaired = change.newValue else { return }
                self.isPaired = isPaired
            }
        }

        isWatchAppInstalledObservation = wcSession.observe(\.isWatchAppInstalled, options: [.new]) { [weak self] _, change in
            Task { @MainActor [weak self] in
                guard let self, let isInstalled = change.newValue else { return }
                self.isWatchAppInstalled = isInstalled
            }
        }
        #endif
    }

    // MARK: - Sending Requests

    /// Sends a request and returns the typed response.
    ///
    /// The response type is automatically inferred from the request's `Response` associated type.
    ///
    /// - Parameters:
    ///   - request: The request to send.
    ///   - strategy: Delivery strategy with fallback options. Default is `.messageWithUserInfoFallback`.
    ///   - delivery: When to deliver: `.immediate` fails if not reachable, `.queued` waits. Default is `.queued`.
    ///   - retryPolicy: Retry and timeout configuration. Default is `.default`.
    /// - Returns: The typed response from the remote device.
    /// - Throws: `WatchConnectionError` if the request fails.
    public func send<R: WatchRequest>(
        _ request: R,
        strategy: DeliveryStrategy = .messageWithUserInfoFallback,
        delivery: DeliveryMode = .queued,
        retryPolicy: RetryPolicy = .default
    ) async throws -> R.Response {
        // Ensure session is activated
        try await ensureActivated()

        // Check immediate reachability requirement
        if delivery.requiresImmediateReachability && !isReachable {
            throw WatchConnectionError.notReachable
        }

        // Create wire request
        let wireRequest = try WireRequest(request: request, isFireAndForget: false)

        // Send with retry logic
        let responseData = try await sendWithRetry(
            wireRequest: wireRequest,
            strategy: strategy,
            delivery: delivery,
            retryPolicy: retryPolicy,
            timeout: retryPolicy.timeout
        )

        // Decode response
        let wireResponse = try decoder.decode(WireResponse.self, from: responseData)

        // Handle response outcome
        switch wireResponse.outcome {
        case .success(let data):
            return try decoder.decode(R.Response.self, from: data)
        case .failure(let error):
            throw error
        }
    }

    /// Sends a fire-and-forget request (no response expected).
    ///
    /// This method returns immediately after queueing the request. The response
    /// (if any) is discarded when received.
    ///
    /// - Parameters:
    ///   - request: The fire-and-forget request to send.
    ///   - strategy: Delivery strategy. Default is `.messageWithUserInfoFallback`.
    public func send<R: FireAndForgetRequest>(
        _ request: R,
        strategy: DeliveryStrategy = .messageWithUserInfoFallback
    ) async {
        do {
            // Ensure session is activated (but don't throw, just return)
            try await ensureActivated()

            // Create wire request
            let wireRequest = try WireRequest(request: request, isFireAndForget: true)

            // Send without waiting for response
            try await sendFireAndForget(wireRequest: wireRequest, strategy: strategy)
        } catch {
            // Fire-and-forget silently ignores errors
        }
    }

    // MARK: - Handler Registration

    /// Registers a handler for a specific request type.
    ///
    /// When a request of this type is received from the remote device, the handler
    /// is invoked and its return value is sent back as the response.
    ///
    /// - Parameters:
    ///   - requestType: The type of request to handle.
    ///   - handler: An async closure that processes the request and returns a response.
    public func register<R: WatchRequest>(
        _ requestType: R.Type,
        handler: @escaping @Sendable (R) async throws -> R.Response
    ) {
        let typeName = String(describing: R.self)

        handlers[typeName] = { [decoder, encoder] data in
            let request = try decoder.decode(R.self, from: data)
            let response = try await handler(request)
            return try encoder.encode(response)
        }
    }

    // MARK: - Waiting for Connection

    /// Waits for the session to be activated.
    ///
    /// - Parameter timeout: Maximum time to wait. Defaults to 10 seconds.
    /// - Throws: `WatchConnectionError.notActivated` if activation fails or times out.
    ///
    /// ```swift
    /// try await connection.waitForActivation()
    /// // Session is now activated
    /// ```
    public func waitForActivation(timeout: Duration = .seconds(10)) async throws {
        // Already activated
        if case .success(.activated) = activationState { return }

        // Already failed
        if case .failure(let error) = activationState { throw error }

        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()

            if case .success(.activated) = activationState { return }
            if case .failure(let error) = activationState { throw error }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw WatchConnectionError.notActivated
    }

    /// Waits for the connection to become ready for messaging.
    ///
    /// This method first waits for activation, then waits for reachability.
    ///
    /// - Parameter timeout: Maximum time to wait. Pass `nil` to wait indefinitely.
    /// - Throws: `WatchConnectionError.notActivated` if activation fails,
    ///           or `WatchConnectionError.timeout` if the timeout expires.
    ///
    /// ```swift
    /// try await connection.waitForConnection(timeout: .seconds(30))
    /// // Connection is ready for messaging
    /// ```
    public func waitForConnection(timeout: Duration? = nil) async throws {
        // Already connected
        if case .success(.activated) = activationState, isReachable { return }

        // Wait for activation first (use min of provided timeout and 10s)
        let activationTimeout: Duration = min(timeout ?? .seconds(10), .seconds(10))
        try await waitForActivation(timeout: activationTimeout)

        // Already reachable after activation
        if isReachable { return }

        // Wait for reachability
        let deadline = timeout.map { ContinuousClock.now + $0 }

        while true {
            try Task.checkCancellation()

            if let deadline, ContinuousClock.now >= deadline {
                throw WatchConnectionError.timeout
            }

            if isReachable { return }

            try await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Convenience Sending

    /// Sends a request, waiting for connection and retrying on failure.
    ///
    /// This method waits for the connection to become available, sends the
    /// request, and retries if the connection is lost during transmission.
    ///
    /// - Parameters:
    ///   - request: The request to send.
    ///   - strategy: Delivery strategy with fallback options.
    ///   - maxAttempts: Maximum number of connection attempts. Defaults to 3.
    ///   - connectionTimeout: Maximum time to wait for each connection attempt.
    /// - Returns: The typed response from the remote device.
    /// - Throws: `WatchConnectionError` if all attempts fail.
    ///
    /// ```swift
    /// let response = try await connection.sendWhenReady(
    ///     MyRequest(),
    ///     maxAttempts: 5,
    ///     connectionTimeout: .seconds(60)
    /// )
    /// ```
    public func sendWhenReady<R: WatchRequest>(
        _ request: R,
        strategy: DeliveryStrategy = .messageWithUserInfoFallback,
        maxAttempts: Int = 3,
        connectionTimeout: Duration = .seconds(30)
    ) async throws -> R.Response {
        var lastError: Error = WatchConnectionError.notReachable
        var attempt = 0

        while attempt < maxAttempts {
            try Task.checkCancellation()

            do {
                try await waitForConnection(timeout: connectionTimeout)
                return try await send(request, strategy: strategy, delivery: .immediate, retryPolicy: .none)
            } catch let error as WatchConnectionError {
                switch error {
                case .notReachable, .timeout, .deliveryFailed:
                    attempt += 1
                    lastError = error
                    if attempt < maxAttempts {
                        try await Task.sleep(for: .milliseconds(500))
                    }
                default:
                    throw error
                }
            }
        }

        throw lastError
    }

    // MARK: - Queue Management

    /// Cancels all queued requests.
    ///
    /// Queued requests will receive a `.cancelled` error.
    public func cancelAllQueuedRequests() {
        for queuedRequest in requestQueue {
            if let continuation = pendingRequests.removeValue(forKey: queuedRequest.wireRequest.requestID) {
                continuation.resume(throwing: WatchConnectionError.cancelled)
            }
        }
        requestQueue.removeAll()
        pendingRequestCount = 0
    }

    /// Cancels a specific queued request by its ID.
    ///
    /// - Parameter id: The request ID to cancel.
    public func cancelQueuedRequest(id: UUID) {
        if let index = requestQueue.firstIndex(where: { $0.wireRequest.requestID == id }) {
            let queuedRequest = requestQueue.remove(at: index)
            if let continuation = pendingRequests.removeValue(forKey: queuedRequest.wireRequest.requestID) {
                continuation.resume(throwing: WatchConnectionError.cancelled)
            }
            pendingRequestCount = requestQueue.count
        }
    }

    // MARK: - File Transfers

    /// Transfers a file to the counterpart device.
    ///
    /// Files are transferred in the background and continue even if your app is suspended.
    /// The returned `FileTransfer` object can be used to track progress or cancel the transfer.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of the file to transfer. Must be a local file URL.
    ///   - metadata: Optional metadata dictionary to send with the file. Values must be
    ///               property list types (String, Number, Date, Data, Array, Dictionary).
    /// - Returns: A `FileTransfer` object for tracking the transfer.
    /// - Throws: `WatchConnectionError.fileNotFound` if the file doesn't exist.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let fileURL = documentsDirectory.appendingPathComponent("data.json")
    /// let transfer = try await connection.transferFile(fileURL, metadata: ["type": "backup"])
    ///
    /// // Wait for completion
    /// try await transfer.waitForCompletion()
    ///
    /// // Or track progress
    /// for await progress in transfer.progressUpdates {
    ///     print("Progress: \(Int(progress * 100))%")
    /// }
    /// ```
    @discardableResult
    public func transferFile(
        _ fileURL: URL,
        metadata: [String: Any]? = nil
    ) async throws -> FileTransfer {
        // Ensure session is activated
        try await ensureActivated()

        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw WatchConnectionError.fileNotFound(url: fileURL.path)
        }

        // Start the transfer
        let wcTransfer = _session.transferFile(fileURL, metadata: metadata)

        // Create and track the FileTransfer
        let transfer = FileTransfer(
            fileURL: fileURL,
            metadata: metadata,
            wcTransfer: wcTransfer
        )

        activeFileTransfers[wcTransfer] = transfer
        activeFileTransferCount = activeFileTransfers.count

        emitDiagnostic(.fileTransferStarted(fileURL: fileURL, hasMetadata: metadata != nil))

        return transfer
    }

    /// Returns all in-progress file transfers.
    ///
    /// Use this to monitor or cancel pending transfers.
    public var outstandingFileTransfers: [FileTransfer] {
        Array(activeFileTransfers.values)
    }

    /// Cancels all pending file transfers.
    public func cancelAllFileTransfers() {
        for (wcTransfer, transfer) in activeFileTransfers {
            wcTransfer.cancel()
            transfer.markFailed(.cancelled)
        }
        activeFileTransfers.removeAll()
        activeFileTransferCount = 0
    }

    // MARK: - Session Recovery

    /// Attempts to recover from an unhealthy session state.
    ///
    /// This method re-activates the WCSession and flushes any pending requests.
    /// Use this when `sessionHealth` indicates persistent issues.
    ///
    /// ```swift
    /// if !connection.sessionHealth.isHealthy {
    ///     await connection.attemptRecovery()
    /// }
    /// ```
    public func attemptRecovery() async {
        emitDiagnostic(.recoveryAttempted)

        // Re-activate session
        _session.activate()

        // Wait for activation
        do {
            try await Task.sleep(for: .seconds(1))
        } catch {
            emitDiagnostic(.recoveryFailed(error: .cancelled))
            return
        }

        // Check if activation succeeded
        if case .success(.activated) = activationState {
            // Reset health state
            healthTracker.reset()
            updateHealthState()

            // Flush pending requests
            processQueuedRequests()

            emitDiagnostic(.recoverySucceeded)
        } else {
            emitDiagnostic(.recoveryFailed(error: .notActivated))
        }
    }

    // MARK: - Diagnostics

    /// Emits a diagnostic event to subscribers.
    private func emitDiagnostic(_ event: DiagnosticEvent) {
        diagnosticContinuation?.yield(event)
    }

    /// Updates the published sessionHealth from the health tracker.
    private func updateHealthState() {
        let previousHealth = sessionHealth
        sessionHealth = healthTracker.health

        if previousHealth != sessionHealth {
            emitDiagnostic(.healthChanged(from: previousHealth, to: sessionHealth))
        }
    }

    /// Records a successful communication and updates health.
    private func recordSuccess() {
        let (_, changed) = healthTracker.recordSuccess()
        if changed {
            updateHealthState()
        }
    }

    /// Records a failed communication and updates health.
    private func recordFailure() {
        let (_, changed) = healthTracker.recordFailure()
        if changed {
            updateHealthState()
        }
    }

    // MARK: - Private: Sending Implementation

    private func sendWithRetry(
        wireRequest: WireRequest,
        strategy: DeliveryStrategy,
        delivery: DeliveryMode,
        retryPolicy: RetryPolicy,
        timeout: Duration
    ) async throws -> Data {
        let deadline = ContinuousClock.now + timeout
        let startTime = ContinuousClock.now
        var lastError: Error = WatchConnectionError.notReachable
        var attempt = 0

        while attempt < retryPolicy.maxAttempts {
            // Check timeout
            if ContinuousClock.now >= deadline {
                recordFailure()
                throw WatchConnectionError.timeout
            }

            // Check cancellation
            try Task.checkCancellation()

            do {
                // Try primary method
                let result = try await sendViaMethod(
                    wireRequest: wireRequest,
                    method: strategy.primaryMethod,
                    timeout: deadline - ContinuousClock.now
                )

                // Success - record and emit diagnostic
                recordSuccess()
                let duration = ContinuousClock.now - startTime
                emitDiagnostic(.messageSent(requestType: wireRequest.typeName, duration: duration))

                return result
            } catch {
                lastError = error
                let watchError = WatchConnectionError(error: error)
                let willRetry = retryPolicy.shouldRetry(error) && attempt < retryPolicy.maxAttempts - 1

                emitDiagnostic(.deliveryFailed(
                    requestType: wireRequest.typeName,
                    error: watchError,
                    willRetry: willRetry
                ))

                // Check if we should try fallback
                if let fallbackMethod = strategy.fallbackMethod {
                    emitDiagnostic(.fallbackUsed(from: strategy.primaryMethod, to: fallbackMethod))

                    do {
                        let result = try await sendViaMethod(
                            wireRequest: wireRequest,
                            method: fallbackMethod,
                            timeout: deadline - ContinuousClock.now
                        )

                        // Fallback succeeded
                        recordSuccess()
                        let duration = ContinuousClock.now - startTime
                        emitDiagnostic(.messageSent(requestType: wireRequest.typeName, duration: duration))

                        return result
                    } catch {
                        lastError = error
                    }
                }

                // Record failure
                recordFailure()

                // Check if error is retryable
                if !retryPolicy.shouldRetry(error) {
                    throw error
                }

                // Wait before retry (fixed 200ms delay)
                let delay = Duration.milliseconds(200)
                if ContinuousClock.now + delay >= deadline {
                    throw WatchConnectionError.timeout
                }

                try await Task.sleep(for: delay)
                attempt += 1
            }
        }

        throw lastError
    }

    private func sendViaMethod(
        wireRequest: WireRequest,
        method: DeliveryMethod,
        timeout: Duration
    ) async throws -> Data {
        switch method {
        case .message:
            return try await sendViaMessage(wireRequest: wireRequest, timeout: timeout)
        case .userInfo:
            return try await sendViaUserInfo(wireRequest: wireRequest, timeout: timeout)
        case .context:
            return try await sendViaContext(wireRequest: wireRequest, timeout: timeout)
        }
    }

    private func sendViaMessage(wireRequest: WireRequest, timeout: Duration) async throws -> Data {
        guard isReachable else {
            throw WatchConnectionError.notReachable
        }

        let requestData = try encoder.encode(wireRequest)

        return try await withCheckedThrowingContinuation { continuation in
            // Store continuation for response
            self.pendingRequests[wireRequest.requestID] = continuation

            // Set up timeout
            Task {
                try await Task.sleep(for: timeout)
                if let cont = self.pendingRequests.removeValue(forKey: wireRequest.requestID) {
                    cont.resume(throwing: WatchConnectionError.timeout)
                }
            }

            // Send message
            _session.sendMessageData(requestData, replyHandler: { [weak self] responseData in
                Task { @MainActor in
                    // Remove from pending and resume
                    if let cont = self?.pendingRequests.removeValue(forKey: wireRequest.requestID) {
                        cont.resume(returning: responseData)
                    }
                }
            }, errorHandler: { [weak self] error in
                Task { @MainActor in
                    if let cont = self?.pendingRequests.removeValue(forKey: wireRequest.requestID) {
                        cont.resume(throwing: WatchConnectionError(error: error))
                    }
                }
            })
        }
    }

    private func sendViaUserInfo(wireRequest: WireRequest, timeout: Duration) async throws -> Data {
        // For userInfo, we queue the request and wait for the response via the reply mechanism
        // Since transferUserInfo doesn't have a direct reply, we need to wait for an incoming message
        // This is a simplified implementation - in practice you'd need a correlation mechanism

        // Queue for sending
        let queuedRequest = QueuedRequest(
            wireRequest: wireRequest,
            enqueuedAt: Date(),
            strategy: .userInfoOnly
        )
        requestQueue.append(queuedRequest)
        pendingRequestCount = requestQueue.count

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[wireRequest.requestID] = continuation

            // Set up timeout
            Task {
                try await Task.sleep(for: timeout)
                if let cont = self.pendingRequests.removeValue(forKey: wireRequest.requestID) {
                    // Remove from queue
                    self.requestQueue.removeAll { $0.wireRequest.requestID == wireRequest.requestID }
                    self.pendingRequestCount = self.requestQueue.count
                    cont.resume(throwing: WatchConnectionError.timeout)
                }
            }

            // Send via transferUserInfo
            do {
                let userInfo = try WireUserInfo(request: wireRequest).toDictionary(encoder: self.encoder)
                self._session.transferUserInfo(userInfo)
            } catch {
                if let cont = self.pendingRequests.removeValue(forKey: wireRequest.requestID) {
                    cont.resume(throwing: WatchConnectionError(error: error))
                }
            }
        }
    }

    private func sendViaContext(wireRequest: WireRequest, timeout: Duration) async throws -> Data {
        // For applicationContext, we update the context and wait for response
        // This is a simplified implementation

        let requestData = try encoder.encode(wireRequest)

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[wireRequest.requestID] = continuation

            // Set up timeout
            Task {
                try await Task.sleep(for: timeout)
                if let cont = self.pendingRequests.removeValue(forKey: wireRequest.requestID) {
                    cont.resume(throwing: WatchConnectionError.timeout)
                }
            }

            // Send via applicationContext
            do {
                var context = self._session.applicationContext
                context["WatchConnectivitySwift.Request"] = requestData
                try self._session.updateApplicationContext(context)
            } catch {
                if let cont = self.pendingRequests.removeValue(forKey: wireRequest.requestID) {
                    cont.resume(throwing: WatchConnectionError(error: error))
                }
            }
        }
    }

    private func sendFireAndForget(wireRequest: WireRequest, strategy: DeliveryStrategy) async throws {
        let requestData = try encoder.encode(wireRequest)

        switch strategy.primaryMethod {
        case .message:
            if isReachable {
                _session.sendMessageData(requestData, replyHandler: nil, errorHandler: nil)
            } else if let fallback = strategy.fallbackMethod {
                try await sendFireAndForgetViaMethod(wireRequest: wireRequest, method: fallback)
            }
        case .userInfo:
            let userInfo = try WireUserInfo(request: wireRequest).toDictionary(encoder: encoder)
            _session.transferUserInfo(userInfo)
        case .context:
            var context = _session.applicationContext
            context["WatchConnectivitySwift.FireAndForget.\(wireRequest.requestID)"] = requestData
            try _session.updateApplicationContext(context)
        }
    }

    private func sendFireAndForgetViaMethod(wireRequest: WireRequest, method: DeliveryMethod) async throws {
        switch method {
        case .message:
            let requestData = try encoder.encode(wireRequest)
            _session.sendMessageData(requestData, replyHandler: nil, errorHandler: nil)
        case .userInfo:
            let userInfo = try WireUserInfo(request: wireRequest).toDictionary(encoder: encoder)
            _session.transferUserInfo(userInfo)
        case .context:
            let requestData = try encoder.encode(wireRequest)
            var context = _session.applicationContext
            context["WatchConnectivitySwift.FireAndForget.\(wireRequest.requestID)"] = requestData
            try _session.updateApplicationContext(context)
        }
    }

    // MARK: - Private: Activation

    private func ensureActivated() async throws {
        // If already activated, return immediately
        if case .success(.activated) = activationState {
            return
        }

        // Wait up to 5 seconds for activation
        let deadline = ContinuousClock.now + .seconds(5)

        while ContinuousClock.now < deadline {
            if case .success(.activated) = activationState {
                // Small settling time for isReachable to update
                try await Task.sleep(for: .milliseconds(50))
                return
            }

            if case .failure(let error) = activationState {
                throw error
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw WatchConnectionError.notActivated
    }

    // MARK: - Private: Queue Processing

    private func processQueuedRequests() {
        guard !requestQueue.isEmpty else { return }

        queueProcessingTask?.cancel()
        queueProcessingTask = Task {
            var flushedCount = 0

            while !requestQueue.isEmpty && isReachable {
                guard let queuedRequest = requestQueue.first else { break }

                do {
                    let responseData = try await sendViaMessage(
                        wireRequest: queuedRequest.wireRequest,
                        timeout: .seconds(10)
                    )

                    // Success - remove from queue and resume continuation
                    requestQueue.removeFirst()
                    pendingRequestCount = requestQueue.count
                    flushedCount += 1

                    recordSuccess()

                    if let continuation = pendingRequests.removeValue(forKey: queuedRequest.wireRequest.requestID) {
                        continuation.resume(returning: responseData)
                    }
                } catch {
                    // If not reachable, stop processing
                    if case WatchConnectionError.notReachable = error {
                        break
                    }

                    // For other errors, fail this request and continue
                    guard !requestQueue.isEmpty else { break }
                    requestQueue.removeFirst()
                    pendingRequestCount = requestQueue.count

                    recordFailure()

                    if let continuation = pendingRequests.removeValue(forKey: queuedRequest.wireRequest.requestID) {
                        continuation.resume(throwing: error)
                    }
                }
            }

            // Emit diagnostic if we flushed any requests
            if flushedCount > 0 {
                emitDiagnostic(.queueFlushed(count: flushedCount))
            }
        }
    }

    // MARK: - Private: Incoming Message Handling

    /// Processes an incoming request and returns the response data.
    ///
    /// This method runs on MainActor to access handlers and state safely.
    private func processIncomingRequest(data: Data) async -> Data {
        do {
            let wireRequest = try decoder.decode(WireRequest.self, from: data)

            // Emit diagnostic event
            emitDiagnostic(.messageReceived(requestType: wireRequest.typeName))

            // Look up handler
            guard let handler = handlers[wireRequest.typeName] else {
                let error = WatchConnectionError.handlerNotRegistered(requestType: wireRequest.typeName)
                let response = WireResponse.failure(error, requestID: wireRequest.requestID)
                return (try? encoder.encode(response)) ?? Data()
            }

            // Execute handler
            do {
                let responseData = try await handler(wireRequest.payload)
                // Use the overload that takes already-encoded Data (handler already encoded the response)
                let response = WireResponse.success(responseData, requestID: wireRequest.requestID)
                recordSuccess()
                return try encoder.encode(response)
            } catch {
                let watchError = WatchConnectionError(error: error)
                let response = WireResponse.failure(watchError, requestID: wireRequest.requestID)
                return (try? encoder.encode(response)) ?? Data()
            }
        } catch {
            // Failed to decode request - send error response
            let watchError = WatchConnectionError.decodingFailed(description: error.localizedDescription)
            let response = WireResponse.failure(watchError, requestID: UUID())
            return (try? encoder.encode(response)) ?? Data()
        }
    }

    /// Processes a fire-and-forget request (no response needed).
    private func processFireAndForgetRequest(typeName: String, payload: Data) async {
        guard let handler = handlers[typeName] else { return }
        _ = try? await handler(payload)
    }

    /// Sends a response if the counterpart is reachable.
    private func sendResponseIfReachable(_ responseData: Data) {
        guard isReachable else { return }
        _session.sendMessageData(responseData, replyHandler: nil, errorHandler: nil)
    }

    private func handleIncomingResponse(data: Data) {
        do {
            let wireResponse = try decoder.decode(WireResponse.self, from: data)

            // Find pending request
            if let continuation = pendingRequests.removeValue(forKey: wireResponse.requestID) {
                // Remove from queue if present
                requestQueue.removeAll { $0.wireRequest.requestID == wireResponse.requestID }
                pendingRequestCount = requestQueue.count

                continuation.resume(returning: data)
            }
        } catch {
            // Ignore malformed responses
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnection: WCSessionDelegate {

    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor in
            if let error {
                self.activationState = .failure(WatchConnectionError(error: error))
                self.recordFailure()
            } else {
                self.activationState = .success(activationState)
                if activationState == .activated {
                    self.emitDiagnostic(.sessionActivated)
                    self.recordSuccess()
                }
            }
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping @Sendable (Data) -> Void
    ) {
        // Capture data before crossing isolation boundary
        let data = messageData
        Task {
            let responseData = await self.processIncomingRequest(data: data)
            replyHandler(responseData)
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data
    ) {
        // Capture data before crossing isolation boundary
        let data = messageData
        Task { @MainActor in
            // This could be a response or a fire-and-forget request
            self.handleIncomingResponse(data: data)
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        // Extract and decode on current thread to avoid sending non-Sendable across boundary
        let localDecoder = JSONDecoder()
        guard let wireUserInfoData = userInfo[WireUserInfo.key] as? Data,
              let wireUserInfo = try? localDecoder.decode(WireUserInfo.self, from: wireUserInfoData) else {
            return
        }

        let request = wireUserInfo.request
        let localEncoder = JSONEncoder()
        Task {
            if request.isFireAndForget {
                await self.processFireAndForgetRequest(typeName: request.typeName, payload: request.payload)
            } else {
                // Encode the full WireRequest for processIncomingRequest
                guard let requestData = try? localEncoder.encode(request) else {
                    return
                }
                // Process request and get response
                let responseData = await self.processIncomingRequest(data: requestData)
                // Send response via message if reachable (check on MainActor)
                await self.sendResponseIfReachable(responseData)
            }
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        // Extract request data before crossing isolation boundaries
        let requestData = applicationContext["WatchConnectivitySwift.Request"] as? Data

        // Wrap the context to make it sendable (property list types are thread-safe)
        let sendableContext = SendableContext(applicationContext)

        Task { @MainActor in
            // Emit diagnostic event
            self.emitDiagnostic(.applicationContextReceived)

            // Yield to stream for SharedState and other observers
            self.receivedApplicationContextsContinuation?.yield(sendableContext.value)
        }

        // Handle requests embedded in context
        if let requestData {
            Task {
                // Process request and get response
                let responseData = await self.processIncomingRequest(data: requestData)
                // Send response via message if reachable
                await self.sendResponseIfReachable(responseData)
            }
        }
    }

    // MARK: - File Transfer Delegate Methods

    nonisolated public func session(
        _ session: WCSession,
        didReceive file: WCSessionFile
    ) {
        // Capture values before crossing isolation boundary
        let fileURL = file.fileURL
        let metadata = file.metadata

        Task { @MainActor in
            let receivedFile = ReceivedFile(fileURL: fileURL, metadata: metadata)
            self.emitDiagnostic(.fileReceived(
                fileURL: fileURL,
                hasMetadata: metadata != nil
            ))
            self.recordSuccess()

            // Notify via callback
            self.onFileReceived?(receivedFile)

            // Emit to stream
            self.receivedFilesContinuation?.yield(receivedFile)
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: (any Error)?
    ) {
        // Capture values before crossing isolation boundary
        let wcTransfer = fileTransfer
        let transferError = error

        Task { @MainActor in
            guard let transfer = self.activeFileTransfers.removeValue(forKey: wcTransfer) else {
                return
            }

            self.activeFileTransferCount = self.activeFileTransfers.count

            if let error = transferError {
                let watchError = WatchConnectionError(error: error)
                transfer.markFailed(watchError)
                self.emitDiagnostic(.fileTransferFailed(fileURL: transfer.fileURL, error: watchError))
                self.recordFailure()
            } else {
                transfer.markCompleted()
                self.emitDiagnostic(.fileTransferCompleted(fileURL: transfer.fileURL))
                self.recordSuccess()
            }
        }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.emitDiagnostic(.sessionBecameInactive)
        }
    }

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.emitDiagnostic(.sessionDeactivated)
            // Re-activate for watch switching support
            self._session.activate()
        }
    }
    #endif
}

// MARK: - Supporting Types

/// A queued request waiting to be sent.
struct QueuedRequest: Sendable {
    let wireRequest: WireRequest
    let enqueuedAt: Date
    let strategy: DeliveryStrategy
}

/// Wrapper to make `[String: Any]` sendable for application context.
///
/// Property list types (String, Number, Date, Data, Array, Dictionary) are
/// thread-safe value types, so this wrapper is safe to send across isolation
/// boundaries. WCSession guarantees the context only contains property list types.
struct SendableContext: @unchecked Sendable {
    let value: [String: Any]

    init(_ value: [String: Any]) {
        self.value = value
    }
}
