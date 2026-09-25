#!/bin/bash
#
# The greeter's power menu. Runs as uid `zero` inside the greeter's logind
# session, launched by the panel's power button - waybar/config-login names this
# file and nothing else.
#
# Separate from login.sh deliberately: the user list and the power controls are
# two menus, not one, and neither offers what the other does. The single thing
# they have to agree on is which of them is on screen.
#
# Which is not a matter of taste. fuzzel takes an exclusive lock on
# $XDG_RUNTIME_DIR/fuzzel-$WAYLAND_DISPLAY.lock at startup and refuses to run
# while another instance holds it:
#
#     failed to acquire lock: fuzzel already running?
#
# login.sh keeps a prompt up at all times, so that lock is always held and a
# second fuzzel simply exits. This menu cannot draw next to the login prompt.
# It has to replace it.
#
# So the order is: take the lock below, which is what stops login.sh redrawing;
# kill the prompt; wait for it to be gone; then start. Preemption runs one way
# only - the power button interrupts the prompt, never the reverse - which is
# what keeps a person from being locked out of shutting the machine down.
#
# The first version of this file did none of that and its fuzzel died on
# startup every time, which on screen looks exactly like a button that is not
# wired up. `journalctl -b -t zero-login` is where that line goes.
#
# The actions do not go through zero-login's pipe. `autostart` closes fds 3 and
# 4 on waybar, so nothing here inherits them and there is nothing to close;
# systemctl is called directly. systemd's shipped policy allows power-off,
# reboot and suspend for an Active session on a local seat, and the greeter's
# session has to be Active to hold the GPU at all. See docs/LOGIN.md.
#
# Nothing here is configurable and nothing here parses a config file - there is
# no power-menu.ini in this directory, unlike a Zero profile.

set -u

PROFILE=/etc/zero/login
RUNTIME="${XDG_RUNTIME_DIR:?no XDG_RUNTIME_DIR}"

# The lock login.sh waits on, and the pid of the fuzzel it stands for.
LOCK="$RUNTIME/zero-power.lock"
PIDFILE="$RUNTIME/zero-power.pid"

# Appearance and position, from the file that holds both menus' styling side by
# side so neither can be restyled without the other being in view. This menu
# uses LOOK_POWER, which anchors it under the panel's power button; the login
# prompt uses LOOK_LOGIN and stays centred.
. "$PROFILE/look.sh" || exit 1

# Presentation only. The case at the bottom matches the position of the item
# chosen and never its text, so these can be reworded, retranslated or restyled
# without anything below having to be kept in step - see --index there. What
# does matter is the order, which is the interface between the two.
#
# Cancel runs nothing and is there so the menu can be dismissed with the mouse
# alone.
#
# The glyphs need a font that has them: ⏻ is U+23FB and ⏸ is U+23F8, and neither
# is in DejaVu or Liberation - fontconfig usually answers with Noto Sans Symbols
# 2, which a minimal machine will not have installed. install.sh checks for them
# because a missing one is only a blank space on screen.
ITEMS=("⏻  Shutdown" "↻  Reboot" "⏸  Standby" "✖  Cancel")

# Take the screen off the login prompt, and do not come back until it is really
# gone - fuzzel checks its instance lock at startup, so a prompt still shutting
# down is a menu that never opens.
#
# Signalling every fuzzel is safe here and only here: this runs while the power
# lock is held, so login.sh is blocked before its next prompt and the only
# fuzzel that can exist is the one being replaced. login.sh reads the SIGTERM as
# a dismissal rather than a failure - see the exit codes at the top of it.
#
# The retry is for one narrow race: login.sh may have passed its wait and be
# between there and its next fuzzel, in which case the first kill finds nothing
# and a prompt appears just after it. It cannot get past the wait twice, so a
# second pass always wins.
dismiss_prompt() {
    local attempt tick

    for attempt in 1 2 3; do
        pkill -x fuzzel 2>/dev/null || :
        for tick in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -x fuzzel >/dev/null 2>&1 || return 0
            sleep 0.1
        done
    done
    return 1
}

# fd 9 is the lock. The kernel drops it when this process exits, whichever way
# it goes, so a fuzzel that dies badly still gives the prompt its screen back.
#
# `9>&-` below is load-bearing for the same reason `3>&- 4>&-` is in autostart,
# and it fails the same silent way. A descriptor is inherited, and the lock is
# held for as long as any process holds the descriptor - not for as long as this
# script runs. One child outliving this script would keep the login prompt off
# the screen until login.sh's timeout gave up on it.
exec 9>"$LOCK" || exit 1

if ! flock -n 9; then
    # The menu is already up, so this is a second click on the power button.
    # The session's panel treats that as "close it" (lib/configure/menus.py) and
    # so does this.
    #
    # By pid, not by `pkill -x fuzzel` the way the session does it: the holder
    # may have exited between the failed lock and here, in which case login.sh
    # has the screen back and the only fuzzel running is the login prompt.
    # Killing that one exits login.sh, which takes the whole greeter with it.
    # A stale pid is a kill that quietly fails instead.
    if [ -r "$PIDFILE" ] && read -r pid < "$PIDFILE" && [[ $pid =~ ^[0-9]+$ ]]; then
        kill "$pid" 2>/dev/null || :
    fi
    exit 0
fi

# Nothing below can draw until this succeeds. Giving up leaves the login prompt
# where it is, which is the right way to fail: the screen keeps working and the
# journal keeps the reason.
if ! dismiss_prompt; then
    echo "power.sh: the login prompt will not go, leaving the screen alone" >&2
    exit 1
fi

# fuzzel's choice cannot come back through a pipeline substitution here: the pid
# is needed while it runs, and only a backgrounded job has one.
CHOICE=$(mktemp "$RUNTIME/zero-power.XXXXXX") || exit 1
trap 'rm -f "$CHOICE" "$PIDFILE"' EXIT

printf '%s\n' "${ITEMS[@]}" |
    fuzzel --dmenu --index --lines="${#ITEMS[@]}" --prompt='' "${LOOK_POWER[@]}" 9>&- >"$CHOICE" &
menu_pid=$!
printf '%s\n' "$menu_pid" > "$PIDFILE"

wait "$menu_pid"
rc=$?

# 0 chosen, 2 cancelled with ESC or by losing focus, 143 dismissed by the second
# click above, anything else fuzzel in trouble. Only 0 is a decision.
(( rc == 0 )) || exit 0

# --index makes fuzzel print the position of the chosen item in the list it was
# given, rather than the item. The label never reaches this script, so the two
# ends agree on an ordinal and nothing here can be broken by an edit to ITEMS
# that a person would call cosmetic.
#
# It was the text once, matched literally, and that is a trap this file has
# already fallen into: adding a glyph and two spaces to the front of every label
# left `Shutdown)` matching nothing, every branch falling through the catch-all
# and a menu that opened, took the click and did nothing at all. Whitespace,
# translation and a UTF-8 label under a C-locale fuzzel are three more ways to
# arrive at the same silence. An integer has none of them.
#
# fuzzel prints -1 for text typed that matched no entry (wayland.c, and it is
# what --dmenu would have echoed back as an unrecognised line). It falls through
# the catch-all with everything else that is not one of the four.
read -r choice < "$CHOICE" || exit 0
case "$choice" in
    0) systemctl poweroff ;;
    1) systemctl reboot   ;;
    2) systemctl suspend  ;;
    3)                    ;;   # Cancel
    *)                    ;;   # -1, no match; or a list that grew
esac 9>&-
