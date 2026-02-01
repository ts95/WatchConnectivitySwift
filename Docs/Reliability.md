# Reliability Features

WatchConnectivitySwift includes comprehensive reliability features to handle the inherent unreliability of WCSession connections. This guide explains how to use them effectively.

## Overview

Watch connectivity is inherently unreliable due to:

- Bluetooth connection drops
- Device sleep states
- App backgrounding
- System resource constraints
- "Phantom reachability" (isReachable is true but messages fail)

The library addresses these issues through:

1. **Waiting Utilities** - Wait for activation or connection
2. **Retry Policies** - Automatic retry with fixed delay
3. **Delivery Strategies** - Fallback transport mechanisms
4. **Health Monitoring** - Detect and recover from persistent issues
5. **Recovery Suggestions** - User-facing guidance for connectivity issues
6. **Request Queuing** - Queue requests during offline periods

## Connection State

### Observing State

Use the `@Published` properties on `WatchConnection` to observe connection state:

```swift
struct ConnectionStatusView: View {
    @ObservedObject var connection: WatchConnection

    var body: some View {
        HStack {
            Circle()
                .fill(connection.isReachable ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(connection.isReachable ? "Connected" : "Disconnected")
        }
    }
}
```

### Waiting for Connection

Wait for the session to be ready:

```swift
// Wait for activation only
try await connection.waitForActivation(timeout: .seconds(10))

// Wait for full connectivity (activation + reachability)
try await connection.waitForConnection(timeout: .seconds(30))

// Wait indefinitely for connection
try await connection.waitForConnection()
```

### Send When Ready

For requests that should wait for connectivity and retry on failure:

```swift
let response = try await connection.sendWhenReady(
    MyRequest(),
    maxAttempts: 5,
    connectionTimeout: .seconds(60)
)
```

This method:
1. Waits for the connection to become available
2. Sends the request
3. Retries if the connection is lost during transmission

## Retry Policies

### Built-in Policies

```swift
// Default policy (recommended for most cases)
// - 3 attempts
// - 200ms fixed delay between retries
// - 10 second total timeout
let response = try await connection.send(request)

// Patient policy (for important requests)
// - 5 attempts
// - 200ms fixed delay between retries
// - 30 second timeout
let response = try await connection.send(request, retryPolicy: .patient)

// No retries (fail immediately on error)
let response = try await connection.send(request, retryPolicy: .none)
```

### Custom Policies

```swift
// Custom retry count and timeout
let policy = RetryPolicy(maxAttempts: 4, timeout: .seconds(15))
let response = try await connection.send(request, retryPolicy: policy)
```

### How Retries Work

```
Time: 0ms    200ms    400ms    600ms
      |       |        |         |
      v       v        v         v
   [Try 1] [Try 2]  [Try 3]   [Try 4]
             +200     +200      +200
           (fixed)  (fixed)   (fixed)
```

Retries use a fixed 200ms delay between attempts. The library automatically retries on transient errors like `.notReachable`, `.deliveryFailed`, and `.replyFailed`.

## Delivery Strategies

### Available Strategies

| Strategy | Primary | Fallback | Use Case |
|----------|---------|----------|----------|
| `messageWithUserInfoFallback` | Message | UserInfo | Default, guaranteed delivery |
| `messageWithContextFallback` | Message | Context | Latest-value-only state |
| `messageOnly` | Message | None | Real-time, time-sensitive |
| `userInfoOnly` | UserInfo | None | Guaranteed ordered delivery |
| `contextOnly` | Context | None | State synchronization |

### Transport Characteristics

| Transport | Requires Active Apps | Ordering | Delivery |
|-----------|---------------------|----------|----------|
| `sendMessageData` | Yes | N/A | Immediate or fail |
| `transferUserInfo` | No | FIFO | Queued, guaranteed |
| `applicationContext` | No | Last wins | Latest value only |

### Choosing a Strategy

```swift
// Real-time feature (game, live tracking)
// Fail fast if not reachable
let response = try await connection.send(
    request,
    strategy: .messageOnly,
    delivery: .immediate
)

// Important data that must be delivered
// Try real-time, fall back to queue
let response = try await connection.send(
    request,
    strategy: .messageWithUserInfoFallback
)

// Settings/preferences sync
// Only latest value matters
let response = try await connection.send(
    request,
    strategy: .messageWithContextFallback
)

// Log events that must arrive in order
let response = try await connection.send(
    request,
    strategy: .userInfoOnly
)
```

## Health Monitoring

### Session Health States

```swift
enum SessionHealth {
    case healthy
    // Session is working normally

    case unhealthy
    // Persistent failures, likely needs user intervention
}
```

### Health Transitions

```
healthy ──(failures)──> unhealthy
   ▲                         │
   │                         │
(success)                (success)
   │                         │
   └─────────────────────────┘
```

### Monitoring Health

