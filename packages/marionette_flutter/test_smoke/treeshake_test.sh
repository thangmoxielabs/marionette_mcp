#!/bin/bash
# Tree-shake verification for broker transport.
#
# Verifies that broker transport code is excluded from builds
# when the MARIONETTE_ENABLED flag is not set.

set -euo pipefail

echo "=== Tree-shake Verification ==="

cd "$(dirname "$0")/../../example/broker_release_smoke"

# Build without flag
echo "[1/3] Building without MARIONETTE_ENABLED..."
flutter build web --release
mv build/web build-noflag

# Build with flag
echo "[2/3] Building with MARIONETTE_ENABLED=true..."
flutter build web --dart-define=MARIONETTE_ENABLED=true --release

# Verify symbols
echo "[3/3] Checking for BrokerTransport symbols..."

NOFLAG_COUNT=$(grep -c 'BrokerTransport' build-noflag/main.dart.js 2>/dev/null || echo "0")
FLAG_COUNT=$(grep -c 'BrokerTransport' build/web/main.dart.js 2>/dev/null || echo "0")

echo "  Without flag: $NOFLAG_COUNT occurrences"
echo "  With flag:    $FLAG_COUNT occurrences"

if [ "$NOFLAG_COUNT" -eq "0" ]; then
  echo "  PASS: BrokerTransport not present in no-flag build"
else
  echo "  FAIL: BrokerTransport found in no-flag build ($NOFLAG_COUNT occurrences)"
  exit 1
fi

if [ "$FLAG_COUNT" -gt "0" ]; then
  echo "  PASS: BrokerTransport present in flagged build"
else
  echo "  FAIL: BrokerTransport not found in flagged build"
  exit 1
fi

echo ""
echo "=== Tree-shake verification PASSED ==="

# Cleanup
rm -rf build-noflag
