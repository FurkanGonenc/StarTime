# StarTime

A tiny macOS stopwatch you control with one shortcut.

- **⌘ + ⌥** (press together, release): starts the stopwatch, then pauses / resumes it.
- A small translucent, blurred window shows `HH:MM:SS`. Drag it anywhere.
- On another desktop (or when minimized) the menu bar shows `**:**:**` instead of the time —
  only while running (hidden when paused) — so you can see the state without watching the clock.
- The close button resets the stopwatch; the app keeps running in the background for the next ⌘ + ⌥.

## Build

```bash
./build.sh
open build/StarTime.app
```

Grant Accessibility access the first time: System Settings → Privacy & Security → Accessibility → StarTime.
