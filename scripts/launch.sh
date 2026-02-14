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
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

# --- Helper Functions ---
info() { echo -e "${BLUE}${BOLD}info:${NC} $1"; }
success() { echo -e "${GREEN}${BOLD}success:${NC} $1"; }
error() { echo -e "${RED}${BOLD}error:${NC} $1"; }

usage() {
    echo -e "${BOLD}Usage:${NC} $0 [OPTIONS]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --log-level LEVEL   Log levels to show (comma-separated)"
    echo "                      Available: default, info, debug, error, fault, all"
    echo "                      Default: default,error,fault"
    echo "  --help              Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0                          # default,error,fault"
    echo "  $0 --log-level all          # Show all log levels"
    echo "  $0 --log-level error,fault  # Errors & faults only"
    echo "  $0 --log-level debug        # Debug only"
    exit 0
}

# --- Parse Arguments ---
LOG_LEVEL="default,error,fault"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Build the log predicate from comma-separated levels
build_predicate() {
    local levels="$1"
    local predicate="process == \"$SCHEME\""

    if [[ "$levels" == "all" ]]; then
        # No messageType filter — show everything from the app
        echo "$predicate"
        return
    fi

    local type_clauses=""
    IFS=',' read -ra LEVEL_ARRAY <<< "$levels"
    for level in "${LEVEL_ARRAY[@]}"; do
        level=$(echo "$level" | xargs) # trim whitespace
        case "$level" in
            default|info|debug|error|fault)
                if [[ -n "$type_clauses" ]]; then
                    type_clauses="$type_clauses OR messageType == $level"
                else
                    type_clauses="messageType == $level"
                fi
                ;;
            *)
                error "Invalid log level: '$level'. Valid: default, info, debug, error, fault, all"
                exit 1
                ;;
        esac
    done

    echo "$predicate AND ($type_clauses)"
}

LOG_PREDICATE=$(build_predicate "$LOG_LEVEL")

cleanup() {
    echo -e "\n${BOLD}--- Stream Stopped ---${NC}"
    info "Stopping $SCHEME..."
    # Kill by PID if launched directly, fallback to pkill
    if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null
        wait "$APP_PID" 2>/dev/null
    fi
    pkill -x "$SCHEME" 2>/dev/null || true
    success "App stopped."
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
APP_PATH="$BUILD_DIR/$SCHEME.app"

# Launch app directly so stdout/stderr (print statements) appear in this terminal
"$APP_PATH/Contents/MacOS/$SCHEME" &
APP_PID=$!
success "Launched $SCHEME (PID: $APP_PID)"

# 4. Filtered Stream
echo -e "${BOLD}--- Streaming Logs [${YELLOW}$LOG_LEVEL${NC}${BOLD}] (Ctrl+C to stop) ---${NC}"
info "Predicate: $LOG_PREDICATE"

log stream \
    --predicate "$LOG_PREDICATE" \
    --style compact