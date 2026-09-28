#
# The greeter's fuzzel styling, and the wording of the hint bar under it.
# Sourced, never run: it sets two arrays and two strings and does nothing else,
# which is why it is installed 0644 rather than executable.
#
# login.sh and power.sh are two separate menus that take turns on one screen,
# and they no longer look the same - the login prompt is a dialog in the middle
# of an empty screen, the power menu is a dropdown under a 30px panel, and the
# proportions that suit one are wrong for the other. So there are two blocks,
# each complete in itself: a script passes its own array and inherits nothing.
#
# What keeps them from drifting is that both are here, in one file, one above
# the other. That is the whole mechanism, and it is worth stating because the
# alternative has already been tried: the power menu used to be spelled out
# inside waybar's on-click in the session's green, copied from
# defaults/power-menu.ini, while the login prompt was grey - and nobody noticed,
# because that menu never managed to stay on screen long enough to be looked at.
# See docs/LOGIN.md. The two palettes differ today - the prompt grey, the power
# menu red - and that is a decision rather than the old bug returning. What
# adjacency buys is the difference being made here, against the block above it,
# instead of found on screen: a colour that diverges by accident looks exactly
# like one that diverges on purpose, and the only place to tell them apart is
# with both in view.
#
# Not a config file, and there is nothing here that parses one. A login screen
# is not a Zero profile: this is a shell fragment two scripts share, read from a
# root-owned directory, and the only way to change it is to edit it and install
# again.
#
# --cache=/dev/null is not cosmetic: the password prompt in login.sh is a dmenu
# too, and no part of it belongs in a cache file.
#
# Every flag below is also a version requirement, and the version is noted where
# the flag is. fuzzel exits on an option it does not know rather than ignoring
# it, so a flag added here without a thought for the floor is a menu that does
# not draw on an older machine - and the machine it is written on always has the
# newest fuzzel, so nothing here will ever show it. The floor is the newest flag
# in the file, currently 1.13.0 for --hide-prompt; install.sh enforces it and
# docs/LOGIN.md records why. It has been out of date twice already.

# The user list and the password prompt. Centred, and sized as a dialog: at the
# middle of an otherwise empty screen there is nothing for it to be in scale
# with, so it keeps fuzzel's wide default padding - 40 horizontal, 8 vertical,
# neither set below. Grey, and the only menu in the greeter that is: this one
# asks who you are and nothing it does is destructive.
#
# --line-height is the avatar knob, and it is not obvious. fuzzel has no
# icon-size option: an icon is drawn to fill the row it sits in, so the row
# height is the icon height, and the row height comes from the font's metrics
# unless something overrides it. 72px is the override, and the avatars are 72px
# because of it - raising --font alone grows the name and drags the picture
# along only as far as the taller line the glyphs happen to need. Points unless
# the value ends in px, which is why it ends in px.
#
# It is also the only way to put air between the rows, which is worth saying
# because it sounds like there should be another one: fuzzel spaces items by
# making them taller and has no gap setting, so the distance between two names
# and the size of the pictures beside them are one number and cannot be set
# apart. 72 buys both at once. It does not buy them indefinitely - the
# placeholder is 96x96 and AccountsService publishes larger, and --scaling-filter
# is documented for downscaling only, so somewhere past 96 the icons should stop
# growing and the rest should become the gap. Untested, and only worth reaching
# for if 72 reads as cramped: eight accounts at 72px is already 576px of list
# before any padding.
#
# --inner-pad is the one piece of vertical space that is not the rows: the gap
# between the input line and the list under it, 0 by default, which on a list
# this size ran the first name straight into the box above it.
#
# --line-height is fuzzel 1.5.0 and --inner-pad is older than the 1.13.0 floor
# --hide-prompt sets below - it is in fuzzel man pages shipped with FreeBSD 13.2,
# though upstream's changelog never announced it and no release could be pinned
# to it. So the version requirement in the header is unchanged.
#
# Both prompts wear this, the list and the password box alike, and only the list
# has an icon in it - so the 48px row that fits an avatar is spent on a password
# field that has nothing to put in it, and that field is now a tall grey band
# around a line of asterisks. That is the cost of the two sharing one array. If
# it grates, the fix is a third block here rather than a flag added at the call
# site in login.sh: what keeps these palettes honest is that they are all in
# this file, in view of each other.
LOOK_LOGIN=(
    --cache=/dev/null
    --background='1a1a1aee'
    --text-color='d6d5d4ff'
    --match-color='0102ffff'
    --selection-color='f6f5f4ff'
    --selection-text-color='000000ff'
    --selection-match-color='0102ffff'
    --border-color='474747ff'
    --font='Sans:size=32'
    --line-height=72px
    --horizontal-pad=30
    --vertical-pad=20
    --inner-pad=15
    --border-width=3
    --border-radius=10
    --width=20
    --anchor=center
)