```swift
// Check current state
if connection.sessionHealth.isHealthy {
    // Normal operation
} else {
    // Prompt user for action
    showRecoveryDialog()
}

// Observe health changes
Task {
    for await event in connection.diagnosticEvents {
        if case .healthChanged(let from, let to) = event {
            handleHealthChange(from: from, to: to)
        }
    }
}
```

### Recovery

```swift
// Attempt automatic recovery
if !connection.sessionHealth.isHealthy {
    await connection.attemptRecovery()
}

// If still unhealthy, guide user with the recovery suggestion
if case .unhealthy(let suggestion) = connection.sessionHealth {
    showAlert(suggestion.localizedDescription)
}
```

## Recovery Suggestions

When the session becomes unhealthy, it includes a `RecoverySuggestion` that can be displayed to users:

```swift
// Access suggestion when unhealthy
if case .unhealthy(let suggestion) = connection.sessionHealth {
    showAlert(suggestion.localizedDescription)
}

// Or observe health changes via diagnostics
Task {
    for await event in connection.diagnosticEvents {
        if case .healthChanged(_, let to) = event,
           case .unhealthy(let suggestion) = to {
            showAlert(suggestion.localizedDescription)
        }
    }
}
```

### Available Suggestions

| Suggestion | Description |
|------------|-------------|
| `openCompanionApp` | Ask user to open the app on the counterpart device |
| `restartWatch` | Ask user to restart their Apple Watch |

Suggestions use Swift's String Catalogs for localization.

## Diagnostic Events

The library emits detailed events for debugging:

```swift
Task {
    for await event in connection.diagnosticEvents {
        switch event {
        // Session lifecycle
        case .sessionActivated:
            print("Session activated")
        case .sessionDeactivated:
            print("Session deactivated")

        // Connectivity
        case .reachabilityChanged(let isReachable):
            print("Reachability: \(isReachable)")

        // Message events
        case .messageSent(let type, let duration):
            print("Sent \(type) in \(duration)")
        case .deliveryFailed(let type, let error, let willRetry):
            print("Failed: \(type), retry: \(willRetry)")
        case .fallbackUsed(let from, let to):
            print("Fallback: \(from) → \(to)")

        // Queue events
        case .requestQueued(let type, let size):
            print("Queued: \(type), queue size: \(size)")
        case .queueFlushed(let count):
            print("Flushed \(count) queued requests")

        // Health events
        case .healthChanged(let from, let to):
            print("Health: \(from) → \(to)")
        case .recoveryAttempted:
            print("Recovery attempted")
        case .recoverySucceeded:
            print("Recovery succeeded")
        case .recoveryFailed(let error):
            print("Recovery failed: \(error)")

        default:
            break
        }
    }
}
```

## Request Queuing

When the counterpart is not reachable, requests can be queued:

```swift
// Check pending requests
let pendingCount = connection.pendingRequestCount

// Cancel all queued requests
connection.cancelAllQueuedRequests()

// Cancel specific request
connection.cancelQueuedRequest(id: requestID)
```

### Queue Behavior

1. **Automatic queueing**: Requests are queued when offline (depending on delivery mode)
2. **Automatic flush**: Queued requests are sent when connectivity is restored
3. **In-memory**: Queue is held in memory (not persisted across app termination)

## Best Practices

### 1. Use Appropriate Policies

```swift
// Real-time features: no retries
let response = try await connection.send(
    request,
    delivery: .immediate,
    retryPolicy: .none
)

// Background sync: patient policy
let response = try await connection.send(
    request,
    delivery: .queued,
    retryPolicy: .patient
)
```

### 2. Handle Errors Gracefully

```swift
do {
    let response = try await connection.send(request)
} catch WatchConnectionError.timeout {
    // Specific handling for timeout
    showRetryOption()
} catch WatchConnectionError.notReachable {
    // Queue for later or show offline message
    showOfflineMessage()
} catch {
    // Generic error handling
    showErrorAlert(error)
}
```

### 3. Monitor Health for UX

```swift
struct ConnectionStatusView: View {
    @ObservedObject var connection: WatchConnection

    var body: some View {
        if case .unhealthy(let suggestion) = connection.sessionHealth {
            ErrorBanner(suggestion.localizedDescription) {
                Task { await connection.attemptRecovery() }
            }
        }
    }
}
```

### 4. Use Fire-and-Forget for Non-Critical Data

```swift
// Analytics don't need responses
struct LogEvent: FireAndForgetRequest {
    let name: String
    let parameters: [String: String]
}

// Send without waiting
await connection.send(LogEvent(name: "screen_view", parameters: [:]))
```

### 5. Test with FlakyWCSession

```swift
// Simulate unreliable connection
let flakySession = FlakyWCSession()
flakySession.failureProbability = 0.3  // 30% failure rate
let connection = WatchConnection(session: flakySession)

// Test that your app handles failures gracefully
```
