//
//  AppCoordinator.swift
//  Demo
//
//  The main coordinator for the iOS app that handles Watch communication.
//  This is where you register handlers for requests from the Watch.
//

import Foundation
import WatchConnectivitySwift

/// Coordinates communication between the iPhone and Apple Watch.
///
/// In a real app, this class would:
/// - Connect to your backend services (Firebase, REST API, etc.)
/// - Manage local databases (Core Data, SwiftData, Realm)
/// - Forward analytics to your analytics provider
///
/// For this demo, we use UserDefaults for persistence to keep things simple.
@MainActor
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    /// The WatchConnection instance that handles all Watch communication.
    let connection: WatchConnection

    /// Local storage for recipes (in a real app, this would be a database).
    @Published private(set) var recipes: [Recipe] = Recipe.samples

    /// User preferences synced between devices.
    let sharedPreferences: SharedState<UserPreferences>

    /// Recent analytics events (for demo display purposes).
    @Published private(set) var recentEvents: [AnalyticsEvent] = []

    /// Whether to skip persistence (for previews).
    private let skipPersistence: Bool

    private init() {
        // Initialize with default WatchConnection for production use.
        self.connection = WatchConnection()
        self.skipPersistence = false

        // Initialize shared state for preferences.
        // This uses applicationContext under the hood, so changes sync automatically.
        sharedPreferences = SharedState(
            initialValue: UserPreferences.default,
            connection: connection
        )

        // Load any persisted recipes from UserDefaults.
        loadRecipes()

        // Register all request handlers.
        setupHandlers()

        // Listen for received files from Watch.
        setupFileReceiving()
    }

    /// Creates a coordinator with a custom session for previews and testing.
    ///
    /// - Parameters:
    ///   - session: The session to use for communication.
    ///   - recipes: Optional recipes to use instead of loading from persistence.
    ///   - recentEvents: Optional recent events to display.
    init(
        session: any WCSessionProviding,
        recipes: [Recipe] = Recipe.samples,
        recentEvents: [AnalyticsEvent] = []
    ) {
        self.connection = WatchConnection(session: session)
        self.skipPersistence = true
        self.recipes = recipes
        self.recentEvents = recentEvents

        // Initialize shared state with the custom session.
        sharedPreferences = SharedState(
            initialValue: UserPreferences.default,
            connection: connection
        )

        // Register all request handlers.
        setupHandlers()
    }

    // MARK: - Request Handlers

    private func setupHandlers() {
        // Handle request for all recipes.
        // In a real app, you might fetch from Firestore:
        // let snapshot = try await Firestore.firestore().collection("recipes").getDocuments()
        connection.register(FetchRecipesRequest.self) { [weak self] _ in
            await MainActor.run {
                self?.recipes ?? []
            }
        }

        // Handle request for a specific recipe.
        connection.register(FetchRecipeRequest.self) { [weak self] request in
            await MainActor.run {
                self?.recipes.first { $0.id == request.recipeID }
            }
        }

        // Handle toggling favorite status.
        // In a real app, you'd update your backend:
        // try await Firestore.firestore().collection("recipes").document(id).update(["isFavorite": !current])
        connection.register(ToggleFavoriteRequest.self) { [weak self] request in
            try await MainActor.run {
                guard let self else {
                    throw WatchConnectionError.handlerNotRegistered(requestType: "ToggleFavoriteRequest")
                }

                guard let index = self.recipes.firstIndex(where: { $0.id == request.recipeID }) else {
                    throw WatchConnectionError.decodingFailed(description: "Recipe not found")
                }

                let recipe = self.recipes[index]
                let updated = Recipe(
                    id: recipe.id,
                    title: recipe.title,
                    ingredients: recipe.ingredients,
                    instructions: recipe.instructions,
                    prepTime: recipe.prepTime,
                    isFavorite: !recipe.isFavorite
                )

                self.recipes[index] = updated
                self.saveRecipes()

                // Update shared preferences.
                var prefs = self.sharedPreferences.value
                if updated.isFavorite {
                    if !prefs.favoriteRecipeIDs.contains(updated.id) {
                        prefs.favoriteRecipeIDs.append(updated.id)
                    }
                } else {
                    prefs.favoriteRecipeIDs.removeAll { $0 == updated.id }
                }
                try? self.sharedPreferences.update(prefs)

                return updated
            }
        }

        // Handle preferences request.
        connection.register(FetchPreferencesRequest.self) { [weak self] _ in
            await MainActor.run {
                self?.sharedPreferences.value ?? .default
            }
        }

        // Handle analytics events (fire-and-forget).
        // In a real app, forward to Firebase Analytics, Mixpanel, etc.:
        // Analytics.logEvent(event.name, parameters: event.parameters)
        connection.register(LogAnalyticsRequest.self) { [weak self] request in
            await MainActor.run {
                guard let self else { return VoidResponse() }

                // Store for demo display.
                self.recentEvents.insert(request.event, at: 0)
                if self.recentEvents.count > 10 {
                    self.recentEvents.removeLast()
                }

                print("[Analytics] \(request.event.name): \(request.event.parameters)")
                return VoidResponse()
            }
        }

        // Handle recipe viewed notifications.
        connection.register(RecipeViewedRequest.self) { [weak self] request in
            await MainActor.run {
                guard let self else { return VoidResponse() }

                var prefs = self.sharedPreferences.value
                prefs.lastViewedRecipeID = request.recipeID
                try? self.sharedPreferences.update(prefs)

                return VoidResponse()
            }
        }
    }

    // MARK: - File Receiving

    private func setupFileReceiving() {
        // Listen for files sent from the Watch.
        // In a real app, you might receive workout data, voice memos, etc.
        connection.onFileReceived = { file in
            print("[File Received] \(file.fileURL.lastPathComponent)")

            if let metadata = file.metadata {
                print("[File Metadata] \(metadata)")
            }

            // Move the file to a permanent location.
            // IMPORTANT: Do this synchronously - the file is deleted after this handler returns!
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = documents.appendingPathComponent(file.fileURL.lastPathComponent)

            do {
                // Remove existing file if present.
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: file.fileURL, to: destination)
                print("[File Saved] \(destination.path)")
            } catch {
                print("[File Error] Failed to save: \(error)")
            }
        }
    }

    // MARK: - Persistence (UserDefaults for demo)

    private let recipesKey = "demo.recipes"

    private func loadRecipes() {
        guard !skipPersistence else { return }

        // In a real app, load from Core Data, SwiftData, or fetch from API.
        if let data = UserDefaults.standard.data(forKey: recipesKey),
           let decoded = try? JSONDecoder().decode([Recipe].self, from: data) {
            recipes = decoded
        }
    }

    private func saveRecipes() {
        guard !skipPersistence else { return }

        // In a real app, save to database or sync to backend.
        if let data = try? JSONEncoder().encode(recipes) {
            UserDefaults.standard.set(data, forKey: recipesKey)
        }
    }

    // MARK: - Public Methods

    /// Reset recipes to sample data.
    func resetRecipes() {
        recipes = Recipe.samples
        saveRecipes()

        var prefs = sharedPreferences.value
        prefs.favoriteRecipeIDs = recipes.filter { $0.isFavorite }.map { $0.id }
        try? sharedPreferences.update(prefs)
    }
}
