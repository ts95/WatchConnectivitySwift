//
//  WCSessionProviding.swift
//  WatchConnectivitySwift
//

import Foundation
import WatchConnectivity

/// Protocol that abstracts WCSession for testing purposes.
///
/// This protocol exposes the WCSession APIs used by the library, allowing
/// you to inject a mock implementation for unit tests.
///
/// `WCSession` conforms to this protocol via an extension, so you can
/// use `WCSession.default` directly or inject your own implementation.
///
/// ## Thread Safety
///
/// `WCSessionProviding` requires `Sendable` conformance because WCSession methods
/// are thread-safe and may be called from any thread. The library uses this to
/// perform blocking operations like `updateApplicationContext()` off the main thread.
///
/// ## Example
///
/// ```swift
/// // Production usage
/// let connection = WatchConnection(session: WCSession.default)
///
/// // Test usage
/// let mockSession = MockWCSession()
/// let connection = WatchConnection(session: mockSession)
/// ```
public protocol WCSessionProviding: AnyObject, Sendable {

    // MARK: - State Properties

    /// The current activation state of the session.
    var activationState: WCSessionActivationState { get }

    /// Whether the counterpart app is reachable for live messaging.
    var isReachable: Bool { get }

    /// The most recent application context sent to the counterpart.
    var applicationContext: [String: Any] { get }

    /// The most recent application context received from the counterpart.
    var receivedApplicationContext: [String: Any] { get }

    #if os(iOS)
    /// Whether the current iPhone is paired with an Apple Watch.
    var isPaired: Bool { get }

    /// Whether the Watch app is installed on the paired Apple Watch.
    var isWatchAppInstalled: Bool { get }
    #endif

    // MARK: - Delegate

    /// The delegate that receives session events.
    var delegate: (any WCSessionDelegate)? { get set }

    // MARK: - Session Lifecycle

    /// Activates the session asynchronously.
    func activate()

    // MARK: - Live Messaging

    /// Sends a message to the counterpart and waits for a reply.
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    )

    /// Sends message data to the counterpart and waits for a reply.
    func sendMessageData(
        _ data: Data,
        replyHandler: ((Data) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    )

    // MARK: - Background Transfers

    /// Updates the application context (latest-value-wins).
    func updateApplicationContext(_ applicationContext: [String: Any]) throws

    /// Transfers user info in a queued fashion (guaranteed delivery, ordered).
    @discardableResult
    func transferUserInfo(_ userInfo: [String: Any]) -> WCSessionUserInfoTransfer

    /// Returns the list of in-progress user info transfers.
    var outstandingUserInfoTransfers: [WCSessionUserInfoTransfer] { get }

    // MARK: - File Transfers

    /// Transfers a file to the counterpart device.
    ///
    /// - Parameters:
    ///   - file: The URL of the file to transfer.
    ///   - metadata: Optional metadata dictionary to send with the file.
    /// - Returns: A WCSessionFileTransfer object for tracking the transfer.
    @discardableResult
    func transferFile(_ file: URL, metadata: [String: Any]?) -> WCSessionFileTransfer

    /// Returns the list of in-progress file transfers.
    var outstandingFileTransfers: [WCSessionFileTransfer] { get }
}

// MARK: - WCSession Conformance

// WCSession is thread-safe (delegate methods are called on arbitrary queues,
// and methods like updateApplicationContext can be called from any thread).
// Apple hasn't marked it as Sendable, so we use @retroactive @unchecked.
extension WCSession: @retroactive @unchecked Sendable {}
extension WCSession: WCSessionProviding {}
