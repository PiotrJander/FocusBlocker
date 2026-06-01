#!/usr/bin/env bash
set -euo pipefail

label="com.piotrjander.focusblocker"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installed_binary="/Applications/FocusBlocker.app/Contents/MacOS/FocusBlocker"
built_binary="$repo_dir/build/FocusBlocker.app/Contents/MacOS/FocusBlocker"
plist="$HOME/Library/LaunchAgents/$label.plist"
logs_dir="$HOME/Library/Logs"

if [[ -x "$installed_binary" ]]; then
  binary="$installed_binary"
elif [[ -x "$built_binary" ]]; then
  binary="$built_binary"
else
  echo "Build or install FocusBlocker first:"
  echo "  make build"
  echo "  make install"
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$logs_dir"

python3 - "$plist" "$label" "$binary" "$logs_dir/FocusBlocker.log" "$logs_dir/FocusBlocker.err.log" <<'PY'
import plistlib
import sys

plist_path, label, binary, stdout_path, stderr_path = sys.argv[1:]
plist = {
    "Label": label,
    "ProgramArguments": [binary],
    "RunAtLoad": True,
    "StandardOutPath": stdout_path,
    "StandardErrorPath": stderr_path,
}

with open(plist_path, "wb") as file:
    plistlib.dump(plist, file, sort_keys=False)
PY

launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl kickstart -k "gui/$(id -u)/$label" 2>/dev/null || true

echo "FocusBlocker will now start when you log in."
