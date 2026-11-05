#!/usr/bin/env bash
# frappe-bench-dev: one command to start a Frappe development session.
#
#   ./dev.sh [--site SITE] [--port PORT] [--bench DIR] [--no-watch] [--no-browser]
#
# Starts `bench serve` (auto-reloads Python) and `bench watch` (rebuilds JS/CSS),
# waits until the site answers, then opens it in your browser.
# Ctrl+C stops everything it started.
#
# Works on Linux and macOS, on a remote server through VS Code Remote-SSH,
# and on Windows through WSL.

set -u

PORT="${PORT:-8030}"
SITE="${SITE:-}"
BENCH_DIR="${BENCH_DIR:-}"
WATCH=1
OPEN_BROWSER=1

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --site)       SITE="$2"; shift 2 ;;
    --port)       PORT="$2"; shift 2 ;;
    --bench)      BENCH_DIR="$2"; shift 2 ;;
    --no-watch)   WATCH=0; shift ;;
    --no-browser) OPEN_BROWSER=0; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

is_bench() { [ -d "$1/sites" ] && [ -d "$1/apps" ] && [ -d "$1/apps/frappe" ]; }

# ---------------------------------------------------------------- find bench
find_bench_from() {
  local d
  d="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    is_bench "$d" && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}

if [ -z "$BENCH_DIR" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
  BENCH_DIR="$(find_bench_from "$PWD" || find_bench_from "$SCRIPT_DIR")" \
    || die "No Frappe bench found. Run this from inside a bench, or pass --bench DIR."
fi
is_bench "$BENCH_DIR" || die "$BENCH_DIR is not a Frappe bench (needs sites/ and apps/frappe/)."
cd "$BENCH_DIR" || die "Cannot enter $BENCH_DIR"

command -v bench >/dev/null || die "'bench' is not on PATH."
command -v curl  >/dev/null || die "'curl' is required."

# ------------------------------------------------- shared bench owned by a group
# If the bench belongs to another user's group that you are a member of, but this
# shell has not picked the group up yet (common right after `usermod -aG`),
# re-run through `sg` so bench can write logs and assets.
if [ "$(uname -s)" = "Linux" ] && [ ! -O "$BENCH_DIR" ] && command -v sg >/dev/null; then
  BENCH_GROUP="$(stat -c %G "$BENCH_DIR")"
  if ! id -nG | tr ' ' '\n' | grep -qx "$BENCH_GROUP"; then
    if id -nG "$(id -un)" | tr ' ' '\n' | grep -qx "$BENCH_GROUP"; then
      [ -n "${FBD_REEXEC:-}" ] && die "Could not activate group '$BENCH_GROUP'."
      say "Activating group '$BENCH_GROUP' for this session"
      export FBD_REEXEC=1
      exec sg "$BENCH_GROUP" -c "$(printf '%q ' "$0" --bench "$BENCH_DIR" --port "$PORT" \
        ${SITE:+--site "$SITE"} $([ $WATCH = 0 ] && echo --no-watch) \
        $([ $OPEN_BROWSER = 0 ] && echo --no-browser))"
    fi
    [ -w "$BENCH_DIR/logs" ] || warn "You may not have write access to $BENCH_DIR (owned by group '$BENCH_GROUP')."
  fi
fi

# ----------------------------------------------------------------- pick site
list_sites() {
  local s
  for s in sites/*/; do
    s="${s%/}"; s="${s#sites/}"
    [ -f "sites/$s/site_config.json" ] && echo "$s"
  done
}

if [ -z "$SITE" ]; then
  SITE="$(sed -n 's/.*"default_site"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
          sites/common_site_config.json 2>/dev/null | head -1)"
  [ -n "$SITE" ] || SITE="$(cat sites/currentsite.txt 2>/dev/null)"
  if [ -z "$SITE" ]; then
    SITES="$(list_sites)"
    case "$(printf '%s\n' "$SITES" | grep -c .)" in
      0) die "No sites found in $BENCH_DIR/sites." ;;
      1) SITE="$SITES" ;;
      *) die "Several sites found, choose one with --site: $(echo $SITES)" ;;
    esac
  fi
fi
[ -f "sites/$SITE/site_config.json" ] || die "Site '$SITE' does not exist in $BENCH_DIR/sites."

URL="http://localhost:${PORT}"

# ----------------------------------------------------------- helpers
port_in_use() {
  if command -v ss >/dev/null; then
    ss -ltn "sport = :$1" 2>/dev/null | grep -q LISTEN
  elif command -v lsof >/dev/null; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    curl -s --max-time 2 -o /dev/null "http://localhost:$1"
  fi
}

site_up() { curl -s --max-time 3 "$URL/api/method/ping" | grep -q pong; }

PIDS=()
start_bg() { # start_bg LOGFILE CMD...  (own process group when possible, so Ctrl+C stops children too)
  local log="$1"; shift
  if command -v setsid >/dev/null; then
    setsid "$@" >"$log" 2>&1 &
  else
    set -m; "$@" >"$log" 2>&1 & set +m
  fi
  PIDS+=($!)
}

kill_tree() {
  local pid="$1" child
  kill -TERM -- "-$pid" 2>/dev/null && return
  for child in $(pgrep -P "$pid" 2>/dev/null); do kill_tree "$child"; done
  kill -TERM "$pid" 2>/dev/null
}

cleanup() {
  trap - EXIT INT TERM
  [ ${#PIDS[@]} -eq 0 ] && exit 0
  echo; say "Stopping..."
  for pid in "${PIDS[@]}"; do kill_tree "$pid"; done
  wait 2>/dev/null
  say "Stopped."
  exit 0
}
trap cleanup EXIT INT TERM

open_url() {
  if [ -n "${BROWSER:-}" ]; then "$BROWSER" "$1"                 # VS Code (incl. Remote-SSH): opens on your own computer
  elif [ "$(uname -s)" = "Darwin" ]; then open "$1"               # macOS
  elif command -v wslview >/dev/null; then wslview "$1"           # WSL
  elif grep -qi microsoft /proc/version 2>/dev/null; then cmd.exe /c start "" "$1"
  elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v xdg-open >/dev/null; then xdg-open "$1"
  else return 1
  fi
}

# ------------------------------------------------------------------ run
mkdir -p logs
say "Bench: $BENCH_DIR"
say "Site:  $SITE"

if port_in_use "$PORT"; then
  if site_up; then
    say "Port $PORT already serves a site, reusing it."
  else
    die "Port $PORT is busy with something else (maybe a bench serve started without --site). Stop it or use --port."
  fi
else
  say "Starting dev server on $URL   (log: logs/dev-serve.log)"
  start_bg logs/dev-serve.log bench --site "$SITE" serve --port "$PORT"
fi

if [ "$WATCH" = 1 ]; then
  say "Starting bench watch           (log: logs/dev-watch.log)"
  start_bg logs/dev-watch.log bench watch
fi

printf '\033[1;34m==>\033[0m Waiting for the server'
for _ in $(seq 1 90); do
  site_up && break
  printf '.'; sleep 1
done
echo
site_up || { warn "Server did not come up in 90s. Last lines of logs/dev-serve.log:"; tail -20 logs/dev-serve.log; exit 1; }
say "Ready: $URL"

if [ "$OPEN_BROWSER" = 1 ]; then
  open_url "$URL" >/dev/null 2>&1 && say "Opened in your browser." \
    || say "Open $URL in your browser (forward port $PORT first if this is a remote server)."
fi

echo
say "Save code and refresh the browser. Ctrl+C to stop."
echo "------------------------------------------------------------"
LOGS=(logs/dev-serve.log); [ "$WATCH" = 1 ] && LOGS+=(logs/dev-watch.log)
tail -n 0 -F "${LOGS[@]}" &
PIDS+=($!)
wait
