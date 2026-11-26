#!/bin/sh
# Installs the Release build into ~/Applications and starts it (under the keeper when "Open at login" is on).
# AMS Tria Menu has no fans and no helper: nothing outside the app is touched here.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
NEW="$HERE/build/Build/Products/Release/AMS Tria Menu.app"
APP="$HOME/Applications/AMS Tria Menu.app"
SERVICE="gui/$(id -u)/com.schabbauer.AMSTriaMenu.keeper"
[ -d "$NEW" ] || { echo "no Release build at $NEW"; exit 1; }

# A polite stop: the app ends cleanly (exit 0), so the keeper does not open it again.
pkill -TERM -x "AMS Tria Menu" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq "AMS Tria Menu" || break; sleep 0.5; done
launchctl bootout "$SERVICE" 2>/dev/null || true
pkill -KILL -x "AMS Tria Menu" 2>/dev/null || true

mkdir -p "$HOME/Applications"
rm -rf "$APP"
ditto "$NEW" "$APP"
# Opened by hand: with "Open at login" on, the app writes the keeper's start order and hands itself over.
open -g "$APP"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sleep 0.5
  if launchctl print "$SERVICE" 2>/dev/null | grep -q "state = running"; then echo "running under the keeper"; exit 0; fi
done
if pgrep -xq "AMS Tria Menu"; then echo "running (not under the keeper: Open at login is off)"; exit 0; fi
echo "NOT running — look at the diary"
exit 1
