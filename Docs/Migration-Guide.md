# Migration Guide: v1.x to v5.0.0

Version 5.0.0 is a complete rewrite of WatchConnectivitySwift with a new API designed for Swift 6 and modern concurrency patterns. This guide helps you migrate from v1.x.

## Overview of Changes

| Aspect | v1.x | v5.0.0 |
|--------|------|--------|
| Minimum iOS | 13.0 | 17.0 |
| Minimum watchOS | 8.0 | 10.0 |
| Swift Version | 5.5+ | 6.0+ |
| Main Class | `WatchConnectivityRPCRepository` | `WatchConnection` |
| Request Type | Protocol + enum | Protocol with associated type |
| Response Type | Protocol + enum | Associated type on request |
| Concurrency | Completion handlers | async/await |
| State Sync | Manual | `SharedState<T>` with automatic sync |
| Retry Logic | Custom implementation | Built-in `RetryPolicy` |
| Health Monitoring | None | Built-in `SessionHealth` |

## Step-by-Step Migration

### 1. Update Minimum Deployment Targets

In your `Package.swift` or Xcode project settings:

```swift
// Package.swift
platforms: [
    .iOS(.v17),
    .watchOS(.v10)
]
```

### 2. Replace Request/Response Types

#### v1.x

```swift
enum RecipeRequest: WatchConnectivityRPCRequest, Codable {
    case fetchRecipe(id: String)
    case searchRecipes(query: String)
}

enum RecipeResponse: WatchConnectivityRPCResponse, Codable {
    case recipe(Recipe)
    case recipes([Recipe])
    case error(String)
}
```

#### v5.0.0

```swift
// Each request is its own type with a specific response
struct FetchRecipeRequest: WatchRequest {
    typealias Response = Recipe
    let id: String
}

struct SearchRecipesRequest: WatchRequest {
    typealias Response = [Recipe]
    let query: String
}
```

