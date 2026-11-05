#!/usr/bin/env bash
# frappe-bench-dev: one command to start a Frappe development session.
#
#   ./dev.sh [--site SITE] [--port PORT] [--bench DIR] [--no-watch] [--no-browser]
#            [--keep-dev-mode] [--no-dev-mode]
#
# Turns on developer_mode for the site and clears its cache, starts `bench serve`
# (auto-reloads Python) and `bench watch` (rebuilds JS/CSS), waits until the site
# answers, then opens it in your browser. With several sites and no --site, it
# shows a menu. Ctrl+C stops everything and puts developer_mode back.
#
# Works on Linux and macOS, on a remote server through VS Code Remote-SSH,
# and on Windows through WSL.

set -u

PORT="${PORT:-8030}"
SITE="${SITE:-}"
BENCH_DIR="${BENCH_DIR:-}"
WATCH=1
OPEN_BROWSER=1
DEV_MODE=1        # turn developer_mode on
KEEP_DEV_MODE=0   # leave it on after Ctrl+C

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --site)       SITE="$2"; shift 2 ;;
    --port)       PORT="$2"; shift 2 ;;
    --bench)      BENCH_DIR="$2"; shift 2 ;;
    --no-watch)   WATCH=0; shift ;;
    --no-browser) OPEN_BROWSER=0; shift ;;
    --no-dev-mode)   DEV_MODE=0; shift ;;
    --keep-dev-mode) KEEP_DEV_MODE=1; shift ;;
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
        $([ $OPEN_BROWSER = 0 ] && echo --no-browser) \
        $([ $DEV_MODE = 0 ] && echo --no-dev-mode) \
        $([ $KEEP_DEV_MODE = 1 ] && echo --keep-dev-mode))"
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

# The last site you picked in this bench is remembered and offered as the default next time.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/frappe-bench-dev"
LAST_SITE_FILE="$CACHE_DIR/last-site$(printf '%s' "$BENCH_DIR" | tr '/' '_')"

site_exists() { [ -n "$1" ] && [ -f "sites/$1/site_config.json" ]; }

bench_default_site() {
  local s
  s="$(sed -n 's/.*"default_site"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
       sites/common_site_config.json 2>/dev/null | head -1)"
  [ -n "$s" ] || s="$(cat sites/currentsite.txt 2>/dev/null)"
  echo "$s"
}

choose_site() { # interactive menu; prints the chosen site on stdout
  local default="$1"; shift
  local sites=("$@") i ans mark
  {
    echo
    echo "This bench has ${#sites[@]} sites:"
    for i in "${!sites[@]}"; do
      mark=""; [ "${sites[$i]}" = "$default" ] && mark="  <- default"
      printf '  %2d) %s%s\n' $((i + 1)) "${sites[$i]}" "$mark"
    done
  } >&2
  while true; do
    if [ -n "$default" ]; then
      printf 'Choose a site [1-%d or name, Enter = %s]: ' "${#sites[@]}" "$default" >&2
    else
      printf 'Choose a site [1-%d or name]: ' "${#sites[@]}" >&2
    fi
    IFS= read -r ans </dev/tty || exit 1
    if [ -z "$ans" ] && [ -n "$default" ]; then echo "$default"; return; fi
    if [[ "$ans" =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -le "${#sites[@]}" ]; then
      echo "${sites[$((ans - 1))]}"; return
    fi
    site_exists "$ans" && { echo "$ans"; return; }
    echo "  Not a valid choice, try again." >&2
  done
}

if [ -n "$SITE" ]; then
  site_exists "$SITE" || die "Site '$SITE' does not exist in $BENCH_DIR/sites. Available: $(echo $(list_sites))"
else
  SITES=()
  while IFS= read -r s; do SITES+=("$s"); done < <(list_sites)
  DEFAULT="$(cat "$LAST_SITE_FILE" 2>/dev/null)"
  site_exists "$DEFAULT" || DEFAULT="$(bench_default_site)"
  site_exists "$DEFAULT" || DEFAULT=""

  case "${#SITES[@]}" in
    0) die "No sites found in $BENCH_DIR/sites." ;;
    1) SITE="${SITES[0]}" ;;
    *)
      if [ -t 0 ] && { : </dev/tty; } 2>/dev/null; then
        SITE="$(choose_site "$DEFAULT" "${SITES[@]}")" || exit 1
        mkdir -p "$CACHE_DIR" 2>/dev/null && printf '%s\n' "$SITE" >"$LAST_SITE_FILE" 2>/dev/null
      elif [ -n "$DEFAULT" ]; then
        SITE="$DEFAULT"
      else
        die "This bench has several sites, pass one with --site: $(echo "${SITES[@]}")"
      fi
      ;;
  esac
fi

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

RESTORE_DEV_MODE=""   # value to put back on exit ("None" removes the key)

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [ ${#PIDS[@]} -gt 0 ]; then
    echo; say "Stopping..."
    for pid in "${PIDS[@]}"; do kill_tree "$pid"; done
    wait 2>/dev/null
  fi
  if [ -n "$RESTORE_DEV_MODE" ]; then
    if bench --site "$SITE" set-config developer_mode "$RESTORE_DEV_MODE" >/dev/null 2>&1; then
      bench --site "$SITE" clear-cache >/dev/null 2>&1
      say "Developer mode: turned back off"
    else
      warn "Could not restore developer_mode, check sites/$SITE/site_config.json"
    fi
  fi
  [ ${#PIDS[@]} -gt 0 ] && say "Stopped."
  exit "$rc"
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

# developer mode + cache
json_get() { # json_get FILE KEY -> prints value as JSON, or __MISSING__
  python3 - "$1" "$2" <<'PY' 2>/dev/null || echo __MISSING__
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
print(json.dumps(d[sys.argv[2]]) if sys.argv[2] in d else "__MISSING__")
PY
}

if [ "$DEV_MODE" = 1 ]; then
  RAW="$(json_get "sites/$SITE/site_config.json" developer_mode)"
  EFFECTIVE="$RAW"
  [ "$RAW" = "__MISSING__" ] && EFFECTIVE="$(json_get sites/common_site_config.json developer_mode)"
  case "$EFFECTIVE" in
    1|true) say "Developer mode: already on" ;;
    *)
      bench --site "$SITE" set-config developer_mode 1 >/dev/null 2>&1 \
        || die "Could not turn on developer_mode in sites/$SITE/site_config.json"
      if [ "$KEEP_DEV_MODE" = 1 ]; then
        say "Developer mode: turned on"
      else
        case "$RAW" in
          __MISSING__) RESTORE_DEV_MODE="None" ;;
          false) RESTORE_DEV_MODE="false" ;;
          *) RESTORE_DEV_MODE="$RAW" ;;
        esac
        say "Developer mode: turned on (goes back off when you press Ctrl+C)"
      fi
      ;;
  esac
fi

say "Clearing cache..."
bench --site "$SITE" clear-cache >/dev/null 2>&1 || warn "clear-cache failed"

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
