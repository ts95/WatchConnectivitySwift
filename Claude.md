# WatchConnectivitySwift

A Swift library that simplifies communication between iOS and watchOS apps using Apple's WatchConnectivity framework. Provides async/await support, type-safe request/response patterns, shared state synchronization, and reliability features.

## Current Version

**Version: 5.0.0**

## Version Management

When incrementing the version number, update ALL of the following files:

1. **README.md** - Update the version badge at the top:
   ```markdown
   ![Version](https://img.shields.io/badge/version-X.Y.Z-blue.svg)
   ```

2. **README.md** - Update the SPM installation instruction:
   ```swift
   .package(url: "https://github.com/ts95/WatchConnectivitySwift.git", from: "X.Y.Z")
   ```

3. **CLAUDE.md** - Update the "Current Version" section above

4. **Git tag** - Create a new git tag matching the version:
   ```bash
   git tag X.Y.Z
   git push origin X.Y.Z
   ```

**Important**: Always update all locations simultaneously to maintain consistency. Use semantic versioning (MAJOR.MINOR.PATCH).

## Documentation Maintenance

After making changes to the library code, always update the documentation:

1. **README.md** - Update any affected code examples, feature descriptions, or API references
2. **Docs/*.md** - Update the relevant documentation files:
   - `GettingStarted.md` - Installation and basic usage
   - `Reliability.md` - Retry policies, delivery modes, health monitoring
   - `SharedState.md` - State synchronization API
   - `Architecture.md` - Internal design (if architecture changes)
   - `API-Reference.md` - API details
   - `Migration-Guide.md` - If there are breaking changes

**Important**: Documentation should always reflect the current state of the code. Outdated examples cause confusion.

## Build Commands

```bash
# Build the library (note: requires iOS/watchOS SDK, won't work on macOS-only)
swift build

# Run tests (requires Xcode with iOS/watchOS simulator)
xcodebuild test -scheme WatchConnectivitySwift -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Build for release
swift build -c release
```

Note: This library uses WatchConnectivity which is only available on iOS and watchOS. Building with `swift build` on macOS will fail due to missing WatchConnectivity module. Use Xcode for development and testing.

## Project Structure

```
Sources/WatchConnectivitySwift/
├── WatchConnection.swift         # Main entry point, handles all communication
├── WatchRequest.swift            # Protocol definitions for type-safe requests
├── WCSessionProviding.swift      # Protocol for WCSession abstraction (testability)
├── FileTransfer.swift            # File transfer tracking and received files
├── DeliveryStrategy.swift        # Message delivery strategies with fallbacks
├── DeliveryMode.swift            # Delivery timing modes
├── RetryPolicy.swift             # Simple retry configuration (maxAttempts, timeout)
├── WatchConnectionError.swift    # Comprehensive error types
├── State/
│   └── SharedState.swift         # Simple state synchronization
├── Reliability/
│   ├── SessionHealth.swift       # Session health status (healthy/unhealthy)
│   ├── HealthTracker.swift       # Minimal health monitoring
│   ├── RecoverySuggestion.swift  # Localized recovery suggestions
│   └── DiagnosticEvent.swift     # Diagnostic event stream
├── Internal/
│   └── WireProtocol.swift        # Wire format for messages
└── Testing/
    └── PreviewWCSession.swift    # Public mock session for SwiftUI previews

Tests/WatchConnectivitySwiftTests/
├── WatchConnectionTests.swift    # Main connection tests
├── SharedStateTests.swift        # State synchronization tests
├── RetryPolicyTests.swift        # Retry policy tests
├── DeliveryStrategyTests.swift   # Delivery strategy tests
├── WatchConnectivitySwiftTests.swift  # Error and delivery mode tests
└── Mocks/
    ├── MockWCSession.swift       # Mock WCSession for testing
    └── FlakyWCSession.swift      # Simulated unreliable session for reliability tests
```

## Architecture

**Simplified design (v5.0.0):**

1. **WatchConnection**: Main entry point - handles activation, message sending, request handling, file transfers, and session management. Uses `@MainActor` for thread safety. Provides `receivedApplicationContexts` AsyncStream for context updates.

2. **Type-safe requests**: `WatchRequest` protocol with associated `Response` type. `FireAndForgetRequest` for one-way messages.

3. **SharedState<T>**: Simple state container that syncs via `applicationContext`. Requires a `WatchConnection` instance. No versioning, no conflict resolution - last write wins (WCSession semantics).

4. **File transfers**: `FileTransfer` class for tracking outgoing transfers with progress, `ReceivedFile` struct for incoming files. Background transfers continue when app is suspended.

5. **Minimal health tracking**: `SessionHealth` (healthy/unhealthy), `HealthTracker` (5 consecutive failures = unhealthy), `RecoverySuggestion` with localization support.

## Key Patterns

- **@MainActor**: All public classes are main-actor isolated for thread safety
- **ObservableObject**: `WatchConnection` and `SharedState` expose `@Published` properties for SwiftUI
- **AsyncStream**: Diagnostic events, application contexts, files use continuation-based streams
- **Protocol with associated types**: `WatchRequest` uses associated `Response` type for type safety
- **Delegate-first design**: Data flows through WCSession delegate methods, not KVO (except for `isReachable`)
- **Swift 6 strict concurrency**: Full `Sendable` compliance, `@preconcurrency import WatchConnectivity`
- **Isolated deinit**: Uses Swift 6's `isolated deinit` feature for safe cleanup in `@MainActor` classes

## Swift 6 Concurrency Notes

### Isolated Deinit (SE-0371)

Swift 6 introduced `isolated deinit` which allows deinitializers to run in the actor's isolation context. This is used in `SharedState` to safely cancel observation tasks:

```swift
@MainActor
public final class SharedState<State> {
    private var observationTask: Task<Void, Never>?

    isolated deinit {
        observationTask?.cancel()  // Safe - runs on MainActor
    }
}
```

Before `isolated deinit`, accessing `@MainActor`-isolated properties in `deinit` was unsafe because `deinit` was always nonisolated. With `isolated deinit`, the deinitializer runs on the actor's executor, making it safe to access isolated state.

**Key points:**
- Use `isolated deinit` when you need to access actor-isolated properties during cleanup
- The deinitializer will be scheduled on the actor's executor if not already there
- Introduced in Swift 6.1 (SE-0371)

## Platform Requirements

- iOS 17.0+ / watchOS 10.0+
- Swift 6.0+ (Strict concurrency required)
- Xcode 16+

## Dependencies

No external dependencies. Uses Foundation, WatchConnectivity, and Combine.

## Code Conventions

- Swift 6 strict concurrency (Sendable, @MainActor, @preconcurrency)
- async/await for all asynchronous operations
- Codable for all serialization
- @MainActor classes (not actors) for ObservableObject compatibility
- Fixed 200ms delay between retries (simple and predictable)
- Comprehensive error types with Codable conformance for wire transmission

## Testing

Tests use Swift Testing framework (`@Test`, `@Suite`, `#expect`). Mock classes:

- `MockWCSession`: Configurable mock for unit tests
- `FlakyWCSession`: Simulates unreliable connections for reliability testing

Run tests in Xcode with iOS Simulator target.

## WCSession Behavior Notes

Important characteristics of Apple's WCSession that affect this library:

### Single Delegate Constraint
- **WCSession only supports ONE delegate at a time.** Setting a new delegate overwrites the previous one.
- In apps using this library, ensure only ONE `WatchConnection` instance is active that uses `WCSession.default`.
- Multiple `WatchConnection` instances will fight for the delegate, causing missed messages.

### Threading
- **All WCSession delegate methods are called on a background thread**, not the main thread.
- When using Swift concurrency, wrap handler logic in `Task { @MainActor in ... }` to safely access main-actor-isolated state.
- The `replyHandler` callback can be called from any thread.

### Simulator Quirks
- **`isReachable` may never return `true` in the simulator**, even when both simulators are paired and running.
- Despite incorrect reachability status, `applicationContext` and `sendMessage` may still work.
- There may be a small delay after app launch before the session becomes truly reachable.

### Reliability on Real Devices
- WCSession can be unreliable on real devices—sometimes the watch is reachable, sometimes not.
- Some failure modes require rebooting the watch to resolve.
- `isReachable` may return `true` even when the companion app is not running (e.g., if app is in Dock or has a complication).

### Delegate Method Pairing
- `sendMessage` with a `replyHandler` requires implementing `session(_:didReceiveMessage:replyHandler:)` on the receiver.
- `sendMessage` without a `replyHandler` requires implementing `session(_:didReceiveMessage:)` on the receiver.
- **If you implement the wrong delegate method, the sender will time out waiting for a response.**

### Data Type Constraints
- Message dictionaries (`[String: Any]`) only support **Property List types** (primitives, arrays, dictionaries, Data, Date).
- For complex types, encode to Data using Codable (which is what this library does internally).

### Activation Requirements
- Cannot call `activate()` without first setting a delegate.
- Both devices must independently activate their WCSession.
- Check `WCSession.isSupported()` before using—iOS devices only support sessions when paired with a watch.

### updateApplicationContext Threading
- `updateApplicationContext` can block the calling thread when WCSession is not fully connected or during internal synchronization.
- **Never call on main thread without protection** if you care about UI responsiveness.
- This library runs `updateApplicationContext` calls in a detached Task (`Task.detached(priority: .utility)`) to prevent main thread blocking.

### sendMessage Direction Asymmetry
- **iOS → watchOS**: The watch app must be in the foreground to receive messages.
- **watchOS → iOS**: The iOS app can be in the background and will be woken up to receive messages.
- `updateApplicationContext` works regardless of app state (foreground or background).

## v5.0.0 Breaking Changes (from v1.0.0)

### Removed
- `StateVersion`, `ConflictResolutionStrategy`, `StateConflict`, `StateChange`, `ChangeSource` - versioning/conflict resolution removed
- `SharedState.version`, `.values`, `.conflicts`, `.syncNow()`, `.pendingUpdateCount` - simplified API
- `ConnectionMode`, `ConnectionStatus` - unnecessary complexity
- `PersistentRequestQueue` - unnecessary complexity
- Rate limiting in SharedState - WCSession already coalesces
- Static handler registry - replaced with instance-based AsyncStream
- `SessionHealth.degraded` - simplified to healthy/unhealthy only
- `RecoverySuggestion.bringDevicesCloser`, `.checkBluetoothEnabled`, `.repairDevices` - simplified suggestions

### Changed
- `SharedState` now requires a `WatchConnection` parameter
- `SharedState` updates sync immediately (no 5-second rate limiting)
- `SessionHealth` is now `.healthy` or `.unhealthy(suggestion:)`
- `RecoverySuggestion` uses `localizedDescription` instead of `title`/`message`
- `HealthTracker` uses simpler 5-consecutive-failures threshold

### Added
- `WatchConnection.receivedApplicationContexts: AsyncStream<[String: Any]>` for context observation
- `WatchConnection.session` property for direct session access
- `RecoverySuggestion.localizedDescription` with Swift localization support
