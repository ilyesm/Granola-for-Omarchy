#!/usr/bin/env bash
# Start a Granola recording (used by the Hyprland global bind).
# Opens the app if needed, then sends granola:// so transcription starts.
LAUNCHER="${GRANOLA_INSTALL_DIR:-$HOME/Applications/granola}/granola.sh"
exec "$LAUNCHER" "granola://new-document?auto_transcribe=1&creation_source=application_menu"
