# Chanology

A native iOS client for 4chan, built with SwiftUI.

![Tests](https://github.com/McArdle-Systems/Chanology/actions/workflows/test.yml/badge.svg)
![iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)

## Features

- **Board & Catalog browsing** — Browse all boards and view thread catalogs with image previews
- **Starred boards** — Pin favourite boards to the top of the board list with a swipe action; persisted across launches
- **Watched thread badge** — A red bell indicator appears on watched threads directly in the catalog
- **NSFW toggle** — Show or hide NSFW boards from a Settings sheet; off by default
- **Thread view** — Read threads with full post rendering, inline images, video support, and bare-URL linkification
- **Floating toolbar** — Context-sensitive action toolbar that can be flipped between leading/trailing edges with a long-press + flick gesture
- **Reply posting** — Post replies with image/file attachments and meme flag support (e.g. /pol/)
- **4chan Pass auth** — Log in with a 4chan Pass; credentials are stored securely in the Keychain and used automatically
- **(You) indicators** — Tracks your posts across threads, persisted independently of your watch list
- **Watch list** — Watch threads and get background-refreshed reply counts
- **Push-style notifications** — Local notifications for new replies in watched threads, with direct-reply detection (foreground and background)
- **Notification sounds** — Custom "Hey You" sound for (You) reply notifications; configurable in Settings
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
│   ├── Boards/           # Board list with starred section and NSFW toggle
│   ├── Catalog/          # Thread catalog with watched-thread indicators
│   ├── Settings/         # In-app settings sheet
│   ├── Thread/           # Thread view, compose sheet, login sheet
│   └── WatchList/        # Watched threads list
├── Notifications/        # Local notification scheduling and sound handling
├── Services/             # ForegroundRefreshService (in-app polling)
├── Storage/              # SwiftData models (WatchedThread, MyPosts, StarredBoards)
└── Utilities/            # HTML renderer, URL linkifier, reply map builder, layout helpers
```

## License

Private.
