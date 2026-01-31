#!/bin/bash
#
# End-to-End Test Script for WatchConnectivitySwift
#
# This script:
# 1. Finds or creates paired iOS + watchOS simulators
# 2. Boots both simulators
# 3. Builds and installs the test apps
# 4. Runs the integration tests
# 5. Collects results
#
# Usage:
#   ./Scripts/e2e-test.sh [--no-clean] [--keep-running]
#
# Options:
#   --no-clean      Skip erasing simulators (not recommended, may cause flaky tests)
#   --keep-running  Don't shutdown simulators after tests
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEMO_PROJECT="$PROJECT_ROOT/Demo/Demo.xcodeproj"
DERIVED_DATA="$PROJECT_ROOT/.build/DerivedData"
RESULTS_DIR="$PROJECT_ROOT/.build/TestResults"

# Default simulator names (will use existing or create new)
IOS_SIMULATOR_NAME="WCSwift-iPhone"
WATCH_SIMULATOR_NAME="WCSwift-Watch"

# Parse arguments
# --clean is now the default for reliable results
CLEAN_SIMULATORS=true
KEEP_RUNNING=false

for arg in "$@"; do
    case $arg in
        --no-clean)
            CLEAN_SIMULATORS=false
            ;;
        --keep-running)
            KEEP_RUNNING=true
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get the latest available runtime for a platform
get_latest_runtime() {
    local platform=$1
    xcrun simctl list runtimes --json | \
        jq -r ".runtimes[] | select(.platform == \"$platform\" and .isAvailable == true) | .identifier" | \
        sort -V | tail -1
}

# Get device type for a platform
get_device_type() {
    local platform=$1
    local result=""

    if [ "$platform" = "iOS" ]; then
        # Prefer iPhone 16 Pro, fallback to iPhone 15 Pro, then any iPhone
        result=$(xcrun simctl list devicetypes --json | \
            jq -r '.devicetypes[] | select(.name == "iPhone 16 Pro") | .identifier' | head -1)
        if [ -z "$result" ]; then
            result=$(xcrun simctl list devicetypes --json | \
                jq -r '.devicetypes[] | select(.name == "iPhone 15 Pro") | .identifier' | head -1)
        fi
        if [ -z "$result" ]; then
            result=$(xcrun simctl list devicetypes --json | \
                jq -r '.devicetypes[] | select(.name | contains("iPhone")) | .identifier' | tail -1)
        fi
    else
        # Prefer Apple Watch Series 10, fallback to Series 9, then any Watch
        result=$(xcrun simctl list devicetypes --json | \
            jq -r '.devicetypes[] | select(.name | contains("Apple Watch Series 10")) | .identifier' | head -1)
        if [ -z "$result" ]; then
            result=$(xcrun simctl list devicetypes --json | \
                jq -r '.devicetypes[] | select(.name | contains("Apple Watch Series 9")) | .identifier' | head -1)
        fi
        if [ -z "$result" ]; then
            result=$(xcrun simctl list devicetypes --json | \
                jq -r '.devicetypes[] | select(.name | contains("Apple Watch")) | .identifier' | tail -1)
        fi
    fi

    echo "$result"
}

# Find existing simulator by name
find_simulator() {
    local name=$1
    xcrun simctl list devices --json | \
        jq -r ".devices[][] | select(.name == \"$name\" and .isAvailable == true) | .udid" | head -1
}

# Create a new simulator
create_simulator() {
    local name=$1
    local device_type=$2
    local runtime=$3

    log_info "Creating simulator: $name" >&2
    xcrun simctl create "$name" "$device_type" "$runtime"
}

