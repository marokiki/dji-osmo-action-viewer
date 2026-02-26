# Osmo Action Viewer (macOS)

A macOS video viewer for action-camera footage.
It scans videos recursively from a selected root folder and organizes them by trip directory (section).

## Features
- Recursive scan of videos under the selected folder
- Section-based browsing by subdirectory (for example: `Iki Trip`, `highlight`)
  - switching sections refreshes file changes (added/removed videos)
- Video playback
- Keyboard shortcuts:
  - `Left Arrow`: seek -10s
  - `Right Arrow`: seek +10s
  - `Space`: play/pause
- Marker controls:
  - add marker at current time
  - add marker by seconds
  - jump to marker
  - delete marker
  - export marker highlights (configurable clip length, default 10s)
  - render recording title at top-right on each highlight clip
  - export marker highlights across multiple checked videos
- Clip export (partial range):
  - set start/end seconds
  - export selected range
  - keeps `Captured At` metadata based on original capture time + export start offset
- Delete videos to Trash (single delete or checkbox-based multi-delete)
- Metadata editing per recording:
  - title
  - location text
  - Google Maps link
- Auto-merge support for split DJI segments like `_001`, `_002`, `_003`

## Supported video formats
- `.mp4`
- `.mov`
- `.m4v`

## Metadata persistence
Metadata is stored in SQLite, so it remains available across rebuilds.

- Path: `~/Library/Application Support/OsmoActionViewer/metadata.sqlite`

## Requirements
- macOS 13+
- Swift 5.9+
- Xcode app is not required (Command Line Tools is enough)

## Setup
```bash
git clone https://github.com/marokiki/dji-osmo-action-viewer.git
cd dji-osmo-action-viewer
```

## Build and run (without Xcode)
### Run directly
```bash
swift run
```

### Build then run
```bash
swift build
.build/debug/OsmoActionViewer
```

### Release build
```bash
swift build -c release
.build/release/OsmoActionViewer
```

## Build a DMG for distribution
```bash
swift build -c release
./scripts/make_dmg.sh v0.1.0
```

Output:
- `dist/OsmoActionViewer-v0.1.0.dmg`

## Typical workflow
1. Launch the app.
2. Click `Open Recording Folder`.
3. Select your root folder (for example `Video/`).
4. Choose a section (trip directory).
5. Select a video and play/edit/export as needed.
