#!/bin/bash
#
# Clipboard bridge between a nested Zero session and the desktop it runs inside
#
# Not meant to be run by hand. In nested mode configurator.py copies this file
# into the profile directory and the generated autostart launches the copy with:
#
#   ZERO_OUTER_WAYLAND_DISPLAY  the outer compositor's socket, e.g. wayland-0
#   ZERO_OUTER_DISPLAY          the outer X display, e.g. :0  (x11 method only)
#   ZERO_CLIPBOARD_METHOD       how an outer copy is noticed: wayland, x11 or poll
#
# WAYLAND_DISPLAY is the inner socket, labwc sets it for everything it starts.
# Nothing is detected here, configurator.py probes the outer session before
# launch and bakes the answer into ZERO_CLIPBOARD_METHOD
#
# Clipboard content only. The primary selection, the one middle-click pastes,
# is deliberately left alone: it changes on every drag-select and would flood
# the far side with transfers nobody asked for
#
set -u

OUTER_WL="${ZERO_OUTER_WAYLAND_DISPLAY:-}"
OUTER_X="${ZERO_OUTER_DISPLAY:-}"
METHOD="${ZERO_CLIPBOARD_METHOD:-poll}"
INNER_WL="${WAYLAND_DISPLAY:-}"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
SELF="$0"
DOORBELL="$(dirname "$SELF")/clipboard-doorbell.py"

# Keyed on the inner socket so two nested sessions never share a guard
STATE="$RUNTIME/zero-clipboard-${INNER_WL:-unknown}.hash"

# Only reached when the outer session can be neither watched nor doorbelled
POLL_INTERVAL=1


# Never bridge a session to itself. Without this a stray environment variable
# would point both ends at one compositor and every copy would loop forever
if [ -z "$OUTER_WL" ] || [ -z "$INNER_WL" ] || [ "$OUTER_WL" = "$INNER_WL" ]; then
    exit 0
fi


# The inner socket disappears when labwc exits, which is how the outer watcher
# learns the session is over. The inner watcher simply ends on its own
session_alive() {
    [ -S "$RUNTIME/$INNER_WL" ]
}


# Pick the most faithful type on offer, so an image crosses as an image instead
# of being flattened into whatever text representation happens to be listed
best_type() {
    local types
    types=$(WAYLAND_DISPLAY="$1" timeout 5 wl-paste --list-types 2>/dev/null) || return 1
    echo "$types" | grep -m1 '^image/'                   && return 0
    echo "$types" | grep -m1 '^text/plain;charset=utf-8' && return 0
    echo "$types" | grep -m1 '^text/plain'               && return 0
    echo "$types" | head -n1
}


# Move the current selection from one compositor to the other.
#
# The hash of the last thing moved is kept in a file shared by both watchers.
# Writing a selection makes the far side fire its own watcher, so without this
# guard one copy would bounce back and forth for the life of the session
transfer() {  # transfer <from_socket> <to_socket>
    local from="$1" to="$2" type tmp sum
    type=$(best_type "$from") || return 0
    [ -n "$type" ] || return 0
    tmp=$(mktemp) || return 0
    WAYLAND_DISPLAY="$from" timeout 5 wl-paste --no-newline --type "$type" > "$tmp" 2>/dev/null
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        return 0
    fi
    sum=$(sha256sum < "$tmp" | cut -d' ' -f1)
    if [ "$sum" = "$(cat "$STATE" 2>/dev/null)" ]; then
        rm -f "$tmp"
        return 0
    fi
    printf '%s' "$sum" > "$STATE"
    WAYLAND_DISPLAY="$to" wl-copy --type "$type" < "$tmp"
    rm -f "$tmp"
}


# Both watchers call back into this script rather than duplicating transfer().
# Whatever wl-paste feeds us on stdin is dropped, because it is only ever the
# text form and transfer() re-reads the selection with the right type
case "${1:-}" in
    --push-out)
        cat > /dev/null 2>&1
        transfer "$INNER_WL" "$OUTER_WL"
        exit 0
        ;;
    --push-in)
        cat > /dev/null 2>&1
        transfer "$OUTER_WL" "$INNER_WL"
        exit 0
        ;;
esac


# Inside -> outside. labwc exposes a data control protocol, so this is a real
# event and costs nothing while the clipboard sits unchanged.
#
# exec, so the background subshell becomes wl-paste rather than parenting it.
# Without that, stopping the bridge kills the subshell and leaves the watcher
# orphaned and still holding the clipboard
watch_inner() {
    export WAYLAND_DISPLAY="$INNER_WL"
    exec wl-paste --watch "$SELF" --push-out
}


# Outside -> inside, by whichever route the outer compositor allows

# Preferred: the outer compositor exposes a data control protocol too, so this
# is the same pure Wayland mechanism as the inner side
watch_outer_wayland() {
    export WAYLAND_DISPLAY="$OUTER_WL"
    exec wl-paste --watch "$SELF" --push-in
}

# The outer compositor refuses background clipboard access, so we listen for the
# X selection event it mirrors into Xwayland instead. The doorbell only rings,
# it never reads or writes clipboard content, and it sleeps in between
watch_outer_doorbell() {
    local dir fifo pid
    dir=$(mktemp -d) || return 1
    fifo="$dir/ring"
    mkfifo "$fifo" || { rm -rf "$dir"; return 1; }
    DISPLAY="$OUTER_X" "$DOORBELL" > "$fifo" 2>/dev/null &
    pid=$!
    trap 'kill "$pid" 2>/dev/null; rm -rf "$dir"; exit 0' TERM
    while read -r _; do
        session_alive || break
        transfer "$OUTER_WL" "$INNER_WL"
    done < "$fifo"
    kill "$pid" 2>/dev/null
    rm -rf "$dir"
}

# Last resort when the outer session offers neither. Still pure Wayland, and the
# only route here that uses CPU while nothing is happening
watch_outer_poll() {
    while session_alive; do
        sleep "$POLL_INTERVAL"
        transfer "$OUTER_WL" "$INNER_WL"
    done
}


: > "$STATE"

watch_inner &
inner_pid=$!

case "$METHOD" in
    wayland) watch_outer_wayland  & ;;
    x11)     watch_outer_doorbell & ;;
    *)       watch_outer_poll     & ;;
esac
outer_pid=$!

trap 'kill "$inner_pid" "$outer_pid" 2>/dev/null; rm -f "$STATE"' EXIT

# labwc going away ends the inner watch, which ends the bridge
wait "$inner_pid"
