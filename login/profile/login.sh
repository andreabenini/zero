#!/bin/bash
#
# The greeter's login flow. Runs as uid `zero` inside the greeter's logind
# session, started from this profile's autostart.
#
#   fd 3  ->  zero-login    username \n password \n
#   fd 4  <-  zero-login    OK \n | FAIL \n
#
# This is the only process in the greeter that holds fds 3 and 4 - autostart
# closes them on everything else it launches - so zero-login's read() gets EOF
# the moment this script exits, whichever way it goes. autostart runs
# `labwc -e` straight afterwards, so the compositor goes with it rather than
# leaving a background on screen with no prompt.
#
# Nothing here is configurable and nothing here parses a config file. A login
# screen is not a Zero profile; see docs/LOGIN.md.

set -u

PROFILE=/etc/zero/login
PLACEHOLDER="$PROFILE/avatar.png"
ICONS=/var/lib/AccountsService/icons
AVATARS="${XDG_RUNTIME_DIR:?no XDG_RUNTIME_DIR}/avatars"

# fuzzel exit codes: 0 chosen, 2 cancelled with ESC, 1 anything else
CANCELLED=2

# SIGTERM, and not a failure. fuzzel refuses to run while another instance holds
# $XDG_RUNTIME_DIR/fuzzel-$WAYLAND_DISPLAY.lock, so the power menu cannot open
# beside this prompt - power.sh kills it to take the screen. Treating this as an
# error would exit here, and exiting here takes the whole greeter down every
# time somebody reaches for the power button.
DISMISSED=143

# Appearance and position, read from a shell fragment rather than a config file
# - there is no power-menu.ini or apps-menu.ini in this directory and nothing to
# parse one. The panel's power menu is the other half of the same screen and
# sources the same file, so neither can be restyled without the other being in
# view. Both prompts here use LOOK_LOGIN and stay centred; the power menu uses
# LOOK_POWER and hangs under the panel button.
. "$PROFILE/look.sh" || exit 1

# The panel's power menu is a fuzzel as well, and fuzzel refuses to start while
# another instance holds its lock - see DISMISSED above. This prompt is up
# permanently, so that lock is permanently held and the power menu could never
# open at all: a click on the power button used to do nothing, visibly. The menu
# has to replace this prompt rather than draw beside it.
#
# power.sh holds this lock for as long as its menu is up. Waiting on it before
# every prompt is the whole of the arrangement, and it is one-sided on purpose:
# the power button interrupts the prompt and the prompt only ever waits its
# turn. The timeout is a backstop - a login screen that can never redraw is a
# worse failure than a power menu cut short after a minute of being stared at.
POWER_LOCK="${XDG_RUNTIME_DIR}/zero-power.lock"

await_power_menu() {
    flock -w 60 -s "$POWER_LOCK" true 2>/dev/null || :
}

# The hint bar along the bottom of the screen, which says what the prompt in
# the middle of it is waiting for. waybar draws it; this decides what it reads.
#
# A waybar custom module cannot be handed new text - it re-runs its exec and
# shows whatever comes back - so the state is a file, and the module polls it.
# Writing the file is the whole of the mechanism here. The wording is in
# look.sh and the layout is in waybar/config-login; what is here is only which
# of the two lines applies at which prompt.
#
# It does not signal waybar, and that is the entire point of this comment.
#
# The obvious way to do this is the documented one: give the module a "signal"
# and have the script pkill -RTMIN+n after each write, so the bar changes the
# instant the prompt does. That was written, installed, and it deleted the
# panel - both bars, every run, with not one line in the journal to say why.
#
# A realtime signal terminates a process that has not installed a handler for
# it, and waybar installs its handlers while starting up. autostart backgrounds
# waybar and reaches this script immediately, so the first hint() landed tens of
# milliseconds later, into a waybar that was still coming up and not yet
# defended. pkill did not fail to find it. It found it and killed it, before
# waybar had parsed its own config, which is why the journal showed nothing at
# all and why the config was the first thing suspected and the last thing at
# fault. The greeter still prompted and still logged people in, so the only
# symptom was a login screen with no panels.
#
# There is no version of the signal that is safe here. Waiting for the process
# to appear does not help: `pgrep -x waybar` is true from exec, and the handler
# is installed some unknowable time after that, so the race is narrowed and not
# closed. A greeter must not have a startup race that can silently remove its
# own power button. Polling costs a `cat` a second and cannot do this.
#
# Failure is never fatal. The bar is an instruction, not a control - no route
# through this script is unusable without it - so the write is allowed to fail
# silently rather than take the prompt down with it.
#
# Written through a temporary file and renamed, because the reader is a `cat`
# that can run at any moment, including in the middle of a write. rename(2) is
# atomic within a directory, so the module sees the old line or the new one and
# never half of either.
HINT_FILE="${XDG_RUNTIME_DIR}/zero-hint"

hint() {
    printf '%s\n' "$1" > "$HINT_FILE.new" 2>/dev/null &&
        mv -f "$HINT_FILE.new" "$HINT_FILE" 2>/dev/null || :
}