# Find or create paired simulators
setup_simulators() {
    log_info "Setting up simulators..."

    # Get latest runtimes
    IOS_RUNTIME=$(get_latest_runtime "iOS")
    WATCH_RUNTIME=$(get_latest_runtime "watchOS")

    if [ -z "$IOS_RUNTIME" ]; then
        log_error "No iOS runtime found. Please install iOS Simulator runtime."
        exit 1
    fi

    if [ -z "$WATCH_RUNTIME" ]; then
        log_error "No watchOS runtime found. Please install watchOS Simulator runtime."
        exit 1
    fi

    log_info "iOS Runtime: $IOS_RUNTIME"
    log_info "watchOS Runtime: $WATCH_RUNTIME"

    # Find or create iOS simulator
    IOS_UDID=$(find_simulator "$IOS_SIMULATOR_NAME")
    if [ -z "$IOS_UDID" ]; then
        IOS_DEVICE_TYPE=$(get_device_type "iOS")
        IOS_UDID=$(create_simulator "$IOS_SIMULATOR_NAME" "$IOS_DEVICE_TYPE" "$IOS_RUNTIME")
        log_success "Created iOS simulator: $IOS_UDID"
    else
        log_info "Found existing iOS simulator: $IOS_UDID"
    fi

    # Find or create watchOS simulator
    WATCH_UDID=$(find_simulator "$WATCH_SIMULATOR_NAME")
    if [ -z "$WATCH_UDID" ]; then
        WATCH_DEVICE_TYPE=$(get_device_type "watchOS")
        WATCH_UDID=$(create_simulator "$WATCH_SIMULATOR_NAME" "$WATCH_DEVICE_TYPE" "$WATCH_RUNTIME")
        log_success "Created watchOS simulator: $WATCH_UDID"
    else
        log_info "Found existing watchOS simulator: $WATCH_UDID"
    fi

    # Clean if requested (do this BEFORE pairing)
    if [ "$CLEAN_SIMULATORS" = true ]; then
        log_info "Erasing simulators..."
        xcrun simctl shutdown "$IOS_UDID" 2>/dev/null || true
        xcrun simctl shutdown "$WATCH_UDID" 2>/dev/null || true
        xcrun simctl erase "$IOS_UDID"
        xcrun simctl erase "$WATCH_UDID"
        log_success "Simulators erased"

        # Force re-pair after erase to ensure fresh WatchConnectivity state
        log_info "Re-pairing simulators after erase..."
        # Unpair any existing pair first
        CURRENT_PAIR=$(xcrun simctl list pairs --json | \
            jq -r ".pairs | to_entries[] | select(.value.watch.udid == \"$WATCH_UDID\") | .key" | head -1)
        if [ -n "$CURRENT_PAIR" ]; then
            xcrun simctl unpair "$CURRENT_PAIR" 2>/dev/null || true
        fi
        xcrun simctl pair "$WATCH_UDID" "$IOS_UDID"
        log_success "Re-paired simulators"
    else
        # Check if already paired (only when not cleaning)
        EXISTING_PAIR=$(xcrun simctl list pairs --json | \
            jq -r ".pairs | to_entries[] | select(.value.watch.udid == \"$WATCH_UDID\" and .value.phone.udid == \"$IOS_UDID\") | .key" | head -1)

        if [ -z "$EXISTING_PAIR" ]; then
            log_info "Pairing simulators..."
            # Unpair watch from any existing pair first
            CURRENT_PAIR=$(xcrun simctl list pairs --json | \
                jq -r ".pairs | to_entries[] | select(.value.watch.udid == \"$WATCH_UDID\") | .key" | head -1)
            if [ -n "$CURRENT_PAIR" ]; then
                xcrun simctl unpair "$CURRENT_PAIR" 2>/dev/null || true
            fi

            xcrun simctl pair "$WATCH_UDID" "$IOS_UDID"
            log_success "Paired simulators"
        else
            log_info "Simulators already paired: $EXISTING_PAIR"
        fi
    fi

    export IOS_UDID
    export WATCH_UDID
}

