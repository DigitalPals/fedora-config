# Shared terminal UI helpers for the XPS Fedora wrapper scripts.
# Source this file; do not execute it.
# shellcheck shell=bash

if [[ -t 1 ]]; then
  UI_RED=$'\033[31m'
  UI_GREEN=$'\033[32m'
  UI_YELLOW=$'\033[33m'
  UI_CYAN=$'\033[36m'
  UI_DIM=$'\033[2m'
  UI_BOLD=$'\033[1m'
  UI_RESET=$'\033[0m'
else
  UI_RED='' UI_GREEN='' UI_YELLOW='' UI_CYAN='' UI_DIM='' UI_BOLD='' UI_RESET=''
fi

UI_RULE_WIDTH=52

ui_rule() {
  local line
  printf -v line '%*s' "$UI_RULE_WIDTH" ''
  printf '%s%s%s\n' "$UI_DIM" "${line// /─}" "$UI_RESET"
}

ui_header() {
  printf '%s%s%s\n' "$UI_BOLD" "$*" "$UI_RESET"
  ui_rule
}

ui_section() {
  printf '\n%s%s%s\n' "$UI_BOLD" "$*" "$UI_RESET"
}

# ui_duration <seconds> -> "52s" / "2m 04s"
ui_duration() {
  local s=$1
  if (( s >= 60 )); then
    printf '%dm %02ds' $((s / 60)) $((s % 60))
  else
    printf '%ds' "$s"
  fi
}

# ui_ok/ui_warn/ui_fail <label> [detail]
ui_ok()   { printf '  %s✓%s %-22s%s%s%s\n' "$UI_GREEN" "$UI_RESET" "$1" "$UI_DIM" "${2:-}" "$UI_RESET"; }
ui_warn() { printf '  %s!%s %-22s%s%s%s\n' "$UI_YELLOW" "$UI_RESET" "$1" "$UI_YELLOW" "${2:-}" "$UI_RESET"; }
ui_fail() { printf '  %s✗%s %-22s%s%s%s\n' "$UI_RED" "$UI_RESET" "$1" "$UI_RED" "${2:-}" "$UI_RESET"; }

# ui_tail_log <logfile> [lines] — indented dim excerpt for failure reporting
ui_tail_log() {
  local logfile=$1 lines=${2:-15}
  [[ -r $logfile ]] || return 0
  printf '%s' "$UI_DIM"
  tail -n "$lines" "$logfile" | sed 's/^/    /'
  printf '%s' "$UI_RESET"
}

# ui_spin_while <label> <pid...> — spinner until every pid has exited.
# Does not collect exit statuses; callers still `wait` each pid.
ui_spin_while() {
  local label=$1; shift
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 pid alive
  if [[ ! -t 1 ]]; then
    wait "$@" 2>/dev/null || true
    return 0
  fi
  while :; do
    alive=false
    for pid in "$@"; do
      kill -0 "$pid" 2>/dev/null && { alive=true; break; }
    done
    $alive || break
    printf '\r  %s%s%s %s' "$UI_CYAN" "${frames:i++ % 10:1}" "$UI_RESET" "$label"
    sleep 0.1
  done
  printf '\r\033[2K'
}

# run_step <label> <logfile> <cmd...>
# Runs the command with output captured to the logfile, showing a spinner.
# Prints a ✓/✗ line with duration; returns the command's exit status.
run_step() {
  local label=$1 logfile=$2; shift 2
  local start=$SECONDS rc=0 pid
  mkdir -p "$(dirname -- "$logfile")"
  "$@" >"$logfile" 2>&1 &
  pid=$!
  ui_spin_while "$label" "$pid"
  wait "$pid" || rc=$?
  local dur
  dur=$(ui_duration $((SECONDS - start)))
  if (( rc == 0 )); then
    ui_ok "$label" "($dur)"
  else
    ui_fail "$label" "failed after $dur"
    ui_tail_log "$logfile"
  fi
  return "$rc"
}
