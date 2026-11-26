# AMS Tria Menu

AMS Tria Menu is a small Mac menu bar app that puts today's training session and your Garmin Body Battery one click away. One small icon in the menu bar, the training wave of AMS Triathlon Training's app icon, is green while it has today's note. A click opens a panel with today, tomorrow, the week and a small Body Battery curve. It only reads and never changes your plan.

![The panel by day](Docs/pictures/panel-todo-day.png) ![The panel by night](Docs/pictures/panel-todo-night.png)

The menu bar icon (green with today's note, grey without):

![The menu bar icon](Docs/pictures/menubar-day.png)

All values in the pictures are invented.

It is a personal app for an Apple Silicon Mac, macOS 15 or later. Use it at your own risk.

## What it needs

- AMS Triathlon Training 2.8 or newer on the same Mac. It writes a small note about today that this app reads.
- The AMS Garmin Bridge Board on the same Mac, for Body Battery.

## Build and install

```
xcodegen generate
xcodebuild -scheme "AMS Tria Menu" -configuration Release -derivedDataPath build build
Tools/install.sh
```

## Rule tests

```
swift test --package-path Core
```

The full specification is in `Docs/SPEC.md`.

This repository contains no personal data.
