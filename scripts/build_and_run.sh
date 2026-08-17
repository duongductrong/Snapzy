#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Snapzy"
DEBUG_BUNDLE_NAME="Snapzy Debug"
SCHEME="Snapzy"
PROJECT="Snapzy.xcodeproj"
LOG_SUBSYSTEM="${LOG_SUBSYSTEM:-Snapzy}"

MODE="run"
CONFIGURATION="${CONFIGURATION:-Debug}"
LOG_LEVEL="${LOG_LEVEL:-default,error,fault}"
CLEAN=0
QUIET=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode-derived-data}"

if [[ -t 1 ]]; then
  BLUE=$'\033[0;34m'
  GREEN=$'\033[0;32m'
  RED=$'\033[0;31m'
  BOLD=$'\033[1m'
  NC=$'\033[0m'
else
  BLUE=""
  GREEN=""
  RED=""
  BOLD=""
  NC=""
fi

info() { printf "%sinfo:%s %s\n" "$BLUE$BOLD" "$NC" "$1"; }
success() { printf "%ssuccess:%s %s\n" "$GREEN$BOLD" "$NC" "$1"; }
fail() {
  printf "%serror:%s %s\n" "$RED$BOLD" "$NC" "$1" >&2
  exit 1
}

usage() {
  cat <<USAGE
${BOLD}Usage:${NC} $0 [run|--logs|--telemetry|--debug|--verify] [options]

${BOLD}Modes:${NC}
  run                 Kill, build, and launch Snapzy.app (default)
  --logs, logs        Launch then stream unified logs for the built app process
  --telemetry         Launch then stream unified logs for subsystem == "$LOG_SUBSYSTEM"
  --debug, debug      Build then launch the app binary under lldb
  --verify, verify    Launch and confirm the built app process is running

${BOLD}Options:${NC}
  --configuration C   Build configuration. Default: Debug
  --derived-data PATH Build DerivedData path. Default: .build/xcode-derived-data
  --log-level LEVELS  default,info,debug,error,fault,all. Default: default,error,fault
  --clean             Clean before building
  --verbose           Show full xcodebuild output
  --help, -h          Show this help

${BOLD}Examples:${NC}
  $0
  $0 --verify
  $0 --logs --log-level all
  $0 --configuration Release
USAGE
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "This script only supports macOS."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      run)
        MODE="run"
        shift
        ;;
      --logs|logs)
        MODE="logs"
        shift
        ;;
      --telemetry|telemetry)
        MODE="telemetry"
        shift
        ;;
      --debug|debug)
        MODE="debug"
        shift
        ;;
      --verify|verify)
        MODE="verify"
        shift
        ;;
      --configuration)
        [[ $# -ge 2 ]] || fail "--configuration requires a value."
        CONFIGURATION="$2"
        shift 2
        ;;
      --derived-data|--derived-data-path)
        [[ $# -ge 2 ]] || fail "--derived-data requires a path."
        DERIVED_DATA_PATH="$2"
        shift 2
        ;;
      --log-level)
        [[ $# -ge 2 ]] || fail "--log-level requires a value."
        LOG_LEVEL="$2"
        shift 2
        ;;
      --clean)
        CLEAN=1
        shift
        ;;
      --verbose)
        QUIET=0
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done
}

message_type_predicate() {
  local levels="$1"
  local type_clauses=""

  if [[ "$levels" == "all" ]]; then
    printf ""
    return
  fi

  IFS=',' read -r -a level_array <<<"$levels"
  for level in "${level_array[@]}"; do
    level="${level//[[:space:]]/}"
    case "$level" in
      default|info|debug|error|fault)
        if [[ -n "$type_clauses" ]]; then
          type_clauses="$type_clauses OR messageType == $level"
        else
          type_clauses="messageType == $level"
        fi
        ;;
      *)
        fail "Invalid log level: '$level'. Use default, info, debug, error, fault, or all."
        ;;
    esac
  done

  printf " AND (%s)" "$type_clauses"
}

process_log_predicate() {
  printf "processImagePath == \"%s\"" "$(app_binary_path)"
  message_type_predicate "$LOG_LEVEL"
}

telemetry_log_predicate() {
  printf "subsystem == \"%s\"" "$LOG_SUBSYSTEM"
  message_type_predicate "$LOG_LEVEL"
}

build_products_dir() {
  printf "%s/Build/Products/%s" "$DERIVED_DATA_PATH" "$CONFIGURATION"
}

