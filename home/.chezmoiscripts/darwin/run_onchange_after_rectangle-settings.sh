#!/bin/bash
# Configure Rectangle to tile with Cmd+arrows, matching Win+arrows on Windows.
# Rectangle caches its preferences while running and writes them back, so quit
# it before writing and relaunch it after.
set -euo pipefail

domain=com.knollsoft.Rectangle
cmd=1048576 # NSEventModifierFlagCommand

pid=$(pgrep -x Rectangle || true)
if [ -n "$pid" ]; then
  kill "$pid"
  while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
fi

# Skip the first-launch prompts: the welcome dialog would offer to replace the
# shortcuts below with a default set.
defaults write "$domain" internalTilingNotified -bool true
defaults write "$domain" SUHasLaunchedBefore -bool true
defaults write "$domain" wasWelcomeDisplayed -bool true

defaults write "$domain" allowAnyShortcut -bool true
defaults write "$domain" alternateDefaultShortcuts -bool true
defaults write "$domain" SUEnableAutomaticChecks -bool false
defaults write "$domain" subsequentExecutionMode -int 1

# Arrow key codes: left 123, right 124, down 125, up 126.
defaults write "$domain" center -dict keyCode -int 125 modifierFlags -int "$cmd"
defaults write "$domain" leftHalf -dict keyCode -int 123 modifierFlags -int "$cmd"
defaults write "$domain" maximize -dict keyCode -int 126 modifierFlags -int "$cmd"
defaults write "$domain" rightHalf -dict keyCode -int 124 modifierFlags -int "$cmd"

# An empty dict unbinds an action.
for action in bottomHalf bottomLeft bottomRight larger maximizeHeight \
  nextDisplay previousDisplay restore smaller topHalf topLeft topRight; do
  defaults write "$domain" "$action" -dict
done

if [ -n "$pid" ]; then
  open -a Rectangle
fi
