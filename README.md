# TaskSpool

TaskSpool is a small native macOS menu bar app for running and watching shell commands in the background. It is useful for local dev servers, scripts, watchers, and any long-running command you want to start, restart, inspect, or stop without keeping a terminal tab open.

The name combines a background task spool with the app's yarn-themed icon: commands go onto the spool, and you keep control from the menu bar.

## Features

- Run any shell command through `/bin/zsh -lc`.
- Choose a working directory before launching a task.
- Stream stdout and stderr in real time.
- Keep each command in its own process group.
- Stop a task with `SIGTERM`, then escalate to `SIGKILL` if it does not exit within 2 seconds.
- Restart, remove, or clear logs for individual tasks.
- Kill all running tasks from the menu bar.
- Hide the main window while keeping the status bar controller available.
- Keep recent output bounded to the latest 4,000 log entries per task.

## Requirements

- macOS 13 or later.
- Swift 5.10 or later.

## Run from source

```bash
swift run TaskSpool
```

## Build the macOS app

```bash
chmod +x Scripts/build-app.sh
./Scripts/build-app.sh
open "dist/TaskSpool.app"
```

The build script creates `dist/TaskSpool.app`, copies the app icon and brand assets, and writes a minimal `Info.plist`.

## Usage

1. Enter a command, for example `npm run dev`, `python3 app.py`, or `tail -f app.log`.
2. Set the working directory, or choose one with the folder picker.
3. Click **Start**.
4. Select a task to view logs, kill it, restart it, or clear its output.
5. Use **Hide to Menu Bar** when you want TaskSpool to stay out of the Dock.

## Safety Notes

TaskSpool runs commands locally with the current process environment. It does not add telemetry, network calls, or remote storage of its own, but the commands you launch can do anything your shell command would normally be allowed to do.

Before publishing or sharing a build, avoid including generated directories such as `.build/` or `dist/`. Swift build artifacts can contain local absolute paths from the machine that produced them.

## Project Layout

```text
Package.swift
Sources/TaskSpool/
  AppWindowController.swift
  ContentView.swift
  ShellLauncher.swift
  ShellTask.swift
  StatusBarController.swift
  TaskSpoolApp.swift
  TaskModels.swift
  TaskStore.swift
Resources/
  AppIcon.icns
  Brand/
Scripts/
  build-app.sh
  generate-icons.swift
```

## Sensitive Information Check

The source tree was checked for common secret formats, email addresses, private network addresses, internal-domain markers, and company-specific internal references. No sensitive personal or internal network information was found in source files, scripts, resources, or the README.

Generated local build output is ignored by `.gitignore`; do not publish `.build/` or `dist/`.
