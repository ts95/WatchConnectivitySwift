//
//  DemoWatchApp.swift
//  DemoWatch Watch App
//
//  The main entry point for the watchOS app.
//

import SwiftUI
import WatchConnectivitySwift

@main
struct DemoWatchApp: App {
    // Single shared connection for the entire app
    @StateObject private var appState = WatchAppState()

    // Check if running in E2E test mode
    private var isE2ETestMode: Bool {
        // Check UserDefaults (can be set via simctl)
        let fromDefaults = UserDefaults.standard.bool(forKey: "WCSwiftE2ETest")
        // Check environment variable
        let fromEnv = ProcessInfo.processInfo.environment["WCSWIFT_E2E_TEST"] == "1"
        // Check launch arguments
        let fromArgs = ProcessInfo.processInfo.arguments.contains("-E2ETest")
        return fromDefaults || fromEnv || fromArgs
    }

    var body: some Scene {
        WindowGroup {
            if isE2ETestMode, let responder = appState.testResponder {
                WatchE2ETestView(responder: responder, connection: appState.connection)
            } else {
                ContentView(viewModel: appState.viewModel)
            }
        }
    }
}

// MARK: - E2E Test View for watchOS

struct WatchE2ETestView: View {
    @ObservedObject var responder: E2ETestResponder
    @ObservedObject var connection: WatchConnection

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("E2E Test Mode")
                    .font(.headline)
                    .foregroundStyle(.blue)

                Divider()

                // Connection status
                HStack {
                    Circle()
                        .fill(connection.isReachable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(connection.isReachable ? "iPhone Connected" : "Waiting...")
                        .font(.caption2)
                }

                Divider()

                // Request counts
                VStack(alignment: .leading, spacing: 6) {
                    Text("Requests Handled:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Pings:")
                            .font(.caption2)
                        Spacer()
                        Text("\(responder.pingCount)")
                            .font(.caption2)
                            .bold()
                    }

                    HStack {
                        Text("State Updates:")
                            .font(.caption2)
                        Spacer()
                        Text("\(responder.stateUpdateCount)")
                            .font(.caption2)
                            .bold()
                    }

                    HStack {
                        Text("Recipe Requests:")
                            .font(.caption2)
                        Spacer()
                        Text("\(responder.recipeRequestCount)")
                            .font(.caption2)
                            .bold()
                    }

                    HStack {
                        Text("Fire & Forget:")
                            .font(.caption2)
                        Spacer()
                        Text("\(responder.fireAndForgetCount)")
                            .font(.caption2)
                            .bold()
                    }
                }

                Divider()

                Text("Total: \(responder.totalRequestCount)")
                    .font(.caption)
                    .bold()
            }
            .padding()
        }
    }
}

// MARK: - Shared App State

/// Shared app state that manages the single WatchConnection instance.
@MainActor
final class WatchAppState: ObservableObject {
    let connection: WatchConnection
    let viewModel: RecipeViewModel
    private(set) var testResponder: E2ETestResponder?
    private var testSharedState: SharedState<E2ETestState>?

    init() {
        // Create a single shared connection
        let conn = WatchConnection()
        self.connection = conn

        // Create view model using the shared connection
        self.viewModel = RecipeViewModel(connection: conn)

        // Set up E2E test responder on the same connection
        setupE2EResponder()
    }

    private func setupE2EResponder() {
        let state = SharedState<E2ETestState>(initialValue: E2ETestState(), connection: connection)
        self.testSharedState = state
        self.testResponder = E2ETestResponder(connection: connection, sharedState: state)
        print("[E2E Watch] Test responder initialized on shared connection")
    }
}
