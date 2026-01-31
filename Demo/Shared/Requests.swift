//
//  Requests.swift
//  Demo
//
//  Type-safe request definitions for Watch <-> iPhone communication.
//  This file must be included in BOTH iOS and watchOS targets.
//

import Foundation
import WatchConnectivitySwift

// MARK: - Requests with Responses

/// Request to fetch all available recipes from the iPhone.
/// The iPhone might load these from:
/// - A backend API (Firebase Firestore, REST API, GraphQL)
/// - Local storage (Core Data, SwiftData, Realm)
/// - UserDefaults (for simple cases like this demo)
struct FetchRecipesRequest: WatchRequest {
    typealias Response = [Recipe]
}

/// Request to fetch a specific recipe by ID.
struct FetchRecipeRequest: WatchRequest {
    typealias Response = Recipe?
    let recipeID: String
}

/// Request to toggle the favorite status of a recipe.
/// Returns the updated recipe.
struct ToggleFavoriteRequest: WatchRequest {
    typealias Response = Recipe
    let recipeID: String
}

/// Request to get the current user preferences.
struct FetchPreferencesRequest: WatchRequest {
    typealias Response = UserPreferences
}

// MARK: - Fire-and-Forget Requests

/// Log an analytics event on the iPhone.
/// Fire-and-forget because we don't need confirmation.
/// In a real app, the iPhone would forward this to your analytics service.
struct LogAnalyticsRequest: FireAndForgetRequest {
    let event: AnalyticsEvent
}

/// Notify the iPhone that a recipe was viewed.
/// This updates the "last viewed" preference.
struct RecipeViewedRequest: FireAndForgetRequest {
    let recipeID: String
}
