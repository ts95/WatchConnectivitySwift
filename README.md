# WatchConnectivitySwift

![Version](https://img.shields.io/badge/version-5.1.0-blue.svg)
![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![iOS](https://img.shields.io/badge/iOS-17.0+-green.svg)
![watchOS](https://img.shields.io/badge/watchOS-10.0+-green.svg)
![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)

**WatchConnectivitySwift** is a modern, type-safe Swift library that simplifies communication between iOS and watchOS using Apple's `WatchConnectivity` framework. Built from the ground up with Swift 6 strict concurrency, async/await, and strong typing, it enables you to write robust, reactive, and testable communication layers between your iPhone and Apple Watch apps.

---

## Features

- **Type-safe request/response** using protocols with associated types
- **Swift 6 strict concurrency** compliant with `@MainActor` isolation
- **Automatic retry** with configurable retry policies for reliable message delivery
- **Fallback delivery strategies** (message -> userInfo -> context)
- **File transfers** with progress tracking and async/await support
- **Shared state synchronization** via `applicationContext`
- **Session health monitoring** with automatic recovery
- **SwiftUI integration** via `ObservableObject` with `@Published` properties
- **Comprehensive diagnostics** via `AsyncStream` events

---

## Requirements

| Platform | Minimum Version |
|----------|-----------------|
| iOS      | 17.0+           |
| watchOS  | 10.0+           |
| Swift    | 6.0+            |
| Xcode    | 16.0+           |

---

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ts95/WatchConnectivitySwift.git", from: "5.1.0")
]
```

Or in Xcode: File > Add Package Dependencies, then enter the repository URL.

---

## Quick Start

### 1. Define Your Request Types (Shared Code)

Create a shared Swift file or framework that both your iOS and watchOS targets can access. This ensures both sides understand the same request/response types.

```swift
// 📁 Shared/WatchRequests.swift
// ⚠️ This file must be included in BOTH your iOS and watchOS targets,
//    or placed in a shared framework that both targets depend on.

import WatchConnectivitySwift

// Define a request that the Watch sends to the iPhone.
// The iPhone will handle this and return a Recipe.
struct FetchRecipeRequest: WatchRequest {
    // The response type that the handler must return
    typealias Response = Recipe

    let recipeID: String
}

// The response model - must be Codable for serialization over the wire
struct Recipe: Codable, Sendable {
    let title: String
    let ingredients: [String]
}
```

### 2. Register Handlers on iPhone (iOS Target)

On the iOS side, register handlers for requests that the Watch will send. The iPhone acts as the "server" that responds to Watch requests.

```swift
// 📁 iOS App/AppCoordinator.swift
// 💡 This code runs ONLY on the iPhone

import WatchConnectivitySwift

@MainActor
class AppCoordinator {
    // Create a single WatchConnection instance for your iOS app
    let connection = WatchConnection()

    func setup() {
        // Register a handler for FetchRecipeRequest.
        // When the Watch sends this request, this closure is called
        // and the returned Recipe is sent back to the Watch.
        connection.register(FetchRecipeRequest.self) { request in
            // Access your iOS app's data sources here:
            // - Core Data, SwiftData, Realm
            // - Network APIs, Firestore
            // - UserDefaults, Keychain, etc.
            return Recipe(
                title: "Pasta Carbonara",
                ingredients: ["Pasta", "Eggs", "Pancetta", "Parmesan"]
            )
        }
    }
}
```

### 3. Send Requests from Watch (watchOS Target)

On the watchOS side, send requests to the iPhone and await the typed response.

```swift
// 📁 watchOS App/RecipeViewModel.swift
// 💡 This code runs ONLY on the Apple Watch

import WatchConnectivitySwift

@MainActor
class RecipeViewModel: ObservableObject {
    @Published var recipe: Recipe?
    @Published var error: Error?

    // Create a single WatchConnection instance for your watchOS app
    private let connection = WatchConnection()

    func loadRecipe(id: String) async {
        do {
            // Send the request to the iPhone and await the response.
            // The iPhone's registered handler will process this and return a Recipe.
            recipe = try await connection.send(
                FetchRecipeRequest(recipeID: id),
                strategy: .messageWithUserInfoFallback  // Falls back to queued delivery if unreachable
            )
        } catch {
            self.error = error
        }
    }
}
```

> **Note:** Communication can go both ways. The Watch can also register handlers, and the iPhone can send requests to the Watch using the same pattern.

---

## Core Concepts

### Request Types

```swift
// 📁 Shared/Requests.swift
// ⚠️ Place in shared code accessible by both iOS and watchOS targets

// Standard request expecting a response
struct MyRequest: WatchRequest {
    typealias Response = MyResponse
    let data: String
}

struct MyResponse: Codable, Sendable {
    let result: String
}

// Fire-and-forget request (no response expected)
// Useful for logging, analytics, or notifications where you don't need confirmation
struct LogEventRequest: FireAndForgetRequest {
    let eventName: String
}
```

### Delivery Strategies

Choose how messages are delivered based on your reliability needs. WatchConnectivity provides three transport mechanisms with different tradeoffs:

| Transport | Speed | Reliability | Behavior |
|-----------|-------|-------------|----------|
| `sendMessage` | Instant | May fail | Requires counterpart app to be reachable |
| `transferUserInfo` | Queued | Guaranteed | Delivers in order when app becomes active |
| `applicationContext` | Queued | Guaranteed | Only latest value delivered (overwrites pending) |

**Available strategies:**

```swift
// DEFAULT: Best for most use cases
// Instant delivery when possible, queued backup when not
.messageWithUserInfoFallback

// For settings/state where only latest value matters
// If you send 5 updates while offline, only the last one is delivered
.messageWithContextFallback

// For real-time features only (remote control, live updates)
// Fails immediately if counterpart is unreachable
.messageOnly

// For background sync where order matters
// All messages queued and delivered in order, even if app is suspended
.userInfoOnly

// For state sync where only current value matters
// Overwrites any pending value not yet delivered
.contextOnly
```

**When to use each:**

| Strategy | Use Case |
|----------|----------|
| `messageWithUserInfoFallback` | Chat messages, notifications, data requests—anything that must eventually arrive |
| `messageWithContextFallback` | Settings sync, preferences, status updates where stale values are useless |
| `messageOnly` | Remote camera shutter, live game controls, time-sensitive actions |
| `userInfoOnly` | Workout logs, transaction history, audit trails that need ordering |
| `contextOnly` | Current user state, now-playing info, connection status |

### Retry Policies

Configure retry behavior for transient failures:

```swift
// Built-in policies
.default     // 3 attempts, 10s timeout, 200ms delay between retries
.patient     // 5 attempts, 30s timeout, 200ms delay between retries
.none        // 1 attempt, no retries

// Custom policy
RetryPolicy(maxAttempts: 4, timeout: .seconds(15))
```

### Shared State

Synchronize state between devices. `SharedState` uses `applicationContext` under the hood, which automatically syncs the latest value to the counterpart device.

```swift
// 📁 Shared/AppSettings.swift
// ⚠️ The model must be in shared code accessible by both targets

struct AppSettings: Codable, Sendable, Equatable {
    var theme: String
    var notificationsEnabled: Bool
}
```

```swift
// 📁 iOS App/SettingsManager.swift  (or watchOS App/SettingsManager.swift)
// 💡 Use the same pattern on BOTH iOS and watchOS targets.
//    Each side creates its own SharedState instance with the same structure.
//    Updates from either side automatically sync to the other.

import WatchConnectivitySwift

@MainActor
class SettingsManager {
    let sharedSettings: SharedState<AppSettings>

    init(connection: WatchConnection) {
        // Both iOS and watchOS create a SharedState with the same initial value.
        // The library handles syncing updates between devices automatically.
        sharedSettings = SharedState(
            initialValue: AppSettings(theme: "light", notificationsEnabled: true),
            connection: connection  // Pass the WatchConnection instance
        )
    }

    func updateTheme(_ theme: String) throws {
        // Update locally - the change is automatically pushed to the other device
        var settings = sharedSettings.value
        settings.theme = theme
        try sharedSettings.update(settings)
    }
}

### File Transfers

Transfer files between devices with progress tracking. Files are transferred in the background and continue even when your app is suspended.

```swift
// 📁 iOS App/FileTransferManager.swift  (or watchOS App/FileTransferManager.swift)
// 💡 File transfers work in both directions between iOS and watchOS

import WatchConnectivitySwift

@MainActor
class FileTransferManager {
    private let connection = WatchConnection()

    // MARK: - Sending Files

    func sendFile(_ fileURL: URL, metadata: [String: Any]? = nil) async throws {
        // Start the transfer and get a FileTransfer object for tracking
        let transfer = try await connection.transferFile(fileURL, metadata: metadata)

        // Option 1: Wait for completion
        try await transfer.waitForCompletion()

        // Option 2: Track progress
        for await progress in transfer.progressUpdates {
            print("Progress: \(Int(progress * 100))%")
        }
    }

    // MARK: - Receiving Files

    func setupFileReceiving() {
        // Option 1: Callback-based
        connection.onFileReceived = { file in
            // ⚠️ IMPORTANT: Move the file synchronously!
            // The file will be deleted after this handler returns.
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = documents.appendingPathComponent(file.fileURL.lastPathComponent)
            try? FileManager.default.moveItem(at: file.fileURL, to: destination)

            // Access any metadata sent with the file
            if let id = file.metadata?["id"] as? String {
                print("Received file with ID: \(id)")
            }
        }

        // Option 2: Async stream
        Task {
            for await file in connection.receivedFiles {
                // Process each received file
                let destination = documentsDirectory.appendingPathComponent(file.fileURL.lastPathComponent)
                try? FileManager.default.moveItem(at: file.fileURL, to: destination)
            }
        }
    }
}
```

### Session Health Monitoring

```swift
// 📁 iOS App/ConnectionMonitor.swift  (or watchOS App/ConnectionMonitor.swift)
// 💡 Use on EITHER or BOTH targets to monitor connection health.
//    Each device tracks the health of its connection to the counterpart.

import WatchConnectivitySwift

@MainActor
class ConnectionMonitor: ObservableObject {
    @Published var health: SessionHealth = .healthy

    private let connection = WatchConnection()

    func startMonitoring() {
        // Observe health changes via the diagnostic event stream
        Task {
            for await event in connection.diagnosticEvents {
                if case .healthChanged(_, let newHealth) = event {
                    health = newHealth
                }
            }
        }
    }

    func attemptRecovery() async {
        // Attempt recovery if the session is unhealthy
        if !connection.sessionHealth.isHealthy {
            await connection.attemptRecovery()
        }
    }

    func showRecoverySuggestion() -> String? {
        // Get localized recovery suggestion if unhealthy
        return connection.sessionHealth.suggestion?.localizedDescription
    }
}
```

---

## SwiftUI Integration

```swift
// 📁 watchOS App/ContentView.swift
// 💡 This example shows a watchOS view that requests data from the iPhone.
//    The RecipeViewModel (defined in the Quick Start section) sends the request.

import SwiftUI

struct ContentView: View {
    // The view model handles communication with the iPhone
    @StateObject private var viewModel = RecipeViewModel()

    var body: some View {
        VStack {
            if let recipe = viewModel.recipe {
                Text(recipe.title)
                    .font(.headline)

                ForEach(recipe.ingredients, id: \.self) { ingredient in
                    Text("• \(ingredient)")
                }
            }

            Button("Load Recipe") {
                Task {
                    // This triggers a request to the iPhone
                    await viewModel.loadRecipe(id: "carbonara")
                }
            }
        }
    }
}
```

You can also observe connection state and shared state changes directly in SwiftUI:

```swift
// 📁 iOS App/SettingsView.swift  (or watchOS App/SettingsView.swift)
// 💡 SharedState works on BOTH targets - changes sync automatically

import SwiftUI
import WatchConnectivitySwift

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager

    var body: some View {
        Toggle(
            "Dark Mode",
            isOn: Binding(
                get: { settingsManager.sharedSettings.value.theme == "dark" },
                set: { isDark in
                    try? settingsManager.updateTheme(isDark ? "dark" : "light")
                }
            )
        )
    }
}
```

---

## Documentation

Comprehensive documentation is available in the [Docs](Docs/) folder:

- **[Getting Started](Docs/GettingStarted.md)** - Installation and basic setup
- **[Architecture Overview](Docs/Architecture.md)** - Design and internals
- **[API Reference](Docs/API-Reference.md)** - Complete API documentation
- **[Reliability Features](Docs/Reliability.md)** - Retries, health monitoring, queuing
- **[Shared State](Docs/SharedState.md)** - State synchronization between devices
- **[Migration Guide](Docs/Migration-Guide.md)** - Upgrading from v1.x

---

## Migration from v1.x

Version 5.0.0 is a complete rewrite with a new API. See the [Migration Guide](Docs/Migration-Guide.md) for detailed instructions.

Key changes:

| v1.x | v5.0.0 |
|------|--------|
| `WatchConnectivityService` | `WatchConnection` |
| `WatchConnectivityRPCRepository` | Protocol-based `WatchRequest` |
| Completion handlers | `async/await` |
| Dictionary-based messages | Type-safe Codable requests |
| Manual retry logic | Built-in `RetryPolicy` |
| Manual state sync | `SharedState` for automatic sync |

---

## Testing

The library is designed for testability. You can inject a mock session to test your iOS or watchOS code without a real device connection:

```swift
// 📁 Tests/MyAppTests.swift
// 💡 Use MockWCSession in your unit tests to simulate Watch/iPhone communication

import WatchConnectivitySwift

// Create a mock session instead of a real WCSession
let mockSession = MockWCSession()
let connection = WatchConnection(session: mockSession)

// Configure the mock to return a specific response
// This simulates what the counterpart device would send back
mockSession.sendMessageResponse = try JSONEncoder().encode(
    WireResponse(outcome: .success(responseData), requestID: UUID(), timestamp: Date())
)

// Test your code - the mock handles the "network" layer
let response = try await connection.send(MyRequest())
```

### E2E Tests

The Demo app includes an end-to-end test harness for verifying real iOS-watchOS communication via paired simulators.

```bash
# Run E2E tests (creates/uses paired simulators)
./Scripts/e2e-test.sh

# Keep simulators running after tests for debugging
./Scripts/e2e-test.sh --keep-running

# Skip simulator erase (faster but may be flaky)
./Scripts/e2e-test.sh --no-clean
```

**Warning: E2E tests are inherently unstable.** WatchConnectivity in simulators has known limitations:
- `isReachable` may never report `true` even when communication works
- Timing is unpredictable; tests may pass or fail intermittently
- First launch after simulator erase requires extra warm-up time
- Some failures require rebooting the watch simulator to resolve

These tests are intended for manual verification and debugging, not CI automation. The unit tests with `MockWCSession` provide reliable, deterministic testing.

---

## License

MIT

---

## Authors

Created by [Toni Sucic](https://github.com/ts95).

Co-authored by [Claude Opus 4.5](https://www.anthropic.com/claude) with [Claude Code](https://www.anthropic.com/claude-code).

Contributions and feedback welcome!
