//
//  FileTransfer.swift
//  WatchConnectivitySwift
//

import Foundation
@preconcurrency import WatchConnectivity

/// Represents an in-progress file transfer to the counterpart device.
///
/// Use this type to track transfer progress, check status, or cancel transfers.
///
/// ## Example
///
/// ```swift
/// let transfer = try await connection.transferFile(url, metadata: ["id": "123"])
///
/// // Track progress
/// for await progress in transfer.progressUpdates {
///     print("Progress: \(progress.fractionCompleted * 100)%")
/// }
///
/// // Or wait for completion
/// try await transfer.waitForCompletion()
/// ```
@MainActor
public final class FileTransfer: ObservableObject, Sendable {

    // MARK: - Published State

    /// The fraction of the transfer that has completed (0.0 to 1.0).
    @Published public private(set) var fractionCompleted: Double = 0.0

    /// Whether the transfer is currently in progress.
    @Published public private(set) var isTransferring: Bool = true

    /// Whether the transfer completed successfully.
    @Published public private(set) var isCompleted: Bool = false

    /// The error if the transfer failed.
    @Published public private(set) var error: WatchConnectionError?

    // MARK: - Properties

    /// The URL of the file being transferred.
    public let fileURL: URL

    /// Optional metadata associated with the transfer.
    public let metadata: [String: Any]?

    /// Unique identifier for this transfer.
    public let id: UUID

    // MARK: - Internal

    /// The underlying WCSessionFileTransfer, if available.
    internal var wcTransfer: WCSessionFileTransfer?

    /// Continuation for completion waiting.
    private var completionContinuation: CheckedContinuation<Void, any Error>?

    /// Progress observation.
    private var progressObservation: NSKeyValueObservation?

    /// Continuation for progress streaming.
    private var progressContinuation: AsyncStream<Double>.Continuation?

    // MARK: - Initialization

    /// Creates a new file transfer tracker.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of the file being transferred.
    ///   - metadata: Optional metadata dictionary.
    ///   - wcTransfer: The underlying WCSessionFileTransfer.
    internal init(
        fileURL: URL,
        metadata: [String: Any]?,
        wcTransfer: WCSessionFileTransfer? = nil
    ) {
        self.fileURL = fileURL
        self.metadata = metadata
        self.wcTransfer = wcTransfer
        self.id = UUID()

        if let wcTransfer {
            setupProgressObservation(wcTransfer)
        }
    }

    deinit {
        progressObservation?.invalidate()
        progressContinuation?.finish()
    }

    // MARK: - Public Methods

    /// Cancels the file transfer.
    ///
    /// After cancellation, the transfer will report as failed with a `.cancelled` error.
    public func cancel() {
        wcTransfer?.cancel()
        isTransferring = false
        error = .cancelled
        completionContinuation?.resume(throwing: WatchConnectionError.cancelled)
        completionContinuation = nil
        progressContinuation?.finish()
    }

    /// Waits for the transfer to complete.
    ///
    /// - Throws: `WatchConnectionError` if the transfer fails.
    public func waitForCompletion() async throws {
        // Already completed
        if isCompleted {
            return
        }

        // Already failed
        if let error {
            throw error
        }

        // Wait for completion
        try await withCheckedThrowingContinuation { continuation in
            self.completionContinuation = continuation
        }
    }

    /// An async stream of progress updates (0.0 to 1.0).
    ///
    /// The stream completes when the transfer finishes (successfully or with an error).
    public var progressUpdates: AsyncStream<Double> {
        AsyncStream { continuation in
            self.progressContinuation = continuation

            // Emit current progress immediately
            continuation.yield(self.fractionCompleted)

            // Handle already completed
            if !self.isTransferring {
                continuation.finish()
            }
        }
    }

    // MARK: - Internal Methods

    /// Called when the transfer completes successfully.
    internal func markCompleted() {
        isTransferring = false
        isCompleted = true
        fractionCompleted = 1.0
        completionContinuation?.resume()
        completionContinuation = nil
        progressContinuation?.yield(1.0)
        progressContinuation?.finish()
    }

    /// Called when the transfer fails.
    internal func markFailed(_ error: WatchConnectionError) {
        isTransferring = false
        self.error = error
        completionContinuation?.resume(throwing: error)
        completionContinuation = nil
        progressContinuation?.finish()
    }

    // MARK: - Private Methods

    private func setupProgressObservation(_ transfer: WCSessionFileTransfer) {
        progressObservation = transfer.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.fractionCompleted = progress.fractionCompleted
                self.progressContinuation?.yield(progress.fractionCompleted)
            }
        }

        // Initial value
        fractionCompleted = transfer.progress.fractionCompleted
        isTransferring = transfer.isTransferring
    }
}

// MARK: - Identifiable

extension FileTransfer: Identifiable {}

// MARK: - ReceivedFile

/// A file received from the counterpart device.
///
/// **Important:** The file at `fileURL` will be deleted by the system after the
/// delegate method returns. You must synchronously move or copy the file to a
/// permanent location if you want to keep it.
///
/// ## Example
///
/// ```swift
/// connection.onFileReceived = { file in
///     let destination = documentsDirectory.appendingPathComponent(file.fileURL.lastPathComponent)
///     try FileManager.default.moveItem(at: file.fileURL, to: destination)
///     print("Received file with metadata: \(file.metadata ?? [:])")
/// }
/// ```
@MainActor
public struct ReceivedFile {

    /// The URL of the received file.
    ///
    /// **Warning:** This file will be deleted after the receive handler returns.
    /// Move or copy it synchronously if you need to keep it.
    public let fileURL: URL

    /// Optional metadata sent with the file.
    ///
    /// Values are property list types (String, Number, Date, Data, Array, Dictionary).
    public let metadata: [String: Any]?

    /// Creates a received file from a WCSessionFile.
    internal init(wcFile: WCSessionFile) {
        self.fileURL = wcFile.fileURL
        self.metadata = wcFile.metadata
    }

    /// Creates a received file (for testing).
    public init(fileURL: URL, metadata: [String: Any]?) {
        self.fileURL = fileURL
        self.metadata = metadata
    }
}
