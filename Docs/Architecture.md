# Architecture Overview

WatchConnectivitySwift provides a modern, type-safe abstraction over Apple's WatchConnectivity framework. This document explains the architecture and design decisions.

## Design Principles

### 1. Type Safety

The library uses Swift's type system to ensure compile-time safety:

- **Associated Types**: Each `WatchRequest` declares its `Response` type
- **Codable**: All data is serialized/deserialized using Swift's Codable
- **Sendable**: All types are `Sendable` for Swift 6 concurrency safety

### 2. Swift Concurrency

Built from the ground up for async/await:

- **async/await**: All asynchronous operations use async/await
- **@MainActor**: Public classes are main-actor isolated
- **AsyncStream**: Diagnostic events and application context updates use AsyncStream
- **Isolated deinit**: Uses Swift 6's `isolated deinit` for safe cleanup

### 3. Observable

Designed for SwiftUI integration:

- **ObservableObject**: `WatchConnection` and `SharedState` are ObservableObjects
- **@Published**: All observable state uses @Published properties
- **@Observable**: `SharedState` uses Swift's Observation framework
- **Reactive**: State changes automatically update the UI

## Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        WatchConnection                          │
│  - Session management                                           │
│  - Handler registration                                         │
│  - Request/response routing                                     │
│  - Health monitoring                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │  Delivery   │  │   Retry     │  │     Health Tracker      │ │
│  │  Strategy   │  │   Policy    │  │                         │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Wire Protocol                            ││
│  │  - WireRequest / WireResponse                               ││
│  │  - WireUserInfo                                             ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      SharedState<T>                             │
│  - Simple state synchronization via applicationContext          │
│  - Last-write-wins semantics (WCSession behavior)              │
│  - @Observable for SwiftUI integration                          │
└─────────────────────────────────────────────────────────────────┘
```

## WatchConnection

The central class that manages all watch connectivity operations.

### Responsibilities

1. **Session Management**
   - Activates and monitors WCSession
   - Handles activation state changes
   - Observes reachability via KVO

2. **Message Routing**
   - Routes incoming requests to registered handlers
   - Correlates responses with pending requests
   - Handles fire-and-forget messages

3. **Reliability**
   - Implements retry logic with fixed 200ms delay between attempts
   - Manages fallback delivery strategies
   - Queues requests when offline (in-memory)

4. **Health Monitoring**
   - Tracks success/failure patterns
   - Reports healthy/unhealthy states
   - Supports recovery attempts

### Handler Registration

```swift
// Type-erased handler storage
private var handlers: [String: @Sendable (Data) async throws -> Data] = [:]

// Registration with type safety
func register<R: WatchRequest>(_ type: R.Type, handler: @escaping (R) async throws -> R.Response) {
    let typeName = String(describing: R.self)
    handlers[typeName] = { data in
        let request = try decoder.decode(R.self, from: data)
        let response = try await handler(request)
        return try encoder.encode(response)
    }
}
```

The type name is used as a key to look up handlers. When a request arrives, the library:

1. Decodes the `WireRequest` to get the type name
2. Looks up the handler by type name
3. Decodes the payload to the specific request type
4. Invokes the handler
5. Encodes the response
6. Sends the `WireResponse` back

## Wire Protocol

The wire protocol defines how messages are serialized for transmission.

### WireRequest

```swift
struct WireRequest: Codable, Sendable {
    let typeName: String      // "FetchUserRequest"
    let payload: Data         // JSON-encoded request
    let requestID: UUID       // For response correlation
    let isFireAndForget: Bool // Whether response is expected
    let timestamp: Date       // When request was created
}
```

### WireResponse

```swift
struct WireResponse: Codable, Sendable {
    let outcome: Outcome      // .success(Data) or .failure(Error)
    let requestID: UUID       // Correlates with WireRequest
    let timestamp: Date       // When response was created
}
```

## Delivery Strategies

The library supports multiple WCSession transport mechanisms:

| Method | Characteristics |
|--------|-----------------|
| `sendMessageData` | Real-time, requires both apps active, can fail |
| `transferUserInfo` | Queued, guaranteed delivery, ordered |
| `applicationContext` | Latest-value-wins, guaranteed delivery |

Strategies combine these methods:

```
messageWithUserInfoFallback:
  1. Try sendMessageData
  2. If fails → transferUserInfo

messageWithContextFallback:
  1. Try sendMessageData
  2. If fails → applicationContext

messageOnly:
  1. Try sendMessageData
  2. If fails → throw error
```

## Retry Policy

Retries use a simple, predictable approach:

- Fixed 200ms delay between retry attempts
- Configurable maximum attempts (default: 3)
- Configurable overall timeout (default: 10 seconds)

```swift
// Built-in policies
.default     // 3 attempts, 10s timeout
.patient     // 5 attempts, 30s timeout
.none        // 1 attempt, no retries

// Custom policy
RetryPolicy(maxAttempts: 4, timeout: .seconds(15))
```

## SharedState

`SharedState<T>` provides simple state synchronization via `applicationContext`.

### Semantics

- **Last-write-wins**: If both devices update simultaneously, one wins arbitrarily
- **No versioning**: The library doesn't track versions or sequence numbers
- **No conflict resolution**: WCSession's native behavior is used directly
- **Immediate sync**: Updates are sent immediately (WCSession coalesces internally)

### Multicast Observation

Multiple `SharedState` instances can observe the same `WatchConnection`:

```swift
// All of these receive updates from the same connection
let settingsState = SharedState(initialValue: Settings(), connection: connection)
let profileState = SharedState(initialValue: Profile(), connection: connection)
let statusState = SharedState(initialValue: Status(), connection: connection)
```

This is implemented using `MulticastStream`, which broadcasts incoming application contexts to all subscribers.

## Health Tracking

The `HealthTracker` monitors communication patterns:

```
healthy → (5 consecutive failures) → unhealthy
unhealthy → (any success) → healthy
```

When unhealthy, the library provides localized recovery suggestions to guide users.

## Thread Safety

All public classes use `@MainActor` isolation:

```swift
@MainActor
public final class WatchConnection: NSObject, ObservableObject {
    // All properties and methods run on main actor
}
```

WCSessionDelegate methods are `nonisolated` and dispatch to main actor:

```swift
nonisolated func session(_ session: WCSession, didReceiveMessageData data: Data) {
    Task { @MainActor in
        // Handle on main actor
    }
}
```

## Testing

The library is designed for testability:

1. **WCSessionProviding Protocol**: Abstracts WCSession for mocking
2. **MockWCSession**: Configurable mock for unit tests
3. **FlakyWCSession**: Simulates unreliable connections
4. **PreviewWCSession**: For SwiftUI previews

```swift
// Production
let connection = WatchConnection(session: WCSession.default)

// Testing
let mock = MockWCSession()
mock.sendMessageError = WatchConnectionError.notReachable
let connection = WatchConnection(session: mock)
```
