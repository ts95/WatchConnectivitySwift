//
//  DemoApp.swift
//  Demo
//
//  The main entry point for the iOS app.
//

import SwiftUI
import WatchConnectivitySwift

@main
struct DemoApp: App {
    // Initialize the coordinator early to set up Watch communication.
    @StateObject private var coordinator = AppCoordinator.shared

    // Check if running in E2E test mode
    private var isE2ETestMode: Bool {
        // Check for marker file in app container's tmp directory (most reliable with simctl)
        // The container path is: <container>/tmp/e2e_test_mode
        if let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.deletingLastPathComponent() {
            let markerFile = containerURL.appendingPathComponent("tmp/e2e_test_mode")
            if FileManager.default.fileExists(atPath: markerFile.path) {
                return true
            }
        }

        // Also check UserDefaults and environment as fallback
        let fromDefaults = UserDefaults.standard.bool(forKey: "WCSwiftE2ETest")
        let fromEnv = ProcessInfo.processInfo.environment["WCSWIFT_E2E_TEST"] == "1"
        let fromArgs = ProcessInfo.processInfo.arguments.contains("-E2ETest")
        return fromDefaults || fromEnv || fromArgs
    }

    var body: some Scene {
        WindowGroup {
            if isE2ETestMode {
                E2ETestView()
            } else {
                ContentView()
            }
        }
    }
}

// MARK: - E2E Test View

struct E2ETestView: View {
    @StateObject private var testDriver: E2ETestDriver
    private let connection: WatchConnection

    init() {
        let conn = WatchConnection()
        self.connection = conn
        let sharedState = SharedState<E2ETestState>(initialValue: E2ETestState(), connection: conn)
        _testDriver = StateObject(wrappedValue: E2ETestDriver(
            connection: conn,
            sharedState: sharedState
        ))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("E2E Test Runner")
                .font(.largeTitle)
                .bold()

            if testDriver.isRunning {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Running: \(testDriver.currentTest)")
                    .foregroundStyle(.secondary)
            } else if testDriver.results.isEmpty {
                Text("Starting tests...")
                    .foregroundStyle(.secondary)
            } else {
                // Show results
                List(testDriver.results.indices, id: \.self) { index in
                    let result = testDriver.results[index]
                    HStack {
                        switch result {
                        case .passed(let name, let duration):
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(name)
                            Spacer()
                            Text(String(format: "%.2fs", duration))
                                .foregroundStyle(.secondary)
                        case .failed(let name, let error):
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading) {
                                Text(name)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .skipped(let name, let reason):
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading) {
                                Text(name)
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .task {
            await testDriver.runAllTests()
        }
    }
}
