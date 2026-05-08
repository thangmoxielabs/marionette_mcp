#!/bin/bash
# Release-build smoke test for broker transport.
#
# Prerequisites:
#   - marionette CLI installed
#   - Flutter SDK available
#   - macOS desktop target available
#
# Usage: ./smoke_test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Broker Transport Release Smoke Test ==="

# Step 1: Start broker
echo "[1/5] Starting broker..."
marionette broker start &
BROKER_PID=$!
sleep 2

# Read activation URL from handle file
HANDLE_FILE="$TMPDIR/marionette-broker-$(date +%s).json"
# Find the actual handle file
HANDLE_FILE=$(ls "$TMPDIR"/marionette-broker-*.json 2>/dev/null | head -1)
if [ -z "$HANDLE_FILE" ]; then
  echo "FAIL: No broker handle file found"
  kill $BROKER_PID 2>/dev/null || true
  exit 1
fi

BROKER_PORT=$(python3 -c "import json; print(json.load(open('$HANDLE_FILE'))['port'])")
BROKER_TOKEN=$(python3 -c "import json; print(json.load(open('$HANDLE_FILE'))['token'])")
echo "Broker running on port $BROKER_PORT"

# Step 2: Build release
echo "[2/5] Building release..."
flutter build macos --dart-define=MARIONETTE_ENABLED=true --release
if [ $? -ne 0 ]; then
  echo "FAIL: Build failed"
  kill $BROKER_PID 2>/dev/null || true
  exit 1
fi
echo "Build successful"

# Step 3: Launch app with activation URL
echo "[3/5] Launching app..."
# Note: In a real test, you'd launch with the activation URL
# For now, just verify the binary exists
BINARY="build/macos/Build/Products/Release/broker_release_smoke.app/Contents/MacOS/broker_release_smoke"
if [ ! -f "$BINARY" ]; then
  echo "FAIL: Binary not found at $BINARY"
  kill $BROKER_PID 2>/dev/null || true
  exit 1
fi
echo "Binary found: $BINARY"

# Step 4: Test broker connection (manual step)
echo "[4/5] Manual test required:"
echo "  - Launch the app: open $BINARY"
echo "  - In another terminal: marionette --broker ws://127.0.0.1:$BROKER_PORT?token=$BROKER_TOKEN get-interactive-elements"
echo "  - Verify elements are returned"

# Step 5: Cleanup
echo "[5/5] Cleaning up..."
kill $BROKER_PID 2>/dev/null || true
rm -f "$HANDLE_FILE"

echo ""
echo "=== Smoke test complete ==="
echo "Manual verification required for steps 3-4."
