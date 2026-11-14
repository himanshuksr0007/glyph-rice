#!/bin/sh
# galaga-session: the quiet-boot session wrapper. ./install.sh --quiet-boot
# installs this as /usr/local/bin/galaga-session, and the quiet session entry
# (galaga.desktop, beside the uwsm Hyprland entry) runs the real session
# command through it, so the session's output -- the "Selected compositor
# ID..." / "Created unit..." block that would print on the console after
# login -- is appended to a log in the user's state dir instead.
# A script, not a quoted shell string inside the desktop entry: the entry's
# Exec stays plain words that every reader splits the same way.
mkdir -p "$HOME/.local/state/galaga"
exec "$@" >>"$HOME/.local/state/galaga/session.log" 2>&1