# Boot simulators
boot_simulators() {
    log_info "Booting simulators..."

    # Check current state
    IOS_STATE=$(xcrun simctl list devices --json | jq -r ".devices[][] | select(.udid == \"$IOS_UDID\") | .state")
    WATCH_STATE=$(xcrun simctl list devices --json | jq -r ".devices[][] | select(.udid == \"$WATCH_UDID\") | .state")

    if [ "$IOS_STATE" != "Booted" ]; then
        xcrun simctl boot "$IOS_UDID"
        log_info "Booting iOS simulator..."
    else
        log_info "iOS simulator already booted"
    fi

    if [ "$WATCH_STATE" != "Booted" ]; then
        xcrun simctl boot "$WATCH_UDID"
        log_info "Booting watchOS simulator..."
    else
        log_info "watchOS simulator already booted"
    fi

    # Wait for boot to complete
    # After erasing simulators, they need significantly more time to fully initialize
    # and establish their WatchConnectivity pairing
    if [ "$CLEAN_SIMULATORS" = true ]; then
        log_info "Waiting for simulators to be ready (freshly erased and re-paired, needs more time)..."
        sleep 30
    else
        log_info "Waiting for simulators to be ready..."
        sleep 5
    fi

    # Open Simulator.app to see the devices
    open -a Simulator

    log_success "Simulators booted"
}

# Build the apps
build_apps() {
    log_info "Building iOS app..."
    mkdir -p "$DERIVED_DATA"

    xcodebuild build \
        -project "$DEMO_PROJECT" \
        -scheme "Demo" \
        -destination "id=$IOS_UDID" \
        -derivedDataPath "$DERIVED_DATA" \
        -quiet \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO

    log_success "iOS app built"

    log_info "Building watchOS app..."
    xcodebuild build \
        -project "$DEMO_PROJECT" \
        -scheme "DemoWatch Watch App" \
        -destination "id=$WATCH_UDID" \
        -derivedDataPath "$DERIVED_DATA" \
        -quiet \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO

    log_success "watchOS app built"
}

# Install apps on simulators
install_apps() {
    log_info "Installing apps..."

    # Find the built .app bundles
    IOS_APP=$(find "$DERIVED_DATA" -name "Demo.app" -path "*/Debug-iphonesimulator/*" | head -1)
    WATCH_APP=$(find "$DERIVED_DATA" -name "DemoWatch Watch App.app" -path "*/Debug-watchsimulator/*" | head -1)

    if [ -z "$IOS_APP" ]; then
        log_error "iOS app not found in DerivedData"
        exit 1
    fi

    if [ -z "$WATCH_APP" ]; then
        log_error "watchOS app not found in DerivedData"
        exit 1
    fi

    log_info "iOS app: $IOS_APP"
    log_info "watchOS app: $WATCH_APP"

    # Uninstall old apps first to ensure fresh install
    log_info "Uninstalling old apps (if any)..."
    xcrun simctl uninstall "$IOS_UDID" "com.example.Demo" 2>/dev/null || true
    xcrun simctl uninstall "$WATCH_UDID" "com.example.Demo.watchkitapp" 2>/dev/null || true

    xcrun simctl install "$IOS_UDID" "$IOS_APP"
    log_success "iOS app installed"

    xcrun simctl install "$WATCH_UDID" "$WATCH_APP"
    log_success "watchOS app installed"
}

