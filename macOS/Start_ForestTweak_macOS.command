#!/bin/bash
# XP12 Forest Tweak - macOS starter (double-click in Finder)
cd "$(dirname "$0")" || exit 1
if ! /usr/bin/env python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null; then
    echo "Python 3.8 or newer is needed."
    echo "macOS may now offer to install the 'Command Line Developer Tools' (includes Python 3)."
    echo "Alternatively install Python from https://www.python.org/downloads/macos/"
    echo "Then double-click this file again."
    read -r -p "Press Enter to close."
    exit 1
fi
python3 xp12_forest_tweak.py "$@"
# keep the window open only after an error, so the message can be read
if [ $? -ne 0 ]; then
    echo
    read -r -p "Press Enter to close."
fi