**Benefits of v5.0.0 approach:**
- Compile-time type safety (can't return wrong response type)
- Clearer API (each request clearly states what it returns)
- No need for switch statements on response

### 3. Replace Repository with WatchConnection

#### v1.x

```swift
final class RecipeRepository: WatchConnectivityRPCRepository<
    RecipeRequest,
    RecipeResponse,
    RecipeSharedContext
> {
    override func onRequest(_ request: RecipeRequest) async throws -> RecipeResponse {
        switch request {
        case .fetchRecipe(let id):
            let recipe = try await fetchRecipe(id: id)
            return .recipe(recipe)
        case .searchRecipes(let query):
            let recipes = try await search(query: query)
            return .recipes(recipes)
        }
    }
}
```

#### v5.0.0

```swift
@MainActor
class AppCoordinator {
    let connection = WatchConnection()

    func setup() {
        // Register handlers
        connection.register(FetchRecipeRequest.self) { request in
            try await self.fetchRecipe(id: request.id)
        }

        connection.register(SearchRecipesRequest.self) { request in
            try await self.search(query: request.query)
        }
    }

    private func fetchRecipe(id: String) async throws -> Recipe { ... }
    private func search(query: String) async throws -> [Recipe] { ... }
}
```

### 4. Update Send Calls

#### v1.x

```swift
let repository = RecipeRepository()

func loadRecipe(id: String) {
    Task {
        do {
            let response: RecipeResponse = try await repository.perform(
                request: .fetchRecipe(id: id)
            )
            switch response {
            case .recipe(let recipe):
                self.recipe = recipe
            case .error(let message):
                self.error = message
            default:
                break
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

#### v5.0.0

```swift
let connection = WatchConnection()

func loadRecipe(id: String) async {
    do {
        // Response type is automatically inferred
        recipe = try await connection.send(FetchRecipeRequest(id: id))
    } catch {
        self.error = error
    }
}
```

### 5. Migrate Shared Context to SharedState

#### v1.x

```swift
struct RecipeSharedContext: WatchConnectivityRPCApplicationContext, Codable {
    var lastViewedRecipeID: String?
    var favoriteRecipeIDs: [String]
}

// In repository
func updateSharedContext(_ context: RecipeSharedContext) {
    // Manual sync via applicationContext
}
```

#### v5.0.0

```swift
struct RecipeContext: Codable, Sendable, Equatable {
    var lastViewedRecipeID: String?
    var favoriteRecipeIDs: [String]
}

// Automatic sync (requires WatchConnection instance)
let connection = WatchConnection()
let sharedContext = SharedState(
    initialValue: RecipeContext(),
    connection: connection
)

// Update (automatically syncs)
try sharedContext.update(RecipeContext(
    lastViewedRecipeID: "123",
    favoriteRecipeIDs: ["456", "789"]
))

// Observe changes
Task {
    for await newValue in sharedContext.values {
        print("Context changed: \(newValue)")
    }
}
```

### 6. Add Retry Configuration (Optional)

v5.0.0 has built-in retry logic. Configure as needed:

```swift
// Use built-in policies
let recipe = try await connection.send(
    FetchRecipeRequest(id: id),
    retryPolicy: .patient  // 5 attempts, 30s timeout
)

// Or customize
let recipe = try await connection.send(
    FetchRecipeRequest(id: id),
    retryPolicy: RetryPolicy(maxAttempts: 4, timeout: .seconds(15))
)
```

### 7. Add Health Monitoring (Optional)

v5.0.0 includes session health monitoring:

```swift
// Observe health state
Task {
    for await event in connection.diagnosticEvents {
        if case .healthChanged(_, let to) = event {
            if to.requiresUserIntervention {
                showRecoveryPrompt()
            }
        }
    }
}

// Or check directly
if connection.sessionHealth.requiresUserIntervention {
    await connection.attemptRecovery()
}
```

## API Mapping Reference

### Classes

| v1.x | v5.0.0 |
|------|--------|
| `WatchConnectivityService` | `WatchConnection` |
| `WatchConnectivityRPCRepository<R,S,C>` | `WatchConnection` + handler registration |

### Protocols

| v1.x | v5.0.0 |
|------|--------|
| `WatchConnectivityRPCRequest` | `WatchRequest` |
| `WatchConnectivityRPCResponse` | Associated type `Response` on `WatchRequest` |
| `WatchConnectivityRPCApplicationContext` | State type for `SharedState<T>` |

### Methods

| v1.x | v5.0.0 |
|------|--------|
| `repository.perform(request:)` | `connection.send(_:)` |
| `repository.onRequest(_:)` | `connection.register(_:handler:)` |
| Manual context sync | `sharedState.update(_:)` |

### Properties

| v1.x | v5.0.0 |
|------|--------|
| `service.activationState` | `connection.activationState` |
| `service.isReachable` | `connection.isReachable` |
| `service.isPaired` | `connection.isPaired` (iOS only) |
| N/A | `connection.sessionHealth` |
| N/A | `connection.diagnosticEvents` |
| N/A | `connection.pendingRequestCount` |

## Removed Features

The following v1.x features are replaced with better alternatives:

| v1.x Feature | v5.0.0 Replacement |
|--------------|-------------------|
| `AsyncStream` for raw messages | Type-safe handlers |
| Manual retry loop | Built-in `RetryPolicy` |
| Dictionary-based messages | Codable structs |

## New Features in v5.0.0

Take advantage of these new capabilities:

- **Fire-and-forget requests**: Use `FireAndForgetRequest` for analytics/logging
- **Delivery strategies**: Choose how messages are delivered with fallbacks
- **Shared state**: Automatic synchronization via applicationContext
- **Session health**: Monitor and recover from connectivity issues
- **Diagnostic events**: Debug connectivity behavior

## Need Help?

If you encounter issues during migration:

1. Check the [API Reference](API-Reference.md) for detailed documentation
2. Review the [Architecture Overview](Architecture.md) to understand the design
3. Open an issue on [GitHub](https://github.com/ts95/WatchConnectivitySwift/issues)
