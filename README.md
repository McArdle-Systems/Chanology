# Chanology

A native iOS client for 4chan, built with SwiftUI.

## Features

- **Board & Catalog browsing** — Browse all boards and view thread catalogs with image previews
- **Thread view** — Read threads with full post rendering, inline images, and video support
- **Reply posting** — Post replies with image/file attachments and meme flag support (e.g. /pol/)
- **4chan Pass auth** — Log in with a 4chan Pass; credentials are stored securely in the Keychain and used automatically
- **(You) indicators** — Tracks your posts across threads, persisted independently of your watch list
- **Watch list** — Watch threads and get background-refreshed reply counts
- **Push-style notifications** — Local notifications for new replies in watched threads, with direct-reply detection
- **Image gestures** — Pinch to zoom and pan on images and videos
- **Post quoting** — Tap reply badges to quote posts in the composer

## Requirements

- iOS 17.0+
- Xcode 16+
- Swift 6.0

## Building

Open the project with Xcode.

No other dependencies — the app uses only Apple frameworks.

## Architecture

```
Chanology/
├── API/                  # 4chan read API (ChanAPI) and post API (ChanPostAPI)
│   └── Models/           # Board, Thread, Post models
├── App/                  # App entry point and AppDelegate
├── Auth/                 # Keychain wrapper for 4chan Pass credentials
├── Background/           # BGAppRefresh handler for watched thread polling
├── Features/
│   ├── Boards/           # Board list
│   ├── Catalog/          # Thread catalog
│   ├── Thread/           # Thread view, compose sheet, login sheet
│   └── WatchList/        # Watched threads list
├── Notifications/        # Local notification scheduling
├── Services/             # ForegroundRefreshService (in-app polling)
├── Storage/              # SwiftData models (WatchedThread, MyPosts)
└── Utilities/            # HTML renderer, reply map builder, layout helpers
```

## License

Private.
