//
//  ContentView.swift
//  Demo
//
//  The main view for the iOS app showing connection status and recipes.
//

import SwiftUI
import WatchConnectivitySwift

struct ContentView: View {
    @ObservedObject var coordinator: AppCoordinator

    init(coordinator: AppCoordinator = .shared) {
        self.coordinator = coordinator
    }

    var body: some View {
        NavigationStack {
            List {
                // Connection Status Section
                Section {
                    ConnectionStatusView(connection: coordinator.connection)
                } header: {
                    Text("Watch Connection")
                }

                // Recipes Section
                Section {
                    ForEach(coordinator.recipes) { recipe in
                        RecipeRow(recipe: recipe)
                    }
                } header: {
                    Text("Recipes")
                } footer: {
                    Text("These recipes are available to your Apple Watch. Toggle favorites from either device.")
                }

                // Recent Analytics Section
                if !coordinator.recentEvents.isEmpty {
                    Section {
                        ForEach(coordinator.recentEvents, id: \.timestamp) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.name)
                                    .font(.headline)
                                if !event.parameters.isEmpty {
                                    Text(event.parameters.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Recent Watch Events")
                    } footer: {
                        Text("Analytics events sent from your Apple Watch.")
                    }
                }

                // Shared Preferences Section
                Section {
                    SharedPreferencesView(sharedState: coordinator.sharedPreferences)
                } header: {
                    Text("Shared Preferences")
                } footer: {
                    Text("These preferences sync automatically between iPhone and Apple Watch using SharedState.")
                }

                // Debug Section
                Section {
                    Button("Reset to Sample Data") {
                        coordinator.resetRecipes()
                    }
                } header: {
                    Text("Debug")
                }
            }
            .navigationTitle("Demo")
        }
    }
}

// MARK: - Connection Status View

struct ConnectionStatusView: View {
    @ObservedObject var connection: WatchConnection

    var body: some View {
        HStack {
            Circle()
                .fill(connection.isReachable ? Color.green : Color.orange)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading) {
                Text(connection.isReachable ? "Watch Reachable" : "Watch Not Reachable")
                    .font(.headline)

                Group {
                    if connection.isPaired {
                        if connection.isWatchAppInstalled {
                            Text("Paired and app installed")
                        } else {
                            Text("Paired but app not installed")
                        }
                    } else {
                        Text("No Watch paired")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if connection.activeFileTransferCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                    Text("\(connection.activeFileTransferCount)")
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Recipe Row

struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                Text("\(recipe.prepTime) min • \(recipe.ingredients.count) ingredients")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Shared Preferences View

struct SharedPreferencesView: View {
    // SharedState uses @Observable, so no property wrapper needed
    var sharedState: SharedState<UserPreferences>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Favorites:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sharedState.value.favoriteRecipeIDs.isEmpty ? "None" : sharedState.value.favoriteRecipeIDs.joined(separator: ", "))
                    .font(.caption)
            }

            HStack {
                Text("Last Viewed:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sharedState.value.lastViewedRecipeID ?? "None")
                    .font(.caption)
            }

            HStack {
                Text("Notifications:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sharedState.value.notificationsEnabled ? "Enabled" : "Disabled")
                    .font(.caption)
            }
        }
    }
}

// MARK: - Previews

#Preview("Connected") {
    let session = PreviewWCSession.connected
    let coordinator = AppCoordinator(session: session)
    return ContentView(coordinator: coordinator)
}

#Preview("Disconnected") {
    let session = PreviewWCSession.disconnected
    let coordinator = AppCoordinator(session: session)
    return ContentView(coordinator: coordinator)
}

#Preview("Unpaired") {
    let session = PreviewWCSession.unpaired
    let coordinator = AppCoordinator(session: session)
    return ContentView(coordinator: coordinator)
}

#Preview("With Events") {
    let session = PreviewWCSession.connected
    let events = [
        AnalyticsEvent(name: "recipe_viewed", parameters: ["recipe_id": "1"]),
        AnalyticsEvent(name: "recipe_favorited", parameters: ["recipe_id": "2"])
    ]
    let coordinator = AppCoordinator(session: session, recentEvents: events)
    return ContentView(coordinator: coordinator)
}
