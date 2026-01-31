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

1. **Connection Management** - Class-level connect/disconnect control
2. **Connection State** - Reactive connection status observation
3. **Waiting Utilities** - Wait for activation or connection
4. **Retry Policies** - Automatic retry with exponential backoff
5. **Delivery Strategies** - Fallback transport mechanisms
6. **Health Monitoring** - Detect and recover from persistent issues
7. **Recovery Suggestions** - User-facing guidance for connectivity issues
8. **Request Queuing** - Persist requests during offline periods

## Connection Management

### Connection Mode

Control whether the connection actively maintains connectivity:

```swift
// Start actively maintaining connectivity
await connection.connect()
print(connection.connectionMode) // .active

// Disconnect and cancel all pending requests
connection.disconnect()
print(connection.connectionMode) // .passive
```

In **active mode**:
- Queued requests are processed as soon as connectivity is available
- Diagnostic events are emitted for connection attempts

In **passive mode** (default):
- Connection only attempts to send when explicitly requested

### Observing Connection State

The `connectionState` stream emits the current status immediately on subscription:

```swift
for await status in connection.connectionState {
    if status.canSendMessages {
        // Ready for real-time messaging
    } else if status.canUseBackgroundTransfers {
        // Can use queued delivery
    } else {
        // Offline
    }
}
```

For one-time checks:

```swift
let status = connection.currentConnectionStatus
print(status.isActivated, status.isReachable)
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
if connection.sessionHealth.requiresUserIntervention {
    await connection.attemptRecovery()
}

// If still unhealthy, guide user
if !connection.sessionHealth.isHealthy {
    presentRecoveryInstructions()
    // "Try restarting your Apple Watch and iPhone"
}
```

## Recovery Suggestions

The library provides user-facing recovery suggestions based on session health:

```swift
Task {
    for await suggestion in connection.recoverySuggestions {
        showAlert(
            title: suggestion.title,
            message: suggestion.message
        )

        // Check severity for UI treatment
        switch suggestion.severity {
        case .minor:
            // Subtle indicator
        case .moderate:
            // Warning badge
        case .major, .critical:
            // Prominent alert
        }
    }
}
```

### Available Suggestions

| Suggestion | Severity | When Emitted |
|------------|----------|--------------|
| `bringDevicesCloser` | Minor | Intermittent connectivity |
| `openCompanionApp` | Minor | App not reachable but paired |
| `checkBluetoothEnabled` | Moderate | Bluetooth issues suspected |
| `restartWatch` | Major | Persistent session failures |
| `repairDevices` | Critical | After other recovery fails |

Suggestions are deduplicated with a 30-second window to avoid spamming users.

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
3. **Persistence**: Queue survives app termination (within limits)
4. **Expiration**: Old requests expire after 1 hour

### Queue Configuration

The queue has sensible defaults:

- Maximum 100 queued requests
- Requests expire after 1 hour
- Oldest requests are dropped if queue is full

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
        switch connection.sessionHealth {
        case .healthy:
            EmptyView()
        case .degraded:
            WarningBanner("Connection unstable")
        case .unhealthy:
            ErrorBanner("Connection lost") {
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

### 5. Test with FlakySession

```swift
// Simulate unreliable connection
let flakySession = FlakySession()
flakySession.failureProbability = 0.3  // 30% failure rate
let connection = WatchConnection(session: flakySession)

// Test that your app handles failures gracefully
```
