# Shared State

`SharedState<T>` provides automatic state synchronization between iOS and watchOS using `applicationContext`. This guide explains how to use it effectively.

## Overview

Shared state is useful for:

- User preferences and settings
- App configuration
- Session data (current workout, active timer, etc.)
- Any data that should be the same on both devices

Key features:

- **Automatic sync**: Changes are automatically sent to the counterpart
- **@Observable**: Uses Swift's Observation framework for seamless nested observation
- **Persistence**: Survives app termination (via applicationContext)
- **SwiftUI ready**: Works with both `@Observable` view models and legacy `ObservableObject`
- **Simple semantics**: Last-write-wins, no versioning complexity

## Basic Usage

### 1. Define Your State Type

Your state type must conform to `Codable`, `Sendable`, and `Equatable`:

```swift
struct AppSettings: Codable, Sendable, Equatable {
    var theme: Theme = .system
    var notificationsEnabled: Bool = true
    var dailyGoal: Int = 10000

    enum Theme: String, Codable, Sendable {
        case light, dark, system
    }
}
```

### 2. Create SharedState

```swift
@MainActor
class SettingsManager: ObservableObject {
    let settings: SharedState<AppSettings>

    init(connection: WatchConnection) {
        settings = SharedState(
            initialValue: AppSettings(),
            connection: connection
        )
    }
}
```

### 3. Read and Update

```swift
// Read current value
let currentTheme = settingsManager.settings.value.theme

// Update
try settingsManager.settings.update(
    AppSettings(
        theme: .dark,
        notificationsEnabled: true,
        dailyGoal: 12000
    )
)
```

### 4. Observe Changes

Changes to `SharedState.value` are automatically observable via Swift's Observation framework:

```swift
// SwiftUI - automatic observation
struct SettingsView: View {
    @ObservedObject var manager: SettingsManager

    var body: some View {
        Toggle("Notifications", isOn: Binding(
            get: { manager.settings.value.notificationsEnabled },
            set: { newValue in
                var updated = manager.settings.value
                updated.notificationsEnabled = newValue
                try? manager.settings.update(updated)
            }
        ))
    }
}
```

## How Sync Works

`SharedState` uses `applicationContext` for synchronization:

1. When you call `update()`, the new value is stored locally
2. The value is encoded and sent via `updateApplicationContext`
3. The counterpart device receives it via the WCSession delegate
4. Both devices now have the same value

**Important**: Only the latest value is synced. If you update multiple times before the counterpart receives an update, only the final value is delivered. This is WCSession's built-in behavior.

## SwiftUI Integration

### With @Observable View Model (Recommended)

`SharedState` uses `@Observable`, so it works seamlessly when embedded in other `@Observable` view models - no forwarding or binding required:

```swift
@Observable @MainActor
final class SettingsViewModel {
    private let sharedState: SharedState<AppSettings>

    // Just access properties directly - observation is automatic
    var theme: AppSettings.Theme { sharedState.value.theme }
    var notificationsEnabled: Bool { sharedState.value.notificationsEnabled }
    var dailyGoal: Int { sharedState.value.dailyGoal }

    init(sharedState: SharedState<AppSettings>) {
        self.sharedState = sharedState
    }

    func updateTheme(_ theme: AppSettings.Theme) {
        var settings = sharedState.value
        settings.theme = theme
        try? sharedState.update(settings)
    }
}

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Picker("Theme", selection: Binding(
                get: { viewModel.theme },
                set: { viewModel.updateTheme($0) }
            )) {
                ForEach(AppSettings.Theme.allCases, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
        }
    }
}
```

### Direct Binding

```swift
struct SettingsView: View {
    var settings: SharedState<AppSettings>

    var body: some View {
        Form {
            Picker("Theme", selection: binding(\.theme)) {
                ForEach(AppSettings.Theme.allCases, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }

            Toggle("Notifications", isOn: binding(\.notificationsEnabled))

            Stepper("Daily Goal: \(settings.value.dailyGoal)", value: binding(\.dailyGoal))
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settings.value[keyPath: keyPath] },
            set: { newValue in
                var updated = settings.value
                updated[keyPath: keyPath] = newValue
                try? settings.update(updated)
            }
        )
    }
}
```


## Best Practices

### 1. Keep State Small

ApplicationContext has size limits. Keep your state lean:

```swift
// Good: Small, focused state
struct UserPreferences: Codable, Sendable, Equatable {
    var theme: String
    var units: String
}

// Bad: Large state with binary data
struct AppState: Codable, Sendable, Equatable {
    var preferences: UserPreferences
    var cachedImages: [Data]  // Don't include large data!
    var fullUserProfile: Profile
}
```

### 2. Use Multiple SharedStates for Different Concerns

```swift
@MainActor
class AppCoordinator {
    // Separate concerns into different states
    let userPreferences: SharedState<UserPreferences>
    let workoutSession: SharedState<WorkoutSession>
    let syncStatus: SharedState<SyncStatus>

    init(connection: WatchConnection) {
        userPreferences = SharedState(initialValue: UserPreferences(), connection: connection)
        workoutSession = SharedState(initialValue: WorkoutSession(), connection: connection)
        syncStatus = SharedState(initialValue: SyncStatus(), connection: connection)
    }
}
```

### 3. Handle Sync Failures

```swift
do {
    try settings.update(newSettings)
} catch WatchConnectionError.encodingFailed {
    // State couldn't be serialized
    showError("Failed to save settings")
} catch {
    // Other sync errors
    // Note: State is updated locally even if sync fails
    // It will be synced when connectivity is restored
}
```

### 4. Avoid Rapid Updates Before sendMessage

Due to WCSession limitations, calling `updateApplicationContext` can interfere with `sendMessage`. If you need to send a message immediately after updating shared state, consider:

```swift
// Option 1: Update state, wait briefly, then send message
try settings.update(newSettings)
try await Task.sleep(for: .seconds(1))
let response = try await connection.send(request)

// Option 2: Use request/response instead of shared state for critical data
let response = try await connection.send(UpdateSettingsRequest(settings: newSettings))
```

## Limitations

1. **Size limits**: ApplicationContext has size limits (~250KB). Keep state small.
2. **Last-write-wins**: If both devices update simultaneously, one update will be overwritten. There is no conflict resolution.
3. **Single value**: ApplicationContext stores only the latest value (no history).
4. **No partial updates**: The entire state is replaced on each update.

For large or complex data, consider using request/response patterns instead.
