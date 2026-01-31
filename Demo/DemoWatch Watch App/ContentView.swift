//
//  ContentView.swift
//  DemoWatch Watch App
//
//  The main view for the watchOS app.
//

import SwiftUI
import WatchConnectivitySwift

struct ContentView: View {
    @ObservedObject var viewModel: RecipeViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.recipes.isEmpty {
                    ProgressView("Loading...")
                } else if let error = viewModel.errorMessage, viewModel.recipes.isEmpty {
                    ErrorView(message: error) {
                        Task {
                            await viewModel.loadRecipes()
                        }
                    }
                } else {
                    RecipeListView(viewModel: viewModel)
                }
            }
            .navigationTitle("Recipes")
            .navigationDestination(item: $viewModel.selectedRecipe) { recipe in
                RecipeDetailView(recipe: recipe, viewModel: viewModel)
            }
        }
        .task {
            await viewModel.loadRecipes()
        }
    }
}

// MARK: - Recipe List View

struct RecipeListView: View {
    @ObservedObject var viewModel: RecipeViewModel

    var body: some View {
        List {
            // Connection status.
            Section {
                WatchConnectionStatusView(connection: viewModel.connection)
            }

            // Recipes.
            Section("Recipes") {
                ForEach(viewModel.recipes) { recipe in
                    Button {
                        Task {
                            await viewModel.viewRecipe(recipe)
                        }
                    } label: {
                        RecipeRowView(recipe: recipe)
                    }
                }
            }

            // Settings.
            Section("Settings") {
                Toggle("Notifications", isOn: Binding(
                    get: { viewModel.sharedPreferences.value.notificationsEnabled },
                    set: { _ in viewModel.toggleNotifications() }
                ))
            }
        }
        .refreshable {
            await viewModel.loadRecipes()
        }
    }
}

// MARK: - Watch Connection Status

struct WatchConnectionStatusView: View {
    @ObservedObject var connection: WatchConnection

    var body: some View {
        HStack {
            Circle()
                .fill(connection.isReachable ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(connection.isReachable ? "iPhone Connected" : "iPhone Unreachable")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Recipe Row

struct RecipeRowView: View {
    let recipe: Recipe

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(recipe.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(recipe.prepTime) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Recipe Detail View

struct RecipeDetailView: View {
    let recipe: Recipe
    @ObservedObject var viewModel: RecipeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Title and favorite button.
                HStack {
                    Text(recipe.title)
                        .font(.headline)
                    Spacer()
                    Button {
                        Task {
                            await viewModel.toggleFavorite(for: recipe)
                        }
                    } label: {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(recipe.isFavorite ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Prep time.
                Label("\(recipe.prepTime) minutes", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                // Ingredients.
                Text("Ingredients")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(recipe.ingredients, id: \.self) { ingredient in
                    Text("• \(ingredient)")
                        .font(.caption2)
                }

                Divider()

                // Instructions.
                Text("Instructions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(recipe.instructions)
                    .font(.caption2)
            }
            .padding()
        }
        .navigationTitle("Recipe")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)

            Button("Retry", action: retry)
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("With Recipes") {
    let session = PreviewSession.connected
    let viewModel = RecipeViewModel(session: session, recipes: Recipe.samples)
    return ContentView(viewModel: viewModel)
}

#Preview("Disconnected") {
    let session = PreviewSession.disconnected
    let viewModel = RecipeViewModel(session: session, recipes: Recipe.samples)
    return ContentView(viewModel: viewModel)
}

#Preview("Loading") {
    let session = PreviewSession.connected
    let viewModel = RecipeViewModel(session: session, recipes: [])
    return ContentView(viewModel: viewModel)
}

#Preview("Recipe Detail") {
    RecipeDetailView(
        recipe: Recipe.samples[0],
        viewModel: RecipeViewModel(session: PreviewSession.connected, recipes: Recipe.samples)
    )
}

#Preview("Error State") {
    ErrorView(message: "Failed to load recipes: iPhone not reachable") {
        print("Retry tapped")
    }
}