# Run the integration tests
run_tests() {
    log_info "Running integration tests..."
    mkdir -p "$RESULTS_DIR"

    # Launch apps with test mode
    # The iOS app will coordinate the tests
    IOS_BUNDLE_ID="com.example.Demo"
    WATCH_BUNDLE_ID="com.example.Demo.watchkitapp"

    # Terminate any existing instances (do this right before launch to ensure fresh start)
    log_info "Terminating any existing app instances..."
    xcrun simctl terminate "$IOS_UDID" "$IOS_BUNDLE_ID" 2>/dev/null || true
    xcrun simctl terminate "$WATCH_UDID" "$WATCH_BUNDLE_ID" 2>/dev/null || true
    sleep 2

    # After a fresh clean/erase, do a warmup launch cycle to establish WatchConnectivity
    # The first launch after erase is unreliable, so we launch, wait, kill, then relaunch
    if [ "$CLEAN_SIMULATORS" = true ]; then
        log_info "Performing warmup launch (first launch after clean is unreliable)..."
        xcrun simctl launch "$WATCH_UDID" "$WATCH_BUNDLE_ID"
        sleep 1
        xcrun simctl launch "$IOS_UDID" "$IOS_BUNDLE_ID"
        log_info "Waiting for WatchConnectivity to initialize..."
        sleep 5
        log_info "Terminating warmup instances..."
        xcrun simctl terminate "$IOS_UDID" "$IOS_BUNDLE_ID" 2>/dev/null || true
        xcrun simctl terminate "$WATCH_UDID" "$WATCH_BUNDLE_ID" 2>/dev/null || true
        sleep 3
        log_success "Warmup complete, proceeding with actual tests"
    fi

    # Launch watch app first (it needs to be running to receive messages)
    log_info "Launching watchOS app in test mode..."
    SIMCTL_CHILD_WCSWIFT_E2E_TEST=1 xcrun simctl launch "$WATCH_UDID" "$WATCH_BUNDLE_ID" -E2ETest

    # Give watchOS app time to boot properly
    sleep 1
    log_info "Launching iOS app in test mode..."
    SIMCTL_CHILD_WCSWIFT_E2E_TEST=1 xcrun simctl launch "$IOS_UDID" "$IOS_BUNDLE_ID" -E2ETest

    # Get the container path after launch
    sleep 2
    IOS_CONTAINER=$(xcrun simctl get_app_container "$IOS_UDID" "$IOS_BUNDLE_ID" data 2>/dev/null || echo "")
    RESULTS_FILE="$IOS_CONTAINER/Documents/e2e_test_results.txt"

    log_info "Waiting for tests to complete..."
    log_info "Results will be written to: $RESULTS_FILE"

    TIMEOUT=120
    ELAPSED=0
    TEST_PASSED=false

    while [ $ELAPSED -lt $TIMEOUT ]; do
        # Check the results file written by the app
        if [ -f "$RESULTS_FILE" ]; then
            if grep -q "E2E_TEST_PASSED" "$RESULTS_FILE" 2>/dev/null; then
                TEST_PASSED=true
                break
            fi
            if grep -q "E2E_TEST_FAILED" "$RESULTS_FILE" 2>/dev/null; then
                break
            fi
        fi

        # Show progress
        if [ $((ELAPSED % 10)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
            log_info "Still waiting... ($ELAPSED seconds elapsed)"
        fi

        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done

    # Copy results file if it exists
    if [ -f "$RESULTS_FILE" ]; then
        cp "$RESULTS_FILE" "$RESULTS_DIR/e2e_results.txt"
        echo ""
        echo "=== Test Results ==="
        cat "$RESULTS_FILE"
        echo "===================="
    else
        log_warning "No results file found - tests may have timed out waiting for connection"
    fi

    if [ "$TEST_PASSED" = true ]; then
        log_success "Integration tests PASSED"
        return 0
    else
        log_error "Integration tests FAILED or timed out"
        log_info "Results saved to: $RESULTS_DIR/e2e_results.txt"
        return 1
    fi
}

# Shutdown simulators
shutdown_simulators() {
    if [ "$KEEP_RUNNING" = true ]; then
        log_info "Keeping simulators running (--keep-running)"
        return
    fi

    log_info "Shutting down simulators..."
    xcrun simctl shutdown "$IOS_UDID" 2>/dev/null || true
    xcrun simctl shutdown "$WATCH_UDID" 2>/dev/null || true
    log_success "Simulators shut down"
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "  WatchConnectivitySwift E2E Tests"
    echo "=========================================="
    echo ""

    setup_simulators
    boot_simulators
    build_apps
    install_apps

    TEST_RESULT=0
    run_tests || TEST_RESULT=$?

    shutdown_simulators

    echo ""
    if [ $TEST_RESULT -eq 0 ]; then
        log_success "All tests completed successfully!"
    else
        log_error "Tests failed with exit code: $TEST_RESULT"
    fi

    exit $TEST_RESULT
}

main
