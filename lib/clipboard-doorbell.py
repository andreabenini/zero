#!/usr/bin/env python3
#
# Clipboard doorbell for compositors that refuse background clipboard access
#
# Not meant to be run by hand. In nested mode configurator.py copies this file
# into the profile directory, and clipboard-bridge.sh runs the copy only when
# the outer compositor exposes no data control protocol.
#
# Prints one line every time the outer clipboard changes owner, and nothing
# else. It never reads clipboard content and never writes it, so the bridge
# stays the only thing that touches your data.
#
# Compositors that hide the clipboard from unfocused Wayland clients still
# mirror it into Xwayland, where a selection change is an ordinary X event.
# GTK is asked for the X11 backend so it can register that listener, then it
# sleeps in a main loop until the event arrives, costing no CPU in between
#
import os
import sys

os.environ['GDK_BACKEND'] = 'x11'

try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk
except (ImportError, ValueError) as e:
    # configurator.py checks for this before choosing the doorbell, so reaching
    # here means the session changed underneath us. Exiting lets the bridge
    # carry on with whatever it can still do
    print(f"clipboard-doorbell: GTK unavailable: {e}", file=sys.stderr)
    sys.exit(1)


def ring(clipboard, event):
    print("ring", flush=True)


clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
clipboard.connect('owner-change', ring)

try:
    Gtk.main()
except KeyboardInterrupt:
    pass
