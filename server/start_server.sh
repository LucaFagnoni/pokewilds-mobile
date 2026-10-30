#!/usr/bin/env bash
# Starts the PokeWilds dedicated server (Linux and macOS); start_server.bat's twin.
# The server runs in a process group of its own, so Ctrl+C reaches this script
# and not the server (a release build of Godot dies at once on Ctrl+C): Ctrl+C
# (or closing the terminal) sends it "stop 0", and it saves the world before it
# exits. Typed lines are sent to the server as commands. A server that ends for
# `restart` (exit code 75) is started again. Options go on the command line:
# ./start_server.sh --world Isola --size L
dir=$(cd "$(dirname "$0")" && pwd)
if [ -x "$dir/PokeWilds.app/Contents/MacOS/PokeWilds" ]; then
    exe="$dir/PokeWilds.app/Contents/MacOS/PokeWilds"
    # Downloaded files are quarantined; the first launch would be refused.
    xattr -dr com.apple.quarantine "$dir/PokeWilds.app" 2>/dev/null
else
    exe="$dir/PokeWilds.x86_64"
fi
[ -x "$exe" ] || { echo "PokeWilds not found or not executable: $exe"; exit 1; }

# The data and the settings beside this script, also inside a macOS .app.
args=(--headless --server)
case " $* " in *" --data "*) ;; *) args+=(--data "$dir/server_data") ;; esac
case " $* " in *" --config "*) ;; *) args+=(--config "$dir/server.cfg") ;; esac

set -m
fifo=$(mktemp -u "${TMPDIR:-/tmp}/pokewilds-server.XXXXXX")
mkfifo "$fifo" || exit 1
trap 'rm -f "$fifo"' EXIT
stop() { printf 'stop 0\n' >&3 2>/dev/null; }
trap stop INT TERM HUP

while :; do
    "$exe" "${args[@]}" "$@" < "$fifo" &
    pid=$!
    exec 3> "$fifo"
    # Keeps the Mac awake while the server runs (Linux desktops may still sleep).
    command -v caffeinate > /dev/null && caffeinate -i -w "$pid" &
    # Typed lines are the server's commands; with no terminal (a service) just wait.
    while kill -0 "$pid" 2> /dev/null; do
        if IFS= read -r -t 1 line; then
            printf '%s\n' "$line" >&3
        elif [ $? -eq 1 ]; then
            break
        fi
    done
    wait "$pid"; code=$?
    while [ "$code" -gt 128 ] && kill -0 "$pid" 2> /dev/null; do wait "$pid"; code=$?; done
    exec 3>&-
    # `restart` typed in the server: it saved and ended with code 75. Start it again.
    [ "$code" -eq 75 ] || exit "$code"
    echo "SERVER starting again..."
done
