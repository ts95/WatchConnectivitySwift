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
- **AsyncStream**: Diagnostic events and state changes use AsyncStream

### 3. Observable

Designed for SwiftUI integration:

- **ObservableObject**: `WatchConnection` and `SharedState` are ObservableObjects
- **@Published**: All observable state uses @Published properties
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
│  │  - WireApplicationContext                                   ││
│  │  - WireUserInfo                                             ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      SharedState<T>                             │
│  - Versioned state synchronization                              │
│  - Conflict detection and resolution                            │
│  - Change observation                                           │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │   State     │  │  Conflict   │  │      State Change       │ │
│  │   Version   │  │  Resolution │  │                         │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
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
   - Implements retry logic with exponential backoff
   - Manages fallback delivery strategies
   - Queues requests when offline
   - Persists queue for crash recovery

4. **Health Monitoring**
   - Tracks success/failure patterns
   - Reports degraded/unhealthy states
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

Retries use exponential backoff with jitter:

```
Attempt 0: immediate
Attempt 1: initialDelay * multiplier^0 + jitter
Attempt 2: initialDelay * multiplier^1 + jitter
Attempt 3: initialDelay * multiplier^2 + jitter
...
```

Jitter prevents thundering herd problems when multiple requests retry simultaneously.

## SharedState

`SharedState<T>` provides versioned, conflict-resolving state synchronization.

### State Versioning

Each state update includes:

```swift
struct StateVersion {
    let sequenceNumber: UInt64  // Monotonically increasing per device
    let timestamp: Date         // When update was created
    let origin: DeviceOrigin    // .iOS or .watchOS
    let updateID: UUID          // Unique identifier
}
```

### Conflict Detection

A conflict occurs when:
1. Local device has pending updates (not yet acknowledged)
2. Remote update arrives

### Conflict Resolution

The library provides built-in strategies:

```swift
.latestWins          // Most recent timestamp wins
.earliestWins        // Earliest timestamp wins
.iOSWins             // iOS always wins
.watchOSWins         // watchOS always wins
.highestSequenceWins // Higher sequence number wins
.custom { local, remote in ... } // Custom merge
```

## Health Tracking

The `HealthTracker` monitors communication patterns:

```
healthy → (3 consecutive failures) → degraded
degraded → (success) → healthy
degraded → (10 consecutive failures) → unhealthy
unhealthy → (success) → healthy
```

When unhealthy, the library recommends user intervention (e.g., restarting devices).

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

1. **SessionProviding Protocol**: Abstracts WCSession for mocking
2. **MockSession**: Configurable mock for unit tests
3. **FlakySession**: Simulates unreliable connections

```swift
// Production
let connection = WatchConnection(session: WCSession.default)

// Testing
let mock = MockSession()
mock.sendMessageError = WatchConnectionError.notReachable
let connection = WatchConnection(session: mock)
```
