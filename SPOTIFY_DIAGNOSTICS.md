# CarPlay26 v0.2.48 — Spotify diagnostic build

This adds an independent Spotify page to Settings > Tweaks > CarPlay26, accessible under **App Appearance**

- **Capture on Host Launch** (off by default): attempts a bounded read-only snapshot after the CarPlayTemplateUIHost process launches. RootHide can isolate preferences, so the manual button is preferred
- **Capture Spotify Layout Report**: sends a Darwin notification to the already-running CarPlayTemplateUIHost process. This captures only class names, frames, bounds, hidden state, colour metadata, corner radii and controller types
- **No appearance changes in this release**: do not modify Spotify's app binary, private feature flags, tab behaviour, playback, artwork, text or navigation
- **One file at a time**: each capture overwrites the previous template-host report

## How to test

1. In parked WinPlay, open Spotify Home
2. On iPhone, open **Settings > Tweaks > CarPlay26 > Spotify**
3. Tap **Capture Spotify Layout Report**
4. On the iPhone terminal, run:

   `sudo find /private/var/mobile /private/var/root -type f -name 'CarPlay26-Spotify-TemplateUIHost.txt' -print 2>/dev/null`

5. Check the file, then provide the report for analysis. Capture again on Now Playing, after saving the previous report

The report can contain internal class names and view geometry, but **not song names, contacts, messages or album artwork**

## Project history

v0.2.48: Introduce Spotify page, preference and read-only template host capture. No visual hooks added. Requires on-device confirmation; does not imply the iOS 26 Spotify interface can run on iOS 16
