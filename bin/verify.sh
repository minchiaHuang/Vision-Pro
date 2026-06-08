#!/usr/bin/env bash
#
# bin/verify.sh — Clean-build smoke test for Visiting Artisan.
#
# Runs `xcodebuild clean build` for the iPad and Apple Vision Pro
# simulators and prints a pass/fail summary. Designed to catch
# clean-clone regressions (e.g. missing Secrets.swift, broken
# pbxproj edits, AppIcon errors) before they hit a teammate.
#
# Usage:
#   bash bin/verify.sh
#
# Exit codes:
#   0 — all platforms built successfully
#   1 — one or more builds failed (see per-target log path printed above)
#
# Requirements:
#   - Xcode 26.5+ with iOS 26 and visionOS 26 simulator runtimes installed
#   - Run from the repo root (where VisitingArtisan.xcodeproj lives)

set -uo pipefail

PROJECT="VisitingArtisan.xcodeproj"
SCHEME="VisitingArtisan"

if [[ ! -d "$PROJECT" ]]; then
    echo "Error: $PROJECT not found in $(pwd)."
    echo "Run this script from the repo root."
    exit 2
fi

LOG_DIR="$(mktemp -d)"
PASS=0
FAIL=0
FAILED_TARGETS=()

run_build() {
    local label="$1"
    local destination="$2"
    local log_file="$LOG_DIR/${label// /_}.log"

    printf "→ Building %s ... " "$label"

    if xcodebuild -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "$destination" \
        -configuration Debug \
        CODE_SIGNING_ALLOWED=NO \
        clean build > "$log_file" 2>&1; then
        printf "✅ PASS\n"
        PASS=$((PASS + 1))
    else
        printf "❌ FAIL\n"
        echo "   log: $log_file"
        FAIL=$((FAIL + 1))
        FAILED_TARGETS+=("$label")
    fi
}

run_test() {
    local label="$1"
    local destination="$2"
    local log_file="$LOG_DIR/${label// /_}.log"

    printf "→ Testing %s ... " "$label"

    if xcodebuild -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "$destination" \
        -configuration Debug \
        CODE_SIGNING_ALLOWED=NO \
        test > "$log_file" 2>&1; then
        printf "✅ PASS\n"
        PASS=$((PASS + 1))
    else
        printf "❌ FAIL\n"
        echo "   log: $log_file"
        FAIL=$((FAIL + 1))
        FAILED_TARGETS+=("$label")
    fi
}

echo "Visiting Artisan — clean-build verification"
echo "==========================================="

run_build "iPad Pro 13-inch (M5) sim" \
    "platform=iOS Simulator,name=iPad Pro 13-inch (M5)"

run_build "Apple Vision Pro sim" \
    "platform=visionOS Simulator,name=Apple Vision Pro"

run_test "Unit tests (Apple Vision Pro sim)" \
    "platform=visionOS Simulator,name=Apple Vision Pro"

echo
echo "Summary: $PASS passed, $FAIL failed."

if (( FAIL > 0 )); then
    echo "Failed targets:"
    for target in "${FAILED_TARGETS[@]}"; do
        echo "  - $target"
    done
    echo "Logs preserved under $LOG_DIR"
    exit 1
fi

# Cleanup logs on full success only.
rm -rf "$LOG_DIR"
echo "All builds succeeded."
exit 0
