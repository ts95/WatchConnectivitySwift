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

struct RequestCountRow: View {
    let label: String
    let count: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.caption2)
            Spacer()
            Text("\(count)")
                .font(.caption2)
                .bold()
        }
    }
}

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

                    RequestCountRow(label: "Pings:", count: responder.pingCount)
                    RequestCountRow(label: "State Updates:", count: responder.stateUpdateCount)
                    RequestCountRow(label: "Recipe Requests:", count: responder.recipeRequestCount)
                    RequestCountRow(label: "Fire & Forget:", count: responder.fireAndForgetCount)
                    RequestCountRow(label: "Reverse Pings:", count: responder.reversePingCount)
                    RequestCountRow(label: "Multicast Verify:", count: responder.multicastVerifyCount)
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
