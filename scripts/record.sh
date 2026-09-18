#!/usr/bin/env bash
# Start a Granola recording (used by the Hyprland global bind).
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/status.py" record
