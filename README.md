# StreamSnip — Privacy-focused video player for iOS, iPadOS, macOS and tvOS

<div align="center">

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20tvOS-blue)](https://github.com/alzimerahmed/StreamSnip)
[![Language](https://img.shields.io/badge/language-Swift%206-orange)](https://swift.org)
[![Framework](https://img.shields.io/badge/framework-SwiftUI-0568af)](https://developer.apple.com/swiftui/)
[![Player](https://img.shields.io/badge/player-libmpv-red)](https://mpv.io)
[![License](https://img.shields.io/badge/license-AGPL%20v3-blue)](https://www.gnu.org/licenses/agpl-3.0.en.html)

*Watch and clip video from YouTube (via Invidious, Piped or a self-hosted backend), PeerTube, Jellyfin, local files, SMB and WebDAV — with a native MPV-powered player and no tracking.*

[Download](https://github.com/alzimerahmed/StreamSnip/releases) • [Features](#features) • [Building](#building)

</div>

---

## Features

| Area | What you get |
|---|---|
| Player | Custom [libmpv](https://mpv.io) pipeline — H.264/H.265/VP9/AV1, up to 4K, HDR; custom controls, gestures, seek previews |
| Playback modes | Fullscreen, Picture in Picture, background audio, queue, resume, chapter navigation |
| Sources | Invidious, Piped, PeerTube, Jellyfin, self-hosted Yattee Server (yt-dlp, 1000+ sites), local files, SMB, WebDAV, direct HLS/DASH links |
| Clips | Mark in/out points, save clips to a library, organize into collections, share timestamps, deep-link via `streamsnip://clip/...` |
| Integrations | [SponsorBlock](https://sponsor.ajay.app/) (configurable skip categories), DeArrow, Return YouTube Dislike |
| Sync | iCloud (CloudKit) sync of subscriptions, bookmarks, playlists, history and settings; Handoff between devices |
| Extras | Downloads with quality selection and Live Activity progress, tvOS TopShelf, Share extension, Shortcuts/Siri automation via `streamsnip://` |

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI, multiplatform (`#if os(...)` conditionals), iOS 18 / macOS 15 / tvOS 18 |
| Player | libmpv (vendored MPVKit), custom `MPVController` render pipeline |
| API layer | `API` protocol with per-backend implementations (Invidious, Piped, PeerTube, Jellyfin, Yattee Server, Local, SMB, WebDAV) |
| Persistence | SwiftData (`DataManager`) + CloudKit sync; Keychain-backed credentials |
| Concurrency | Swift 6 strict concurrency (`@MainActor`, Sendable) |
| Updates | Sparkle (Developer ID builds only; App Store/TestFlight builds are Sparkle-free) |

## Project Structure

```
StreamSnip.xcodeproj
StreamSnip/               # single multiplatform source tree
  Core/                   # app environment, settings, accounts
  Services/API/           # per-backend API implementations
  Services/Player/        # MPV pipeline, Player facade
  Views/                  # SwiftUI screens (player, settings, instances, clips)
StreamSnipShareExtension/ # share extension target
StreamSnipTopShelf/       # tvOS TopShelf extension target
StreamSnipTests/          # Swift Testing suite (macOS-hosted)
.github/workflows/        # CI + release pipelines
```

## Download

Grab the unsigned builds from [GitHub Releases](https://github.com/alzimerahmed/StreamSnip/releases): a macOS `.zip` (right-click the app and choose **Open** on first launch, or allow it in System Settings → Privacy & Security) and an iOS `.ipa` (sideload via AltStore/Sideloadly, or re-sign with your own certificate).

## Building

1. Clone the repository and open `StreamSnip.xcodeproj` in Xcode 16+ (or 26.x).
2. Let Xcode resolve package dependencies (MPVKit, Sparkle, Nuke, others).
3. Select the `StreamSnip` scheme and run on an iOS/macOS/tvOS destination.

CI builds and tests every push to `main` (unsigned, macOS runner); see `.github/workflows/ci.yml`.

## Usage

Add a source under **Settings → Instances** (an Invidious/Piped/Jellyfin instance, a Yattee Server, or an SMB/WebDAV share), pick a video, and it opens in the MPV player. While watching, use the clip controls to mark in/out points and save a clip to your library — clips sync over iCloud and are shareable as `streamsnip://clip/...` links.

## Contributing

Fork the repository, create a feature branch, and open a pull request against `main`. Commits follow [Conventional Commits](https://www.conventionalcommits.org); CI must be green before merge.

## Roadmap

- [ ] Clip re-encode export (ffmpeg/AVFoundation transcode pipeline)
- [ ] Queue WidgetKit widget extension
- [ ] Universal Links domain for `streamsnip://` deep links

## Changelog

See [GitHub Releases](https://github.com/alzimerahmed/StreamSnip/releases).

## License

StreamSnip is a fork of [Yattee](https://github.com/yattee/yattee) (fork base `main@03599d3`) and is licensed under [AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.en.html). All credit for the original project goes to the Yattee authors and contributors. Maintained by Alzimer Ahmed.