# Accounts to offer: UID inside the UID_MIN..UID_MAX window from
# /etc/login.defs, with a shell that is not nologin or false. No hand-kept
# allowlist, and it is what keeps the `zero` account off its own login screen
# without a special case - `zero` is a system UID with a nologin shell.
list_users() {
    local min max name uid shell
    min=$(awk '$1 == "UID_MIN" { print $2 }' /etc/login.defs 2>/dev/null)
    max=$(awk '$1 == "UID_MAX" { print $2 }' /etc/login.defs 2>/dev/null)
    : "${min:=1000}"
    : "${max:=60000}"
    while IFS=: read -r name _ uid _ _ _ shell; do
        [[ $uid =~ ^[0-9]+$ ]] || continue
        (( uid >= min && uid <= max )) || continue
        case "$shell" in
            */nologin|*/false|nologin|false) continue ;;
        esac
        printf '%s\n' "$name"
    done < /etc/passwd
}

mapfile -t USERS < <(list_users)
if (( ${#USERS[@]} == 0 )); then
    echo "login.sh: no accounts between UID_MIN and UID_MAX to offer" >&2
    exit 1
fi

# fuzzel picks its image loader from the last three characters of the path, and
# the AccountsService files have no extension, so every avatar is symlinked to
# a .png name in the runtime directory. PNG is what AccountsService publishes;
# anything else simply renders without an icon.
mkdir -p "$AVATARS" || exit 1
for user in "${USERS[@]}"; do
    src="$ICONS/$user"
    [ -f "$src" ] || src="$PLACEHOLDER"
    ln -sfn "$src" "$AVATARS/$user.png"
done

# Rofi's extended dmenu protocol: label NUL "icon" US path. The unit separator
# is written in octal because \x is not portable across printf implementations.
user_menu() {
    local user
    for user in "${USERS[@]}"; do
        printf '%s\0icon\037%s\n' "$user" "$AVATARS/$user.png"
    done
}

is_listed() {
    local user
    for user in "${USERS[@]}"; do
        [ "$user" = "$1" ] && return 0
    done
    return 1
}

# Show at most this many rows, so a machine with many accounts does not get a
# full-height window. Filtering by typing still reaches the rest.
rows=${#USERS[@]}
(( rows > 8 )) && rows=8
# Consecutive failures to draw the prompt, reset by every prompt that draws.
failures=0

while :; do
    await_power_menu
    # Set at the top of each pass rather than once before the loop, so every
    # way back to the list - ESC, a bad password, the power menu closing -
    # restores the line without any of them having to remember to.
    hint "$HINT_USER"
    user=$(user_menu | fuzzel --dmenu --lines="$rows" --hide-prompt --prompt='' "${LOOK_LOGIN[@]}")
    rc=$?

    # ESC here has nowhere to go back to, so the list is simply redrawn. A
    # dismissal is the power menu taking the screen: same redraw, and the wait
    # at the top of the loop holds it back until the menu is gone.
    if (( rc == CANCELLED || rc == DISMISSED )); then
        failures=0
        continue
    fi

    # Anything else is fuzzel failing rather than a person choosing, and the
    # likeliest one is losing the race for its own instance lock to a fuzzel
    # that is still shutting down. That is worth another go: exiting here takes
    # the greeter with it, and a screen that blanks and restarts every time
    # somebody uses the power button is worse than a prompt half a second late.
    #
    # Three in a row is fuzzel actually broken - a missing font, no compositor -
    # and retrying that forever would spin. Exit and let systemd restart clean.
    if (( rc != 0 )); then
        (( ++failures >= 3 )) && exit 1
        sleep 0.5
        continue
    fi
    failures=0

    # --dmenu echoes whatever was typed when nothing matches it, so a typed
    # name that is not on the list arrives here. Drop it instead of sending it.
    is_listed "$user" || continue

    while :; do
        await_power_menu
        hint "$HINT_PASSWORD"
        # --prompt='' where this once read 'Password (ESC to go back) '. The
        # instruction moved to the hint bar, and the box is now unlabelled on
        # purpose: what it wants is said along the bottom of the screen, and
        # the dialog is free to be as narrow as LOOK_LOGIN's --width asks.
        # --password still renders every keystroke as an asterisk, so there is
        # no doubt about which of the two prompts is on screen.
        password=$(fuzzel --dmenu --password --lines=0 \
                          --prompt='' "${LOOK_LOGIN[@]}" </dev/null)
        rc=$?

        # ESC, an empty entry, or fuzzel in trouble - all three go back to the
        # user list. A broken fuzzel then fails there too and exits, so this
        # cannot spin.
        (( rc != 0 )) && break

        printf '%s\n%s\n' "$user" "$password" >&3
        read -r verdict <&4 || exit 1
        [ "$verdict" = "OK" ] && exit 0
        # FAIL: same user still selected, ask again. Attempts are not counted
        # here - pam_faillock is in the stack behind zero-login and does it.
    done
done
