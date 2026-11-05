#!/bin/sh
# XP12 Forest Tweak - Linux starter. Run in a terminal:  sh start_forest_tweak_linux.sh
# (c) E11i0t09. Free community project, not for sale. License: CC BY-NC-SA 4.0 with additional permission (free use also for companies and flight schools), see the LICENSE file.
cd "$(dirname "$0")" || exit 1
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null; then
    echo "Python 3.8 or newer is needed (e.g. 'sudo apt install python3' or 'sudo pacman -S python')."
    exit 1
fi
exec python3 xp12_forest_tweak.py "$@"
