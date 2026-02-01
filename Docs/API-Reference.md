# API Reference

Complete reference documentation for all public types, properties, and methods in WatchConnectivitySwift.

## Table of Contents

- [WatchConnection](#watchconnection)
- [WatchRequest Protocol](#watchrequest-protocol)
- [FireAndForgetRequest Protocol](#fireandforgetrequest-protocol)
- [SharedState](#sharedstate)
- [FileTransfer](#filetransfer)
- [ReceivedFile](#receivedfile)
- [DeliveryStrategy](#deliverystrategy)
- [DeliveryMode](#deliverymode)
- [RetryPolicy](#retrypolicy)
- [WatchConnectionError](#watchconnectionerror)
- [SessionHealth](#sessionhealth)
- [DiagnosticEvent](#diagnosticevent)
- [WCSessionProviding Protocol](#wcsessionproviding-protocol)

---

## WatchConnection

The main entry point for watch connectivity communication.

```swift
@MainActor
public final class WatchConnection: NSObject, ObservableObject
```

### Initializers

```swift
public init(
    session: any WCSessionProviding = WCSession.default,
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder()
)
```

**Parameters:**
- `session`: The WCSession to use. Defaults to `WCSession.default`.
- `encoder`: JSON encoder for serializing requests.
- `decoder`: JSON decoder for deserializing responses.

### Published Properties

| Property | Type | Description |
|----------|------|-------------|
| `activationState` | `Result<WCSessionActivationState, WatchConnectionError>` | Current session activation state |
| `isReachable` | `Bool` | Whether counterpart is reachable |
| `pendingRequestCount` | `Int` | Number of queued requests |
| `activeFileTransferCount` | `Int` | Number of file transfers in progress |
| `sessionHealth` | `SessionHealth` | Current health state |
| `isPaired` | `Bool` | Whether Watch is paired (iOS only) |
| `isWatchAppInstalled` | `Bool` | Whether Watch app is installed (iOS only) |

### Computed Properties

| Property | Type | Description |
|----------|------|-------------|
| `diagnosticEvents` | `AsyncStream<DiagnosticEvent>` | Stream of diagnostic events |
| `receivedFiles` | `AsyncStream<ReceivedFile>` | Stream of received files |
| `receivedApplicationContexts` | `AsyncStream<[String: Any]>` | Stream of received application contexts |
| `outstandingFileTransfers` | `[FileTransfer]` | In-progress file transfers |
| `session` | `any WCSessionProviding` | The underlying session for direct access |

### Callback Properties

| Property | Type | Description |
|----------|------|-------------|
| `onFileReceived` | `(@MainActor @Sendable (ReceivedFile) -> Void)?` | Called when file is received |

### Methods

#### send(_:strategy:delivery:retryPolicy:)

Sends a request and returns the typed response.

```swift
public func send<R: WatchRequest>(
    _ request: R,
    strategy: DeliveryStrategy = .messageWithUserInfoFallback,
    delivery: DeliveryMode = .queued,
    retryPolicy: RetryPolicy = .default
) async throws -> R.Response
```

**Parameters:**
- `request`: The request to send.
- `strategy`: Delivery strategy with fallback options.
- `delivery`: When to deliver if not immediately reachable.
- `retryPolicy`: Retry and timeout configuration.

**Returns:** The typed response from the remote device.

**Throws:** `WatchConnectionError` if the request fails.

#### send(_:strategy:) (Fire-and-Forget)

Sends a fire-and-forget request.

```swift
public func send<R: FireAndForgetRequest>(
    _ request: R,
    strategy: DeliveryStrategy = .messageWithUserInfoFallback
) async
```

**Parameters:**
- `request`: The fire-and-forget request to send.
- `strategy`: Delivery strategy.

#### register(_:handler:)

Registers a handler for a specific request type.

```swift
public func register<R: WatchRequest>(
    _ requestType: R.Type,
    handler: @escaping @Sendable (R) async throws -> R.Response
)
```

**Parameters:**
- `requestType`: The type of request to handle.
- `handler`: An async closure that processes the request.

#### connect()

Activates the connection and attempts to establish connectivity.

```swift
public func connect() async
```

In active mode:
- Queued requests are processed as soon as connectivity is available
- Diagnostic events are emitted for connection attempts

#### disconnect()

Disconnects and cancels all pending requests.

```swift
public func disconnect()
```

#### waitForActivation(timeout:)

Waits for the session to be activated.

```swift
public func waitForActivation(timeout: Duration = .seconds(10)) async throws
```

**Parameters:**
- `timeout`: Maximum time to wait. Defaults to 10 seconds.

**Throws:** `WatchConnectionError.notActivated` if activation fails or times out.

#### waitForConnection(timeout:)

Waits for the connection to become ready for messaging.

```swift
public func waitForConnection(timeout: Duration? = nil) async throws
```

**Parameters:**
- `timeout`: Maximum time to wait. Pass `nil` to wait indefinitely.

**Throws:** `WatchConnectionError.notActivated` if activation fails, or `WatchConnectionError.timeout` if the timeout expires.

#### sendWhenReady(_:strategy:maxAttempts:connectionTimeout:)

Sends a request, waiting for connection and retrying on failure.

```swift
public func sendWhenReady<R: WatchRequest>(
    _ request: R,
    strategy: DeliveryStrategy = .messageWithUserInfoFallback,
    maxAttempts: Int = 3,
    connectionTimeout: Duration = .seconds(30)
) async throws -> R.Response
```

**Parameters:**
- `request`: The request to send.
- `strategy`: Delivery strategy with fallback options.
- `maxAttempts`: Maximum number of connection attempts. Defaults to 3.
- `connectionTimeout`: Maximum time to wait for each connection attempt.

**Returns:** The typed response from the remote device.

**Throws:** `WatchConnectionError` if all attempts fail.

#### cancelAllQueuedRequests()

Cancels all queued requests.

```swift
public func cancelAllQueuedRequests()
```

#### cancelQueuedRequest(id:)

Cancels a specific queued request.

```swift
public func cancelQueuedRequest(id: UUID)
```

#### attemptRecovery()

Attempts to recover from a degraded or unhealthy session.

```swift
public func attemptRecovery() async
```

#### transferFile(_:metadata:)

Transfers a file to the counterpart device.

```swift
@discardableResult
public func transferFile(
    _ fileURL: URL,
    metadata: [String: Any]? = nil
) async throws -> FileTransfer
```

**Parameters:**
- `fileURL`: The URL of the file to transfer. Must be a local file URL.
- `metadata`: Optional metadata dictionary (property list types only).

**Returns:** A `FileTransfer` object for tracking progress or cancellation.

**Throws:** `WatchConnectionError.fileNotFound` if the file doesn't exist.

#### cancelAllFileTransfers()

Cancels all pending file transfers.

```swift
public func cancelAllFileTransfers()
```

---

## WatchRequest Protocol

Base protocol for all watch connectivity requests.

```swift
public protocol WatchRequest: Codable, Sendable {
    associatedtype Response: Codable & Sendable
}
```

### Associated Types

| Type | Constraints | Description |
|------|-------------|-------------|
| `Response` | `Codable & Sendable` | The response type this request produces |

### Example

```swift
struct FetchUserRequest: WatchRequest {
    typealias Response = User
    let userID: String
}
```

---

## FireAndForgetRequest Protocol

Marker protocol for requests that don't need a response.

```swift
public protocol FireAndForgetRequest: WatchRequest where Response == VoidResponse
```

### Example

```swift
struct LogEventRequest: FireAndForgetRequest {
    let eventName: String
    let parameters: [String: String]
}
```

---

## SharedState

A synchronized state container for sharing data between devices via `applicationContext`.

```swift
@Observable
@MainActor
public final class SharedState<State: Codable & Sendable & Equatable>
```

Uses Swift's `@Observable` macro for seamless nested observation in SwiftUI.

### Initializers

```swift
public init(
    initialValue: State,
    connection: WatchConnection,
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder()
)
```

**Parameters:**
- `initialValue`: The initial state value.
- `connection`: The WatchConnection instance to use for synchronization.
- `encoder`: JSON encoder for serializing state.
- `decoder`: JSON decoder for deserializing state.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `value` | `State` | Current state value (observable via `@Observable`) |

### Methods

#### update(_:)

Updates the state and synchronizes to the counterpart device.

```swift
public func update(_ newValue: State) throws
```

**Throws:** `WatchConnectionError.encodingFailed` if serialization fails.

---

## FileTransfer

Represents an in-progress file transfer to the counterpart device.

```swift
@MainActor
public final class FileTransfer: ObservableObject, Sendable, Identifiable
```

### Published Properties

| Property | Type | Description |
|----------|------|-------------|
| `fractionCompleted` | `Double` | Progress (0.0 to 1.0) |
| `isTransferring` | `Bool` | Whether transfer is in progress |
| `isCompleted` | `Bool` | Whether transfer completed successfully |
| `error` | `WatchConnectionError?` | Error if transfer failed |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `fileURL` | `URL` | URL of file being transferred |
| `metadata` | `[String: Any]?` | Metadata sent with file |
| `id` | `UUID` | Unique identifier |

### Computed Properties

| Property | Type | Description |
|----------|------|-------------|
| `progressUpdates` | `AsyncStream<Double>` | Stream of progress updates |

### Methods

#### cancel()

Cancels the file transfer.

```swift
public func cancel()
```

#### waitForCompletion()

Waits for the transfer to complete.

```swift
public func waitForCompletion() async throws
```

**Throws:** `WatchConnectionError` if the transfer fails.

### Example

```swift
let transfer = try await connection.transferFile(fileURL, metadata: ["type": "backup"])

// Track progress
for await progress in transfer.progressUpdates {
    print("Progress: \(Int(progress * 100))%")
}

// Or wait for completion
try await transfer.waitForCompletion()

// Or cancel
transfer.cancel()
```

---

## ReceivedFile

A file received from the counterpart device.

```swift
public struct ReceivedFile: @unchecked Sendable
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `fileURL` | `URL` | URL of the received file |
| `metadata` | `[String: Any]?` | Metadata sent with the file |

### Important

The file at `fileURL` will be deleted by the system after the receive handler returns. You must synchronously move or copy the file to a permanent location if you want to keep it.

### Example

```swift
connection.onFileReceived = { file in
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let destination = documents.appendingPathComponent(file.fileURL.lastPathComponent)
    try? FileManager.default.moveItem(at: file.fileURL, to: destination)

    if let id = file.metadata?["id"] as? String {
        print("Received file with ID: \(id)")
    }
}
```

---

## DeliveryStrategy

Strategy for delivering messages with fallback options.

```swift
public enum DeliveryStrategy: String, Sendable, Hashable, Codable
```

### Cases

| Case | Primary | Fallback | Description |
|------|---------|----------|-------------|
| `messageWithUserInfoFallback` | Message | UserInfo | Default strategy |
| `messageWithContextFallback` | Message | Context | For latest-value state |
| `messageOnly` | Message | None | Real-time only |
| `userInfoOnly` | UserInfo | None | Guaranteed ordered |
| `contextOnly` | Context | None | Latest value only |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `primaryMethod` | `DeliveryMethod` | Primary delivery method |
| `fallbackMethod` | `DeliveryMethod?` | Fallback method, if any |
| `hasFallback` | `Bool` | Whether strategy has fallback |

---

## DeliveryMode

Controls when a request should be delivered.

```swift
public enum DeliveryMode: Sendable, Hashable
```

### Cases

| Case | Description |
|------|-------------|
| `queued` | Queue if not reachable, send when connectivity restored (default) |
| `immediate` | Fail immediately if not reachable |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `requiresImmediateReachability` | `Bool` | Whether immediate reachability is required |

---

## RetryPolicy

Configuration for retry behavior.

```swift
public struct RetryPolicy: Sendable
```

### Initializers

```swift
public init(maxAttempts: Int, timeout: Duration = .seconds(10))
```

**Parameters:**
- `maxAttempts`: Maximum number of attempts (including the initial attempt).
- `timeout`: Maximum total time before timeout.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `maxAttempts` | `Int` | Maximum attempts |
| `timeout` | `Duration` | Total timeout |

### Static Properties (Built-in Policies)

| Policy | Attempts | Timeout | Description |
|--------|----------|---------|-------------|
| `default` | 3 | 10s | Balanced default |
| `none` | 1 | 10s | No retries |
| `patient` | 5 | 30s | Important requests |

Retries use a fixed 200ms delay between attempts. The library automatically retries on transient errors (`.notReachable`, `.deliveryFailed`, `.replyFailed`).

---

## WatchConnectionError

Errors that can occur during watch connectivity operations.

```swift
public enum WatchConnectionError: Error, Codable, Sendable, Hashable
```

### Cases

| Case | Description |
|------|-------------|
| `notActivated` | Session not activated |
| `notReachable` | Counterpart not reachable |
| `notPaired` | No Watch paired (iOS) |
| `watchAppNotInstalled` | Watch app not installed (iOS) |
| `deliveryFailed(reason:)` | Message delivery failed |
| `timeout` | Operation timed out |
| `cancelled` | Operation cancelled |
| `replyFailed(reason:)` | Reply handler failed |
| `encodingFailed(description:)` | Encoding error |
| `decodingFailed(description:)` | Decoding error |
| `handlerNotRegistered(requestType:)` | No handler for request type |
| `handlerError(description:)` | Handler threw error |
| `remoteError(description:)` | Remote device error |
| `sessionError(code:description:)` | WCSession error |
| `sessionUnhealthy(reason:)` | Session unhealthy |
| `fileNotFound(url:)` | File not found at URL |
| `fileAccessDenied(url:)` | File access denied |
| `insufficientSpace` | Not enough storage space |

### Initializers

```swift
public init(wcError: WCError)
public init(error: Error)
```

---

## SessionHealth

Health state of the WCSession connection.

```swift
public enum SessionHealth: Sendable, Hashable, Equatable
```

### Cases

| Case | Description |
|------|-------------|
| `healthy` | Normal operation |
| `unhealthy(suggestion:)` | Persistent failures, includes recovery suggestion |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `isHealthy` | `Bool` | Whether session is healthy |
| `suggestion` | `RecoverySuggestion?` | Recovery suggestion if unhealthy |

---

## DiagnosticEvent

Events emitted for debugging and monitoring.

```swift
public enum DiagnosticEvent: Sendable
```

### Session Lifecycle Events

| Event | Description |
|-------|-------------|
| `sessionActivated` | Session activated |
| `sessionDeactivated` | Session deactivated |
| `sessionBecameInactive` | Session became inactive |

### Connectivity Events

| Event | Description |
|-------|-------------|
| `reachabilityChanged(isReachable:)` | Reachability changed |

### Message Events

| Event | Description |
|-------|-------------|
| `messageSent(requestType:duration:)` | Message sent successfully |
| `messageReceived(requestType:)` | Message received |
| `deliveryFailed(requestType:error:willRetry:)` | Delivery failed |
| `fallbackUsed(from:to:)` | Fallback method used |

### Queue Events

| Event | Description |
|-------|-------------|
| `requestQueued(requestType:queueSize:)` | Request queued |
| `queueFlushed(count:)` | Queue flushed |
| `requestExpired(requestType:)` | Request expired |

### Health Events

| Event | Description |
|-------|-------------|
| `healthChanged(from:to:)` | Health state changed |
| `recoveryAttempted` | Recovery attempted |
| `recoverySucceeded` | Recovery succeeded |
| `recoveryFailed(error:)` | Recovery failed |

### File Transfer Events

| Event | Description |
|-------|-------------|
| `fileTransferStarted(fileURL:hasMetadata:)` | File transfer started |
| `fileTransferCompleted(fileURL:)` | File transfer completed |
| `fileTransferFailed(fileURL:error:)` | File transfer failed |
| `fileReceived(fileURL:hasMetadata:)` | File received from counterpart |

---

## WCSessionProviding Protocol

Protocol for WCSession abstraction (for testing).

```swift
public protocol WCSessionProviding: AnyObject, Sendable
```

### Required Properties

| Property | Type | Description |
|----------|------|-------------|
| `activationState` | `WCSessionActivationState` | Activation state |
| `isReachable` | `Bool` | Reachability |
| `applicationContext` | `[String: Any]` | Sent context |
| `receivedApplicationContext` | `[String: Any]` | Received context |
| `delegate` | `WCSessionDelegate?` | Session delegate |
| `outstandingUserInfoTransfers` | `[WCSessionUserInfoTransfer]` | Pending user info transfers |
| `outstandingFileTransfers` | `[WCSessionFileTransfer]` | Pending file transfers |
| `isPaired` | `Bool` | Watch paired (iOS) |
| `isWatchAppInstalled` | `Bool` | App installed (iOS) |

### Required Methods

| Method | Description |
|--------|-------------|
| `activate()` | Activate session |
| `sendMessage(_:replyHandler:errorHandler:)` | Send dictionary message |
| `sendMessageData(_:replyHandler:errorHandler:)` | Send data message |
| `updateApplicationContext(_:)` | Update context |
| `transferUserInfo(_:)` | Transfer user info |
| `transferFile(_:metadata:)` | Transfer file with metadata |

### Conforming Types

- `WCSession` (via extension)
- `MockWCSession` (for testing)
- `FlakyWCSession` (for reliability testing)

---

## Supporting Types

### VoidResponse

Response type for fire-and-forget requests.

```swift
public struct VoidResponse: Codable, Sendable, Hashable {
    public init()
}
```

### DeliveryMethod

Underlying WCSession delivery method.

```swift
public enum DeliveryMethod: String, Sendable, Hashable, Codable {
    case message   // sendMessageData
    case userInfo  // transferUserInfo
    case context   // applicationContext
}
```

### RecoverySuggestion

User-facing suggestions for recovering from connectivity issues.

```swift
public enum RecoverySuggestion: String, Sendable, Hashable, CaseIterable {
    case openCompanionApp
    case restartWatch

    public var localizedDescription: String
}
```

**Note:** Recovery suggestions use Swift String Catalogs for localization.
