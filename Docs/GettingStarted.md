# Getting Started

This guide walks you through setting up WatchConnectivitySwift in your iOS and watchOS apps.

## Installation

### Swift Package Manager

Add the following dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ts95/WatchConnectivitySwift.git", from: "5.1.0")
]
```

Then add `WatchConnectivitySwift` to your target's dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: ["WatchConnectivitySwift"]
)
```

### Xcode

1. Open your project in Xcode
2. Go to File > Add Package Dependencies
3. Enter the repository URL: `https://github.com/ts95/WatchConnectivitySwift.git`
4. Select version 5.1.0 or later
5. Add the package to both your iOS and watchOS targets

## Basic Setup

### 1. Define Your Request Types

Create a shared Swift file accessible to both your iOS and watchOS targets:

```swift
import WatchConnectivitySwift

// A request that expects a response
struct FetchUserRequest: WatchRequest {
    typealias Response = User
    let userID: String
}

struct User: Codable, Sendable {
    let id: String
    let name: String
    let email: String
}

// A fire-and-forget request (no response)
struct LogAnalyticsEvent: FireAndForgetRequest {
    let eventName: String
    let parameters: [String: String]
}
```

### 2. Create the Connection

On both iOS and watchOS, create a `WatchConnection` instance. Typically, you'd store this as a singleton or in your app's environment:

```swift
import WatchConnectivitySwift

@MainActor
class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    let connection = WatchConnection()

    private init() {
        setupHandlers()
    }
}
```

### 3. Register Handlers (Receiving Side)

On the device that will **receive** requests, register handlers:

```swift
// On iPhone - handling requests from Watch
func setupHandlers() {
    connection.register(FetchUserRequest.self) { request in
        // Fetch user from your backend, database, etc.
        let user = try await UserService.fetchUser(id: request.userID)
        return user
    }

    connection.register(LogAnalyticsEvent.self) { request in
        Analytics.log(event: request.eventName, parameters: request.parameters)
        return VoidResponse()
    }
}
```

### 4. Send Requests (Sending Side)

On the device that will **send** requests:

```swift
// On Watch - sending requests to iPhone
@MainActor
class UserViewModel: ObservableObject {
    @Published var user: User?
    @Published var error: Error?

    private let connection: WatchConnection

    init(connection: WatchConnection = AppCoordinator.shared.connection) {
        self.connection = connection
    }

    func loadUser(id: String) async {
        do {
            user = try await connection.send(FetchUserRequest(userID: id))
        } catch {
            self.error = error
        }
    }

    func logEvent(_ name: String) async {
        await connection.send(LogAnalyticsEvent(eventName: name, parameters: [:]))
    }
}
```

## SwiftUI Integration

### Using with @StateObject

```swift
struct UserView: View {
    @StateObject private var viewModel = UserViewModel()

    var body: some View {
        VStack {
            if let user = viewModel.user {
                Text(user.name)
                Text(user.email)
                    .font(.caption)
            } else if let error = viewModel.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
            } else {
                ProgressView()
            }
        }
        .task {
            await viewModel.loadUser(id: "123")
        }
    }
}
```

### Observing Connection State

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

## Configuration Options

### Delivery Strategies

Choose how messages are delivered:

```swift
// Default: try message, fall back to userInfo queue
let response = try await connection.send(request)

// For state that only needs latest value
let response = try await connection.send(
    request,
    strategy: .messageWithContextFallback
)

// Real-time only (fail if not reachable)
let response = try await connection.send(
    request,
    strategy: .messageOnly
)
```

### Retry Policies

Configure retry behavior:

```swift
// Use built-in policies
let response = try await connection.send(request, retryPolicy: .patient)  // 5 attempts, 30s timeout
let response = try await connection.send(request, retryPolicy: .none)     // No retries

// Or create custom policies
let customPolicy = RetryPolicy(maxAttempts: 4, timeout: .seconds(15))
let response = try await connection.send(request, retryPolicy: customPolicy)
```

### Delivery Mode

Control when requests are sent:

```swift
// Queue if not reachable (default)
let response = try await connection.send(request, delivery: .queued)

// Fail immediately if not reachable
let response = try await connection.send(request, delivery: .immediate)
```

## File Transfers

Transfer files between devices with progress tracking:

### Sending Files

```swift
@MainActor
class DocumentSender {
    private let connection: WatchConnection

    func sendDocument(_ fileURL: URL) async throws {
        // Start the transfer
        let transfer = try await connection.transferFile(
            fileURL,
            metadata: ["type": "document", "name": fileURL.lastPathComponent]
        )

        // Track progress (optional)
        for await progress in transfer.progressUpdates {
            print("Uploading: \(Int(progress * 100))%")
        }

        // Or just wait for completion
        try await transfer.waitForCompletion()
    }

    // Cancel a transfer
    func cancelTransfer(_ transfer: FileTransfer) {
        transfer.cancel()
    }

    // Cancel all transfers
    func cancelAll() {
        connection.cancelAllFileTransfers()
    }
}
```

### Receiving Files

```swift
@MainActor
class DocumentReceiver {
    private let connection: WatchConnection

    func setup() {
        // Option 1: Callback
        connection.onFileReceived = { [weak self] file in
            self?.handleReceivedFile(file)
        }

        // Option 2: Async stream
        Task {
            for await file in connection.receivedFiles {
                handleReceivedFile(file)
            }
        }
    }

    private func handleReceivedFile(_ file: ReceivedFile) {
        // ⚠️ IMPORTANT: Move file synchronously!
        // It will be deleted after this method returns
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destination = documents.appendingPathComponent(file.fileURL.lastPathComponent)

        do {
            try FileManager.default.moveItem(at: file.fileURL, to: destination)
            print("Saved file to: \(destination)")

            // Access metadata
            if let type = file.metadata?["type"] as? String {
                print("File type: \(type)")
            }
        } catch {
            print("Failed to save file: \(error)")
        }
    }
}
```

### Monitoring Transfer Status

```swift
// Check active transfers
let activeTransfers = connection.outstandingFileTransfers
print("Active transfers: \(activeTransfers.count)")

// Observe transfer count changes via @Published property
// connection.activeFileTransferCount
```

## Next Steps

- Read the [Architecture Overview](Architecture.md) to understand how the library works
- Learn about [Shared State](SharedState.md) for synchronizing data
- Explore [Reliability Features](Reliability.md) for handling connectivity issues
- See the [API Reference](API-Reference.md) for complete documentation
