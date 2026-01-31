//
//  Models.swift
//  Demo
//
//  Shared models used by both iOS and watchOS targets.
//  This file must be included in BOTH targets.
//

import Foundation

/// A recipe model that can be synced between iOS and watchOS.
/// In a real app, this might come from a backend API like Firebase Firestore,
/// a REST API, or a local database like Core Data/SwiftData.
struct Recipe: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let ingredients: [String]
    let instructions: String
    let prepTime: Int // minutes
    let isFavorite: Bool

    static let samples: [Recipe] = [
        Recipe(
            id: "1",
            title: "Pasta Carbonara",
            ingredients: ["400g Spaghetti", "200g Pancetta", "4 Eggs", "100g Parmesan", "Black Pepper"],
            instructions: "Cook pasta. Fry pancetta. Mix eggs with cheese. Combine all with pasta water.",
            prepTime: 25,
            isFavorite: true
        ),
        Recipe(
            id: "2",
            title: "Chicken Stir Fry",
            ingredients: ["500g Chicken Breast", "Mixed Vegetables", "Soy Sauce", "Ginger", "Garlic"],
            instructions: "Slice chicken. Stir fry with vegetables. Add sauce and serve with rice.",
            prepTime: 20,
            isFavorite: false
        ),
        Recipe(
            id: "3",
            title: "Greek Salad",
            ingredients: ["Tomatoes", "Cucumber", "Red Onion", "Feta Cheese", "Olives", "Olive Oil"],
            instructions: "Chop vegetables. Add feta and olives. Drizzle with olive oil.",
            prepTime: 10,
            isFavorite: true
        )
    ]
}

/// User preferences that can be synced between devices using SharedState.
struct UserPreferences: Codable, Sendable, Equatable {
    var favoriteRecipeIDs: [String]
    var lastViewedRecipeID: String?
    var notificationsEnabled: Bool

    static let `default` = UserPreferences(
        favoriteRecipeIDs: [],
        lastViewedRecipeID: nil,
        notificationsEnabled: true
    )
}

/// Analytics event for tracking user actions.
/// In a real app, you might send these to Firebase Analytics, Mixpanel, etc.
struct AnalyticsEvent: Codable, Sendable {
    let name: String
    let parameters: [String: String]
    let timestamp: Date

    init(name: String, parameters: [String: String] = [:]) {
        self.name = name
        self.parameters = parameters
        self.timestamp = Date()
    }
}
