#!/usr/bin/env bash
set -euo pipefail

# Check if FLUTTER_ROOT is set
: "${FLUTTER_ROOT:?FLUTTER_ROOT must be set}"

# Add Flutter to PATH (includes both flutter and dart commands)
export PATH="$FLUTTER_ROOT/bin:$PATH"

# Verify Dart version (via Flutter)
dart --version

# Check for frontend_server snapshot (modern Flutter uses AOT version)
SNAPSHOTS_DIR="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/snapshots"
if test -f "$SNAPSHOTS_DIR/frontend_server.dart.snapshot"; then
    echo "Found frontend_server.dart.snapshot ✅"
elif test -f "$SNAPSHOTS_DIR/frontend_server_aot.dart.snapshot"; then
    echo "Found frontend_server_aot.dart.snapshot (modern Flutter) ✅"
    echo "Note: Use 'flutter test' instead of 'dart test' for optimal compatibility"
else
    echo "Warning: frontend_server snapshot not found, but continuing..."
fi

echo "Using Flutter-bundled Dart SDK ✅"
echo ""
echo "Usage examples:"
echo "  # For pure Dart packages:"
echo "  flutter test test/your_test.dart"
echo "  # Or for all tests:"
echo "  flutter test"