# The power menu, hung under the panel's ⏻ button.
#
# --anchor=top-right with a small --y-margin, and not the panel's height plus a
# gap: fuzzel is a layer-shell surface that respects waybar's exclusive zone, so
# the anchor is already the bottom edge of the panel rather than the top of the
# screen. Measured, not assumed - at --y-margin=0 the menu sits flush against
# the panel. --x-margin matches the button's own margin-right in
# waybar/style-login.css, which is what puts the menu's right edge under the
# button's rather than near it.
#
# Red, where the prompt above is grey. Three of the four items here act on the
# machine - two of them end it - and this is the one menu in the greeter where a
# misclick costs something, so it does not share the prompt's palette.
#
# Tighter than the dialog and set in a larger face: padding cut to 10 and 5 from
# fuzzel's 40 and 8, the font up to 18 from the prompt's 16. --width is in
# characters and fits the longest label, so the menu is the size of what it
# contains rather than fuzzel's 30-character default, and the size is spent on
# four short labels instead of on width.
#
# --hide-prompt (fuzzel 1.13.0) drops the input row; typing still filters, it
# just is not drawn.
# Four labelled items under a button someone has already clicked with the mouse
# is a list to point at, not a thing to search, and an empty input line at the
# top of it invited a keystroke for no reason. Not the first choice: a smaller
# font on the input alone would have said the same thing more quietly, and
# fuzzel has one --font for the whole surface - the comma-separated form is a
# fallback chain for missing glyphs, not a per-element size. So this, or
# nothing. Do not carry it up into LOOK_LOGIN: that input is the password
# field, and login.sh renders it as asterisks precisely so it can be seen.
LOOK_POWER=(
    --cache=/dev/null
    --background='1A1A1AF2'
    --text-color='F67574ff'
    --match-color='01ffffff'
    --selection-color='EE4747BB'
    --selection-text-color='FFFFFFFF'
    --selection-match-color='01ffffff'
    --border-color='FF4747BB'
    --font='Sans:size=18'
    --border-width=3
    --border-radius=10
    --anchor=top-right
    --x-margin=5
    --y-margin=6
    --width=13
    --horizontal-pad=10
    --vertical-pad=5
    --hide-prompt
)

# The hint bar's two lines, one per thing the greeter can be waiting for.
#
# Here rather than in login.sh because they are what the screen says, not what
# it does: login.sh knows there is a line to show at each prompt and nothing
# about what it reads, so the wording can be changed, translated or emptied
# without opening the script that authenticates people. It sits with the fuzzel
# palettes for the same reason those sit together - the hint is under the prompt
# it describes, and the two are worth editing in one place.
#
# One of these replaced a fuzzel --prompt. The password box used to carry
# 'Password (ESC to go back) ' inside it, which made the dialog at least 26
# characters wide however narrow the user list was set - the width of the box
# was decided by the length of an instruction. Down here the instruction is on
# its own panel and costs the dialog nothing, and that is why --width in
# LOOK_LOGIN can now be whatever suits the names.
#
# Plain text, and the bar is centred: the layout is config-login's, the colour
# and size are style-login.css's, and a prefix or pango markup belongs in that
# module's "format" rather than in the string here.
HINT_USER='Select Your Username'
HINT_PASSWORD='Enter Your Password   (or press ESC to go back)'
