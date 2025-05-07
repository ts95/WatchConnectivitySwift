# 📡 WatchConnectivitySwift

**WatchConnectivitySwift** is a modern, high-level Swift library that simplifies and streamlines communication between iOS and watchOS using Apple’s `WatchConnectivity` framework. Built from the ground up with Swift Concurrency and strong typing in mind, it enables you to write robust, reactive, and testable communication layers between your iPhone and Apple Watch apps—without wrestling with delegate boilerplate or fragile dictionary casting.

---

## 🎯 Purpose

This library abstracts the complexity of Apple's `WCSession` and introduces:

- `AsyncStream`-based message and data reception  
- Retryable `async/await` message sending  
- JSON-RPC–inspired request/response flows via generics  
- Strongly typed shared state synchronization via `applicationContext`  
- Seamless SwiftUI and Combine integration  

Use it when you want to build connected iOS/watchOS apps with **modern Swift paradigms**.

---

## 🛠 Requirements

- **iOS 15+**  
- **watchOS 8+**  
- **Xcode 13+**  
- Written in **Swift 5.5+**  
- Supports **Swift Concurrency (async/await)** and **Codable**

---

## 🔧 Installation

Use Swift Package Manager:

```swift
.package(url: "https://github.com/ts95/WatchConnectivitySwift.git", from: "1.0.0")
```

Then add it to the target dependencies for your iOS and watchOS apps.

---

## 💡 Use Cases

- Communicate with a backend service (e.g., Firestore, REST, CloudKit) via the iPhone and relay results to the Watch  
- Share state, like user preferences or health goals, across iOS and watchOS  
- Use the iPhone as a gateway for data acquisition (e.g., location, weather, Bluetooth peripherals)  
- Perform RPC-style message exchange between devices using strongly typed requests and responses  

---

## 🚀 Code Example: Firestore-backed Recipe Fetcher

Imagine an Apple Watch app that fetches recipes from Firestore—but Firestore isn’t supported on watchOS. This example shows how the Watch sends a request, and the iPhone responds.

### 1. Define Request/Response

```swift
enum RecipeRequest: WatchConnectivityRPCRequest, Codable {
    case fetchRecipe(id: String)
}

enum RecipeResponse: WatchConnectivityRPCResponse, Codable {
    case recipe(title: String, ingredients: [String])
}
```

### 2. Shared State (Optional)

```swift
struct RecipeSharedContext: WatchConnectivityRPCApplicationContext, Codable {
    var lastViewedRecipeID: String?
}
```

### 3. On iPhone: Subclass the Repository

```swift
final class RecipeRepository: WatchConnectivityRPCRepository<RecipeRequest, RecipeResponse, RecipeSharedContext> {
    override func onRequest(_ request: RecipeRequest) async throws -> RecipeResponse {
        switch request {
        case .fetchRecipe(let id):
            let snapshot = try await Firestore.firestore().collection("recipes").document(id).getDocument()
            let data = snapshot.data() ?? [:]
            let title = data["title"] as? String ?? "Unknown"
            let ingredients = data["ingredients"] as? [String] ?? []
            return .recipe(title: title, ingredients: ingredients)
        }
    }
}
```

### 4. On Apple Watch: Send the Request

```swift
@MainActor
final class RecipeViewModel: ObservableObject {
    private let repository: RecipeRepository

    @Published var title: String = ""
    @Published var ingredients: [String] = []

    init(repository: RecipeRepository) {
        self.repository = repository
    }

    func loadRecipe(id: String) {
        Task {
            do {
                let response: RecipeResponse = try await repository.perform(request: .fetchRecipe(id: id))
                switch response {
                case .recipe(let title, let ingredients):
                    self.title = title
                    self.ingredients = ingredients
                }
            } catch {
                print("Error fetching recipe: \(error)")
            }
        }
    }
}
```

---

## 📦 What You Get

### `WatchConnectivityService`

- Wraps the `WCSession` with async `sendMessage`, `sendMessageData`, `transferUserInfo`, and `applicationContext`
- Reactive `AsyncStream`s for received data
- Publishes `activationState`, `isReachable`, and (on iOS) `isPaired`

### `WatchConnectivityRPCRepository`

- Generic base class for request/response interaction
- Handles decoding, dispatch, response encoding, and error handling
- Synchronizes shared state using `applicationContext`

---

## ✅ Advantages

- No boilerplate `WCSessionDelegate` code  
- Swift-native: async/await, Codable, Combine  
- Perfectly suited for SwiftUI architecture  
- Retryable message sending for better UX  
- Type-safe and testable  

---

## 🧪 Testing & Debugging

- Use dependency injection to mock the `WatchConnectivityService`  
- Subclass your RPC repository in tests to override `onRequest(_:)`  
- Add logging to your streams during development for better observability  

---

## 📜 License

MIT

---

## 👨‍💻 Author

Created by [Toni Sucic](https://github.com/ts95) – iOS developer and protocol abstraction enthusiast.  
Contributions and feedback welcome!
