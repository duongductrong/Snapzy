#!/bin/bash

# Exit on error
set -e

# --- Configuration ---
SCHEME="Snapzy"
PROJECT="Snapzy.xcodeproj"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# --- Helper Functions ---
info() { echo -e "${BLUE}${BOLD}info:${NC} $1"; }
success() { echo -e "${GREEN}${BOLD}success:${NC} $1"; }
error() { echo -e "${RED}${BOLD}error:${NC} $1"; }

cleanup() {
    echo -e "\n${BOLD}--- Stream Stopped ---${NC}"
    exit 0
}
trap cleanup SIGINT

# --- Execution ---

echo -e "${BOLD}--- Initializing Pipeline for $SCHEME ---${NC}"

# 1. Cleanup
pkill -x "$SCHEME" 2>/dev/null || true

# 2. Build
info "Building..."
if xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug build -quiet; then
    success "Build successful."
else
    error "Build failed."
    exit 1
fi

# 3. Launch
BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')
open "$BUILD_DIR/$SCHEME.app"

# 4. Filtered Stream
echo -e "${BOLD}--- Streaming Errors & Faults (Ctrl+C to stop) ---${NC}"

# Filter: Only show logs where process is your app AND level is Error or Fault
log stream \
    --predicate "process == \"$SCHEME\" AND (messageType == error OR messageType == fault)" \
    --style compact