app_bundle_path() {
  local bundle_name="$APP_NAME"
  if [[ "$CONFIGURATION" == "Debug" ]]; then
    bundle_name="$DEBUG_BUNDLE_NAME"
  fi

  printf "%s/%s.app" "$(build_products_dir)" "$bundle_name"
}

app_binary_path() {
  printf "%s/Contents/MacOS/%s" "$(app_bundle_path)" "$APP_NAME"
}

# The Debug bundle ("Snapzy Debug.app") and the published app
# ("/Applications/Snapzy.app") both run a process named "Snapzy", so matching
# by process name cannot tell them apart. Match the built binary's absolute
# path instead (ERE-escaped for pgrep/pkill -f).
process_pattern() {
  printf '%s' "$(app_binary_path)" | sed 's/[][^$.*/+?(){}|]/\\&/g'
}

stop_app() {
  local pattern
  pattern="$(process_pattern)"

  if pgrep -f "$pattern" >/dev/null 2>&1; then
    info "Stopping existing $(basename "$(app_bundle_path)") process..."
    pkill -f "$pattern" >/dev/null 2>&1 || true

    local waited=0
    while pgrep -f "$pattern" >/dev/null 2>&1; do
      [[ "$waited" -ge 20 ]] && break
      sleep 0.1
      waited=$((waited + 1))
    done
  fi
}

run_xcodebuild() {
  local action="$1"
  local args=(
    xcodebuild
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
  )

  if [[ "$QUIET" -eq 1 ]]; then
    args+=(-quiet)
  fi

  args+=("$action")
  "${args[@]}"
}

build_app() {
  cd "$ROOT_DIR"

  if [[ "$CLEAN" -eq 1 ]]; then
    info "Cleaning $SCHEME ($CONFIGURATION)..."
    run_xcodebuild clean
  fi

  info "Building $SCHEME ($CONFIGURATION)..."
  run_xcodebuild build

  local app_bundle
  app_bundle="$(app_bundle_path)"
  [[ -d "$app_bundle" ]] || fail "Build finished but app bundle was not found: $app_bundle"
  [[ -x "$(app_binary_path)" ]] || fail "Built app binary is not executable: $(app_binary_path)"

  success "Build ready: $app_bundle"
}

open_app() {
  local app_bundle
  app_bundle="$(app_bundle_path)"
  info "Launching $APP_NAME..."
  /usr/bin/open -n "$app_bundle"
  success "Launched $APP_NAME"
}

verify_app() {
  open_app
  sleep 2

  if pgrep -f "$(process_pattern)" >/dev/null 2>&1; then
    success "$APP_NAME is running."
  else
    fail "$(app_bundle_path) did not stay running after launch."
  fi
}

stream_logs() {
  local predicate="$1"

  open_app

  # Run `log stream` in the background and wait on it: bash defers traps
  # while a foreground child runs, so with a plain foreground call the
  # cleanup would only execute once `log stream` happened to exit (and the
  # app would be left running if `log stream` died on its own).
  local log_stream_pid=""
  cleanup_stream() {
    trap - INT TERM
    printf "\n"
    if [[ -n "$log_stream_pid" ]]; then
      kill "$log_stream_pid" 2>/dev/null || true
    fi
    info "Stopping $APP_NAME..."
    pkill -f "$(process_pattern)" >/dev/null 2>&1 || true
    success "App stopped."
  }
  trap cleanup_stream INT TERM

  info "Streaming logs for predicate: $predicate"
  /usr/bin/log stream --info --debug --style compact --predicate "$predicate" &
  log_stream_pid=$!
  wait "$log_stream_pid" 2>/dev/null || true
  cleanup_stream
}

launch_debugger() {
  require_command lldb
  info "Launching under lldb..."
  exec lldb -o run -- "$(app_binary_path)"
}

main() {
  parse_args "$@"
  require_macos
  require_command xcodebuild
  require_command pgrep
  require_command pkill

  # Process matching relies on the absolute binary path, so resolve a
  # relative --derived-data value against the repo root.
  if [[ "$DERIVED_DATA_PATH" != /* ]]; then
    DERIVED_DATA_PATH="$ROOT_DIR/${DERIVED_DATA_PATH#./}"
  fi

  cd "$ROOT_DIR"
  stop_app
  build_app

  case "$MODE" in
    run)
      open_app
      ;;
    logs)
      stream_logs "$(process_log_predicate)"
      ;;
    telemetry)
      stream_logs "$(telemetry_log_predicate)"
      ;;
    verify)
      verify_app
      ;;
    debug)
      launch_debugger
      ;;
    *)
      fail "Unsupported mode: $MODE"
      ;;
  esac
}

main "$@"
