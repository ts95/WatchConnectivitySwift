//
//  RecipeViewModel.swift
//  DemoWatch Watch App
//
//  View model that handles communication with the iPhone.
//

import Foundation
import WatchConnectivity
import WatchConnectivitySwift

/// View model for the Watch app that communicates with the iPhone.
///
/// This demonstrates:
/// - Sending requests and receiving typed responses
/// - Fire-and-forget requests for analytics
/// - Handling errors gracefully
/// - Using delivery strategies and retry policies
@MainActor
final class RecipeViewModel: ObservableObject {
    /// The WatchConnection instance for communication.
    let connection: WatchConnection

    /// All available recipes from the iPhone.
    @Published private(set) var recipes: [Recipe] = []

    /// The currently selected recipe for detail view.
    @Published var selectedRecipe: Recipe?

    /// Loading state.
    @Published private(set) var isLoading = false

    /// Error message to display.
    @Published var errorMessage: String?

    /// Shared preferences synced with iPhone.
    let sharedPreferences: SharedState<UserPreferences>

    /// Creates a view model with an existing WatchConnection.
    ///
    /// - Parameter connection: The shared connection to use for communication.
    init(connection: WatchConnection) {
        self.connection = connection

        // Initialize shared state - this syncs automatically with iPhone.
        sharedPreferences = SharedState(
            initialValue: UserPreferences.default,
            connection: connection
        )
    }

    /// Creates a view model with a custom session for previews and testing.
    ///
    /// - Parameters:
    ///   - session: The session to use for communication.
    ///   - recipes: Optional recipes to pre-populate (for previews).
    init(session: any SessionProviding, recipes: [Recipe] = []) {
        self.connection = WatchConnection(session: session)
        self.recipes = recipes

        // Initialize shared state with the custom session.
        sharedPreferences = SharedState(
            initialValue: UserPreferences.default,
            connection: connection
        )
    }

    // MARK: - Data Loading

    /// Fetch all recipes from the iPhone.
    func loadRecipes() async {
        isLoading = true
        errorMessage = nil

        do {
            // Send the request to iPhone.
            // Uses messageWithUserInfoFallback: tries live message first,
            // falls back to userInfo queue if iPhone is not immediately reachable.
            recipes = try await connection.send(
                FetchRecipesRequest(),
                strategy: .messageWithUserInfoFallback,
                retryPolicy: .default
            )

            // Log analytics event (fire-and-forget).
            await logEvent("recipes_loaded", parameters: ["count": "\(recipes.count)"])
        } catch {
            errorMessage = "Failed to load recipes: \(error.localizedDescription)"
            print("[Watch] Error loading recipes: \(error)")
        }

        isLoading = false
    }

    /// Toggle the favorite status of a recipe.
    func toggleFavorite(for recipe: Recipe) async {
        do {
            let updated = try await connection.send(
                ToggleFavoriteRequest(recipeID: recipe.id),
                strategy: .messageWithUserInfoFallback
            )

            // Update local state.
            if let index = recipes.firstIndex(where: { $0.id == updated.id }) {
                recipes[index] = updated
            }

            // Update selected recipe if it's the one being toggled.
            if selectedRecipe?.id == updated.id {
                selectedRecipe = updated
            }

            // Log analytics.
            await logEvent(
                updated.isFavorite ? "recipe_favorited" : "recipe_unfavorited",
                parameters: ["recipe_id": recipe.id]
            )
        } catch {
            errorMessage = "Failed to update favorite: \(error.localizedDescription)"
            print("[Watch] Error toggling favorite: \(error)")
        }
    }

    /// Mark a recipe as viewed.
    func viewRecipe(_ recipe: Recipe) async {
        selectedRecipe = recipe

        // Notify iPhone (fire-and-forget).
        await connection.send(RecipeViewedRequest(recipeID: recipe.id))

        // Log analytics.
        await logEvent("recipe_viewed", parameters: ["recipe_id": recipe.id])
    }

    // MARK: - Analytics

    /// Log an analytics event to the iPhone.
    private func logEvent(_ name: String, parameters: [String: String] = [:]) async {
        let event = AnalyticsEvent(name: name, parameters: parameters)
        await connection.send(LogAnalyticsRequest(event: event))
    }

    // MARK: - Preferences

    /// Toggle notifications preference.
    func toggleNotifications() {
        var prefs = sharedPreferences.value
        prefs.notificationsEnabled.toggle()
        try? sharedPreferences.update(prefs)
    }
}
